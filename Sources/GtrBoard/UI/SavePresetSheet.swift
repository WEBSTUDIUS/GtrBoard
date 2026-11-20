//  SavePresetSheet.swift
//  GtrBoard
//
//  Naming and documenting a new user preset.

import SwiftUI
import BoardCore

struct SavePresetSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Save Preset")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Captures the full board, graphic EQ and master level.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
            }
            .padding(20)

            Hairline()

            VStack(alignment: .leading, spacing: 12) {
                field("Name", text: $model.presetNameDraft, placeholder: "Texas Flood")
                field("Gear", text: $model.presetGearDraft, placeholder: "TS-808 → Deluxe Reverb")
                field("Tags", text: $model.presetTagsDraft, placeholder: "blues, lead")

                VStack(alignment: .leading, spacing: 5) {
                    Text("NOTES")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.faint)
                    TextEditor(text: $model.presetNotesDraft)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(height: 84)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 1)
                        )
                }
            }
            .padding(20)

            Hairline()

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.subtext)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.05)))

                Button {
                    model.commitSavePreset()
                } label: {
                    Text("Save Preset")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.accent.opacity(canSave ? 1 : 0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 430)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var canSave: Bool {
        !model.presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.faint)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        }
    }
}
