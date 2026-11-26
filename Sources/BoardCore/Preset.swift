//  Preset.swift
//  GtrBoard
//
//  Factory and user presets, the on-disk document envelope and the JSON
//  codec. A preset is a named, self-contained snapshot of the whole board,
//  so exporting one is enough to share a complete rig.

import Foundation

/// A named snapshot of the whole board.
public struct Preset: Identifiable, Codable, Equatable, Sendable {
    /// Stable identifier. Factory presets use `builtin.<slug>`.
    public var id: String
    public var name: String
    /// Who made the preset; factory presets use the app author.
    public var author: String
    /// Short gear description, e.g. `TS-808 → Deluxe Reverb`.
    public var gear: String
    /// Liner notes shown in the browser and in exported files.
    public var notes: String
    /// Free-form tags such as `blues`, `lead`, `ambient`.
    public var tags: [String]
    public var settings: BoardSettings
    public var isBuiltIn: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        author: String = "GtrBoard",
        gear: String = "",
        notes: String = "",
        tags: [String] = [],
        settings: BoardSettings,
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.gear = gear
        self.notes = notes
        self.tags = tags
        self.settings = settings
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, author, gear, notes, tags, settings, isBuiltIn, createdAt, modifiedAt
    }

    /// Tolerant decoder for presets from earlier builds.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "GtrBoard"
        gear = try container.decodeIfPresent(String.self, forKey: .gear) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        settings = (try container.decodeIfPresent(BoardSettings.self, forKey: .settings) ?? .defaultBoard())
            .sanitized()
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    /// True when the current board still matches this preset.
    public func matches(_ settings: BoardSettings) -> Bool {
        self.settings.sanitized() == settings.sanitized()
    }

    /// File-safe slug used for exports.
    public var slug: String {
        Self.slug(from: name)
    }

    /// Converts arbitrary user text into a safe file name.
    public static func slug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var lastWasDash = false
        for scalar in name.lowercased().unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "preset" : String(trimmed.prefix(48))
    }
}

/// Errors surfaced by the preset store and importer.
public enum PresetError: LocalizedError, Equatable {
    case unreadableFile
    case invalidJSON
    case unsupportedFormat(String)
    case emptyFile
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The preset file could not be read."
        case .invalidJSON:
            return "The file is not a valid GtrBoard preset (bad JSON)."
        case let .unsupportedFormat(format):
            return "Unsupported preset format: \(format)."
        case .emptyFile:
            return "The preset file is empty."
        case let .writeFailed(reason):
            return "The preset could not be written: \(reason)"
        }
    }
}

/// On-disk envelope. Keeping `format` and `version` at the top level lets
/// future versions migrate files instead of guessing.
public struct PresetDocument: Codable, Sendable {
    public static let formatIdentifier = "com.andreyilin.gtrboard.preset"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var preset: Preset

    public init(preset: Preset) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.preset = preset
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, preset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? Self.formatIdentifier
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        preset = try container.decode(Preset.self, forKey: .preset)
    }

    /// Encodes the envelope as pretty JSON with ISO-8601 dates.
    public func encoded() throws -> Data {
        try PresetCodec.encoder.encode(self)
    }

    /// Decodes either a full envelope or a bare preset object.
    public static func decode(_ data: Data) throws -> Preset {
        guard !data.isEmpty else { throw PresetError.emptyFile }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            throw PresetError.unreadableFile
        }
        guard let object = json as? [String: Any] else {
            throw PresetError.invalidJSON
        }

        if object["preset"] != nil || object["format"] != nil || object["version"] != nil {
            guard let document = try? PresetCodec.decoder.decode(PresetDocument.self, from: data) else {
                throw PresetError.invalidJSON
            }
            if document.format != formatIdentifier {
                throw PresetError.unsupportedFormat(document.format)
            }
            guard document.version <= currentVersion else {
                throw PresetError.unsupportedFormat("version \(document.version)")
            }
            return document.preset
        }

        guard object["name"] is String || object["settings"] is [String: Any],
              let preset = try? PresetCodec.decoder.decode(Preset.self, from: data) else {
            throw PresetError.invalidJSON
        }
        return preset
    }
}

/// Shared JSON configuration. Dates are ISO-8601 so exported presets are
/// readable and diff-friendly.
public enum PresetCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
