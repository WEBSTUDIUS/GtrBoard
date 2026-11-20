//  AppModel.swift
//  GtrBoard
//
//  Single source of truth for the interface: the board, the preset library,
//  the audio engine, the device selection and all user actions. Views never
//  talk to Core Audio or to the filesystem directly.

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BoardCore

/// Peak meters live in their own observable object so 30 fps updates do not
/// invalidate the whole pedalboard.
@MainActor
final class MeterModel: ObservableObject {
    @Published var input: Float = 0
    @Published var output: Float = 0
}

/// A/B preset slots. Space switches between them when both are assigned,
/// otherwise it toggles bypass.
enum PresetBank: String, CaseIterable, Identifiable, Sendable {
    case a
    case b

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - Published state

    /// The board. Every edit is pushed to the renderer immediately and saved
    /// with a short debounce.
    @Published var settings: BoardSettings {
        didSet {
            let transition = pendingPresetTransition
            pendingPresetTransition = false
            engine.update(settings: settings, transition: transition)
            scheduleSave()
        }
    }

    @Published private(set) var userPresets: [Preset]
    @Published var selectedPresetID: String?

    @Published private(set) var engineState: AudioEngineState = .idle
    @Published private(set) var format: AudioEngineFormat?

    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    static let noInputUID = "com.andreyilin.gtrboard.no-input"

    @Published var selectedInputUID: String? {
        didSet {
            guard oldValue != selectedInputUID else { return }
            if let selectedInputUID {
                UserDefaults.standard.set(selectedInputUID, forKey: Keys.inputUID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.inputUID)
            }
            restartAudioIfNeeded()
        }
    }
    @Published var selectedOutputUID: String? {
        didSet {
            guard oldValue != selectedOutputUID else { return }
            UserDefaults.standard.set(selectedOutputUID, forKey: Keys.outputUID)
            restartAudioIfNeeded()
        }
    }
    @Published var bufferSize: Int {
        didSet {
            UserDefaults.standard.set(bufferSize, forKey: Keys.bufferSize)
            restartAudioIfNeeded()
        }
    }

    @Published var isShowingPresets = false
    @Published var isShowingSavePreset = false
    @Published var isShowingMicrophoneHelp = false

    @Published var presetNameDraft = ""
    @Published var presetGearDraft = ""
    @Published var presetNotesDraft = ""
    @Published var presetTagsDraft = ""

    /// Snapshot assigned to Bank A/B. Stored as a full preset so a custom
    /// board can be banked too, even if it was never saved.
    @Published var bankA: Preset?
    @Published var bankB: Preset?
    @Published var activeBank: PresetBank = .a

    @Published var toast: String?

    /// Whether the user wants audio running. Persisted across launches.
    @Published private(set) var isEnabled: Bool

    // MARK: - Services

    let engine = AudioEngine()
    let meter = MeterModel()
    let store = PresetStore()
    let recorder = Recorder()

    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var lastRecordingURL: URL?
    /// 24-bit PCM (default) or 32-bit float WAV.
    @Published private(set) var recordingBitDepth: Int

    /// Set by ContentView so AppDelegate can reopen a closed SwiftUI window
    /// from the Dock icon or the menu bar.
    var openWindowAction: (() -> Void)?

    private var saveWorkItem: DispatchWorkItem?
    private var toastWorkItem: DispatchWorkItem?
    /// Set while assigning `settings` from a preset so the renderer can duck
    /// instead of jumping coefficients and delay state instantly.
    private var pendingPresetTransition = false
    private var meterTimer: Timer?
    private var isRestarting = false

