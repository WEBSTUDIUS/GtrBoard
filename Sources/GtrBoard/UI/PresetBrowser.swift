//  PresetBrowser.swift
//  GtrBoard
//
//  Preset library: factory rigs and the user's own snapshots, with search,
//  preview, load, export, duplicate and delete.

import SwiftUI
import BoardCore

struct PresetBrowserView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?

    private var filteredFactory: [Preset] { filter(BuiltInPresets.all) }
    private var filteredUser: [Preset] { filter(model.userPresets) }

    private var selectedPreset: Preset? {
        guard let selection else { return nil }
        return model.allPresets.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            HStack(spacing: 0) {
                list
                    .frame(width: 320)
                Hairline().frame(width: 1, height: nil)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Hairline()
            footer
        }
        .frame(width: 860, height: 570)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            selection = model.selectedPresetID ?? BuiltInPresets.all.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preset Library")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(BuiltInPresets.all.count) factory rigs · \(model.userPresets.count) user presets")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faint)
                TextField("Search by name, gear or tag", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text)
                    .frame(width: 190)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                if !filteredFactory.isEmpty {
                    Section {
                        ForEach(filteredFactory) { preset in
                            row(preset)
                        }
                    } header: {
                        listHeader("Factory", count: filteredFactory.count)
                    }
                }
                if !filteredUser.isEmpty {
                    Section {
                        ForEach(filteredUser) { preset in
                            row(preset)
                        }
                    } header: {
                        listHeader("User", count: filteredUser.count)
                    }
                }
                if filteredFactory.isEmpty && filteredUser.isEmpty {
                    Text("No presets match “\(query)”.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .padding(20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Theme.panelSoft.opacity(0.6))
    }

    private func listHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.faint)
            Spacer()
            Text("\(count)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Theme.panelSoft)
    }

    private func row(_ preset: Preset) -> some View {
        let isSelected = selection == preset.id
        return Button {
            selection = preset.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.text : Theme.subtext)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if model.selectedPresetID == preset.id {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    }
                }
                Text(preset.gear.isEmpty ? preset.settings.chainSummary : preset.gear)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let preset = selectedPreset {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Text(preset.gear)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.subtext)
                        }

                        HStack(spacing: 6) {
                            TagPill(text: preset.isBuiltIn ? "Factory" : "User")
                            ForEach(preset.tags, id: \.self) { tag in
                                TagPill(text: tag, tint: Theme.mint)
                            }
                            if abs(preset.settings.outputTrim) > 0.05 {
                                TagPill(
                                    text: String(format: "Level %+.1f dB", preset.settings.outputTrim),
                                    tint: Theme.cyan
                                )
                            }
                        }

                        if !preset.notes.isEmpty {
                            Text(preset.notes)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.subtext)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            SectionLabel(text: "Signal chain", trailing: preset.settings.chainSummary)
                            VStack(spacing: 0) {
                                ForEach(Array(preset.settings.units.enumerated()), id: \.element.id) { index, unit in
                                    if unit.enabled {
                                        HStack(spacing: 8) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Theme.faint)
                                                .frame(width: 16, alignment: .leading)
                                            Circle()
                                                .fill(Theme.color(for: unit.kind))
                                                .frame(width: 6, height: 6)
                                            Text(unit.descriptor.name)
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(Theme.text)
                                            Text(unit.descriptor.subtitle)
                                                .font(.system(size: 8.5))
                                                .foregroundStyle(Theme.faint)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                            Text(unit.descriptor.shortName)
                                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Theme.faint)
                                        }
                                        .padding(.vertical, 5)
                                        Divider().overlay(Theme.stroke)
                                    }
                                }
                            }
                        }

                        if !preset.settings.graphicEQ.isFlat {
                            VStack(alignment: .leading, spacing: 5) {
                                SectionLabel(text: "Graphic EQ")
                                Text(preset.settings.graphicEQ.gains
                                    .enumerated()
                                    .map { String(format: "%@:%+.0f", GraphicEQSettings.labels[$0.offset], $0.element) }
                                    .joined(separator: "  "))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Theme.mint.opacity(0.8))
                            }
                        }
                    }
                    .padding(20)
                }

                Hairline()
                HStack(spacing: 8) {
                    Button {
                        model.apply(preset)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Load Preset")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)

                    PillButton(title: "Export", systemName: "square.and.arrow.up") {
                        model.exportPreset(preset)
                    }
                    PillButton(title: "Duplicate", systemName: "plus.square.on.square") {
                        model.duplicatePreset(preset)
                        selection = model.selectedPresetID
                    }
                    Menu {
                        Button("Set as Bank A") { model.assignBank(.a, preset: preset) }
                        Button("Set as Bank B") { model.assignBank(.b, preset: preset) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Banks")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.subtext)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.045)))
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    if !preset.isBuiltIn {
                        PillButton(title: "Delete", systemName: "trash", tint: Theme.red) {
                            model.deletePreset(preset)
                            selection = nil
                        }
                    }
                    Spacer()
                    if preset.isBuiltIn {
                        Text("Factory presets are read-only — save a copy to edit.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Theme.faint)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.faint)
                Text("Select a preset to preview its rig")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PillButton(title: "Import Preset…", systemName: "square.and.arrow.down") {
                model.importPresetFromPanel()
            }
            Spacer()
            Text("Presets are plain JSON — share the .gtrpreset file")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.faint)
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func filter(_ presets: [Preset]) -> [Preset] {
        guard !query.isEmpty else { return presets }
        let needle = query.lowercased()
        return presets.filter { preset in
            preset.name.lowercased().contains(needle)
                || preset.gear.lowercased().contains(needle)
                || preset.notes.lowercased().contains(needle)
                || preset.tags.joined(separator: " ").lowercased().contains(needle)
        }
    }
}
