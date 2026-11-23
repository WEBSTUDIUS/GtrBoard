//  FeedbackSuppressor.swift
//  BoardCore
//
//  Automatic feedback and open-jack suppressor that sits before the pedal
//  chain, where it can hear the raw guitar and act before the amp multiplies
//  the problem.
//
//  Two mechanisms run in parallel:
//
//  * Narrow-band peaks that *grow* over a few analysis frames are the classic
//    acoustic-feedback signature. They get an automatic notch, so the loop is
//    broken without touching a decaying guitar note.
//  * A steady 50/60 Hz mains component with strong harmonics is the signature
//    of a floating input — an unplugged cable lying on the floor. It gets
//    narrow notches at the fundamental and its first harmonics.
//
//  A last-resort gain rider catches the rare case of a signal that sits near
//  full scale for most of a second, which no notch can fix.
//
//  Analysis runs on the audio thread but only every 512 samples; all buffers
//  and the FFT setup are allocated in `prepare`.

import Foundation
import os.lock

/// What the suppressor is doing right now, for the interface.
public struct FeedbackGuardStatus: Equatable, Sendable {
    /// Number of notches currently applied.
    public var activeNotches: Int
    /// True when a mains-hum / open-input signature was detected.
    public var humDetected: Bool
    /// Emergency gain offset in dB (0 when the guard is only notching).
    public var gainReductionDB: Double
    /// True when the guard latched the input off because a howl would not
    /// stop. The user clears this from the footer.
    public var muted: Bool

    public init(
        activeNotches: Int = 0,
        humDetected: Bool = false,
        gainReductionDB: Double = 0,
        muted: Bool = false
    ) {
        self.activeNotches = activeNotches
        self.humDetected = humDetected
        self.gainReductionDB = gainReductionDB
        self.muted = muted
    }

    /// A guard that is switching itself on should be visible in the UI.
    public var isActive: Bool {
        activeNotches > 0 || humDetected || muted || gainReductionDB < -0.2
    }

    public static let idle = FeedbackGuardStatus()
}

/// Lock-free-ish status channel between the render thread and SwiftUI.
public final class FeedbackGuardMeter: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private var status = FeedbackGuardStatus.idle

    public init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func publish(_ newStatus: FeedbackGuardStatus) {
        guard os_unfair_lock_trylock(lock) else { return }
        status = newStatus
        os_unfair_lock_unlock(lock)
    }

    /// Safe from the main thread at UI rate.
    public func snapshot() -> FeedbackGuardStatus {
        os_unfair_lock_lock(lock)
        let value = status
        os_unfair_lock_unlock(lock)
        return value
    }
}

final class FeedbackSuppressor {
    static let analysisSize = 2_048
    static let humWindowSize = 4_096
    static let hop = 512
    static let maxNotches = 8
    static let maxCandidates = 8
    static let rmsHistorySize = 64

    let meter = FeedbackGuardMeter()

    private var sampleRate: Double = 48_000
    private var enabled = true

    private var fft: FFT?
    private var window: UnsafeMutablePointer<Float>?
    private var humWindow: UnsafeMutablePointer<Float>?
    private var ring: UnsafeMutablePointer<Float>?
    private var humRing: UnsafeMutablePointer<Float>?
    private var frame: UnsafeMutablePointer<Float>?
    private var spectrumReal: UnsafeMutablePointer<Float>?
    private var spectrumImaginary: UnsafeMutablePointer<Float>?
    private var magnitudes: UnsafeMutablePointer<Float>?
    private var humFrame: UnsafeMutablePointer<Float>?
    private var candidateHistory: UnsafeMutablePointer<Double>?

    private var ringPosition = 0
    private var humPosition = 0
    private var sinceAnalysis = 0
    private var sinceHum = 0

    private var candidates: [Candidate] = []
    private var notches: [Notch] = []

    private var gain: Double = 1
    private var gainStep: Double = 0.001
    private var panicAttackStep: Double = 0.002
    private var notchMixStep: Double = 0.001
    private var runawayFrames = 0
    private var nearClipFrames = 0
    private var humScore = 0
    private var humActive = false
    private var lastPublished = FeedbackGuardStatus.idle

