//  Amp.swift
//  GtrBoard
//
//  Valve preamp and speaker cabinet. The preamp has four voicings, a passive
//  tone-stack approximation and a small amount of power-supply sag; the
//  cabinet provides the low/high cut, the low resonance and the upper-mid
//  bite of a close-miked 4x12.

import Foundation

/// Four-voicing guitar preamp.
final class AmpNode: FXNode {
    let kind: FXKind = .amp

    private let oversampler = Oversampler4x()
    private var sampleRate: Double = 48_000

    private var preL = BiquadState(), preR = BiquadState()
    private var bassL = BiquadState(), bassR = BiquadState()
    private var midL = BiquadState(), midR = BiquadState()
    private var trebleL = BiquadState(), trebleR = BiquadState()
    private var presenceL = BiquadState(), presenceR = BiquadState()
    private var dcL = DCBlocker(), dcR = DCBlocker()

    private var preCoefficients = BiquadCoefficients.identity
    private var bassCoefficients = BiquadCoefficients.identity
    private var midCoefficients = BiquadCoefficients.identity
    private var trebleCoefficients = BiquadCoefficients.identity
    private var presenceCoefficients = BiquadCoefficients.identity

    private var gainDB: Double = 12
    private var bassDB: Double = 0
    private var midDB: Double = 0
    private var trebleDB: Double = 0
    private var presenceDB: Double = 3
    private var masterDB: Double = -8
    private var voicing: Int = 1

    private var master = Smoothed(0.4)
    private var preGain = Smoothed(1)
    private var sagEnvelope: Double = 0
    private var cachedSignature: Int = -1

    private let iGain = parameterIndex("gain", in: .amp)
    private let iBass = parameterIndex("bass", in: .amp)
    private let iMid = parameterIndex("mid", in: .amp)
    private let iTreble = parameterIndex("treble", in: .amp)
    private let iPresence = parameterIndex("presence", in: .amp)
    private let iMaster = parameterIndex("master", in: .amp)
    private let iVoicing = parameterIndex("voicing", in: .amp)

    /// Headroom offset per voicing. Clean stays clean at low gain, high gain
    /// saturates after a few millimetres of knob travel.
    private static let voicingBaseDB: [Double] = [-6, 8, 16, 24]

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        oversampler.prepare(maxFrames: maxFrames)
        reset()
        updateCoefficients(force: true)
    }

    func reset() {
        oversampler.reset()
        preL.reset(); preR.reset()
        bassL.reset(); bassR.reset()
        midL.reset(); midR.reset()
        trebleL.reset(); trebleR.reset()
        presenceL.reset(); presenceR.reset()
        dcL.reset(); dcR.reset()
        sagEnvelope = 0
        cachedSignature = -1
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        gainDB = parameterValue(values, iGain, count: count, fallback: 12)
        bassDB = parameterValue(values, iBass, count: count, fallback: 0)
        midDB = parameterValue(values, iMid, count: count, fallback: 0)
        trebleDB = parameterValue(values, iTreble, count: count, fallback: 0)
        presenceDB = parameterValue(values, iPresence, count: count, fallback: 3)
        masterDB = parameterValue(values, iMaster, count: count, fallback: -8)
        voicing = Int(parameterValue(values, iVoicing, count: count, fallback: 1).rounded())

        let base = AmpNode.voicingBaseDB[min(max(voicing, 0), 3)]
        preGain.set(dbToGain(gainDB + base) * 0.5)
        master.set(dbToGain(masterDB))
        updateCoefficients(force: false)
    }

    private func updateCoefficients(force: Bool) {
        let signature = Int(bassDB * 10) &* 31 &+ Int(midDB * 10) &* 131 &+ Int(trebleDB * 10) &* 613 &+ Int(presenceDB * 10)
        guard force || signature != cachedSignature else { return }
        cachedSignature = signature

        preCoefficients = BiquadDesign.coefficients(
            shape: .highPass, frequency: 65, gainDB: 0, q: 0.7, sampleRate: sampleRate
        )
        bassCoefficients = BiquadDesign.coefficients(
            shape: .lowShelf, frequency: 110, gainDB: bassDB, q: 0.72, sampleRate: sampleRate
        )
        midCoefficients = BiquadDesign.coefficients(
            shape: .peak, frequency: 650, gainDB: midDB, q: 0.75, sampleRate: sampleRate
        )
        trebleCoefficients = BiquadDesign.coefficients(
            shape: .highShelf, frequency: 3_000, gainDB: trebleDB, q: 0.72, sampleRate: sampleRate
        )
        presenceCoefficients = BiquadDesign.coefficients(
            shape: .highShelf, frequency: 6_500, gainDB: presenceDB, q: 0.7, sampleRate: sampleRate
        )
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        updateCoefficients(force: false)
        let drive = preGain.step(0.2)
        let output = master.step(0.2)
        let bias = voicing == 0 ? 0.02 : 0.10
        let biasOffset = tanh(bias)
        let sagAttack = 1 - exp(-1 / (0.004 * sampleRate))
        let sagRelease = 1 - exp(-1 / (0.180 * sampleRate))

        for frame in 0..<frames {
            left[frame] = preL.process(left[frame], preCoefficients)
            right[frame] = preR.process(right[frame], preCoefficients)
        }

        oversampler.upsample(left: left, right: right, frames: frames)
        let count = frames * 4
        for index in 0..<count {
            let l = oversampler.upLeft[index] * drive
            let r = oversampler.upRight[index] * drive
            let shapedL = tanh(l * 1.25 + bias) - biasOffset
            let shapedR = tanh(r * 1.25 + bias) - biasOffset
            oversampler.upLeft[index] = shapedL
            oversampler.upRight[index] = shapedR

            // Sag must follow the *normalised* (post-clip) signal: using the
            // driven value would collapse the gain by tens of dB at high gain
            // settings and make the amp quiet and squashed.
            let peak = max(abs(shapedL), abs(shapedR))
            if peak > sagEnvelope {
                sagEnvelope += (peak - sagEnvelope) * sagAttack
            } else {
                sagEnvelope += (peak - sagEnvelope) * sagRelease
            }
            let sag = 1 / (1 + sagEnvelope * 0.08)
            oversampler.upLeft[index] *= sag
            oversampler.upRight[index] *= sag
        }

        oversampler.downsample(left: left, right: right, frames: frames)

        for frame in 0..<frames {
            var l = dcL.process(left[frame])
            var r = dcR.process(right[frame])
            l = bassL.process(l, bassCoefficients)
            r = bassR.process(r, bassCoefficients)
            l = midL.process(l, midCoefficients)
            r = midR.process(r, midCoefficients)
            l = trebleL.process(l, trebleCoefficients)
            r = trebleR.process(r, trebleCoefficients)
            l = presenceL.process(l, presenceCoefficients)
            r = presenceR.process(r, presenceCoefficients)
            left[frame] = l * output
            right[frame] = r * output
        }
    }
}

