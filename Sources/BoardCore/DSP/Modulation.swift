//  Modulation.swift
//  GtrBoard
//
//  Chorus, flanger, phaser and tremolo. All four share a low-frequency
//  oscillator but use it differently: delay modulation (chorus/flanger),
//  all-pass frequency sweep (phaser) and amplitude modulation (tremolo).

import Foundation

/// Analog-style chorus with two delayed voices and a stereo LFO offset.
final class ChorusNode: FXNode {
    let kind: FXKind = .chorus

    private var sampleRate: Double = 48_000
    private let delayL = DelayLine(maxSamples: 24_000)
    private let delayR = DelayLine(maxSamples: 24_000)
    private var lfoL = LFO(phase: 0)
    private var lfoR = LFO(phase: 0)

    private var rate: Double = 0.8
    private var depth: Double = 0.5
    private var mix: Double = 0.4
    private var width: Double = 0.7
    private var mixValue = Smoothed(0.4)
    private var depthValue = Smoothed(0.5)

    private let iRate = parameterIndex("rate", in: .chorus)
    private let iDepth = parameterIndex("depth", in: .chorus)
    private let iMix = parameterIndex("mix", in: .chorus)
    private let iWidth = parameterIndex("width", in: .chorus)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        delayL.resize(maxSamples: Int(sampleRate * 0.08))
        delayR.resize(maxSamples: Int(sampleRate * 0.08))
        reset()
    }

    func reset() {
        delayL.clear()
        delayR.clear()
        lfoL = LFO(phase: 0)
        lfoR = LFO(phase: 0.25)
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        rate = parameterValue(values, iRate, count: count, fallback: 0.8)
        depth = parameterValue(values, iDepth, count: count, fallback: 0.5)
        mix = parameterValue(values, iMix, count: count, fallback: 0.4)
        width = parameterValue(values, iWidth, count: count, fallback: 0.7)
        mixValue.set(mix)
        depthValue.set(depth)
        lfoR.phase = lfoL.phase + width * 0.5
        if lfoR.phase >= 1 { lfoR.phase -= 1 }
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let baseMS = 13.0
        let depthMS = depthValue.step(0.15) * 8.0
        let wet = mixValue.step(0.15)
        let spreadMS = width * 1.2

        for frame in 0..<frames {
            lfoL.advance(rate: rate, sampleRate: sampleRate)
            lfoR.advance(rate: rate, sampleRate: sampleRate)

            let modL = lfoL.value(shape: 0)
            let modR = lfoR.value(shape: 0)
            let delaySamplesL = (baseMS + depthMS * modL) * 0.001 * sampleRate
            let delaySamplesR = (baseMS + spreadMS + depthMS * modR) * 0.001 * sampleRate

            let dryL = left[frame]
            let dryR = right[frame]
            delayL.write(dryL)
            delayR.write(dryR)
            let wetL = delayL.read(delaySamplesL)
            let wetR = delayR.read(delaySamplesR)

            left[frame] = dryL * (1 - wet * 0.5) + wetL * wet * 0.9
            right[frame] = dryR * (1 - wet * 0.5) + wetR * wet * 0.9
        }
    }
}

/// Feedback flanger: a very short modulated delay with a resonant comb.
final class FlangerNode: FXNode {
    let kind: FXKind = .flanger

    private var sampleRate: Double = 48_000
    private let delayL = DelayLine(maxSamples: 24_000)
    private let delayR = DelayLine(maxSamples: 24_000)
    private var lfoL = LFO(phase: 0)
    private var lfoR = LFO(phase: 0.25)

    private var rate: Double = 0.25
    private var depth: Double = 0.6
    private var feedback: Double = 0.35
    private var mix: Double = 0.5
    private var manualMS: Double = 2.5
    private var mixValue = Smoothed(0.5)

    private let iRate = parameterIndex("rate", in: .flanger)
    private let iDepth = parameterIndex("depth", in: .flanger)
    private let iFeedback = parameterIndex("feedback", in: .flanger)
    private let iMix = parameterIndex("mix", in: .flanger)
    private let iManual = parameterIndex("manual", in: .flanger)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        delayL.resize(maxSamples: Int(sampleRate * 0.04))
        delayR.resize(maxSamples: Int(sampleRate * 0.04))
        reset()
    }

    func reset() {
        delayL.clear()
        delayR.clear()
        lfoL = LFO(phase: 0)
        lfoR = LFO(phase: 0.25)
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        rate = parameterValue(values, iRate, count: count, fallback: 0.25)
        depth = parameterValue(values, iDepth, count: count, fallback: 0.6)
        feedback = parameterValue(values, iFeedback, count: count, fallback: 0.35)
        mix = parameterValue(values, iMix, count: count, fallback: 0.5)
        manualMS = parameterValue(values, iManual, count: count, fallback: 2.5)
        mixValue.set(mix)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let wet = mixValue.step(0.2)
        let base = manualMS * 0.001 * sampleRate
        let sweep = depth * manualMS * 0.9 * 0.001 * sampleRate
        let fb = clampValue(feedback, -0.95, 0.95)

        for frame in 0..<frames {
            lfoL.advance(rate: rate, sampleRate: sampleRate)
            lfoR.advance(rate: rate, sampleRate: sampleRate)

            let modL = lfoL.value(shape: 0)
            let modR = lfoR.value(shape: 0)
            let delayedL = delayL.read(base + sweep * (modL + 1) * 0.5)
            let delayedR = delayR.read(base + sweep * (modR + 1) * 0.5)

            let dryL = left[frame]
            let dryR = right[frame]
            delayL.write(dryL + delayedL * fb)
            delayR.write(dryR + delayedR * fb)

            left[frame] = dryL * (1 - wet * 0.5) + delayedL * wet
            right[frame] = dryR * (1 - wet * 0.5) + delayedR * wet
        }
    }
}

