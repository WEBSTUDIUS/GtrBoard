//  PresetMenu.swift
//  GtrBoard
//
//  Native pull-down preset menu. AppKit gives us exact control over the
//  popup width and section headers, which a SwiftUI Menu cannot do reliably
//  for a wide custom label.

import AppKit
import BoardCore

/// NSMenuItem that runs a closure instead of an Objective-C selector.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, state: NSControl.StateValue = .off, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.state = state
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}

@MainActor
enum PresetMenuPresenter {
    static func show(model: AppModel) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(section("FACTORY"))
        for preset in BuiltInPresets.all {
            menu.addItem(presetItem(preset, model: model))
        }

        menu.addItem(.separator())
        menu.addItem(section("USER"))
        if model.userPresets.isEmpty {
            let empty = NSMenuItem(title: "No user presets yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for preset in model.userPresets {
                menu.addItem(presetItem(preset, model: model))
            }
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Browse Presets…") {
            model.isShowingPresets = true
        })
        menu.addItem(ClosureMenuItem(title: "Save Preset…") {
            model.beginSavePreset()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Import Preset…") {
            model.importPresetFromPanel()
        })
        menu.addItem(ClosureMenuItem(title: "Export Preset…") {
            model.exportCurrentPreset()
        })

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func section(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func presetItem(_ preset: Preset, model: AppModel) -> NSMenuItem {
        ClosureMenuItem(
            title: preset.name,
            state: model.selectedPresetID == preset.id ? .on : .off
        ) {
            model.apply(preset)
        }
    }
}