    /// Latched panic state: the loop could not be broken by notches or a
    /// gentle duck, so the input is muted until the user resumes.
    private var panicMuted = false
    private var resetRequested = false
    private let resetLock: UnsafeMutablePointer<os_unfair_lock_s>
    private var outputLevel: Double = 0
    private var rmsHistory: UnsafeMutablePointer<Double>?
    private var rmsHistoryIndex = 0
    private var rmsHistoryCount = 0
    private var previousMagnitudes: UnsafeMutablePointer<Float>?
    private var stationaryScore = 0
    private var rmsSlow: Double = 0

    init() {
        resetLock = .allocate(capacity: 1)
        resetLock.initialize(to: os_unfair_lock_s())
        candidates = Array(repeating: Candidate(), count: Self.maxCandidates)
        notches = Array(repeating: Notch(), count: Self.maxNotches)
    }

    deinit {
        window?.deallocate()
        humWindow?.deallocate()
        ring?.deallocate()
        humRing?.deallocate()
        frame?.deallocate()
        spectrumReal?.deallocate()
        spectrumImaginary?.deallocate()
        magnitudes?.deallocate()
        humFrame?.deallocate()
        candidateHistory?.deallocate()
        rmsHistory?.deallocate()
        previousMagnitudes?.deallocate()
        resetLock.deinitialize(count: 1)
        resetLock.deallocate()
    }

    /// Allocates the analysis state. Audio is stopped when this runs.
    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = max(8_000, sampleRate)
        runawayFrames = Int(0.8 * self.sampleRate)
        gainStep = 1 - exp(-1 / (0.030 * self.sampleRate))
        panicAttackStep = 1 - exp(-1 / (0.012 * self.sampleRate))
        notchMixStep = 1 - exp(-1 / (0.020 * self.sampleRate))

        if fft == nil || fft?.size != Self.analysisSize {
            fft = FFT(size: Self.analysisSize)
        }

        deallocateBuffers()
        window = allocate(Self.analysisSize)
        humWindow = allocate(Self.humWindowSize)
        ring = allocate(Self.analysisSize)
        humRing = allocate(Self.humWindowSize)
        frame = allocate(Self.analysisSize)
        spectrumReal = allocate(Self.analysisSize)
        spectrumImaginary = allocate(Self.analysisSize)
        magnitudes = allocate(Self.analysisSize / 2 + 1)
        humFrame = allocate(Self.humWindowSize)
        candidateHistory = UnsafeMutablePointer<Double>.allocate(capacity: Self.maxCandidates * 8)
        candidateHistory?.initialize(repeating: -120, count: Self.maxCandidates * 8)
        rmsHistory = UnsafeMutablePointer<Double>.allocate(capacity: Self.rmsHistorySize)
        rmsHistory?.initialize(repeating: -120, count: Self.rmsHistorySize)
        previousMagnitudes = UnsafeMutablePointer<Float>.allocate(capacity: Self.analysisSize / 2 + 1)
        previousMagnitudes?.initialize(repeating: 0, count: Self.analysisSize / 2 + 1)

