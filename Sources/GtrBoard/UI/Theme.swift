//  Theme.swift
//  GtrBoard
//
//  Warm, pedalboard-inspired palette and shared surfaces. One place to tune
//  the entire look of the app.

import SwiftUI
import AppKit
import BoardCore

enum Theme {
    static let background = Color(hex: 0x0B0908)
    static let backgroundLifted = Color(hex: 0x100D0B)
    static let panel = Color(hex: 0x15110F)
    static let panelRaised = Color(hex: 0x1C1714)
    static let panelSoft = Color(hex: 0x110E0C)

    static let stroke = Color.white.opacity(0.075)
    static let strokeStrong = Color.white.opacity(0.14)

    static let text = Color(hex: 0xF6F1EA)
    static let subtext = Color(hex: 0x9C948B)
    static let faint = Color(hex: 0x6C655E)

    /// Warm amber is the primary accent, like the lamp on a valve amp.
    static let accent = Color(hex: 0xFFB26B)
    static let accentSoft = Color(hex: 0xFFB26B).opacity(0.16)
    /// Cool mint for EQ and secondary highlights.
    static let mint = Color(hex: 0x6EE7C7)
    static let cyan = Color(hex: 0x67E8F9)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xFB7185)
    static let green = Color(hex: 0x4ADE80)

    static func color(for kind: FXKind) -> Color {
        Color(hex: kind.descriptor.colorHex)
    }

    static let monoSmall = Font.system(size: 9.5, weight: .medium, design: .monospaced)
    static let monoValue = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 9.5, weight: .semibold, design: .default)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Rounded panel with the standard hairline border.
struct PanelBackground: View {
    var radius: CGFloat = 16
    var raised: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(raised ? Theme.panelRaised : Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

/// Applies the standard panel padding and background.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var raised: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(PanelBackground(raised: raised))
    }
}

/// Uppercase tracked section header with optional right-aligned detail.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.ui(9.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.subtext)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
    }
}

/// Small round icon button used in the header and browser.
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var isActive: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : (hovering ? Theme.text : Theme.subtext))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.07) : Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Pill-shaped text button.
struct PillButton: View {
    let title: String
    var systemName: String?
    var isActive: Bool = false
    var tint: Color = Theme.accent
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.ui(10.5, .semibold))
            }
            .foregroundStyle(isActive ? Theme.background : (hovering ? Theme.text : Theme.subtext))
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(
                Capsule()
                    .fill(isActive ? tint : Color.white.opacity(hovering ? 0.08 : 0.045))
            )
            .overlay(
                Capsule().stroke(isActive ? tint.opacity(0.9) : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Horizontal peak meter with a green→amber→red gradient.
struct LevelMeterBar: View {
    var level: Float
    var width: CGFloat = 64
    var segments: Int = 14
    var isActive: Bool = true

    private var normalized: Double {
        guard isActive, level > 0 else { return 0 }
        let db = 20 * log10(max(Double(level), 0.00001))
        return ((db + 48) / 48).clamped(to: 0...1)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Double(index + 1) / Double(segments)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color(for: Double(index) / Double(segments)))
                    .opacity(normalized >= threshold ? 1 : 0.12)
            }
        }
        .frame(width: width, height: 7)
    }

    private func color(for position: Double) -> Color {
        if position > 0.86 { return Theme.red }
        if position > 0.68 { return Theme.amber }
        return Theme.mint
    }
}

/// Moving-average style signal meter used in the header.
struct SignalMeter: View {
    @ObservedObject var meter: MeterModel

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("IN")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                    LevelMeterBar(level: meter.input, width: 52)
                }
                HStack(spacing: 4) {
                    Text("OUT")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                    LevelMeterBar(level: meter.output, width: 52)
                }
            }
        }
    }
}

/// Small on/off switch used for the graphic EQ and the limiter.
struct MiniSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Theme.accent
    var label: String?

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                if let label {
                    Text(label.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(isOn ? Theme.text : Theme.faint)
                }
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? tint.opacity(0.85) : Color.white.opacity(0.08))
                        .frame(width: 28, height: 16)
                    Circle()
                        .fill(isOn ? Theme.background : Theme.subtext)
                        .frame(width: 11, height: 11)
                        .padding(.horizontal, 2.5)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Tag pill used in the preset browser.
struct TagPill: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
    }
}

/// Transient confirmation message.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.mint)
            Text(message)
                .font(.ui(11.5, .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Theme.panelRaised)
                .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        )
    }
}

/// Lets the header drag the window while keeping the rest of the UI clickable.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DraggingView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

extension NSColor {
    static var appBackground: NSColor {
        NSColor(calibratedRed: 11 / 255, green: 9 / 255, blue: 8 / 255, alpha: 1)
    }
}
