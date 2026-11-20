//  Primitives.swift
//  GtrBoard
//
//  Small, allocation-free DSP building blocks used by every pedal: gain
//  conversion, parameter smoothing, one-pole filters, DC blocking, LFOs,
//  fractional delay lines, a 4x oversampler for the drive stages and a
//  Freeverb-derived reverb core.

import Foundation

/// Decibels to linear gain.
@inline(__always) func dbToGain(_ db: Double) -> Double {
    pow(10, db / 20)
}

/// Linear gain to decibels, floored to avoid -inf.
@inline(__always) func gainToDB(_ gain: Double) -> Double {
    20 * log10(max(gain, 1e-9))
}

@inline(__always) func clampValue(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

/// One-pole smoothed value. Parameters are moved once per block; the short
/// time constant (about 3 ms at 128-frame blocks) removes zipper noise while
/// staying responsive enough for real-time knob turns.
struct Smoothed {
    var current: Double
    var target: Double

    init(_ value: Double) {
        current = value
        target = value
    }

    mutating func set(_ newTarget: Double) {
        target = newTarget.isFinite ? newTarget : current
    }

    mutating func step(_ coefficient: Double = 0.3) -> Double {
        current += (target - current) * coefficient
        return current
    }

    mutating func snap() {
        current = target
    }
}

/// One-pole low-pass. `a = exp(-2π f / fs)` gives the usual RC response.
struct OnePoleLowPass {
    private(set) var z: Double = 0
    private(set) var a: Double = 0

    init() {}

    mutating func setCutoff(_ frequency: Double, sampleRate: Double) {
        let f = clampValue(frequency, 10, sampleRate * 0.49)
        a = exp(-2 * Double.pi * f / sampleRate)
    }

    mutating func reset() { z = 0 }

    @inline(__always)
    mutating func process(_ input: Double) -> Double {
        z = input * (1 - a) + z * a
        return z
    }
}

/// One-pole high-pass, implemented as input minus its low-passed version.
struct OnePoleHighPass {
    private var low = OnePoleLowPass()

    init() {}

    mutating func setCutoff(_ frequency: Double, sampleRate: Double) {
        low.setCutoff(frequency, sampleRate: sampleRate)
    }

    mutating func reset() { low.reset() }

    @inline(__always)
    mutating func process(_ input: Double) -> Double {
        input - low.process(input)
    }
}

/// Removes the DC offset that asymmetric waveshapers inevitably create.
struct DCBlocker {
    private var previousInput: Double = 0
    private var previousOutput: Double = 0
    private let r: Double = 0.9975

    init() {}

    mutating func reset() {
        previousInput = 0
        previousOutput = 0
    }

    @inline(__always)
    mutating func process(_ input: Double) -> Double {
        let output = input - previousInput + r * previousOutput
        previousInput = input
        previousOutput = output.isFinite ? output : 0
        return previousOutput
    }
}

/// Low-frequency oscillator shared by the modulation pedals.
struct LFO {
    var phase: Double = 0

    init(phase: Double = 0) {
        self.phase = phase - floor(phase)
    }

    /// Advances by one sample and wraps the phase into 0…1.
    @inline(__always)
    mutating func advance(rate: Double, sampleRate: Double) {
        phase += rate / sampleRate
        if phase >= 1 { phase -= floor(phase) }
        if phase < 0 { phase += 1 }
    }

    /// Waveform value in -1…1. 0 = sine, 1 = triangle, 2 = square.
    @inline(__always)
    func value(shape: Int) -> Double {
        switch shape {
        case 1:
            return 4 * abs(phase - 0.5) - 1
        case 2:
            return phase < 0.5 ? 1 : -1
        default:
            return sin(2 * Double.pi * phase)
        }
    }
}

/// Circular delay line with linear interpolation and a fractional tap.
final class DelayLine {
    private var storage: UnsafeMutablePointer<Double>
    private var capacity: Int
    private var index: Int = 0

    /// Allocates `maxSamples + 2` doubles. Never call from the audio thread.
    init(maxSamples: Int) {
        capacity = max(4, maxSamples + 2)
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Changes the maximum delay. Only call while audio is stopped.
    func resize(maxSamples: Int) {
        let newCapacity = max(4, maxSamples + 2)
        guard newCapacity != capacity else { return }
        storage.deallocate()
        capacity = newCapacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        index = 0
    }

    func clear() {
        storage.update(repeating: 0, count: capacity)
        index = 0
    }

    var maxDelay: Double { Double(capacity - 2) }

    @inline(__always)
    func write(_ sample: Double) {
        storage[index] = sample.isFinite ? sample : 0
        index += 1
        if index >= capacity { index = 0 }
    }

    /// Reads `delay` samples back (0 = the most recently written sample).
    @inline(__always)
    func read(_ delay: Double) -> Double {
        let d = clampValue(delay, 0, maxDelay)
        var position = Double(index) - (d + 1)
        while position < 0 { position += Double(capacity) }
        let base = Int(position)
        let fraction = position - Double(base)
        let i0 = base % capacity
        let i1 = (i0 + 1) % capacity
        return storage[i0] * (1 - fraction) + storage[i1] * fraction
    }

    /// Feedback tap with a one-pole low-pass, used by the delay pedal.
    @inline(__always)
    func readFiltered(_ delay: Double, lowPass: inout OnePoleLowPass) -> Double {
        lowPass.process(read(delay))
    }
}

/// One 2x half-band stage: 31-tap windowed-sinc low-pass, linear phase.
final class HalfbandStage {
    private static let taps: [Double] = {
        let count = 31
        let middle = 15
        let cutoff = 0.24
        var coefficients = [Double](repeating: 0, count: count)
        var sum = 0.0
        for n in 0..<count {
            let x = Double(n - middle)
            let sinc = x == 0 ? 2 * cutoff : sin(2 * Double.pi * cutoff * x) / (Double.pi * x)
            let phase = 2 * Double.pi * Double(n) / Double(count - 1)
            let window = 0.42 - 0.5 * cos(phase) + 0.08 * cos(2 * phase)
            coefficients[n] = sinc * window
            sum += coefficients[n]
        }
        return coefficients.map { $0 / sum }
    }()

    private static let evenTaps: [Double] = stride(from: 0, to: 31, by: 2).map { taps[$0] }
    private static let oddTaps: [Double] = stride(from: 1, to: 30, by: 2).map { taps[$0] }

    private var history: UnsafeMutablePointer<Double>
    private var position: Int = 0

    init() {
        history = .allocate(capacity: 64)
        history.initialize(repeating: 0, count: 64)
    }

    deinit {
        history.deallocate()
    }

    func reset() {
        history.update(repeating: 0, count: 64)
        position = 0
    }

    @inline(__always) private func push(_ input: Double) {
        history[position] = input
        position = (position + 1) & 63
    }

    /// Delay-tap access: 0 is the most recent sample.
    @inline(__always) private func tap(_ delay: Int) -> Double {
        history[(position - 1 - delay) & 63]
    }

    /// Upsamples one input sample to two output samples.
    @inline(__always)
    func up(_ input: Double, even: inout Double, odd: inout Double) {
        push(input)
        var e = 0.0
        var o = 0.0
        for k in 0..<16 {
            e += HalfbandStage.evenTaps[k] * tap(k)
        }
        for k in 0..<15 {
            o += HalfbandStage.oddTaps[k] * tap(k)
        }
        even = e * 2
        odd = o * 2
    }

    /// Filters one 2x-rate sample. The caller decimates every other output.
    @inline(__always)
    func down(_ input: Double) -> Double {
        push(input)
        var y = 0.0
        for k in 0..<31 {
            y += HalfbandStage.taps[k] * tap(k)
        }
        return y
    }
}

/// 4x oversampling around a non-linear stage. Higher oversampling moves the
/// aliases produced by clipping well above the audible band, which is what
/// separates a musical drive pedal from a buzzy waveshaper.
final class Oversampler4x {
    // The up and down paths need independent filter histories: a half-band
    // stage that filters 1x samples on the way up cannot also hold the 2x
    // history on the way down, otherwise every block boundary starts from a
    // corrupted state and produces a click at the buffer rate.
    private let upAL = HalfbandStage()
    private let upAR = HalfbandStage()
    private let upBL = HalfbandStage()
    private let upBR = HalfbandStage()
    private let downAL = HalfbandStage()
    private let downAR = HalfbandStage()
    private let downBL = HalfbandStage()
    private let downBR = HalfbandStage()

    private var stage2L: UnsafeMutablePointer<Double>
    private var stage2R: UnsafeMutablePointer<Double>
    private var stage4L: UnsafeMutablePointer<Double>
    private var stage4R: UnsafeMutablePointer<Double>
    private var capacity: Int = 0

    init() {
        stage2L = .allocate(capacity: 1)
        stage2R = .allocate(capacity: 1)
        stage4L = .allocate(capacity: 1)
        stage4R = .allocate(capacity: 1)
    }

    deinit {
        stage2L.deallocate()
        stage2R.deallocate()
        stage4L.deallocate()
        stage4R.deallocate()
    }

    func prepare(maxFrames: Int) {
        let needed = max(64, maxFrames) * 2 + 8
        guard needed > capacity else { return }
        stage2L.deallocate()
        stage2R.deallocate()
        stage4L.deallocate()
        stage4R.deallocate()
        stage2L = .allocate(capacity: needed * 2)
        stage2R = .allocate(capacity: needed * 2)
        stage4L = .allocate(capacity: needed * 4)
        stage4R = .allocate(capacity: needed * 4)
        stage2L.initialize(repeating: 0, count: needed * 2)
        stage2R.initialize(repeating: 0, count: needed * 2)
        stage4L.initialize(repeating: 0, count: needed * 4)
        stage4R.initialize(repeating: 0, count: needed * 4)
        capacity = needed
    }

    func reset() {
        upAL.reset()
        upAR.reset()
        upBL.reset()
        upBR.reset()
        downAL.reset()
        downAR.reset()
        downBL.reset()
        downBR.reset()
    }

    /// The 4x-rate left buffer. Valid after ``upsample``.
    var upLeft: UnsafeMutablePointer<Double> { stage4L }
    /// The 4x-rate right buffer. Valid after ``upsample``.
    var upRight: UnsafeMutablePointer<Double> { stage4R }

    /// Upsamples a block by 4. Output length is `frames * 4`.
    func upsample(left: UnsafeMutablePointer<Double>, right: UnsafeMutablePointer<Double>, frames: Int) {
        for frame in 0..<frames {
            var even = 0.0, odd = 0.0
            upAL.up(left[frame], even: &even, odd: &odd)
            stage2L[frame * 2] = even
            stage2L[frame * 2 + 1] = odd
            upAR.up(right[frame], even: &even, odd: &odd)
            stage2R[frame * 2] = even
            stage2R[frame * 2 + 1] = odd
        }
        let count = frames * 2
        for frame in 0..<count {
            var even = 0.0, odd = 0.0
            upBL.up(stage2L[frame], even: &even, odd: &odd)
            stage4L[frame * 2] = even
            stage4L[frame * 2 + 1] = odd
            upBR.up(stage2R[frame], even: &even, odd: &odd)
            stage4R[frame * 2] = even
            stage4R[frame * 2 + 1] = odd
        }
    }

    /// Downsamples the 4x buffers back to `frames` samples.
    func downsample(left: UnsafeMutablePointer<Double>, right: UnsafeMutablePointer<Double>, frames: Int) {
        let count4x = frames * 4
        for index in 0..<count4x {
            let leftFiltered = downBL.down(stage4L[index])
            let rightFiltered = downBR.down(stage4R[index])
            if index % 2 == 1 {
                stage2L[index / 2] = leftFiltered
                stage2R[index / 2] = rightFiltered
            }
        }
        let count2x = frames * 2
        for index in 0..<count2x {
            let leftFiltered = downAL.down(stage2L[index])
            let rightFiltered = downAR.down(stage2R[index])
            if index % 2 == 1 {
                left[index / 2] = leftFiltered
                right[index / 2] = rightFiltered
            }
        }
    }
}

/// One comb filter in the reverb network.
private final class ReverbComb {
    private var buffer: UnsafeMutablePointer<Double>
    private var size: Int
    private var index: Int = 0
    private var store: Double = 0

    init(size: Int) {
        self.size = max(4, size)
        buffer = .allocate(capacity: self.size)
        buffer.initialize(repeating: 0, count: self.size)
    }

    deinit { buffer.deallocate() }

    func clear() {
        buffer.update(repeating: 0, count: size)
        index = 0
        store = 0
    }

    @inline(__always)
    func process(_ input: Double, feedback: Double, damping: Double) -> Double {
        let output = buffer[index]
        store = output * (1 - damping) + store * damping
        buffer[index] = input + store * feedback
        index += 1
        if index >= size { index = 0 }
        return output
    }
}

/// One all-pass diffuser in the reverb network.
private final class ReverbAllpass {
    private var buffer: UnsafeMutablePointer<Double>
    private var size: Int
    private var index: Int = 0

    init(size: Int) {
        self.size = max(4, size)
        buffer = .allocate(capacity: self.size)
        buffer.initialize(repeating: 0, count: self.size)
    }

    deinit { buffer.deallocate() }

    func clear() {
        buffer.update(repeating: 0, count: size)
        index = 0
    }

    @inline(__always)
    func process(_ input: Double) -> Double {
        let stored = buffer[index]
        buffer[index] = input + stored * 0.5
        index += 1
        if index >= size { index = 0 }
        return -input + stored
    }
}

/// Stereo Freeverb-style reverb. Eight parallel comb filters feed four
/// all-pass diffusers per channel; mode changes the network length and
/// feedback to cover room, hall and plate territory.
final class ReverbCore {
    private static let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTunings = [556, 441, 341, 225]
    private static let stereoSpread = 23

    private var combsLeft: [ReverbComb] = []
    private var combsRight: [ReverbComb] = []
    private var allpassLeft: [ReverbAllpass] = []
    private var allpassRight: [ReverbAllpass] = []

    func prepare(sampleRate: Double) {
        let scale = sampleRate / 44_100 * 1.18

        combsLeft = ReverbCore.combTunings.map {
            ReverbComb(size: Int(Double($0) * scale))
        }
        combsRight = ReverbCore.combTunings.map {
            ReverbComb(size: Int(Double($0 + ReverbCore.stereoSpread) * scale))
        }
        allpassLeft = ReverbCore.allpassTunings.map {
            ReverbAllpass(size: Int(Double($0) * scale))
        }
        allpassRight = ReverbCore.allpassTunings.map {
            ReverbAllpass(size: Int(Double($0 + ReverbCore.stereoSpread) * scale))
        }
    }

    func clear() {
        combsLeft.forEach { $0.clear() }
        combsRight.forEach { $0.clear() }
        allpassLeft.forEach { $0.clear() }
        allpassRight.forEach { $0.clear() }
    }

    /// Processes one stereo sample. `size` and `damping` are 0…1.
    @inline(__always)
    func process(
        left: Double,
        right: Double,
        size: Double,
        damping: Double,
        feedback: Double
    ) -> (Double, Double) {
        let input = (left + right) * 0.018
        let damp = clampValue(damping, 0, 1) * 0.55
        var wetLeft = 0.0
        var wetRight = 0.0

        for index in 0..<combsLeft.count {
            wetLeft += combsLeft[index].process(input, feedback: feedback, damping: damp)
            wetRight += combsRight[index].process(input, feedback: feedback, damping: damp)
        }
        for allpass in allpassLeft {
            wetLeft = allpass.process(wetLeft)
        }
        for allpass in allpassRight {
            wetRight = allpass.process(wetRight)
        }
        return (wetLeft * 2.6, wetRight * 2.6)
    }
}
