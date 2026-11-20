//  HeaderBar.swift
//  GtrBoard
//
//  Brand, preset switcher, live status, bypass and power. Also the window
//  drag surface.

import SwiftUI
import AppKit
import BoardCore

struct HeaderBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            brand
                .padding(.leading, 78)

            presetControls

            Spacer(minLength: 8)

            status
            SignalMeter(meter: model.meter)
                .padding(.leading, 2)
            bypassButton
            powerButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .frame(height: 78)
        .background(WindowDragArea())
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: 32, height: 3)
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 92).allowsHitTesting(false)
                WindowDragArea()
            }
            .frame(height: 20)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Color(hex: 0xD97706)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 2)

                PickShape()
                    .fill(Color(hex: 0x1A120C))
                    .frame(width: 17, height: 19)

                Circle()
                    .fill(Color(hex: 0x1A120C).opacity(0.55))
                    .frame(width: 3.2, height: 3.2)
                    .offset(y: -1)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("GTRBOARD")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .tracking(2.4)
                    .foregroundStyle(Theme.text)
                Text("GUITAR RIG · LOW LATENCY")
                    .font(.system(size: 6.8, weight: .medium, design: .default))
                    .tracking(1.1)
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize()
    }

    private var presetControls: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "chevron.left", help: "Previous preset") {
                model.stepPreset(by: -1)
            }

            Button {
                PresetMenuPresenter.show(model: model)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(model.activePresetName)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(model.activePreset?.gear ?? "Your own chain · \(model.settings.units.filter(\.enabled).count) pedals")
                            .font(.ui(8.5))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 11)
                .frame(width: 260, height: 38, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .frame(width: 260, height: 38)

            IconButton(systemName: "chevron.right", help: "Next preset") {
                model.stepPreset(by: 1)
            }
            IconButton(systemName: "square.and.arrow.down", help: "Save preset") {
                model.beginSavePreset()
            }
            IconButton(systemName: "rectangle.stack", help: "Browse presets") {
                model.isShowingPresets = true
            }

            HStack(spacing: 3) {
                bankButton(.a)
                bankButton(.b)
            }
            .padding(.leading, 2)
        }
    }

    /// Compact A/B slot. Empty slot assigns the current board; filled slot
    /// loads the bank. Right-click reassigns or clears it.
    private func bankButton(_ bank: PresetBank) -> some View {
        let preset = model.bankPreset(bank)
        let isActive = model.activeBank == bank && preset != nil

        return Button {
            if preset == nil {
                model.assignCurrentToBank(bank)
            } else {
                model.loadBank(bank)
            }
        } label: {
            Text(bank.title)
                .font(.system(size: 9, weight: .bold, design: .default))
                .foregroundStyle(isActive ? Theme.background : (preset == nil ? Theme.faint : Theme.text))
                .frame(width: 25, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Theme.accent : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? Theme.accent : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(preset == nil
              ? "Assign the current board to Bank \(bank.title)"
              : "Bank \(bank.title): \(preset!.name) — click to load")
        .contextMenu {
            Button("Set to Current Board") { model.assignCurrentToBank(bank) }
            if preset != nil {
                Button("Load Bank \(bank.title)") { model.loadBank(bank) }
                Button("Clear Bank \(bank.title)", role: .destructive) { model.clearBank(bank) }
            }
        }
    }

    private var status: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 6.5, height: 6.5)
                .shadow(color: statusColor.opacity(0.8), radius: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.text)
                Text(statusDetail)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 140, maxWidth: 190, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .failed = model.engineState {
                model.isShowingMicrophoneHelp = true
            }
        }
        .help(model.routeLabel)
    }

    private var statusColor: Color {
        switch model.engineState {
        case .running: return Theme.green
        case .starting: return Theme.amber
        case .failed: return Theme.red
        case .idle: return Theme.faint
        }
    }

    private var statusTitle: String {
        switch model.engineState {
        case .running: return "LIVE"
        case .starting: return "OPENING AUDIO"
        case .failed: return "AUDIO ERROR"
        case .idle: return "AUDIO OFF"
        }
    }

    private var statusDetail: String {
        switch model.engineState {
        case .running:
            guard let format = model.format else { return model.routeLabel }
            return "\(format.sampleRateLabel) · \(format.bufferFrames) smp · \(format.latencyLabel)"
        case .starting:
            return "Preparing device…"
        case let .failed(message):
            return message
        case .idle:
            return "Press power to start"
        }
    }

    private var bypassButton: some View {
        PillButton(
            title: "BYPASS",
            systemName: "arrow.uturn.left",
            isActive: model.isBypassed,
            tint: Theme.amber
        ) {
            model.setBypass(!model.isBypassed)
        }
        .help("Pass the guitar through untouched (A/B the board)")
    }

    private var powerButton: some View {
        Button {
            model.togglePower()
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.isRunning ? Theme.background : (model.isStarting ? Theme.amber : Theme.subtext))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(model.isRunning ? Theme.accent : Color.white.opacity(0.05))
                )
                .overlay(
                    Circle().stroke(model.isRunning ? Theme.accent : Theme.stroke, lineWidth: 1)
                )
                .shadow(color: model.isRunning ? Theme.accent.opacity(0.45) : .clear, radius: 9)
        }
        .buttonStyle(.plain)
        .help(model.isRunning ? "Stop audio" : "Start audio")
    }
}
