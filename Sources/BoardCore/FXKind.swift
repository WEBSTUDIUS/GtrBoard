//  FXKind.swift
//  GtrBoard
//
//  The complete pedalboard catalogue. Every effect owns a descriptor with
//  its knob layout, colours and defaults; the interface, the preset format
//  and the DSP all derive from this single table.

import Foundation

/// Broad grouping used for colour coding and the preset browser.
public enum FXCategory: String, Codable, CaseIterable, Sendable {
    case dynamics
    case drive
    case modulation
    case time
    case amp

    public var displayName: String {
        switch self {
        case .dynamics: return "Dynamics"
        case .drive: return "Drive"
        case .modulation: return "Modulation"
        case .time: return "Time"
        case .amp: return "Amp & Cab"
        }
    }
}

/// Every effect available on the board. One instance of each kind exists on
/// the board at a time, exactly like a physical pedalboard.
public enum FXKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gate
    case compressor
    case boost
    case overdrive
    case distortion
    case fuzz
    case amp
    case cabinet
    case ir
    case chorus
    case flanger
    case phaser
    case tremolo
    case delay
    case reverb

    public var id: String { rawValue }

    /// Descriptor with labels, colours and knob metadata.
    public var descriptor: FXDescriptor { FXCatalog.descriptor(for: self) }

    /// Position in the default signal chain.
    public var defaultChainIndex: Int {
        FXKind.defaultChain.firstIndex(of: self) ?? 0
    }

    /// Default order of the pedals: guitar → dynamics → drive → amp → cab →
    /// modulation → time effects.
    public static let defaultChain: [FXKind] = [
        .gate, .compressor, .boost, .overdrive, .distortion, .fuzz,
        .amp, .cabinet, .ir,
        .chorus, .flanger, .phaser, .tremolo,
        .delay, .reverb
    ]
}

/// Static metadata for one effect.
public struct FXDescriptor: Identifiable, Sendable {
    public var kind: FXKind
    public var name: String
    public var shortName: String
    public var subtitle: String
    public var category: FXCategory
    public var colorHex: UInt32
    public var parameters: [FXParameter]
    public var defaultEnabled: Bool

    public var id: FXKind { kind }

    /// Parameter by stable key.
    public func parameter(_ id: String) -> FXParameter? {
        parameters.first { $0.id == id }
    }

    /// Default value table for a fresh unit.
    public var defaults: [String: Double] {
        var values: [String: Double] = [:]
        for parameter in parameters {
            values[parameter.id] = parameter.fallback
        }
        return values
    }
}

/// Descriptor factory. The table is a `static let` so parameter metadata is
/// built once per process and knob positions stay stable while the UI redraws.
public enum FXCatalog {
    public static let descriptors: [FXKind: FXDescriptor] = {
        var table: [FXKind: FXDescriptor] = [:]
        for descriptor in makeDescriptors() {
            table[descriptor.kind] = descriptor
        }
        return table
    }()

    public static func descriptor(for kind: FXKind) -> FXDescriptor {
        descriptors[kind] ?? makeDescriptors()[0]
    }

    /// Parameter metadata for a knob, or a fallback 0…1 control.
    private static func p(
        _ id: String,
        _ name: String,
        _ range: ClosedRange<Double>,
        _ defaultValue: Double,
        _ unit: ParameterUnit,
        log: Bool = false,
        choices: [String] = []
    ) -> FXParameter {
        FXParameter(
            id: id,
            name: name,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            defaultValue: defaultValue,
            unit: unit,
            logarithmic: log,
            choices: choices
        )
    }