    private enum Keys {
        static let board = "gtrboard.board.v1"
        static let selectedPreset = "gtrboard.selectedPreset.v1"
        static let inputUID = "gtrboard.inputUID"
        static let outputUID = "gtrboard.outputUID"
        static let bufferSize = "gtrboard.bufferSize"
        static let enabled = "gtrboard.enabled"
        static let bankA = "gtrboard.bankA.v1"
        static let bankB = "gtrboard.bankB.v1"
        static let activeBank = "gtrboard.activeBank.v1"
        static let recordBitDepth = "gtrboard.recordBitDepth"
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        var loadedSettings: BoardSettings
        if let data = defaults.data(forKey: Keys.board),
           let decoded = try? JSONDecoder().decode(BoardSettings.self, from: data) {
            loadedSettings = decoded.sanitized()
        } else {
            loadedSettings = .defaultBoard()
        }

        let loadedPresetID = defaults.string(forKey: Keys.selectedPreset)
        // Migration: boards saved before 0.2.1 have outputTrim == 0. If the
        // board still points at a factory preset, adopt its calibrated level
        // so an old "Funk Clean *" does not stay 24 dB quieter than the preset.
        if loadedSettings.outputTrim == 0,
           let loadedPresetID,
           let factory = BuiltInPresets.all.first(where: { $0.id == loadedPresetID }) {
            loadedSettings.outputTrim = factory.settings.outputTrim
        }

        settings = loadedSettings
        userPresets = store.loadUserPresets()
        selectedPresetID = loadedPresetID
        bankA = defaults.data(forKey: Keys.bankA)
            .flatMap { try? PresetCodec.decoder.decode(Preset.self, from: $0) }
        bankB = defaults.data(forKey: Keys.bankB)
            .flatMap { try? PresetCodec.decoder.decode(Preset.self, from: $0) }
        activeBank = PresetBank(rawValue: defaults.string(forKey: Keys.activeBank) ?? "a") ?? .a
        bufferSize = defaults.object(forKey: Keys.bufferSize) as? Int ?? 128
        let storedDepth = defaults.object(forKey: Keys.recordBitDepth) as? Int ?? 24
        recordingBitDepth = storedDepth == 32 ? 32 : 24
        isEnabled = defaults.bool(forKey: Keys.enabled)

        let ins = AudioDevices.inputs()
        let outs = AudioDevices.outputs()
        inputDevices = ins
        outputDevices = outs
        let storedInputUID = defaults.string(forKey: Keys.inputUID)
        if storedInputUID == Self.noInputUID {
            selectedInputUID = Self.noInputUID
        } else if let storedInputUID, AudioDevices.isOwnAggregate(uid: storedInputUID) {
            // Never restore our own aggregate; it would nest the engine.
            selectedInputUID = Self.noInputUID
        } else if let storedInputUID, ins.contains(where: { $0.uid == storedInputUID }) {
            selectedInputUID = storedInputUID
        } else {
            selectedInputUID = ins.first(where: \.isDefaultInput)?.uid ?? ins.first?.uid
        }
        selectedOutputUID = defaults.string(forKey: Keys.outputUID)
            .flatMap { uid in outs.contains { $0.uid == uid } ? uid : nil }
            ?? outs.first(where: \.isDefaultOutput)?.uid
            ?? outs.first?.uid

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            self.engineState = state
            if case let .failed(message) = state {
                self.isEnabled = false
                defaults.set(false, forKey: Keys.enabled)
                self.showToast(message)
            }
        }
        engine.onFormatChange = { [weak self] format in
            self?.format = format
        }
        engine.recorder = recorder

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--preset"),
           arguments.indices.contains(index + 1),
           let preset = BuiltInPresets.all.first(where: {
               $0.name.localizedCaseInsensitiveCompare(arguments[index + 1]) == .orderedSame
           }) {
            settings = preset.settings
            selectedPresetID = preset.id
        }

        engine.update(settings: settings)

        startMeterTimer()

