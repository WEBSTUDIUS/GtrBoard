//  PluginBoardView.swift
//  GtrBoardAU
//
//  The pedalboard inside the DAW plug-in window. It reuses the standalone
//  pedal cards and theme, but talks to the audio unit through PluginModel.

import SwiftUI
import BoardCore

struct PluginBoardView: View {
    @ObservedObject var model: PluginModel

    private static let eqParameters: [FXParameter] = (0..<GraphicEQSettings.frequencies.count).map { index in
        FXParameter(
            id: "eqBand\(index)",
            name: GraphicEQSettings.labels[index] + " Hz",
            minValue: GraphicEQSettings.range.lowerBound,
            maxValue: GraphicEQSettings.range.upperBound,
            defaultValue: 0,
            unit: .decibels
        )
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                Hairline()
                board
                Hairline()
                eqPanel
            }
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                PickShape()
                    .fill(Theme.accent)
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GTRBOARD")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                    Text("AUv3 · GUITAR RIG")
                        .font(.system(size: 7, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.faint)
                }
            }
            .fixedSize()

            Menu {
                ForEach(BuiltInPresets.all) { preset in
                    Button(preset.name) {
                        model.applyPreset(preset)
                    }
                }
                Divider()
                Button("Init / Default Board") {
                    model.resetBoard()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.presetName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Factory preset")

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("MASTER")
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.faint)
                Slider(
                    value: Binding(
                        get: { model.settings.masterVolume },
                        set: { model.setMaster($0) }
                    ),
                    in: BoardSettings.masterRange
                )
                .frame(width: 110)
                .controlSize(.mini)
                .tint(Theme.accent)
                Text(String(format: "%+.1f", model.settings.masterVolume))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, alignment: .trailing)
            }

            MiniSwitch(
                isOn: Binding(
                    get: { model.settings.feedbackGuard },
                    set: { model.setFeedbackGuard($0) }
                ),
                tint: Theme.mint,
                label: "GUARD"
            )
            MiniSwitch(
                isOn: Binding(
                    get: { model.settings.limiter },
                    set: { model.setLimiter($0) }
                ),
                tint: Theme.amber,
                label: "LIMIT"
            )
            MiniSwitch(
                isOn: Binding(
                    get: { model.settings.bypass },
                    set: { model.setBypass($0) }
                ),
                tint: Theme.red,
                label: "BYPASS"
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.panelSoft)
    }

    private var board: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(model.settings.units.enumerated()), id: \.element.id) { index, unit in
                    PedalCard(
                        unit: unit,
                        position: index,
                        total: model.settings.units.count,
                        onToggle: {
                            model.setUnitEnabled(unit.kind, !unit.enabled)
                        },
                        onParameter: { parameter, value in
                            model.setParameter(unit.kind, parameter, value)
                        },
                        onMove: { offset in
                            model.moveUnit(unit.kind, by: offset)
                        },
                        onImportIR: nil,
                        customIRName: nil,
                        allowsCustomIR: false
                    )

                    if index < model.settings.units.count - 1 {
                        CableConnector(tint: Theme.color(for: unit.kind))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var eqPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GRAPHIC EQ")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.subtext)
                MiniSwitch(
                    isOn: Binding(
                        get: { model.settings.graphicEQ.enabled },
                        set: { model.setEQEnabled($0) }
                    ),
                    tint: Theme.mint
                )
            }
            .frame(width: 70, alignment: .leading)

            ForEach(Array(Self.eqParameters.enumerated()), id: \.offset) { index, parameter in
                Knob(
                    parameter: parameter,
                    value: Binding(
                        get: {
                            model.settings.graphicEQ.gains.indices.contains(index)
                                ? model.settings.graphicEQ.gains[index]
                                : 0
                        },
                        set: { model.setEQBand(index, $0) }
                    ),
                    tint: Theme.mint,
                    isEnabled: model.settings.graphicEQ.enabled
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 96)
        .background(Theme.panelSoft)
    }
}