    private static func makeDescriptors() -> [FXDescriptor] {
        [
            FXDescriptor(
                kind: .gate,
                name: "Noise Gate",
                shortName: "GATE",
                subtitle: "Hysteresis noise gate",
                category: .dynamics,
                colorHex: 0x64748B,
                parameters: [
                    p("threshold", "Threshold", -80...(-20), -60, .decibels),
                    p("decay", "Decay", 20...1_000, 180, .milliseconds, log: true),
                    p("range", "Range", 0...80, 60, .decibels)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .compressor,
                name: "Compressor",
                shortName: "COMP",
                subtitle: "Studio-style feed-forward compressor",
                category: .dynamics,
                colorHex: 0x38BDF8,
                parameters: [
                    p("threshold", "Threshold", -60...0, -24, .decibels),
                    p("ratio", "Ratio", 1...20, 4, .ratio),
                    p("attack", "Attack", 0.5...100, 10, .milliseconds, log: true),
                    p("release", "Release", 20...1_000, 180, .milliseconds, log: true),
                    p("makeup", "Makeup", 0...24, 6, .decibels)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .boost,
                name: "Clean Boost",
                shortName: "BOOST",
                subtitle: "Transparent gain + tilt EQ",
                category: .drive,
                colorHex: 0xFBBF24,
                parameters: [
                    p("gain", "Gain", 0...30, 9, .decibels),
                    p("tone", "Tilt", -12...12, 0, .decibels),
                    p("tight", "Tight", 20...400, 70, .hertz, log: true)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .overdrive,
                name: "Overdrive",
                shortName: "OD",
                subtitle: "Tube Screamer-style soft clip",
                category: .drive,
                colorHex: 0xF59E0B,
                parameters: [
                    p("drive", "Drive", 0...40, 18, .decibels),
                    p("tone", "Tone", 0...1, 0.55, .percent),
                    p("level", "Level", -30...6, -6, .decibels),
                    p("mid", "Mid", 0...1, 0.6, .percent)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .distortion,
                name: "Distortion",
                shortName: "DIST",
                subtitle: "Diode hard-clip distortion",
                category: .drive,
                colorHex: 0xEF4444,
                parameters: [
                    p("gain", "Gain", 0...50, 26, .decibels),
                    p("tone", "Tone", 0...1, 0.55, .percent),
                    p("level", "Level", -30...6, -8, .decibels),
                    p("edge", "Edge", 0...1, 0.5, .percent)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .fuzz,
                name: "Fuzz",
                shortName: "FUZZ",
                subtitle: "Big Muff-style sustain wall",
                category: .drive,
                colorHex: 0xA855F7,
                parameters: [
                    p("sustain", "Sustain", 0...1, 0.7, .percent),
                    p("tone", "Tone", 0...1, 0.5, .percent),
                    p("level", "Level", -30...6, -6, .decibels),
                    p("bias", "Bias", 0...1, 0.5, .percent)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .amp,
                name: "Amplifier",
                shortName: "AMP",
                subtitle: "Four-voicing valve preamp",
                category: .amp,
                colorHex: 0xF97316,
                parameters: [
                    p("gain", "Gain", 0...40, 12, .decibels),
                    p("bass", "Bass", -12...12, 0, .decibels),
                    p("mid", "Mid", -12...12, 0, .decibels),
                    p("treble", "Treble", -12...12, 0, .decibels),
                    p("presence", "Presence", 0...12, 3, .decibels),
                    p("master", "Master", -40...6, -8, .decibels),
                    p("voicing", "Voicing", 0...3, 1, .choice,
                      choices: ["Clean", "Crunch", "Lead", "High Gain"])
                ],
                defaultEnabled: true
            ),
            FXDescriptor(
                kind: .cabinet,
                name: "Cabinet",
                shortName: "CAB",
                subtitle: "Dynamic speaker + mic simulation",
                category: .amp,
                colorHex: 0xD97706,
                parameters: [
                    p("lowCut", "Low Cut", 40...250, 80, .hertz, log: true),
                    p("highCut", "High Cut", 2_000...12_000, 5_500, .hertz, log: true),
                    p("resonance", "Resonance", 0...12, 4, .decibels)
                ],
                defaultEnabled: true
            ),
            FXDescriptor(
                kind: .ir,
                name: "IR Cabinet",
                shortName: "IR",
                subtitle: "Loaded speaker impulse responses",
                category: .amp,
                colorHex: 0x14B8A6,
                parameters: [
                    p("model", "Cabinet", 0...Double(CabinetIRLibrary.presetNames.count - 1), 0, .choice,
                      choices: CabinetIRLibrary.presetNames),
                    p("mix", "Mix", 0...1, 1, .percent),
                    p("lowCut", "Low Cut", 40...250, 80, .hertz, log: true),
                    p("highCut", "High Cut", 3_000...16_000, 9_000, .hertz, log: true),
                    p("level", "Level", -24...12, 0, .decibels)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .chorus,
                name: "Chorus",
                shortName: "CHORUS",
                subtitle: "Lush analog chorus",
                category: .modulation,
                colorHex: 0x22D3EE,
                parameters: [
                    p("rate", "Rate", 0.05...8, 0.8, .hertz, log: true),
                    p("depth", "Depth", 0...1, 0.5, .percent),
                    p("mix", "Mix", 0...1, 0.4, .percent),
                    p("width", "Width", 0...1, 0.7, .percent)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .flanger,
                name: "Flanger",
                shortName: "FLANGE",
                subtitle: "Jet-sweep feedback flanger",
                category: .modulation,
                colorHex: 0x818CF8,
                parameters: [
                    p("rate", "Rate", 0.02...5, 0.25, .hertz, log: true),
                    p("depth", "Depth", 0...1, 0.6, .percent),
                    p("feedback", "Feedback", -0.95...0.95, 0.35, .percent),
                    p("mix", "Mix", 0...1, 0.5, .percent),
                    p("manual", "Manual", 0.5...10, 2.5, .milliseconds, log: true)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .phaser,
                name: "Phaser",
                shortName: "PHASER",
                subtitle: "Four-to-twelve-stage phase shifter",
                category: .modulation,
                colorHex: 0xE879F9,
                parameters: [
                    p("rate", "Rate", 0.02...5, 0.35, .hertz, log: true),
                    p("depth", "Depth", 0...1, 0.6, .percent),
                    p("feedback", "Feedback", 0...0.9, 0.3, .percent),
                    p("mix", "Mix", 0...1, 0.5, .percent),
                    p("stages", "Stages", 0...3, 1, .choice,
                      choices: ["4", "6", "8", "12"])
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .tremolo,
                name: "Tremolo",
                shortName: "TREM",
                subtitle: "Stereo amplitude modulation",
                category: .modulation,
                colorHex: 0x2DD4BF,
                parameters: [
                    p("rate", "Rate", 0.2...12, 4.5, .hertz, log: true),
                    p("depth", "Depth", 0...1, 0.6, .percent),
                    p("shape", "Shape", 0...2, 0, .choice,
                      choices: ["Sine", "Triangle", "Square"]),
                    p("stereo", "Stereo", 0...1, 0, .percent)
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .delay,
                name: "Delay",
                shortName: "DELAY",
                subtitle: "Digital, analog and ping-pong echoes",
                category: .time,
                colorHex: 0x60A5FA,
                parameters: [
                    p("time", "Time", 20...1_500, 380, .milliseconds, log: true),
                    p("feedback", "Feedback", 0...0.95, 0.35, .percent),
                    p("mix", "Mix", 0...1, 0.3, .percent),
                    p("tone", "Tone", 0...1, 0.55, .percent),
                    p("mode", "Mode", 0...2, 1, .choice,
                      choices: ["Digital", "Analog", "Ping-Pong"])
                ],
                defaultEnabled: false
            ),
            FXDescriptor(
                kind: .reverb,
                name: "Reverb",
                shortName: "VERB",
                subtitle: "Room, hall and plate spaces",
                category: .time,
                colorHex: 0x94A3B8,
                parameters: [
                    p("size", "Size", 0...1, 0.55, .percent),
                    p("damping", "Damping", 0...1, 0.45, .percent),
                    p("mix", "Mix", 0...1, 0.22, .percent),
                    p("predelay", "Pre-Delay", 0...120, 20, .milliseconds),
                    p("mode", "Mode", 0...2, 1, .choice,
                      choices: ["Room", "Hall", "Plate"])
                ],
                defaultEnabled: true
            )
        ]
    }
}