        if arguments.contains("--show-presets") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isShowingPresets = true
            }
        }

        if isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.startEngine()
            }
        }
    }

    // MARK: - Derived state

    var isRunning: Bool { engineState.isRunning }
    var isStarting: Bool { engineState.isStarting }
    var isBypassed: Bool { settings.bypass }

    var allPresets: [Preset] { BuiltInPresets.all + userPresets }

    var activePreset: Preset? {
        guard let selectedPresetID else { return nil }
        return allPresets.first { $0.id == selectedPresetID }
    }

    var isPresetModified: Bool {
        guard let activePreset else { return true }
        return activePreset.settings.sanitized() != settings.sanitized()
    }

    var activePresetName: String {
        guard let activePreset else { return "Custom" }
        return isPresetModified ? "\(activePreset.name) *" : activePreset.name
    }

    var selectedInput: AudioDevice? {
        guard selectedInputUID != Self.noInputUID else { return nil }
        return inputDevices.first { $0.uid == selectedInputUID }
    }

    var selectedOutput: AudioDevice? {
        outputDevices.first { $0.uid == selectedOutputUID }
    }

    var routeLabel: String {
        guard let output = selectedOutput else { return "No audio devices" }
        return "\(selectedInput?.name ?? "No input") → \(output.name)"
    }

    var latencyLabel: String {
        format?.latencyLabel ?? "—"
    }

    var sampleRateLabel: String {
        format?.sampleRateLabel ?? "—"
    }

    var bufferLabel: String {
        "\(format?.bufferFrames ?? bufferSize) smp"
    }

    /// Used by the empty-state banner.
    var needsAudioSetup: Bool { selectedOutput == nil }

    // MARK: - Audio control

    func startEngine() {
        guard !engineState.isRunning, !engineState.isStarting else { return }
        let input = selectedInput
        guard let output = selectedOutput else {
            showToast("Choose an output device first.")
            return
        }

        isEnabled = true
        UserDefaults.standard.set(true, forKey: Keys.enabled)
        engineState = .starting

        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = input == nil ? true : await AudioEngine.requestInputPermission()
            guard self.isEnabled else { return }
            guard granted else {
                self.isEnabled = false
                UserDefaults.standard.set(false, forKey: Keys.enabled)
                self.engineState = .failed("Microphone access is required to hear your guitar.")
                self.isShowingMicrophoneHelp = true
                return
            }
            self.engine.start(
                input: input,
                output: output,
                bufferSize: self.bufferSize,
                settings: self.settings
            )
        }
    }

    func stopEngine() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Keys.enabled)
        engine.stop()
        engineState = .idle
    }

    func togglePower() {
        if engineState.isRunning || engineState.isStarting {
            stopEngine()
        } else {
            startEngine()
        }
    }

    private func restartAudioIfNeeded() {
        guard isEnabled, !isRestarting else { return }
        guard engineState.isRunning || engineState.isStarting else { return }
        isRestarting = true
        engine.stop()
        engineState = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.isRestarting = false
            self.startEngine()
        }
    }

    func refreshDevices() {
        let ins = AudioDevices.inputs()
        let outs = AudioDevices.outputs()
        inputDevices = ins
        outputDevices = outs

        if selectedInputUID == Self.noInputUID {
            // Keep the explicit "No Input" choice.
        } else if let current = selectedInputUID, ins.contains(where: { $0.uid == current }) {
            // Still available.
        } else {
            selectedInputUID = ins.first(where: \.isDefaultInput)?.uid ?? ins.first?.uid
        }
        if !outs.contains(where: { $0.uid == selectedOutputUID }) {
            selectedOutputUID = outs.first(where: \.isDefaultOutput)?.uid ?? outs.first?.uid
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recording

    private var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return base.appendingPathComponent("GtrBoard", isDirectory: true)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        if !engineState.isRunning {
            startEngine()
            waitForEngineThenRecord(attempts: 0)
            return
        }
        startRecordingNow()
    }

    private func waitForEngineThenRecord(attempts: Int) {
        if engineState.isRunning, format != nil {
            startRecordingNow()
            return
        }
        guard attempts < 30 else {
            showToast("Audio did not start in time.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForEngineThenRecord(attempts: attempts + 1)
        }
    }

    private func startRecordingNow() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
            let stamp = DateFormatter.recordingStamp.string(from: Date())
            let url = recordingsDirectory.appendingPathComponent("GtrBoard-\(stamp).wav")
            try recorder.start(
                url: url,
                sampleRate: format?.sampleRate ?? 48_000,
                bitDepth: recordingBitDepth
            )
            lastRecordingURL = url
            recordingStartedAt = Date()
            isRecording = true
            showToast("Recording \(recordingBitDepth)-bit to Music/GtrBoard")
        } catch {
            showToast("Recording failed: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        let url = recorder.stop()
        isRecording = false
        recordingStartedAt = nil
        if let url {
            lastRecordingURL = url
            showToast("Saved \(url.lastPathComponent)")
        }
    }

    func setRecordingBitDepth(_ depth: Int) {
        let value = depth == 32 ? 32 : 24
        guard value != recordingBitDepth else { return }
        recordingBitDepth = value
        UserDefaults.standard.set(value, forKey: Keys.recordBitDepth)
        showToast("Recording format: \(value)-bit")
    }

    func revealLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Board edits

    func setUnitEnabled(_ kind: FXKind, _ enabled: Bool) {
        settings.setEnabled(enabled, for: kind)
    }

    func setParameter(_ kind: FXKind, _ parameter: String, _ value: Double) {
        settings.setParam(value, for: kind, parameter: parameter)
    }

    func moveUnit(_ kind: FXKind, by offset: Int) {
        settings.shiftUnit(kind, by: offset)
    }

    /// Single entry point for preset/bank/chain loads. Preset changes duck the
    /// output for ~24 ms; ordinary knob edits stay immediate.
    private func loadBoard(_ board: BoardSettings, transition: Bool) {
        pendingPresetTransition = transition
        settings = board
        pendingPresetTransition = false
    }

    func resetChain() {
        var board = settings
        board.units = FXKind.defaultChain.map { kind in
            FXUnit(kind: kind, enabled: kind.descriptor.defaultEnabled)
        }
        loadBoard(board, transition: true)
        showToast("Chain reset to factory order")
    }

    func setMasterVolume(_ value: Double) {
        settings.masterVolume = value.clamped(to: BoardSettings.masterRange)
    }

    /// Per-preset loudness trim (after master, before the limiter).
    func setPresetLevel(_ value: Double) {
        settings.outputTrim = value.clamped(to: BoardSettings.trimRange)
    }

    /// Restores the level stored in the active preset, or 0 dB for a custom
    /// board. Useful after experimenting with the level slider.
    func resetPresetLevelToPreset() {
        settings.outputTrim = activePreset?.settings.outputTrim ?? 0
    }

    func setBypass(_ bypass: Bool) {
        settings.bypass = bypass
    }

    func setLimiter(_ enabled: Bool) {
        settings.limiter = enabled
    }

    func setGraphicGain(_ index: Int, _ value: Double) {
        guard settings.graphicEQ.gains.indices.contains(index) else { return }
        settings.graphicEQ.gains[index] = value.clamped(to: GraphicEQSettings.range)
    }

    func setGraphicEnabled(_ enabled: Bool) {
        settings.graphicEQ.enabled = enabled
    }

    func resetGraphicEQ() {
        settings.graphicEQ.gains = Array(repeating: 0, count: GraphicEQSettings.frequencies.count)
    }

    /// Restores a single pedal to its factory defaults.
    func resetUnit(_ kind: FXKind) {
        guard let index = settings.units.firstIndex(where: { $0.kind == kind }) else { return }
        var unit = FXUnit(kind: kind, enabled: settings.units[index].enabled)
        unit.enabled = settings.units[index].enabled
        settings.units[index] = unit
    }

    // MARK: - Presets

    func apply(_ preset: Preset) {
        loadBoard(preset.settings.sanitized(), transition: true)
        selectedPresetID = preset.id
        UserDefaults.standard.set(preset.id, forKey: Keys.selectedPreset)
        if bankA?.id == preset.id {
            activeBank = .a
        } else if bankB?.id == preset.id {
            activeBank = .b
        }
        UserDefaults.standard.set(activeBank.rawValue, forKey: Keys.activeBank)
        showToast("Loaded \(preset.name)")
    }

    func stepPreset(by offset: Int) {
        let presets = allPresets
        guard !presets.isEmpty else { return }
        let currentIndex = presets.firstIndex { $0.id == selectedPresetID } ?? -1
        let next = (currentIndex + offset + presets.count) % presets.count
        apply(presets[next])
    }

    func beginSavePreset() {
        let preset = activePreset
        presetNameDraft = preset?.name ?? "My Rig"
        presetGearDraft = preset?.gear ?? ""
        presetNotesDraft = preset?.notes ?? ""
        presetTagsDraft = preset?.tags.joined(separator: ", ") ?? ""
        isShowingSavePreset = true
    }

    func commitSavePreset() {
        let name = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showToast("Give the preset a name.")
            return
        }

        var preset: Preset
        if let active = activePreset, !active.isBuiltIn {
            preset = active
        } else if let existing = userPresets.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            preset = existing
        } else {
            preset = Preset(name: name, settings: settings)
        }

        preset.name = name
        preset.gear = presetGearDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.notes = presetNotesDraft
        preset.tags = presetTagsDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        preset.settings = settings.sanitized()
        preset.isBuiltIn = false

        do {
            try store.save(preset)
            reloadUserPresets()
            selectedPresetID = preset.id
            UserDefaults.standard.set(preset.id, forKey: Keys.selectedPreset)
            isShowingSavePreset = false
            showToast("Saved “\(preset.name)”")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func deletePreset(_ preset: Preset) {
        guard !preset.isBuiltIn else { return }
        do {
            try store.delete(preset)
            reloadUserPresets()
            if selectedPresetID == preset.id {
                selectedPresetID = nil
                UserDefaults.standard.removeObject(forKey: Keys.selectedPreset)
            }
            showToast("Deleted “\(preset.name)”")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func duplicatePreset(_ preset: Preset) {
        var copy = preset
        copy.id = UUID().uuidString
        copy.name += " Copy"
        copy.isBuiltIn = false
        copy.settings = preset.settings.sanitized()
        do {
            try store.save(copy)
            reloadUserPresets()
            apply(copy)
            showToast("Duplicated “\(preset.name)”")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func reloadUserPresets() {
        userPresets = store.loadUserPresets()
    }

    // MARK: - Import / export

    private var presetContentType: UTType {
        UTType(exportedAs: "com.andreyilin.gtrboard.preset", conformingTo: .json)
    }

    func exportCurrentPreset() {
        var preset = activePreset ?? Preset(name: "Custom Rig", settings: settings)
        preset.settings = settings.sanitized()
        if preset.isBuiltIn {
            preset = Preset(name: preset.name, author: preset.author, gear: preset.gear,
                            notes: preset.notes, tags: preset.tags, settings: settings)
        }
        presentExportPanel(for: preset)
    }

    func exportPreset(_ preset: Preset) {
        presentExportPanel(for: preset)
    }

    private func presentExportPanel(for preset: Preset) {
        let panel = NSSavePanel()
        panel.title = "Export Preset"
        panel.nameFieldStringValue = "\(preset.slug).gtrpreset"
        panel.allowedContentTypes = [presetContentType, .json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(preset, to: url)
            showToast("Exported “\(preset.name)”")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func importPresetFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Preset"
        panel.allowedContentTypes = [presetContentType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPreset(from: url)
    }

    func importPreset(from url: URL) {
        do {
            var preset = try store.importPreset(from: url)
            if preset.name.isEmpty { preset.name = url.deletingPathExtension().lastPathComponent }
            try store.save(preset)
            reloadUserPresets()
            apply(preset)
            showToast("Imported “\(preset.name)”")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - A/B banks

    var hasBothBanks: Bool { bankA != nil && bankB != nil }

    func bankPreset(_ bank: PresetBank) -> Preset? {
        bank == .a ? bankA : bankB
    }

    func bankName(_ bank: PresetBank) -> String {
        bankPreset(bank)?.name ?? "—"
    }

    /// Stores a full snapshot in a bank and immediately loads it.
    func assignBank(_ bank: PresetBank, preset: Preset) {
        var snapshot = preset
        snapshot.settings = preset.settings.sanitized()
        if bank == .a { bankA = snapshot } else { bankB = snapshot }
        activeBank = bank
        persistBanks()
        apply(snapshot)
        showToast("Bank \(bank.title): \(snapshot.name)")
    }

    /// Banks whatever is currently on the board, including an unsaved custom
    /// chain. This is what the A/B buttons do when the slot is empty.
    func assignCurrentToBank(_ bank: PresetBank) {
        var snapshot = activePreset ?? Preset(name: "Custom Board", settings: settings)
        snapshot.settings = settings.sanitized()
        snapshot.isBuiltIn = false
        assignBank(bank, preset: snapshot)
    }

    func clearBank(_ bank: PresetBank) {
        if bank == .a { bankA = nil } else { bankB = nil }
        persistBanks()
        showToast("Bank \(bank.title) cleared")
    }

    func loadBank(_ bank: PresetBank) {
        guard let preset = bankPreset(bank) else {
            assignCurrentToBank(bank)
            return
        }
        activeBank = bank
        UserDefaults.standard.set(bank.rawValue, forKey: Keys.activeBank)
        loadBoard(preset.settings.sanitized(), transition: true)
        if allPresets.contains(where: { $0.id == preset.id }) {
            selectedPresetID = preset.id
        } else {
            selectedPresetID = nil
        }
        showToast("Bank \(bank.title): \(preset.name)")
    }

    /// Space bar. With two banks assigned it auditions A/B; otherwise it is a
    /// global processing bypass.
    func handleSpace() {
        if hasBothBanks {
            let next: PresetBank = activeBank == .a ? .b : .a
            loadBank(next)
        } else {
            settings.bypass.toggle()
            showToast(settings.bypass ? "Processing bypassed" : "Processing on")
        }
    }

    private func persistBanks() {
        let defaults = UserDefaults.standard
        if let bankA, let data = try? PresetCodec.encoder.encode(bankA) {
            defaults.set(data, forKey: Keys.bankA)
        } else {
            defaults.removeObject(forKey: Keys.bankA)
        }
        if let bankB, let data = try? PresetCodec.encoder.encode(bankB) {
            defaults.set(data, forKey: Keys.bankB)
        } else {
            defaults.removeObject(forKey: Keys.bankB)
        }
        defaults.set(activeBank.rawValue, forKey: Keys.activeBank)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.board)
        }
        defaults.set(selectedPresetID, forKey: Keys.selectedPreset)
        defaults.set(bufferSize, forKey: Keys.bufferSize)
        defaults.set(selectedInputUID, forKey: Keys.inputUID)
        defaults.set(selectedOutputUID, forKey: Keys.outputUID)
        defaults.set(isEnabled, forKey: Keys.enabled)
    }

    func shutdown() {
        saveWorkItem?.cancel()
        saveNow()
        if isRecording {
            _ = recorder.stop()
            isRecording = false
        }
        engine.stop()
    }

    // MARK: - Feedback

    func showToast(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.toast = nil
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private func startMeterTimer() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let peaks = self.engine.processor.levels.snapshot()
                self.meter.input = max(peaks.input, self.meter.input * 0.82)
                self.meter.output = max(peaks.output, self.meter.output * 0.82)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }
}


private extension DateFormatter {
    static let recordingStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
