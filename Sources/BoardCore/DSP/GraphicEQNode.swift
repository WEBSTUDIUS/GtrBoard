//  GraphicEQNode.swift
//  GtrBoard
//
//  Ten-band graphic equalizer at the end of the pedalboard. Coefficients are
//  interpolated per sample so dragging a slider sounds continuous and never
//  zippers.

import Foundation

final class GraphicEQNode {
    static let bandCount = 10
    private static let q = 1.41

    private var sampleRate: Double = 48_000
    private var states = [BiquadState](repeating: BiquadState(), count: GraphicEQNode.bandCount * 2)
    private var current = [BiquadCoefficients](repeating: .identity, count: GraphicEQNode.bandCount)
    private var target = [BiquadCoefficients](repeating: .identity, count: GraphicEQNode.bandCount)
    private var smoothing: Double = 0.002
    private var enabled = true
    private var gains = [Double](repeating: 0, count: GraphicEQNode.bandCount)

    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        smoothing = 1 - exp(-1 / (0.012 * sampleRate))
        reset()
    }

    func reset() {
        for index in 0..<(Self.bandCount * 2) {
            states[index].reset()
        }
        for index in 0..<Self.bandCount {
            current[index] = .identity
            target[index] = .identity
        }
    }

    /// Applies new gains and bypass state. Called on the audio thread while
    /// draining a settings snapshot; only preallocated storage is touched.
    func apply(gains newGains: UnsafePointer<Double>, enabled isEnabled: Bool) {
        enabled = isEnabled
        for index in 0..<Self.bandCount {
            let gain = newGains[index]
            gains[index] = gain.isFinite ? gain : 0
            if isEnabled {
                target[index] = BiquadDesign.coefficients(
                    shape: .peak,
                    frequency: GraphicEQSettings.frequencies[index],
                    gainDB: gains[index],
                    q: Self.q,
                    sampleRate: sampleRate
                )
            } else {
                target[index] = .identity
            }
        }
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        let step = smoothing
        for frame in 0..<frames {
            var l = left[frame]
            var r = right[frame]
            for band in 0..<Self.bandCount {
                let goal = target[band]
                var coefficients = current[band]
                coefficients.b0 += (goal.b0 - coefficients.b0) * step
                coefficients.b1 += (goal.b1 - coefficients.b1) * step
                coefficients.b2 += (goal.b2 - coefficients.b2) * step
                coefficients.a1 += (goal.a1 - coefficients.a1) * step
                coefficients.a2 += (goal.a2 - coefficients.a2) * step
                current[band] = coefficients

                l = states[band * 2].process(l, coefficients)
                r = states[band * 2 + 1].process(r, coefficients)
            }
            left[frame] = l
            right[frame] = r
        }
    }
}