/// JFET-style phaser with four to twelve modulated all-pass stages.
final class PhaserNode: FXNode {
    let kind: FXKind = .phaser

    private static let maxStages = 12
    private var sampleRate: Double = 48_000
    private var x1L = [Double](repeating: 0, count: PhaserNode.maxStages)
    private var x1R = [Double](repeating: 0, count: PhaserNode.maxStages)
    private var y1L = [Double](repeating: 0, count: PhaserNode.maxStages)
    private var y1R = [Double](repeating: 0, count: PhaserNode.maxStages)
    private var lfoL = LFO(phase: 0)
    private var lfoR = LFO(phase: 0.25)

    private var rate: Double = 0.35
    private var depth: Double = 0.6
    private var feedback: Double = 0.3
    private var mix: Double = 0.5
    private var stages: Int = 6
    private var mixValue = Smoothed(0.5)

    private let iRate = parameterIndex("rate", in: .phaser)
    private let iDepth = parameterIndex("depth", in: .phaser)
    private let iFeedback = parameterIndex("feedback", in: .phaser)
    private let iMix = parameterIndex("mix", in: .phaser)
    private let iStages = parameterIndex("stages", in: .phaser)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
    }

    func reset() {
        for index in 0..<PhaserNode.maxStages {
            x1L[index] = 0; x1R[index] = 0
            y1L[index] = 0; y1R[index] = 0
        }
        lfoL = LFO(phase: 0)
        lfoR = LFO(phase: 0.25)
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        rate = parameterValue(values, iRate, count: count, fallback: 0.35)
        depth = parameterValue(values, iDepth, count: count, fallback: 0.6)
        feedback = parameterValue(values, iFeedback, count: count, fallback: 0.3)
        mix = parameterValue(values, iMix, count: count, fallback: 0.5)
        let stageChoice = Int(parameterValue(values, iStages, count: count, fallback: 1).rounded())
        stages = [4, 6, 8, 12][min(max(stageChoice, 0), 3)]
        mixValue.set(mix)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let wet = mixValue.step(0.2)
        let fb = clampValue(feedback, 0, 0.9)

        for frame in 0..<frames {
            lfoL.advance(rate: rate, sampleRate: sampleRate)
            lfoR.advance(rate: rate, sampleRate: sampleRate)

            let sweepL = 500 * pow(2, depth * lfoL.value(shape: 0) * 1.8)
            let sweepR = 500 * pow(2, depth * lfoR.value(shape: 0) * 1.8)
            let aL = PhaserNode.allpassCoefficient(frequency: sweepL, sampleRate: sampleRate)
            let aR = PhaserNode.allpassCoefficient(frequency: sweepR, sampleRate: sampleRate)

            let dryL = left[frame]
            let dryR = right[frame]
            var stageL = dryL + y1L[stages - 1] * fb
            var stageR = dryR + y1R[stages - 1] * fb

            for stage in 0..<stages {
                let outputL = aL * stageL + x1L[stage] - aL * y1L[stage]
                x1L[stage] = stageL
                y1L[stage] = outputL
                stageL = outputL

                let outputR = aR * stageR + x1R[stage] - aR * y1R[stage]
                x1R[stage] = stageR
                y1R[stage] = outputR
                stageR = outputR
            }

            left[frame] = dryL * (1 - wet * 0.5) + stageL * wet
            right[frame] = dryR * (1 - wet * 0.5) + stageR * wet
        }
    }

    @inline(__always)
    private static func allpassCoefficient(frequency: Double, sampleRate: Double) -> Double {
        let f = clampValue(frequency, 40, sampleRate * 0.42)
        let t = tan(Double.pi * f / sampleRate)
        return (1 - t) / (1 + t)
    }
}

/// Amplitude tremolo with sine/triangle/square shapes and stereo phase.
final class TremoloNode: FXNode {
    let kind: FXKind = .tremolo

    private var sampleRate: Double = 48_000
    private var lfoL = LFO(phase: 0)
    private var lfoR = LFO(phase: 0)

    private var rate: Double = 4.5
    private var depth: Double = 0.6
    private var shape: Int = 0
    private var stereo: Double = 0

    private let iRate = parameterIndex("rate", in: .tremolo)
    private let iDepth = parameterIndex("depth", in: .tremolo)
    private let iShape = parameterIndex("shape", in: .tremolo)
    private let iStereo = parameterIndex("stereo", in: .tremolo)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
    }

    func reset() {
        lfoL = LFO(phase: 0)
        lfoR = LFO(phase: 0)
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        rate = parameterValue(values, iRate, count: count, fallback: 4.5)
        depth = parameterValue(values, iDepth, count: count, fallback: 0.6)
        shape = Int(parameterValue(values, iShape, count: count, fallback: 0).rounded())
        stereo = parameterValue(values, iStereo, count: count, fallback: 0)
        lfoR.phase = lfoL.phase + stereo * 0.5
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let amount = clampValue(depth, 0, 1)
        for frame in 0..<frames {
            lfoL.advance(rate: rate, sampleRate: sampleRate)
            lfoR.advance(rate: rate, sampleRate: sampleRate)
            let gainL = 1 - amount * (0.5 - 0.5 * lfoL.value(shape: shape))
            let gainR = 1 - amount * (0.5 - 0.5 * lfoR.value(shape: shape))
            left[frame] *= gainL
            right[frame] *= gainR
        }
    }
}
