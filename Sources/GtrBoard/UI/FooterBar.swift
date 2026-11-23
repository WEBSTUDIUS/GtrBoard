//  FooterBar.swift
//  GtrBoard
//
//  Device routing, buffer size, limiter, master volume and the live session
//  readout.

import SwiftUI
import BoardCore

struct FooterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            deviceMenu(
                icon: "mic.fill",
                title: model.selectedInput?.name ?? "No Input",
                devices: model.inputDevices,
                selection: $model.selectedInputUID,
                allowsNone: true
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.faint)

            deviceMenu(
                icon: "hifispeaker.fill",
                title: model.selectedOutput?.name ?? "Output",
                devices: model.outputDevices,
                selection: $model.selectedOutputUID
            )

            bufferMenu

            Spacer(minLength: 8)

            recordButton

            bitDepthMenu

            divider

            presetLevelControl

            masterLevelControl

            MiniSwitch(
                isOn: Binding(
                    get: { model.settings.limiter },
                    set: { model.setLimiter($0) }
                ),
                tint: Theme.amber,
                label: "LIMIT"
            )

            guardControl

            IconButton(systemName: "arrow.clockwise", help: "Refresh audio devices") {
                model.refreshDevices()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.panelSoft)
        .overlay(alignment: .top) { Hairline() }
    }


    /// Feedback guard switch plus a live status badge. The switch is the
    /// explicit off button; the badge only appears while the guard is doing
    /// something and doubles as the re-arm control after a MUTED latch.
    private var guardControl: some View {
        HStack(spacing: 6) {
            MiniSwitch(
                isOn: Binding(
                    get: { model.settings.feedbackGuard },
                    set: { model.setFeedbackGuard($0) }
                ),
                tint: Theme.mint,
                label: "GUARD"
            )
            .help("Automatic feedback guard: notches howls above 2 kHz and mains hum. Switch it off here if a sustained note gets caught.")

            if model.settings.feedbackGuard, model.guardStatus.isActive {
                guardBadge
            }
        }
    }

    private var guardBadge: some View {
        let status = model.guardStatus
        let muted = status.muted
        let tint: Color = muted
            ? Theme.red
            : (status.humDetected ? Theme.amber : Theme.red)
        let title: String = {
            if muted { return "MUTED" }
            if status.humDetected { return "HUM" }
            if status.activeNotches > 0 { return "FB \(status.activeNotches)" }
            if status.gainReductionDB < -0.2 { return "DUCK" }
            return ""
        }()

        return Button {
            if muted { model.resetFeedbackMute() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: muted
                      ? "speaker.slash.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(muted
              ? "The input is muted because a feedback loop would not stop. Click to re-arm — headphones or an interface are the real fix."
              : "Feedback guard is working on this signal.")
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 20)
    }

    private var bitDepthMenu: some View {
        Menu {
            Button {
                model.setRecordingBitDepth(24)
            } label: {
                if model.recordingBitDepth == 24 {
                    Label("24-bit PCM", systemImage: "checkmark")
                } else {
                    Text("24-bit PCM")
                }
            }
            Button {
                model.setRecordingBitDepth(32)
            } label: {
                if model.recordingBitDepth == 32 {
                    Label("32-bit float", systemImage: "checkmark")
                } else {
                    Text("32-bit float")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(model.recordingBitDepth)-bit")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 5.5, weight: .bold))
            }
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.isRecording)
        .help("Recording format: 24-bit PCM (default, smaller files) or 32-bit float")
    }

    private var presetLevelControl: some View {
        HStack(spacing: 6) {
            Text("PRESET")
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            Slider(
                value: Binding(
                    get: { model.settings.outputTrim },
                    set: { model.setPresetLevel($0) }
                ),
                in: BoardSettings.trimRange
            )
            .frame(width: 74)
            .controlSize(.mini)
            .tint(Theme.mint)
            Text(String(format: "%+.1f", model.settings.outputTrim))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.mint)
                .frame(width: 34, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.setPresetLevel(0) }
        }
        .help("Per-preset output level (after master, before limiter). Double-click the value for 0 dB.")
        .contextMenu {
            Button("Reset to 0 dB") { model.setPresetLevel(0) }
            Button("Use Current Preset Level") { model.resetPresetLevelToPreset() }
        }
    }

    private var masterLevelControl: some View {
        HStack(spacing: 7) {
            Text("MASTER")
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            Slider(
                value: Binding(
                    get: { model.settings.masterVolume },
                    set: { model.setMasterVolume($0) }
                ),
                in: BoardSettings.masterRange
            )
            .frame(width: 92)
            .controlSize(.mini)
            .tint(Theme.accent)
            Text(String(format: "%+.1f", model.settings.masterVolume))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: 36, alignment: .trailing)
        }
        .help("Global output level for every preset")
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(model.isRecording ? Theme.red.opacity(0.18) : Color.white.opacity(0.04))
                        .frame(width: 26, height: 26)
                    if model.isRecording {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.red)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .overlay(
                    Circle().stroke(model.isRecording ? Theme.red.opacity(0.7) : Theme.stroke, lineWidth: 1)
                )

                if model.isRecording, let started = model.recordingStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.durationLabel(context.date.timeIntervalSince(started)))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.red)
                    }
                } else {
                    Text("REC")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.subtext)
                }
            }
        }
        .buttonStyle(.plain)
        .help(model.isRecording
              ? "Stop and save the processed output"
              : "Record the processed output to ~/Music/GtrBoard and drag the WAV into your DAW")
        .contextMenu {
            if model.lastRecordingURL != nil {
                Button("Reveal Last Recording in Finder") { model.revealLastRecording() }
            }
        }
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func deviceMenu(
        icon: String,
        title: String,
        devices: [AudioDevice],
        selection: Binding<String?>,
        allowsNone: Bool = false
    ) -> some View {
        Menu {
            if allowsNone {
                Button {
                    selection.wrappedValue = AppModel.noInputUID
                } label: {
                    HStack {
                        if selection.wrappedValue == AppModel.noInputUID {
                            Image(systemName: "checkmark")
                        }
                        Text("No Input")
                        Spacer()
                        Text("silent")
                    }
                }
                Divider()
            }
            if devices.isEmpty {
                Text("No devices found")
            } else {
                ForEach(devices) { device in
                    Button {
                        selection.wrappedValue = device.uid
                    } label: {
                        HStack {
                            if selection.wrappedValue == device.uid {
                                Image(systemName: "checkmark")
                            }
                            Text(device.name)
                            Spacer()
                            Text(device.channelLabel)
                        }
                    }
                }
            }
            Divider()
            Button("Refresh Devices") { model.refreshDevices() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.9))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 9)
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
    }

    private var bufferMenu: some View {
        Menu {
            ForEach([64, 128, 256, 512], id: \.self) { size in
                Button {
                    model.bufferSize = size
                } label: {
                    HStack {
                        if model.bufferSize == size { Image(systemName: "checkmark") }
                        Text("\(size) samples")
                        Spacer()
                        Text(String(format: "%.1f ms", Double(size) / (model.format?.sampleRate ?? 48_000) * 1_000))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Text("\(model.bufferSize) smp")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Audio buffer size. Lower is tighter; 64–128 samples is a good guitar range.")
    }
}