        for index in 0..<Self.analysisSize {
            window?[index] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(Self.analysisSize - 1)))
        }
        for index in 0..<Self.humWindowSize {
            humWindow?[index] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(Self.humWindowSize - 1)))
        }
        resetState()
    }

    /// Enables or bypasses the guard. Disabling clears every notch.
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        resetState()
        publish(force: true)
    }

    /// Clears the latched feedback mute. Called from the footer when the user
    /// clicks MUTED; the audio thread reads the request without blocking.
    func requestPanicReset() {
        os_unfair_lock_lock(resetLock)
        resetRequested = true
        os_unfair_lock_unlock(resetLock)
    }

    /// Reports the peak of the block the chain just produced, so the panic
    /// detector can require that the howl is actually loud at the output.
    func noteOutputPeak(_ peak: Float) {
        let level = Double(peak)
        outputLevel += (level - outputLevel) * 0.08
    }

    /// Clears all suppression state but keeps the configuration.
    func reset() {
        resetState()
        publish(force: true)
    }

    /// Processes in place. Pass-through when disabled, real-time safe.
    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        guard enabled, frames > 0,
              let ring, let humRing, let frame, let humFrame,
              let spectrumReal, let spectrumImaginary, let magnitudes,
              let window, let humWindow else { return }

        let analysisMask = Self.analysisSize - 1
        let humMask = Self.humWindowSize - 1

        if consumeResetRequest() {
            panicMuted = false
            stationaryScore = 0
            rmsHistoryCount = 0
            previousMagnitudes?.update(repeating: 0, count: Self.analysisSize / 2 + 1)
            publish(force: true)
        }

        for index in 0..<frames {
            let rawLeft = left[index]
            let rawRight = right[index]
            let mono = (rawLeft + rawRight) * 0.5

            ring[ringPosition] = Float(mono)
            ringPosition = (ringPosition + 1) & analysisMask
            humRing[humPosition] = Float(mono)
            humPosition = (humPosition + 1) & humMask

            sinceAnalysis += 1
            if sinceAnalysis >= Self.hop {
                sinceAnalysis = 0
                analyse(
                    ring: ring, frame: frame, window: window,
                    spectrumReal: spectrumReal, spectrumImaginary: spectrumImaginary,
                    magnitudes: magnitudes
                )
            }

            sinceHum += 1
            if sinceHum >= Self.hop {
                sinceHum = 0
                analyseHum(ring: humRing, frame: humFrame, window: humWindow)
            }

            var processedLeft = rawLeft
            var processedRight = rawRight
            for slot in 0..<Self.maxNotches {
                let target = notches[slot].target
                let currentMix = notches[slot].mix
                if currentMix > 0.0001 || target > 0 {
                    let mix = currentMix + (target - currentMix) * notchMixStep
                    notches[slot].mix = mix
                    if mix > 0.0001 {
                        let coefficients = notches[slot].coefficients
                        let notchedLeft = notches[slot].stateLeft.process(processedLeft, coefficients)
                        let notchedRight = notches[slot].stateRight.process(processedRight, coefficients)
                        processedLeft += (notchedLeft - processedLeft) * mix
                        processedRight += (notchedRight - processedRight) * mix
                    }
                }
            }

            // Last-resort runaway rider. A guitar never sits above -3 dBFS for
            // 0.8 s; a self-oscillating loop does.
            let peak = max(abs(rawLeft), abs(rawRight))
            if peak > 0.7 {
                nearClipFrames += 1
            } else {
                nearClipFrames = max(0, nearClipFrames - 2)
            }
            var targetGain = nearClipFrames > runawayFrames ? dbToGain(-12) : 1
            if panicMuted { targetGain = dbToGain(-60) }
            let step = targetGain < gain ? panicAttackStep : gainStep
            gain += (targetGain - gain) * step

            left[index] = processedLeft * gain
            right[index] = processedRight * gain
        }

        publish(force: false)
    }

    // MARK: - Analysis

    private func analyse(
        ring: UnsafeMutablePointer<Float>,
        frame: UnsafeMutablePointer<Float>,
        window: UnsafeMutablePointer<Float>,
        spectrumReal: UnsafeMutablePointer<Float>,
        spectrumImaginary: UnsafeMutablePointer<Float>,
        magnitudes: UnsafeMutablePointer<Float>
    ) {
        guard let fft else { return }
        let size = Self.analysisSize
        let mask = size - 1

        for index in 0..<size {
            frame[index] = ring[(ringPosition + index) & mask] * window[index]
        }
        fft.forward(
            real: frame, imaginary: nil,
            outputReal: spectrumReal, outputImaginary: spectrumImaginary
        )

        let half = size / 2
        for bin in 0...half {
            let real = spectrumReal[bin]
            let imaginary = spectrumImaginary[bin]
            magnitudes[bin] = 4 * sqrt(real * real + imaginary * imaginary) / Float(size)
        }

        var sumSquares = 0.0
        for index in 0..<size {
            let value = Double(ring[(ringPosition + index) & mask])
            sumSquares += value * value
        }
        let rms = sqrt(sumSquares / Double(size))
        let rmsDB = 20 * log10(max(rms, 1e-9))

        var fluxChange = 0.0
        var fluxTotal = 0.0
        if let previous = previousMagnitudes {
            for bin in 1...half {
                let value = Double(magnitudes[bin])
                fluxChange += abs(value - Double(previous[bin]))
                fluxTotal += value
                previous[bin] = magnitudes[bin]
            }
        }
        let spectralFlux = fluxChange / max(fluxTotal, 1e-9)

        var firstFrequency = 0.0, firstAmplitude = 0.0
        var secondFrequency = 0.0, secondAmplitude = 0.0
        var thirdFrequency = 0.0, thirdAmplitude = 0.0
        let minBin = max(1, Int(120 * Double(size) / sampleRate))
        let maxBin = min(half - 2, Int(12_000 * Double(size) / sampleRate))
        if maxBin > minBin + 2 {
            for bin in minBin...maxBin {
                let amplitude = Double(magnitudes[bin])
                guard amplitude > 0.0008 else { continue }
                guard amplitude > Double(magnitudes[bin - 1]),
                      amplitude >= Double(magnitudes[bin + 1]) else { continue }

                var sum = 0.0
                var count = 0
                let low = max(1, bin - 40)
                let high = min(half, bin + 40)
                var neighbour = low
                while neighbour <= high {
                    if abs(neighbour - bin) > 2 {
                        sum += Double(magnitudes[neighbour])
                        count += 1
                    }
                    neighbour += 1
                }
                let mean = sum / Double(max(count, 1))
                guard amplitude > mean * 5 else { continue }

                let frequency = Double(bin) * sampleRate / Double(size)
                if amplitude > firstAmplitude {
                    thirdFrequency = secondFrequency
                    thirdAmplitude = secondAmplitude
                    secondFrequency = firstFrequency
                    secondAmplitude = firstAmplitude
                    firstFrequency = frequency
                    firstAmplitude = amplitude
                } else if amplitude > secondAmplitude {
                    thirdFrequency = secondFrequency
                    thirdAmplitude = secondAmplitude
                    secondFrequency = frequency
                    secondAmplitude = amplitude
                } else if amplitude > thirdAmplitude {
                    thirdFrequency = frequency
                    thirdAmplitude = amplitude
                }
            }
        }

        for index in candidates.indices {
            candidates[index].missed += 1
        }

        updateStationarity(
            rmsDB: rmsDB,
            flux: spectralFlux,
            dominantFrequency: firstFrequency
        )

        if firstAmplitude > 0 {
            processPeak(frequency: firstFrequency, amplitude: firstAmplitude)
        }
        if secondAmplitude > 0 {
            processPeak(frequency: secondFrequency, amplitude: secondAmplitude)
        }
        if thirdAmplitude > 0 {
            processPeak(frequency: thirdFrequency, amplitude: thirdAmplitude)
        }

        for index in candidates.indices where candidates[index].missed > 60 {
            candidates[index] = Candidate()
        }

        for index in notches.indices where notches[index].target > 0 {
            notches[index].staleFrames += 1
            if notches[index].staleFrames > 1_200 {
                notches[index].target = 0
            }
        }
    }

    /// Matches one detected peak against the tracker, or starts tracking it.
    private func processPeak(frequency: Double, amplitude: Double) {
        guard let history = candidateHistory else { return }
        let levelDB = 20 * log10(max(amplitude, 1e-9))

        var match: Int?
        for index in candidates.indices where candidates[index].frequency > 0 {
            let distance = abs(candidates[index].frequency - frequency) / frequency
            if distance < 0.04 {
                match = index
                break
            }
        }

        if let index = match {
            candidates[index].missed = 0
            candidates[index].age += 1
            candidates[index].levelDB = levelDB
            candidates[index].frequency = candidates[index].frequency * 0.7 + frequency * 0.3

            let base = index * 8
            for slot in stride(from: 7, to: 0, by: -1) {
                history[base + slot] = history[base + slot - 1]
            }
            history[base] = levelDB

            let past = history[base + 5]
            // Ignore the first ~160 ms: an ordinary note also "grows" from
            // silence, while real feedback keeps rising after that.
            let growing = candidates[index].age >= 15 && levelDB - past > 2.0 && levelDB > -50
            let stuckHot = levelDB > -6 && candidates[index].age >= 60
            if growing || stuckHot {
                activate(frequency: candidates[index].frequency)
            }
        } else if let free = candidates.firstIndex(where: { $0.frequency == 0 }) {
            candidates[free].frequency = frequency
            candidates[free].levelDB = levelDB
            candidates[free].age = 1
            candidates[free].missed = 0
            let base = free * 8
            for slot in 0..<8 {
                history[base + slot] = levelDB
            }
        }
    }

    private func analyseHum(
        ring: UnsafeMutablePointer<Float>,
        frame: UnsafeMutablePointer<Float>,
        window: UnsafeMutablePointer<Float>
    ) {
        let size = Self.humWindowSize
        let mask = size - 1

        var energy = 0.0
        for index in 0..<size {
            let value = Double(ring[(humPosition + index) & mask])
            energy += value * value
        }
        let rms = sqrt(energy / Double(size))
        guard rms > 1e-5 else {
            humScore = 0
            if humActive { humActive = false }
            return
        }

        for index in 0..<size {
            frame[index] = ring[(humPosition + index) & mask] * window[index]
        }
        let amplitude50 = goertzel(frequency: 50, samples: frame, count: size)
        let amplitude60 = goertzel(frequency: 60, samples: frame, count: size)
        let amplitude = max(amplitude50, amplitude60)
        let mains = amplitude50 >= amplitude60 ? 50.0 : 60.0
        let ratio = amplitude / rms

        if amplitude > 0.0025, ratio > 0.25 {
            humScore = min(humScore + 1, 40)
        } else {
            humScore = max(humScore - 1, 0)
        }

        if humScore >= 20 {
            humActive = true
            for harmonic in 1...3 {
                activate(frequency: mains * Double(harmonic), quality: 40)
            }
        } else if humActive, humScore == 0 {
            humActive = false
        }
    }

    private func goertzel(
        frequency: Double,
        samples: UnsafeMutablePointer<Float>,
        count: Int
    ) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var previous = 0.0
        var older = 0.0
        for index in 0..<count {
            let current = Double(samples[index]) + coefficient * previous - older
            older = previous
            previous = current
        }
        let power = previous * previous + older * older - coefficient * previous * older
        return 4 * sqrt(max(power, 0)) / Double(count)
    }

    // MARK: - Notches

    private func activate(frequency: Double, quality: Double = 20) {
        guard frequency > 30, frequency < 12_000 else { return }

        for index in notches.indices where notches[index].target > 0 {
            let distance = abs(notches[index].frequency - frequency) / frequency
            if distance < 0.03 {
                notches[index].staleFrames = 0
                return
            }
        }

        let slot: Int
        if let free = notches.firstIndex(where: { $0.target == 0 && $0.mix < 0.01 }) {
            slot = free
        } else if let oldest = notches.indices.max(by: {
            notches[$0].staleFrames < notches[$1].staleFrames
        }) {
            slot = oldest
        } else {
            return
        }

        notches[slot].frequency = frequency
        notches[slot].coefficients = BiquadDesign.coefficients(
            shape: .notch,
            frequency: frequency,
            gainDB: 0,
            q: quality,
            sampleRate: sampleRate
        )
        notches[slot].stateLeft.reset()
        notches[slot].stateRight.reset()
        notches[slot].target = 1
        notches[slot].staleFrames = 0
    }

    // MARK: - Panic detector

    /// A howl is not a note: it keeps the same level and the same spectrum for
    /// as long as the loop stays above unity. That combination is what the
    /// panic detector looks for, and it mutes the input instead of trying to
    /// notch a broadband roar.
    private func updateStationarity(rmsDB: Double, flux: Double, dominantFrequency: Double) {
        guard let history = rmsHistory else { return }
        let index = rmsHistoryIndex
        let past = history[index]
        history[index] = rmsDB
        rmsHistoryIndex = (index + 1) % Self.rmsHistorySize
        rmsHistoryCount = min(rmsHistoryCount + 1, Self.rmsHistorySize)

        guard !panicMuted, rmsHistoryCount >= Self.rmsHistorySize else { return }

        let levelStable = abs(rmsDB - past) < 1.8
        let audible = rmsDB > -55 && outputLevel > 0.06
        let steadySpectrum = flux < 0.45
        // Acoustic feedback on a guitar rig lives above the fundamentals:
        // 2 kHz and up. A sustained low note is stationary too, but its
        // dominant peak is down where the instrument plays, so it is left
        // alone. This is the difference between "howling" and "holding a note".
        let highFrequencyHowl = dominantFrequency >= 2_000
        if levelStable, audible, steadySpectrum, highFrequencyHowl {
            stationaryScore += 1
        } else {
            stationaryScore = max(0, stationaryScore - 3)
        }

        if stationaryScore >= 45 {
            panicMuted = true
            stationaryScore = 0
            publish(force: true)
        }
    }

    private func consumeResetRequest() -> Bool {
        guard os_unfair_lock_trylock(resetLock) else { return false }
        let requested = resetRequested
        resetRequested = false
        os_unfair_lock_unlock(resetLock)
        return requested
    }

    // MARK: - State

    private func resetState() {
        ring?.update(repeating: 0, count: Self.analysisSize)
        humRing?.update(repeating: 0, count: Self.humWindowSize)
        frame?.update(repeating: 0, count: Self.analysisSize)
        humFrame?.update(repeating: 0, count: Self.humWindowSize)
        ringPosition = 0
        humPosition = 0
        sinceAnalysis = 0
        sinceHum = 0
        for index in candidates.indices {
            candidates[index] = Candidate()
        }
        for index in notches.indices {
            notches[index] = Notch()
        }
        candidateHistory?.update(repeating: -120, count: Self.maxCandidates * 8)
        rmsHistory?.update(repeating: -120, count: Self.rmsHistorySize)
        rmsHistoryIndex = 0
        rmsHistoryCount = 0
        previousMagnitudes?.update(repeating: 0, count: Self.analysisSize / 2 + 1)
        stationaryScore = 0
        panicMuted = false
        outputLevel = 0
        gain = 1
        nearClipFrames = 0
        humScore = 0
        humActive = false
        lastPublished = .idle
    }

    private func publish(force: Bool) {
        var status = FeedbackGuardStatus.idle
        if enabled {
            let active = notches.reduce(0) { $0 + ($1.mix > 0.5 ? 1 : 0) }
            let reduction = 20 * log10(max(gain, 1e-6))
            status = FeedbackGuardStatus(
                activeNotches: active,
                humDetected: humActive,
                gainReductionDB: (reduction * 10).rounded() / 10,
                muted: panicMuted
            )
        }
        guard force || status != lastPublished else { return }
        lastPublished = status
        meter.publish(status)
    }

    private func allocate(_ count: Int) -> UnsafeMutablePointer<Float> {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        pointer.initialize(repeating: 0, count: count)
        return pointer
    }

    private func deallocateBuffers() {
        window?.deallocate(); window = nil
        humWindow?.deallocate(); humWindow = nil
        ring?.deallocate(); ring = nil
        humRing?.deallocate(); humRing = nil
        frame?.deallocate(); frame = nil
        spectrumReal?.deallocate(); spectrumReal = nil
        spectrumImaginary?.deallocate(); spectrumImaginary = nil
        magnitudes?.deallocate(); magnitudes = nil
        humFrame?.deallocate(); humFrame = nil
        candidateHistory?.deallocate(); candidateHistory = nil
        rmsHistory?.deallocate(); rmsHistory = nil
        previousMagnitudes?.deallocate(); previousMagnitudes = nil
    }

    private struct Candidate {
        var frequency: Double = 0
        var levelDB: Double = -120
        var age: Int = 0
        var missed: Int = 0
    }

    private struct Notch {
        var frequency: Double = 0
        var mix: Double = 0
        var target: Double = 0
        var coefficients = BiquadCoefficients.identity
        var stateLeft = BiquadState()
        var stateRight = BiquadState()
        var staleFrames: Int = 0
    }
}
