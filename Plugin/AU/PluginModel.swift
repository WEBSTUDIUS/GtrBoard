//  PluginModel.swift
//  GtrBoardAU
//
//  Small observable bridge between the AUv3 parameters and the SwiftUI board.
//  It deliberately keeps no audio engine of its own: every change goes through
//  the audio unit, which owns the single BoardProcessor.

import SwiftUI
import BoardCore

/// Theme.swift's SignalMeter needs this type; the plugin does not draw meters.
@MainActor
final class MeterModel: ObservableObject {
    @Published var input: Float = 0
    @Published var output: Float = 0
}

@MainActor
final class PluginModel: ObservableObject {
    @Published private(set) var settings: BoardSettings
    @Published private(set) var presetName: String = "Custom"

    private let audioUnit: GtrBoardAudioUnit

    init(audioUnit: GtrBoardAudioUnit) {
        self.audioUnit = audioUnit
        settings = audioUnit.boardSettings
        audioUnit.onSettingsChanged = { [weak self] in
            guard let self else { return }
            let updated = self.audioUnit.boardSettings
            guard updated != self.settings else { return }
            self.settings = updated
            self.presetName = "Custom"
        }
    }

    // MARK: - Board edits

    func setUnitEnabled(_ kind: FXKind, _ enabled: Bool) {
        mutate { $0.setEnabled(enabled, for: kind) }
    }

    func setParameter(_ kind: FXKind, _ parameter: String, _ value: Double) {
        mutate { $0.setParam(value, for: kind, parameter: parameter) }
    }

    func moveUnit(_ kind: FXKind, by offset: Int) {
        mutate { $0.shiftUnit(kind, by: offset) }
    }

    func setMaster(_ value: Double) {
        mutate { $0.masterVolume = value.clamped(to: BoardSettings.masterRange) }
    }

    func setTrim(_ value: Double) {
        mutate { $0.outputTrim = value.clamped(to: BoardSettings.trimRange) }
    }

    func setBypass(_ value: Bool) {
        mutate { $0.bypass = value }
    }

    func setLimiter(_ value: Bool) {
        mutate { $0.limiter = value }
    }

    func setFeedbackGuard(_ value: Bool) {
        mutate { $0.feedbackGuard = value }
    }

    func setEQEnabled(_ value: Bool) {
        mutate { $0.graphicEQ.enabled = value }
    }

    func setEQBand(_ index: Int, _ value: Double) {
        mutate { board in
            guard board.graphicEQ.gains.indices.contains(index) else { return }
            board.graphicEQ.gains[index] = value.clamped(to: GraphicEQSettings.range)
        }
    }

    func applyPreset(_ preset: Preset) {
        settings = preset.settings.sanitized()
        presetName = preset.name
        audioUnit.applySettings(settings)
    }

    func resetBoard() {
        settings = BoardSettings.defaultBoard().sanitized()
        presetName = "Init"
        audioUnit.applySettings(settings)
    }

    private func mutate(_ change: (inout BoardSettings) -> Void) {
        var board = settings
        change(&board)
        let clean = board.sanitized()
        guard clean != settings else { return }
        settings = clean
        presetName = "Custom"
        audioUnit.applySettings(clean)
    }
}
