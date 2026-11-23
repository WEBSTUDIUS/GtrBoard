//  BoardSettings.swift
//  GtrBoard
//
//  The complete audible state of the guitar rig: the ordered pedal chain,
//  the graphic equalizer, master volume and global bypass/limiter switches.
//  This type is the boundary between the editor, the preset store and the
//  real-time renderer, so every value is normalised here.

import Foundation

/// The full board state.
public struct BoardSettings: Codable, Equatable, Sendable {
    /// Pedals in signal order. ``sanitized()`` guarantees exactly one unit per
    /// ``FXKind``, all fourteen of them.
    public var units: [FXUnit]
    /// Ten-band graphic equalizer at the end of the chain.
    public var graphicEQ: GraphicEQSettings
    /// Output level after the graphic EQ, before the limiter.
    public var masterVolume: Double
    /// Per-preset loudness trim in dB. Factory presets use it to keep clean
    /// and high-gain rigs at a comparable level without changing the amp's
    /// drive or the user's master setting.
    public var outputTrim: Double
    /// Look-ahead limiter protecting the output.
    public var limiter: Bool
    /// Automatic feedback / open-jack suppressor at the very start of the
    /// chain. On by default: a dangling cable into a high-gain rig must not be
    /// able to turn the app into a howling oscillator.
    public var feedbackGuard: Bool
    /// Passes the guitar through untouched while keeping the engine running.
    public var bypass: Bool

    public init(
        units: [FXUnit] = BoardSettings.defaultUnits(),
        graphicEQ: GraphicEQSettings = .flat,
        masterVolume: Double = -6,
        outputTrim: Double = 0,
        limiter: Bool = true,
        feedbackGuard: Bool = true,
        bypass: Bool = false
    ) {
        self.units = units
        self.graphicEQ = graphicEQ
        self.masterVolume = masterVolume
        self.outputTrim = outputTrim
        self.limiter = limiter
        self.feedbackGuard = feedbackGuard
        self.bypass = bypass
    }

    private enum CodingKeys: String, CodingKey {
        case units, graphicEQ, masterVolume, outputTrim, limiter, feedbackGuard, bypass
    }

    /// Tolerant decoder used by saved boards and imported presets.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        units = try container.decodeIfPresent([FXUnit].self, forKey: .units) ?? BoardSettings.defaultUnits()
        graphicEQ = try container.decodeIfPresent(GraphicEQSettings.self, forKey: .graphicEQ) ?? .flat
        masterVolume = try container.decodeIfPresent(Double.self, forKey: .masterVolume) ?? -6
        outputTrim = try container.decodeIfPresent(Double.self, forKey: .outputTrim) ?? 0
        limiter = try container.decodeIfPresent(Bool.self, forKey: .limiter) ?? true
        feedbackGuard = try container.decodeIfPresent(Bool.self, forKey: .feedbackGuard) ?? true
        bypass = try container.decodeIfPresent(Bool.self, forKey: .bypass) ?? false
    }

    /// Range of the master volume, in decibels.
    public static let masterRange: ClosedRange<Double> = -60...12

    /// Range of the hidden per-preset loudness trim, in decibels.
    public static let trimRange: ClosedRange<Double> = -24...24

    /// The canonical order of the board.
    public static let standardChain: [FXKind] = FXKind.defaultChain

    /// All pedals at factory defaults, in canonical order.
    public static func defaultUnits() -> [FXUnit] {
        FXKind.defaultChain.map { FXUnit(kind: $0) }
    }

    /// First-run board: clean amp, cabinet and a touch of reverb.
    public static func defaultBoard() -> BoardSettings {
        BoardSettings()
    }

    /// A fully valid copy: one unit per kind, canonical parameter tables,
    /// clamped values and a valid master level.
    public func sanitized() -> BoardSettings {
        var ordered: [FXUnit] = []
        var seen = Set<FXKind>()
        for unit in units where !seen.contains(unit.kind) {
            seen.insert(unit.kind)
            ordered.append(unit.sanitized())
        }
        for kind in FXKind.defaultChain where !seen.contains(kind) {
            ordered.append(FXUnit(kind: kind).sanitized())
        }

        var copy = self
        copy.units = ordered
        copy.graphicEQ = graphicEQ.sanitized()
        copy.masterVolume = masterVolume.isFinite
            ? masterVolume.clamped(to: Self.masterRange)
            : -6
        copy.outputTrim = outputTrim.isFinite
            ? outputTrim.clamped(to: Self.trimRange)
            : 0
        return copy
    }

    /// Unit of a given kind, if present.
    public func unit(_ kind: FXKind) -> FXUnit? {
        units.first { $0.kind == kind }
    }

    /// Replaces the unit of the same kind, keeping the chain position.
    public mutating func setUnit(_ unit: FXUnit) {
        if let index = units.firstIndex(where: { $0.kind == unit.kind }) {
            units[index] = unit
        } else {
            units.append(unit)
        }
    }

    /// Enables or bypasses one pedal.
    public mutating func setEnabled(_ enabled: Bool, for kind: FXKind) {
        guard let index = units.firstIndex(where: { $0.kind == kind }) else { return }
        units[index].enabled = enabled
    }

    /// Updates one knob value.
    public mutating func setParam(_ value: Double, for kind: FXKind, parameter: String) {
        guard let index = units.firstIndex(where: { $0.kind == kind }) else { return }
        units[index].setValue(value, for: parameter)
    }

    /// Moves a pedal to a new position in the chain.
    public mutating func moveUnit(_ kind: FXKind, to newIndex: Int) {
        guard let index = units.firstIndex(where: { $0.kind == kind }) else { return }
        let unit = units.remove(at: index)
        let target = newIndex.clamped(to: 0...units.count)
        units.insert(unit, at: target)
    }

    /// Moves a pedal one slot earlier/later. Used by the arrow buttons.
    public mutating func shiftUnit(_ kind: FXKind, by offset: Int) {
        guard let index = units.firstIndex(where: { $0.kind == kind }) else { return }
        let target = (index + offset).clamped(to: 0...(units.count - 1))
        guard target != index else { return }
        moveUnit(kind, to: target)
    }

    /// Enabled pedals in signal order, e.g. `GATE › OD › AMP › CAB › VERB`.
    public var chainSummary: String {
        let names = units.filter(\.enabled).map(\.descriptor.shortName)
        return names.isEmpty ? "BYPASS" : names.joined(separator: " › ")
    }

    /// Combined graphic-EQ response in decibels (used by the graph).
    public func graphicResponseDB(at frequency: Double, sampleRate: Double = 48_000) -> Double {
        graphicEQ.responseDB(at: frequency, sampleRate: sampleRate)
    }
}
