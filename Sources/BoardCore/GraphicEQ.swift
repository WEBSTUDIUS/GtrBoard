//  GraphicEQ.swift
//  GtrBoard
//
//  The ten-band graphic equalizer that closes the pedalboard, in the spirit
//  of the sliders on a hardware guitar board. It is implemented with ten
//  peaking RBJ biquads and lives at the end of the chain, right before the
//  master volume and the output limiter.

import Foundation

/// Ten-band ISO graphic equalizer state.
public struct GraphicEQSettings: Codable, Equatable, Sendable {
    /// Centre frequencies of the ten sliders.
    public static let frequencies: [Double] = [
        31.5, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    /// Short labels printed under the sliders.
    public static let labels: [String] = [
        "31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"
    ]

    /// Slider range in decibels.
    public static let range: ClosedRange<Double> = -12...12

    /// Q of each peaking band. 1.41 gives roughly one-octave-wide bands,
    /// matching the behaviour of classic ten-band hardware equalizers.
    public static let bandQ: Double = 1.41

    public var enabled: Bool
    /// Ten gains in decibels, one per frequency.
    public var gains: [Double]

    public init(enabled: Bool = true, gains: [Double] = Array(repeating: 0, count: 10)) {
        self.enabled = enabled
        self.gains = gains
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, gains
    }

    /// Tolerant decoder: a renamed or partially written preset still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let raw = try container.decodeIfPresent([Double].self, forKey: .gains) ?? []
        gains = GraphicEQSettings.sanitize(raw)
    }

    /// Pads/truncates to ten values and clamps them to the slider range.
    public static func sanitize(_ raw: [Double]) -> [Double] {
        var values = Array(raw.prefix(10))
        while values.count < 10 { values.append(0) }
        return values.map { $0.isFinite ? $0.clamped(to: range) : 0 }
    }

    public func sanitized() -> GraphicEQSettings {
        GraphicEQSettings(enabled: enabled, gains: Self.sanitize(gains))
    }

    /// All sliders at 0 dB.
    public static var flat: GraphicEQSettings { GraphicEQSettings() }

    public var isFlat: Bool {
        gains.allSatisfy { abs($0) < 0.01 }
    }

    /// Combined response of the enabled bands at a frequency.
    public func responseDB(at frequency: Double, sampleRate: Double) -> Double {
        guard enabled else { return 0 }
        var total = 0.0
        for (index, gain) in gains.enumerated() where abs(gain) > 0.001 {
            total += BiquadDesign.coefficients(
                shape: .peak,
                frequency: Self.frequencies[index],
                gainDB: gain,
                q: Self.bandQ,
                sampleRate: sampleRate
            ).magnitudeDB(at: frequency, sampleRate: sampleRate)
        }
        return total
    }
}