/// Close-miked speaker simulation: 24 dB/octave low and high cut, a low
/// resonance and a fixed upper-mid presence lift.
final class CabinetNode: FXNode {
    let kind: FXKind = .cabinet

    private var sampleRate: Double = 48_000
    private var low1L = BiquadState(), low1R = BiquadState()
    private var low2L = BiquadState(), low2R = BiquadState()
    private var high1L = BiquadState(), high1R = BiquadState()
    private var high2L = BiquadState(), high2R = BiquadState()
    private var resonanceL = BiquadState(), resonanceR = BiquadState()
    private var presenceL = BiquadState(), presenceR = BiquadState()

    private var lowCutHz: Double = 80
    private var highCutHz: Double = 5_500
    private var resonanceDB: Double = 4

    private var lowCutCoefficients = BiquadCoefficients.identity
    private var highCutCoefficients = BiquadCoefficients.identity
    private var resonanceCoefficients = BiquadCoefficients.identity
    private var presenceCoefficients = BiquadCoefficients.identity
    private var cachedSignature: Int = -1

    private let iLow = parameterIndex("lowCut", in: .cabinet)
    private let iHigh = parameterIndex("highCut", in: .cabinet)
    private let iResonance = parameterIndex("resonance", in: .cabinet)

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        reset()
        updateCoefficients(force: true)
    }

    func reset() {
        low1L.reset(); low1R.reset()
        low2L.reset(); low2R.reset()
        high1L.reset(); high1R.reset()
        high2L.reset(); high2R.reset()
        resonanceL.reset(); resonanceR.reset()
        presenceL.reset(); presenceR.reset()
        cachedSignature = -1
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        lowCutHz = parameterValue(values, iLow, count: count, fallback: 80)
        highCutHz = parameterValue(values, iHigh, count: count, fallback: 5_500)
        resonanceDB = parameterValue(values, iResonance, count: count, fallback: 4)
        updateCoefficients(force: false)
    }

    private func updateCoefficients(force: Bool) {
        let signature = Int(lowCutHz) &* 31 &+ Int(highCutHz) &* 131 &+ Int(resonanceDB * 10)
        guard force || signature != cachedSignature else { return }
        cachedSignature = signature

        lowCutCoefficients = BiquadDesign.coefficients(
            shape: .highPass, frequency: lowCutHz, gainDB: 0, q: 0.707, sampleRate: sampleRate
        )
        highCutCoefficients = BiquadDesign.coefficients(
            shape: .lowPass, frequency: highCutHz, gainDB: 0, q: 0.707, sampleRate: sampleRate
        )
        resonanceCoefficients = BiquadDesign.coefficients(
            shape: .peak, frequency: 110, gainDB: resonanceDB, q: 1.1, sampleRate: sampleRate
        )
        presenceCoefficients = BiquadDesign.coefficients(
            shape: .peak, frequency: 2_600, gainDB: 1.8, q: 0.9, sampleRate: sampleRate
        )
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        updateCoefficients(force: false)
        for frame in 0..<frames {
            var l = low1L.process(left[frame], lowCutCoefficients)
            var r = low1R.process(right[frame], lowCutCoefficients)
            l = low2L.process(l, lowCutCoefficients)
            r = low2R.process(r, lowCutCoefficients)
            l = resonanceL.process(l, resonanceCoefficients)
            r = resonanceR.process(r, resonanceCoefficients)
            l = presenceL.process(l, presenceCoefficients)
            r = presenceR.process(r, presenceCoefficients)
            l = high1L.process(l, highCutCoefficients)
            r = high1R.process(r, highCutCoefficients)
            l = high2L.process(l, highCutCoefficients)
            r = high2R.process(r, highCutCoefficients)
            left[frame] = l
            right[frame] = r
        }
    }
}
