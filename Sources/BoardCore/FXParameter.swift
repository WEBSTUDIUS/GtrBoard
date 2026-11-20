//  FXParameter.swift
//  GtrBoard
//
//  Declarative parameter metadata shared by the DSP, the preset format and
//  the interface. Every knob in the app is generated from a descriptor, so a
//  new parameter automatically appears in the UI and in saved presets.

import Foundation

/// Unit shown next to a parameter value. The unit also decides how the value
/// is formatted and how a 0…1 knob position maps back to the real value.
public enum ParameterUnit: String, Codable, Sendable {
    case decibels
    case hertz
    case milliseconds
    case percent
    case ratio
    case choice

    /// Suffix appended to a formatted value, when there is one.
    public var suffix: String? {
        switch self {
        case .decibels: return "dB"
        case .hertz: return nil
        case .milliseconds: return "ms"
        case .percent: return "%"
        case .ratio: return nil
        case .choice: return nil
        }
    }
}

/// Metadata for one knob. `id` is the stable key used by presets and by the
/// DSP, `name` is the label, and the range/default pair keeps every layer of
/// the app honest about what values are allowed.
public struct FXParameter: Identifiable, Codable, Equatable, Sendable {
    /// Stable key, e.g. `drive`, `tone`, `level`.
    public var id: String
    /// Short human label, e.g. `Drive`.
    public var name: String
    public var minValue: Double
    public var maxValue: Double
    public var defaultValue: Double
    public var unit: ParameterUnit
    /// Logarithmic knob travel. Only valid when `minValue > 0`.
    public var logarithmic: Bool
    /// Non-empty for stepped controls. Values are stored as 0…count-1.
    public var choices: [String]

    public init(
        id: String,
        name: String,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        unit: ParameterUnit = .percent,
        logarithmic: Bool = false,
        choices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.unit = unit
        self.logarithmic = logarithmic
        self.choices = choices
    }

    /// True for switches such as the amp voicing selector.
    public var isStepped: Bool { !choices.isEmpty }

    /// Clamps a value into the declared range.
    public func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        let clamped = min(max(value, minValue), maxValue)
        if isStepped {
            return (clamped).rounded()
        }
        return clamped
    }

    /// Knob position (0…1) for a real value.
    public func normalized(_ value: Double) -> Double {
        let value = clamp(value)
        if isStepped {
            let span = max(1, Double(choices.count - 1))
            return ((value - minValue) / span).clamped(to: 0...1)
        }
        guard maxValue > minValue else { return 0 }
        if logarithmic, minValue > 0, value > 0 {
            return (log(value / minValue) / log(maxValue / minValue)).clamped(to: 0...1)
        }
        return ((value - minValue) / (maxValue - minValue)).clamped(to: 0...1)
    }

    /// Real value for a 0…1 knob position.
    public func value(atNormalized position: Double) -> Double {
        let position = position.clamped(to: 0...1)
        if isStepped {
            let span = max(1, Double(choices.count - 1))
            return clamp(minValue + (span * position).rounded())
        }
        if logarithmic, minValue > 0 {
            let value = minValue * pow(maxValue / minValue, position)
            return clamp(value)
        }
        return clamp(minValue + position * (maxValue - minValue))
    }

    /// Human readable value, e.g. `+3.5 dB`, `1.20 kHz`, `68 %`.
    public func display(_ value: Double) -> String {
        let value = clamp(value)
        if isStepped {
            let index = Int(value.rounded()).clamped(to: 0...(choices.count - 1))
            return choices[index]
        }
        switch unit {
        case .decibels:
            if abs(value) < 0.05 { return "0.0 dB" }
            return String(format: "%+.1f dB", value)
        case .hertz:
            if value >= 1_000 {
                return String(format: "%.2f kHz", value / 1_000)
            }
            if value < 10 {
                return String(format: "%.2f Hz", value)
            }
            return String(format: "%.0f Hz", value)
        case .milliseconds:
            return String(format: "%.0f ms", value)
        case .percent:
            if minValue < 0 {
                return String(format: "%+.0f%%", value * 100)
            }
            return String(format: "%.0f%%", value * 100)
        case .ratio:
            return String(format: "%.1f:1", value)
        case .choice:
            return String(format: "%.0f", value)
        }
    }

    /// Compact value used under a knob.
    public func shortDisplay(_ value: Double) -> String {
        if isStepped {
            let index = Int(clamp(value).rounded()).clamped(to: 0...(choices.count - 1))
            return choices[index]
        }
        switch unit {
        case .decibels:
            return String(format: "%+.1f", value)
        case .hertz:
            if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
            return String(format: "%.0f", value)
        case .milliseconds:
            return String(format: "%.0f", value)
        case .percent:
            return String(format: "%.0f", value * 100)
        case .ratio:
            return String(format: "%.1f", value)
        case .choice:
            return String(format: "%.0f", value)
        }
    }

    /// Default value used when a preset predates this parameter.
    public var fallback: Double { clamp(defaultValue) }
}

public extension Comparable {
    /// Clamps into a closed range. Shared by the UI, importer and DSP.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
