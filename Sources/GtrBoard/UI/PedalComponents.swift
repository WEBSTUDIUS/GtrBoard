//  PedalComponents.swift
//  GtrBoard
//
//  The physical vocabulary of the board: knobs, footswitches, jacks and the
//  pedal card itself. All controls are custom so the app feels like hardware
//  rather than a form.

import SwiftUI
import BoardCore

/// 270° arc used as a knob track.
struct KnobArc: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - 2
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(135 + 270 * from),
            endAngle: .degrees(135 + 270 * to),
            clockwise: false
        )
        return path
    }
}

/// One parameter knob. Drag vertically to change, double-click to reset.
struct Knob: View {
    let parameter: FXParameter
    @Binding var value: Double
    var tint: Color
    var isEnabled: Bool = true

    @State private var dragStart: Double?
    @State private var hovering = false

    private var normalized: Double { parameter.normalized(value) }
    private var angle: Double { -135 + 270 * normalized }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                KnobArc(from: 0, to: 1)
                    .stroke(Color.white.opacity(0.075), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                KnobArc(from: 0, to: max(0.001, normalized))
                    .stroke(tint.opacity(isEnabled ? 1 : 0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: tint.opacity(isEnabled ? 0.45 : 0), radius: hovering ? 5 : 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2A2521), Color(hex: 0x16120F)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 27, height: 27)
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                Capsule()
                    .fill(isEnabled ? Theme.text : Theme.faint)
                    .frame(width: 2, height: 9)
                    .offset(y: -8)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if dragStart == nil {
                            dragStart = normalized
                            hovering = true
                        }
                        let delta = -gesture.translation.height / 150
                        let position = ((dragStart ?? normalized) + delta).clamped(to: 0...1)
                        value = parameter.value(atNormalized: position)
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard isEnabled else { return }
                    value = parameter.fallback
                }
            )
            .onHover { hovering = $0 }
            .help("\(parameter.name) — \(parameter.display(value))")

            Text(parameter.shortDisplay(value))
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEnabled ? Theme.text : Theme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(parameter.name.uppercased())
                .font(.system(size: 7, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 58)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

/// Chunky pedal footswitch with a status LED.
struct Footswitch: View {
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x3A332C), Color(hex: 0x15110E)],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 22
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)

                Circle()
                    .fill(isOn ? tint : Color.white.opacity(0.10))
                    .frame(width: 7, height: 7)
                    .shadow(color: isOn ? tint.opacity(0.9) : .clear, radius: 5)
            }
            .scaleEffect(pressing ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
        .help(isOn ? "Bypass this pedal" : "Engage this pedal")
    }
}

/// A patch cable segment between two pedals.
struct CableConnector: View {
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Circle()
                    .fill(tint.opacity(0.55))
                    .frame(width: 5, height: 5)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 20, height: 1.5)
                Circle()
                    .fill(tint.opacity(0.55))
                    .frame(width: 5, height: 5)
            }
            Spacer()
        }
        .frame(width: 30, height: 300)
        .padding(.bottom, 14)
    }
}

/// Guitar-pick logo shape.
struct PickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 2, y: rect.midY * 0.72),
            control: CGPoint(x: rect.minX + 4, y: rect.maxY * 0.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 2),
            control: CGPoint(x: rect.minX + 2, y: rect.minY + 2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.midY * 0.72),
            control: CGPoint(x: rect.maxX - 2, y: rect.minY + 2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - 2),
            control: CGPoint(x: rect.maxX - 4, y: rect.maxY * 0.7)
        )
        path.closeSubpath()
        return path
    }
}

/// One pedal on the board.
struct PedalCard: View {
    let unit: FXUnit
    let position: Int
    let total: Int
    var onToggle: () -> Void
    var onParameter: (String, Double) -> Void
    var onMove: (Int) -> Void

    @State private var hovering = false

    private var descriptor: FXDescriptor { unit.descriptor }
    private var tint: Color { Theme.color(for: unit.kind) }
    private var width: CGFloat {
        switch unit.kind {
        case .amp: return 246
        case .delay, .cabinet, .reverb: return 198
        default: return 178
        }
    }
    private var columns: Int {
        let count = descriptor.parameters.count
        if count <= 3 { return 2 }
        if count <= 4 { return 2 }
        return 3
    }

    var body: some View {
        VStack(spacing: 9) {
            header
            Hairline().opacity(0.6)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                spacing: 8
            ) {
                ForEach(descriptor.parameters) { parameter in
                    Knob(
                        parameter: parameter,
                        value: Binding(
                            get: { unit.value(parameter.id) },
                            set: { onParameter(parameter.id, $0) }
                        ),
                        tint: tint,
                        isEnabled: unit.enabled
                    )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(unit.enabled ? "ENGAGED" : "BYPASSED")
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(unit.enabled ? tint : Theme.faint)
                Spacer(minLength: 0)
                Footswitch(isOn: unit.enabled, tint: tint, action: onToggle)
            }
        }
        .padding(12)
        .frame(width: width, height: 300)
        .background(cardBackground)
        .overlay(cardBorder)
        .overlay(alignment: .top) { topStrip }
        .shadow(color: unit.enabled ? tint.opacity(0.14) : .clear, radius: 12, y: 5)
        .opacity(unit.enabled ? 1 : 0.74)
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                Circle()
                    .fill(unit.enabled ? tint : Color.white.opacity(0.09))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: unit.enabled ? tint.opacity(0.85) : .clear, radius: 4)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.shortName)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.text)
                Text(descriptor.name)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                moveButton(systemName: "chevron.left", offset: -1, disabled: position == 0)
                moveButton(systemName: "chevron.right", offset: 1, disabled: position == total - 1)
            }
            .opacity(hovering ? 1 : 0.35)
        }
    }

    private func moveButton(systemName: String, offset: Int, disabled: Bool) -> some View {
        Button {
            onMove(offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.subtext)
                .frame(width: 15, height: 11)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .help(offset < 0 ? "Move earlier in the chain" : "Move later in the chain")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(unit.enabled ? 0.16 : 0.05),
                        Theme.panel.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(unit.enabled ? tint.opacity(0.32) : Theme.stroke, lineWidth: 1)
    }

    private var topStrip: some View {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 14)
            .fill(tint.opacity(unit.enabled ? 0.85 : 0.25))
            .frame(height: 2.5)
    }
}
