//  PresetStore.swift
//  GtrBoard
//
//  User preset library on disk. Every preset is a small JSON document with
//  the `.gtrpreset` extension, which makes saving, loading, sharing and
//  version control trivial and keeps the app free of a database.

import Foundation

/// Reads and writes user presets in `~/Library/Application Support/GtrBoard/Presets`.
public final class PresetStore {
    /// Folder that contains the user presets.
    public let directory: URL

    public init(directory: URL = PresetStore.defaultDirectory) {
        self.directory = directory
    }

    /// Standard library location.
    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("GtrBoard/Presets", isDirectory: true)
    }

    /// Creates the directory if it does not exist yet.
    @discardableResult
    public func ensureDirectory() -> Bool {
        (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    }

    /// All `.gtrpreset`/`.json` files in the library.
    public func files() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { ["gtrpreset", "json"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Loads every readable user preset, sorted by name. Broken files are
    /// skipped instead of blocking the whole library.
    public func loadUserPresets() -> [Preset] {
        files().compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let preset = try? PresetDocument.decode(data) else { return nil }
            var copy = preset
            copy.isBuiltIn = false
            copy.settings = copy.settings.sanitized()
            return copy
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Saves (or overwrites) a user preset. The file name stays readable and
    /// embeds the preset id, so renaming removes the stale file.
    @discardableResult
    public func save(_ preset: Preset) throws -> URL {
        guard ensureDirectory() else {
            throw PresetError.writeFailed("cannot create \(directory.path)")
        }
        var clean = preset
        clean.isBuiltIn = false
        clean.settings = clean.settings.sanitized()
        clean.modifiedAt = Date()

        let shortID = String(clean.id.prefix(8))
        let name = "\(clean.slug)-\(shortID).gtrpreset"
        let url = directory.appendingPathComponent(name)
        let data = try PresetDocument(preset: clean).encoded()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PresetError.writeFailed(error.localizedDescription)
        }
        removeStaleFiles(for: clean, keeping: url)
        return url
    }

    /// Deletes one user preset.
    public func delete(_ preset: Preset) throws {
        guard !preset.isBuiltIn else { return }
        for url in files() where url.lastPathComponent.contains(String(preset.id.prefix(8))) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes by id (used after an import that replaced a preset).
    public func delete(id: String) {
        for url in files() where url.lastPathComponent.contains(String(id.prefix(8))) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Writes a shareable copy to an arbitrary location.
    public func export(_ preset: Preset, to url: URL) throws {
        let target = url.pathExtension.isEmpty ? url.appendingPathExtension("gtrpreset") : url
        let data = try PresetDocument(preset: preset).encoded()
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw PresetError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads a preset from any `.gtrpreset`/JSON file. Imported presets get a
    /// fresh identity so they never overwrite an existing user preset.
    public func importPreset(from url: URL) throws -> Preset {
        guard let data = try? Data(contentsOf: url) else { throw PresetError.unreadableFile }
        var preset = try PresetDocument.decode(data)
        preset.id = UUID().uuidString
        preset.isBuiltIn = false
        preset.createdAt = Date()
        preset.modifiedAt = Date()
        preset.settings = preset.settings.sanitized()
        return preset
    }

    /// Removes files that belong to the same preset but carry an old name.
    /// Files are matched by decoded id rather than by string prefix, and the
    /// freshly written file is compared by resolved path (macOS reports
    /// `/private/var` while `temporaryDirectory` may say `/var`).
    private func removeStaleFiles(for preset: Preset, keeping url: URL) {
        let keepPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        for candidate in files() {
            let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            guard candidatePath != keepPath else { continue }
            guard let data = try? Data(contentsOf: candidate),
                  let decoded = try? PresetDocument.decode(data),
                  decoded.id == preset.id else { continue }
            try? FileManager.default.removeItem(at: candidate)
        }
    }
}
