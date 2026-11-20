//  MenuBarContent.swift
//  GtrBoard
//
//  Compact menu-bar control surface: window, power, bypass, A/B banks and
//  preset selection, available without bringing the main window forward.

import SwiftUI
import AppKit
import BoardCore

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open GtrBoard") {
            openMainWindow()
        }

        Divider()

        Button(model.isRunning ? "Stop Audio" : "Start Audio") {
            model.togglePower()
        }
        Button(model.isBypassed ? "Enable Processing" : "Bypass Processing") {
            model.setBypass(!model.isBypassed)
        }
        Button(model.hasBothBanks ? "Switch A/B  (Space)" : "Toggle Bypass  (Space)") {
            model.handleSpace()
        }

        Divider()

        bankItem(.a)
        bankItem(.b)

        Divider()

        Menu("Preset") {
            Menu("Factory") {
                ForEach(BuiltInPresets.all) { preset in
                    Button(preset.name) { model.apply(preset) }
                }
            }
            if !model.userPresets.isEmpty {
                Menu("User") {
                    ForEach(model.userPresets) { preset in
                        Button(preset.name) { model.apply(preset) }
                    }
                }
            }
        }

        Button(model.isRecording ? "Stop Recording" : "Record Output") { model.toggleRecording() }
        Button("Save Preset…") {
            openMainWindow()
            model.beginSavePreset()
        }
        Button("Browse Presets…") {
            openMainWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                model.isShowingPresets = true
            }
        }

        Divider()

        Button("Quit GtrBoard") {
            model.shutdown()
            NSApp.terminate(nil)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func bankItem(_ bank: PresetBank) -> some View {
        let preset = model.bankPreset(bank)
        let title = preset == nil
            ? "Assign Current to Bank \(bank.title)"
            : "Load Bank \(bank.title): \(preset!.name)"
        return Button(title) {
            if preset == nil {
                model.assignCurrentToBank(bank)
            } else {
                model.loadBank(bank)
            }
        }
    }
}
