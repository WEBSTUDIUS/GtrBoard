//  LimiterNode.swift
//  GtrBoard
//
//  Transparent look-ahead limiter on the output. It is always in the signal
//  path, so enabling/disabling it never changes latency or clicks.

import Foundation

final class LimiterNode {
    private var sampleRate: Double = 48_000
    private var delayL = DelayLine(maxSamples: 512)
    private var delayR = DelayLine(maxSamples: 512)
    private var lookahead = 72
    private var envelope: Double = 0
    private var gain: Double = 1
    private var release: Double = 0.999
    private var recovery: Double = 0.001
    private var enabled = true
    private let ceiling: Double = 0.95

    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        lookahead = min(500, max(16, Int(sampleRate * 0.0015)))
        delayL.resize(maxSamples: lookahead + 2)
        delayR.resize(maxSamples: lookahead + 2)
        release = exp(-1 / (0.090 * sampleRate))
        recovery = 1 - exp(-1 / (0.160 * sampleRate))
        reset()
    }

    func reset() {
        delayL.clear()
        delayR.clear()
        envelope = 0
        gain = 1
    }

    func setEnabled(_ value: Bool) {
        enabled = value
    }

    var latencyFrames: Int { lookahead }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        for frame in 0..<frames {
            let inL = left[frame]
            let inR = right[frame]
            delayL.write(inL)
            delayR.write(inR)

            let peak = max(abs(inL), abs(inR))
            envelope = max(peak, envelope * release)

            if enabled {
                let desired = envelope > ceiling ? ceiling / envelope : 1
                if desired < gain {
                    gain = desired
                } else {
                    gain += (desired - gain) * recovery
                }
            } else {
                gain += (1 - gain) * recovery
            }

            let delayedL = delayL.read(Double(lookahead))
            let delayedR = delayR.read(Double(lookahead))
            left[frame] = clampValue(delayedL * gain, -1, 1)
            right[frame] = clampValue(delayedR * gain, -1, 1)
        }
    }
}
