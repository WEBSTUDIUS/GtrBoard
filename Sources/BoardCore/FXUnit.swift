//  FXUnit.swift
//  GtrBoard
//
//  One pedal on the board: kind, bypass state and parameter values. Values
//  are stored as real units (dB, Hz, ms, 0…1) and are clamped on every load
//  so presets from an older version can never produce an unsafe DSP value.

import Foundation

/// A single pedal instance.
public struct FXUnit: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: FXKind
    public var enabled: Bool
    /// Real-unit values keyed by ``FXParameter/id``.
    public var params: [String: Double]

    public init(
        id: UUID = UUID(),
        kind: FXKind,
        enabled: Bool? = nil,
        params: [String: Double] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.enabled = enabled ?? kind.descriptor.defaultEnabled
        // A unit is always born complete: every knob has a value, so preset
        // equality and JSON round-trips do not depend on which knobs were
        // explicitly touched.
        self.params = FXUnit.sanitizedParams(params, for: kind)
    }

    public var descriptor: FXDescriptor { kind.descriptor }

    private enum CodingKeys: String, CodingKey {
        case id, kind, enabled, params
    }

    /// Tolerant decoder: missing bypass state and missing parameters fall
    /// back to descriptor defaults, so older presets keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(FXKind.self, forKey: .kind)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? kind.descriptor.defaultEnabled
        let raw = try container.decodeIfPresent([String: Double].self, forKey: .params) ?? [:]
        params = FXUnit.sanitizedParams(raw, for: kind)
    }

    /// Real value for a parameter, or the descriptor default.
    public func value(_ id: String) -> Double {
        guard let parameter = descriptor.parameter(id) else { return 0 }
        return parameter.clamp(params[id] ?? parameter.fallback)
    }

    /// Knob position (0…1) for a parameter.
    public func normalizedValue(_ id: String) -> Double {
        guard let parameter = descriptor.parameter(id) else { return 0 }
        return parameter.normalized(self.value(id))
    }

    /// Sets a real-unit value, clamped to the descriptor range.
    public mutating func setValue(_ value: Double, for id: String) {
        guard let parameter = descriptor.parameter(id) else { return }
        params[id] = parameter.clamp(value)
    }

    /// Sets a value from a 0…1 knob position.
    public mutating func setNormalizedValue(_ position: Double, for id: String) {
        guard let parameter = descriptor.parameter(id) else { return }
        params[id] = parameter.value(atNormalized: position)
    }

    /// Restores one parameter to its factory default.
    public mutating func resetValue(_ id: String) {
        guard let parameter = descriptor.parameter(id) else { return }
        params[id] = parameter.fallback
    }

    /// Fully valid copy: every descriptor parameter present, clamped, and no
    /// unknown keys. This is the only form the renderer and store use.
    public func sanitized() -> FXUnit {
        var copy = self
        copy.params = FXUnit.sanitizedParams(params, for: kind)
        return copy
    }

    private static func sanitizedParams(_ raw: [String: Double], for kind: FXKind) -> [String: Double] {
        var clean: [String: Double] = [:]
        for parameter in kind.descriptor.parameters {
            clean[parameter.id] = parameter.clamp(raw[parameter.id] ?? parameter.fallback)
        }
        return clean
    }

    /// Parameters in descriptor order; used by the DSP snapshot.
    public var orderedValues: [Double] {
        descriptor.parameters.map { value($0.id) }
    }

    /// True when every knob is at its factory default.
    public var isDefault: Bool {
        descriptor.parameters.allSatisfy { abs(value($0.id) - $0.fallback) < 1e-9 }
    }
}
