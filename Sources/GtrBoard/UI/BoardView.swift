//  BoardView.swift
//  GtrBoard
//
//  The pedalboard: an ordered, horizontally scrollable chain of pedals with
//  patch cables between them. Order is the actual DSP order.

import SwiftUI
import BoardCore

struct BoardView: View {
    @ObservedObject var model: AppModel

    private var units: [FXUnit] { model.settings.units }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel(text: "Pedalboard", trailing: model.settings.chainSummary)
                Spacer(minLength: 12)
                Text("\(units.filter(\.enabled).count) of \(units.count) engaged")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.faint)
                PillButton(
                    title: "Reset chain",
                    systemName: "arrow.triangle.2.circlepath",
                    action: resetChain
                )
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        PedalCard(
                            unit: unit,
                            position: index,
                            total: units.count,
                            onToggle: {
                                model.setUnitEnabled(unit.kind, !unit.enabled)
                            },
                            onParameter: { parameter, value in
                                model.setParameter(unit.kind, parameter, value)
                            },
                            onMove: { offset in
                                model.moveUnit(unit.kind, by: offset)
                            },
                            onImportIR: unit.kind == .ir ? {
                                model.importImpulseResponse()
                            } : nil,
                            customIRName: model.customIRName
                        )

                        if index < units.count - 1 {
                            CableConnector(tint: Theme.color(for: unit.kind))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 14) {
                hint(icon: "hand.draw", text: "Drag a knob vertically · double-click resets it")
                hint(icon: "arrow.left.arrow.right", text: "Use the chevrons to change the pedal order")
                hint(icon: "space", text: "Space: A/B or bypass")
                Spacer()
                if !model.settings.graphicEQ.isFlat {
                    Text("Graphic EQ is shaping the output")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.mint.opacity(0.8))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    private func hint(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.faint)
            Text(text)
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.faint)
        }
    }

    private func resetChain() {
        model.resetChain()
    }
}
