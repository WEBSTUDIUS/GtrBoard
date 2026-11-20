//  Time.swift
//  GtrBoard
//
//  Delay and reverb. The delay has digital, analog and ping-pong modes with
//  a filtered feedback path; the reverb is a Freeverb-style network with a
//  pre-delay and room/hall/plate voicings.

import Foundation

/// Stereo delay with a smoothed time control, filtered feedback and an
/// optional cross-feedback ping-pong mode.
final class DelayNode: FXNode {
    let kind: FXKind = .delay

    private var sampleRate: Double = 48_000
    private let delayL = DelayLine(maxSamples: 110_000)
    private let delayR = DelayLine(maxSamples: 110_000)
    private var lowPassL = OnePoleLowPass()
    private var lowPassR = OnePoleLowPass()
    private var lfo = LFO(phase: 0)

    private var timeMS: Double = 380
    private var feedback: Double = 0.35
    private var mix: Double = 0.3
    private var tone: Double = 0.55
    private var mode: Int = 1

    private var currentDelay: Double = 0
    private var targetDelay: Double = 0
    private var mixValue = Smoothed(0.3)
    private var hasRendered = false

    private let iTime = parameterIndex("time", in: .delay)
    private let iFeedback = parameterIndex("feedback", in: .delay)
    private let iMix = parameterIndex("mix", in: .delay)
    private let iTone = parameterIndex("tone", in: .delay)
    private let iMode = parameterIndex("mode", in: .delay)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        delayL.resize(maxSamples: Int(sampleRate * 2.2))
        delayR.resize(maxSamples: Int(sampleRate * 2.2))
        reset()
    }

    func reset() {
        delayL.clear()
        delayR.clear()
        lowPassL.reset()
        lowPassR.reset()
        lfo = LFO(phase: 0)
        currentDelay = timeMS * 0.001 * sampleRate
        targetDelay = currentDelay
        hasRendered = false
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        timeMS = parameterValue(values, iTime, count: count, fallback: 380)
        feedback = parameterValue(values, iFeedback, count: count, fallback: 0.35)
        mix = parameterValue(values, iMix, count: count, fallback: 0.3)
        tone = parameterValue(values, iTone, count: count, fallback: 0.55)
        mode = Int(parameterValue(values, iMode, count: count, fallback: 1).rounded())
        targetDelay = timeMS * 0.001 * sampleRate
        if currentDelay < 1 || !hasRendered { currentDelay = targetDelay }
        mixValue.set(mix)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let wet = mixValue.step(0.2)
        let fb = clampValue(feedback, 0, 0.95)
        let cutoff = 700 * pow(16, clampValue(tone, 0, 1))
        lowPassL.setCutoff(cutoff, sampleRate: sampleRate)
        lowPassR.setCutoff(cutoff, sampleRate: sampleRate)
        hasRendered = true
        let isPingPong = mode == 2
        let modulation = mode == 1 ? 0.00012 * sampleRate : 0

        for frame in 0..<frames {
            currentDelay += (targetDelay - currentDelay) * 0.0006
            lfo.advance(rate: 0.33, sampleRate: sampleRate)
            let wobble = modulation * lfo.value(shape: 0)
            let delay = currentDelay + wobble

            let delayedL = delayL.read(delay)
            let delayedR = delayR.read(delay)
            let filteredL = lowPassL.process(delayedL)
            let filteredR = lowPassR.process(delayedR)

            let dryL = left[frame]
            let dryR = right[frame]

            if isPingPong {
                delayL.write(dryL + filteredR * fb)
                delayR.write(dryR + filteredL * fb)
            } else {
                delayL.write(dryL + filteredL * fb)
                delayR.write(dryR + filteredR * fb)
            }

            let echoL = mode == 0 ? delayedL : filteredL
            let echoR = mode == 0 ? delayedR : filteredR
            left[frame] = dryL * (1 - wet * 0.5) + echoL * wet
            right[frame] = dryR * (1 - wet * 0.5) + echoR * wet
        }
    }
}

/// Freeverb-derived stereo reverb with a pre-delay and three voicings.
final class ReverbNode: FXNode {
    let kind: FXKind = .reverb

    private var sampleRate: Double = 48_000
    private let preDelayL = DelayLine(maxSamples: 24_000)
    private let preDelayR = DelayLine(maxSamples: 24_000)
    private let core = ReverbCore()
    private var coreSampleRate: Double = 0

    private var size: Double = 0.55
    private var damping: Double = 0.45
    private var mix: Double = 0.22
    private var preDelayMS: Double = 20
    private var mode: Int = 1
    private var mixValue = Smoothed(0.22)

    private let iSize = parameterIndex("size", in: .reverb)
    private let iDamping = parameterIndex("damping", in: .reverb)
    private let iMix = parameterIndex("mix", in: .reverb)
    private let iPredelay = parameterIndex("predelay", in: .reverb)
    private let iMode = parameterIndex("mode", in: .reverb)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        preDelayL.resize(maxSamples: Int(sampleRate * 0.15))
        preDelayR.resize(maxSamples: Int(sampleRate * 0.15))
        if abs(sampleRate - coreSampleRate) > 0.5 {
            core.prepare(sampleRate: sampleRate)
            coreSampleRate = sampleRate
        }
        reset()
    }

    func reset() {
        preDelayL.clear()
        preDelayR.clear()
        core.clear()
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        size = parameterValue(values, iSize, count: count, fallback: 0.55)
        damping = parameterValue(values, iDamping, count: count, fallback: 0.45)
        mix = parameterValue(values, iMix, count: count, fallback: 0.22)
        preDelayMS = parameterValue(values, iPredelay, count: count, fallback: 20)
        mode = Int(parameterValue(values, iMode, count: count, fallback: 1).rounded())
        mixValue.set(mix)
    }

    private var feedback: Double {
        let base: Double
        switch mode {
        case 0: base = 0.86    // Room
        case 2: base = 0.91    // Plate
        default: base = 0.89   // Hall
        }
        return clampValue(base + clampValue(size, 0, 1) * 0.06, 0.7, 0.975)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let wet = mixValue.step(0.2)
        let delaySamples = clampValue(preDelayMS, 0, 120) * 0.001 * sampleRate
        let fb = feedback
        let damp = clampValue(damping, 0, 1)
        let sizeValue = clampValue(size, 0, 1)

        for frame in 0..<frames {
            let dryL = left[frame]
            let dryR = right[frame]
            let preL = preDelayL.read(delaySamples)
            let preR = preDelayR.read(delaySamples)
            preDelayL.write(dryL)
            preDelayR.write(dryR)

            let (wetL, wetR) = core.process(
                left: preL,
                right: preR,
                size: sizeValue,
                damping: damp,
                feedback: fb
            )
            left[frame] = dryL * (1 - wet) + wetL * wet
            right[frame] = dryR * (1 - wet) + wetR * wet
        }
    }
}
