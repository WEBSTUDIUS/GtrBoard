//  Drive.swift
//  GtrBoard
//
//  The gain pedals: clean boost, Tube-Screamer-style overdrive, hard-clipping
//  distortion and a Big Muff-flavoured fuzz. All three clippers run inside a
//  4x oversampled loop; the tone network after the clipper is what gives each
//  pedal its own voice.
//
//  Design notes from the classic circuits:
//  * TS: high-pass around 720 Hz before clipping, symmetric soft clip, then a
//    low-pass tone control. That combination is the famous mid hump.
//  * Distortion: asymmetric/harder clipping with a wider, brighter tone range.
//  * Fuzz: two cascaded transistor-style stages and a passive tone blend
//    between a low-pass and a high-pass (the Big Muff mid scoop).

import Foundation

/// Transparent boost with a tilt EQ and a tightening high-pass.
final class BoostNode: FXNode {
    let kind: FXKind = .boost

    private var sampleRate: Double = 48_000
    private var tightL = BiquadState(), tightR = BiquadState()
    private var lowL = BiquadState(), lowR = BiquadState()
    private var highL = BiquadState(), highR = BiquadState()
    private var tightCoefficients = BiquadCoefficients.identity
    private var lowCoefficients = BiquadCoefficients.identity
    private var highCoefficients = BiquadCoefficients.identity

    private var gainDB: Double = 9
    private var toneDB: Double = 0
    private var tightHz: Double = 70
    private var gain = Smoothed(1)

    private let iGain = parameterIndex("gain", in: .boost)
    private let iTone = parameterIndex("tone", in: .boost)
    private let iTight = parameterIndex("tight", in: .boost)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
        updateCoefficients()
        gain = Smoothed(dbToGain(gainDB))
    }

    func reset() {
        tightL.reset(); tightR.reset()
        lowL.reset(); lowR.reset()
        highL.reset(); highR.reset()
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        gainDB = parameterValue(values, iGain, count: count, fallback: 9)
        toneDB = parameterValue(values, iTone, count: count, fallback: 0)
        tightHz = parameterValue(values, iTight, count: count, fallback: 70)
        gain.set(dbToGain(gainDB))
        updateCoefficients()
    }

    private func updateCoefficients() {
        tightCoefficients = BiquadDesign.coefficients(
            shape: .highPass, frequency: tightHz, gainDB: 0, q: 0.707, sampleRate: sampleRate
        )
        lowCoefficients = BiquadDesign.coefficients(
            shape: .lowShelf, frequency: 600, gainDB: -toneDB * 0.5, q: 0.7, sampleRate: sampleRate
        )
        highCoefficients = BiquadDesign.coefficients(
            shape: .highShelf, frequency: 2_600, gainDB: toneDB * 0.5, q: 0.7, sampleRate: sampleRate
        )
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let step = gain.step(0.2)
        for frame in 0..<frames {
            var l = tightL.process(left[frame], tightCoefficients)
            var r = tightR.process(right[frame], tightCoefficients)
            l = lowL.process(l, lowCoefficients)
            r = lowR.process(r, lowCoefficients)
            l = highL.process(l, highCoefficients)
            r = highR.process(r, highCoefficients)
            left[frame] = l * step
            right[frame] = r * step
        }
    }
}

/// One node covers overdrive, distortion and fuzz; the mode selects the
/// clipping curve and the tone network.
final class DriveNode: FXNode {
    let kind: FXKind

    private let oversampler = Oversampler4x()
    private var sampleRate: Double = 48_000

    private var preL = BiquadState(), preR = BiquadState()
    private var toneL = BiquadState(), toneR = BiquadState()
    private var tone2L = BiquadState(), tone2R = BiquadState()
    private var dcL = DCBlocker(), dcR = DCBlocker()
    private var preCoefficients = BiquadCoefficients.identity
    private var toneCoefficients = BiquadCoefficients.identity
    private var tone2Coefficients = BiquadCoefficients.identity

    private var gainDB: Double = 18
    private var tone: Double = 0.55
    private var levelDB: Double = -6
    private var extra: Double = 0.5
    private var gain = Smoothed(1)
    private var level = Smoothed(0.5)
    private var cachedPreHz: Double = 0
    private var cachedToneHz: Double = 0

    private let iGain: Int
    private let iTone: Int
    private let iLevel: Int
    private let iExtra: Int

