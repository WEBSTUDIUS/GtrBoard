//  Dynamics.swift
//  GtrBoard
//
//  Noise gate and compressor. Both are stereo-linked, use a peak detector and
//  smooth their gain so the guitar never clicks when a threshold is crossed.

import Foundation

/// Hysteresis noise gate. `Decay` doubles as the hold/release time and
/// `Range` sets how far down the signal is pushed when the gate closes.
final class GateNode: FXNode {
    let kind: FXKind = .gate

    private var sampleRate: Double = 48_000
    private var envelope: Double = 0
    private var gain: Double = 1
    private var hold: Int = 0

    private var thresholdDB: Double = -60
    private var decayMS: Double = 180
    private var rangeDB: Double = 60

    private let iThreshold = parameterIndex("threshold", in: .gate)
    private let iDecay = parameterIndex("decay", in: .gate)
    private let iRange = parameterIndex("range", in: .gate)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
    }

    func reset() {
        envelope = 0
        gain = 1
        hold = 0
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        thresholdDB = parameterValue(values, iThreshold, count: count, fallback: -60)
        decayMS = parameterValue(values, iDecay, count: count, fallback: 180)
        rangeDB = parameterValue(values, iRange, count: count, fallback: 60)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let threshold = dbToGain(thresholdDB)
        let floorGain = dbToGain(-max(0, rangeDB))
        let attack = 1 - exp(-1 / (0.0008 * sampleRate))
        let release = 1 - exp(-1 / (0.120 * sampleRate))
        let openStep = 1 - exp(-1 / (0.002 * sampleRate))
        let closeStep = 1 - exp(-1 / (0.020 * sampleRate))
        let holdFrames = Int(max(0, decayMS) * 0.001 * sampleRate * 0.35)

        for frame in 0..<frames {
            let peak = max(abs(left[frame]), abs(right[frame]))
            if peak > envelope {
                envelope += (peak - envelope) * attack
            } else {
                envelope += (peak - envelope) * release
            }

            if envelope > threshold {
                hold = holdFrames
            } else if hold > 0 {
                hold -= 1
            }

            let open = envelope > threshold || hold > 0
            let target = open ? 1.0 : floorGain
            let step = open ? openStep : closeStep
            gain += (target - gain) * step

            left[frame] *= gain
            right[frame] *= gain
        }
    }
}

/// Feed-forward compressor with a soft knee. The detector is peak based and
/// stereo linked, which is what makes a guitar comp feel stable on chords.
final class CompressorNode: FXNode {
    let kind: FXKind = .compressor

    private var sampleRate: Double = 48_000
    private var envelope: Double = 0
    private var gain: Double = 1

    private var thresholdDB: Double = -24
    private var ratio: Double = 4
    private var attackMS: Double = 10
    private var releaseMS: Double = 180
    private var makeupDB: Double = 6

    private let iThreshold = parameterIndex("threshold", in: .compressor)
    private let iRatio = parameterIndex("ratio", in: .compressor)
    private let iAttack = parameterIndex("attack", in: .compressor)
    private let iRelease = parameterIndex("release", in: .compressor)
    private let iMakeup = parameterIndex("makeup", in: .compressor)

    private let knee: Double = 6

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
    }

    func reset() {
        envelope = 0
        gain = 1
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        thresholdDB = parameterValue(values, iThreshold, count: count, fallback: -24)
        ratio = max(1, parameterValue(values, iRatio, count: count, fallback: 4))
        attackMS = parameterValue(values, iAttack, count: count, fallback: 10)
        releaseMS = parameterValue(values, iRelease, count: count, fallback: 180)
        makeupDB = parameterValue(values, iMakeup, count: count, fallback: 6)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let attack = 1 - exp(-1 / (max(0.2, attackMS) * 0.001 * sampleRate))
        let release = 1 - exp(-1 / (max(5, releaseMS) * 0.001 * sampleRate))
        let makeup = dbToGain(makeupDB)
        let slope = 1 - 1 / max(1, ratio)
        let kneeHalf = knee / 2

        for frame in 0..<frames {
            let peak = max(abs(left[frame]), abs(right[frame]))
            if peak > envelope {
                envelope += (peak - envelope) * attack
            } else {
                envelope += (peak - envelope) * release
            }

            let levelDB = gainToDB(envelope)
            var reduction = 0.0
            let over = levelDB - thresholdDB
            if over > kneeHalf {
                reduction = over * slope
            } else if over > -kneeHalf {
                let t = over + kneeHalf
                reduction = slope * t * t / (2 * knee)
            }

            let target = dbToGain(-reduction) * makeup
            gain += (target - gain) * 0.4

            left[frame] *= gain
            right[frame] *= gain
        }
    }
}