    init(kind: FXKind) {
        self.kind = kind
        switch kind {
        case .overdrive:
            iGain = parameterIndex("drive", in: kind)
            iTone = parameterIndex("tone", in: kind)
            iLevel = parameterIndex("level", in: kind)
            iExtra = parameterIndex("mid", in: kind)
        case .distortion:
            iGain = parameterIndex("gain", in: kind)
            iTone = parameterIndex("tone", in: kind)
            iLevel = parameterIndex("level", in: kind)
            iExtra = parameterIndex("edge", in: kind)
        default:
            iGain = parameterIndex("sustain", in: kind)
            iTone = parameterIndex("tone", in: kind)
            iLevel = parameterIndex("level", in: kind)
            iExtra = parameterIndex("bias", in: kind)
        }
    }

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        oversampler.prepare(maxFrames: maxFrames)
        reset()
        updateCoefficients(force: true)
    }

    func reset() {
        oversampler.reset()
        preL.reset(); preR.reset()
        toneL.reset(); toneR.reset()
        tone2L.reset(); tone2R.reset()
        dcL.reset(); dcR.reset()
        cachedPreHz = 0
        cachedToneHz = 0
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        gainDB = parameterValue(values, iGain, count: count, fallback: 18)
        tone = parameterValue(values, iTone, count: count, fallback: 0.55)
        levelDB = parameterValue(values, iLevel, count: count, fallback: -6)
        extra = parameterValue(values, iExtra, count: count, fallback: 0.5)

        switch kind {
        case .overdrive:
            gain.set(dbToGain(gainDB) * 0.7)
        case .distortion:
            gain.set(dbToGain(gainDB))
        default:
            gain.set(dbToGain(16 + extra * 0) * dbToGain(gainDB * 42))
        }
        level.set(dbToGain(levelDB))
        updateCoefficients(force: false)
    }

    /// The fuzz uses `sustain` (0…1) rather than decibels; convert it before
    /// it reaches the clipper.
    private var effectiveGain: Double {
        kind == .fuzz ? dbToGain(16 + gainDB * 42) : gain.step(0.25)
    }

    private func updateCoefficients(force: Bool) {
        let preHz: Double
        let toneHz: Double
        switch kind {
        case .overdrive:
            preHz = 400 + extra * 560
            toneHz = 850 * pow(7.5, tone)
        case .distortion:
            preHz = 170
            toneHz = 650 * pow(9.0, tone)
        default:
            preHz = 55
            toneHz = 800
        }
        guard force || abs(preHz - cachedPreHz) > 0.5 || abs(toneHz - cachedToneHz) > 0.5 else { return }
        cachedPreHz = preHz
        cachedToneHz = toneHz

        preCoefficients = BiquadDesign.coefficients(
            shape: .highPass, frequency: preHz, gainDB: 0, q: 0.75, sampleRate: sampleRate
        )
        if kind == .fuzz {
            toneCoefficients = BiquadDesign.coefficients(
                shape: .lowPass, frequency: 800, gainDB: 0, q: 0.6, sampleRate: sampleRate
            )
            tone2Coefficients = BiquadDesign.coefficients(
                shape: .highPass, frequency: 800, gainDB: 0, q: 0.6, sampleRate: sampleRate
            )
        } else {
            toneCoefficients = BiquadDesign.coefficients(
                shape: .lowPass, frequency: toneHz, gainDB: 0, q: 0.72, sampleRate: sampleRate
            )
            tone2Coefficients = .identity
        }
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        updateCoefficients(force: false)
        let drive = effectiveGain
        let outputLevel = level.step(0.2)

        for frame in 0..<frames {
            left[frame] = preL.process(left[frame], preCoefficients)
            right[frame] = preR.process(right[frame], preCoefficients)
        }

        oversampler.upsample(left: left, right: right, frames: frames)
        let count = frames * 4

        switch kind {
        case .overdrive:
            for index in 0..<count {
                oversampler.upLeft[index] = tanh(oversampler.upLeft[index] * drive * 1.15)
                oversampler.upRight[index] = tanh(oversampler.upRight[index] * drive * 1.15)
            }

        case .distortion:
            let edge = clampValue(extra, 0, 1)
            for index in 0..<count {
                let l = oversampler.upLeft[index] * drive
                let r = oversampler.upRight[index] * drive
                let softL = tanh(l * 1.4)
                let softR = tanh(r * 1.4)
                let hardL = clampValue(l * 1.4, -1, 1)
                let hardR = clampValue(r * 1.4, -1, 1)
                oversampler.upLeft[index] = softL + (hardL - softL) * edge
                oversampler.upRight[index] = softR + (hardR - softR) * edge
            }

        default:
            let bias = (clampValue(extra, 0, 1) - 0.5) * 0.8
            let biasOffset = tanh(bias)
            for index in 0..<count {
                let l = oversampler.upLeft[index] * drive
                let r = oversampler.upRight[index] * drive
                let stage1L = tanh(l * 1.5 + bias) - biasOffset
                let stage1R = tanh(r * 1.5 + bias) - biasOffset
                oversampler.upLeft[index] = tanh(stage1L * 2.4 + bias * 0.5)
                oversampler.upRight[index] = tanh(stage1R * 2.4 + bias * 0.5)
            }
        }

        oversampler.downsample(left: left, right: right, frames: frames)

        for frame in 0..<frames {
            var l = dcL.process(left[frame])
            var r = dcR.process(right[frame])
            if kind == .fuzz {
                let lowL = toneL.process(l, toneCoefficients)
                let lowR = toneR.process(r, toneCoefficients)
                let highL = tone2L.process(l, tone2Coefficients)
                let highR = tone2R.process(r, tone2Coefficients)
                l = lowL * (1 - tone) + highL * tone
                r = lowR * (1 - tone) + highR * tone
                l *= 0.9
                r *= 0.9
            } else {
                l = toneL.process(l, toneCoefficients)
                r = toneR.process(r, toneCoefficients)
            }
            left[frame] = l * outputLevel
            right[frame] = r * outputLevel
        }
    }
}
