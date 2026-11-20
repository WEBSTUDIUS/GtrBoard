//  GraphicEQView.swift
//  GtrBoard
//
//  Ten-band graphic equalizer drawn as a hardware-style fader bank with the
//  resulting curve behind the sliders.

import SwiftUI
import BoardCore

struct GraphicEQPanel: View {
    @ObservedObject var model: AppModel

    private var eq: GraphicEQSettings { model.settings.graphicEQ }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                SectionLabel(text: "Graphic EQ", trailing: "10-band · ±12 dB")
                Spacer(minLength: 12)
                MiniSwitch(
                    isOn: Binding(
                        get: { eq.enabled },
                        set: { model.setGraphicEnabled($0) }
                    ),
                    tint: Theme.mint,
                    label: "EQ"
                )
                PillButton(
                    title: "Flat",
                    systemName: "arrow.counterclockwise",
                    action: model.resetGraphicEQ
                )
            }

            EQGraphView(model: model)
                .frame(height: 146)
                .opacity(eq.enabled ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PanelBackground())
        .padding(.horizontal, 16)
    }
}

private struct EQGraphView: View {
    @ObservedObject var model: AppModel

    private let bandCount = 10
    private let range = GraphicEQSettings.range

    private var gains: [Double] { model.settings.graphicEQ.gains }
    private var isEnabled: Bool { model.settings.graphicEQ.enabled }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let faderHeight = max(60, geometry.size.height - 18)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.panelSoft)

                    Canvas { context, size in
                        drawGrid(context: &context, size: size)
                        drawCurve(context: &context, size: size)
                    }
                    .padding(1)

                    faders(width: width, height: faderHeight)
                }
                .frame(height: faderHeight)

                labels(width: width)
                    .frame(height: 18)
            }
        }
    }

    private func yPosition(for gain: Double, height: CGFloat) -> CGFloat {
        let fraction = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1 - CGFloat(fraction))
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let rows: [Double] = [-12, -6, 0, 6, 12]
        for gain in rows {
            let y = yPosition(for: gain, height: size.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let isZero = abs(gain) < 0.01
            context.stroke(
                path,
                with: .color(Theme.stroke.opacity(isZero ? 1.6 : 0.7)),
                lineWidth: isZero ? 1.2 : 0.7
            )
        }

        for index in 0...bandCount {
            let x = size.width * CGFloat(index) / CGFloat(bandCount)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(Theme.stroke.opacity(0.4)), lineWidth: 0.6)
        }
    }

    private func drawCurve(context: inout GraphicsContext, size: CGSize) {
        let points = curvePoints(size: size)
        guard points.count > 1 else { return }

        let path = smoothPath(points: points)
        let zeroY = yPosition(for: 0, height: size.height)

        var fill = path
        fill.addLine(to: CGPoint(x: points.last?.x ?? 0, y: zeroY))
        fill.addLine(to: CGPoint(x: points.first?.x ?? 0, y: zeroY))
        fill.closeSubpath()

        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [Theme.mint.opacity(isEnabled ? 0.22 : 0.08), Theme.mint.opacity(0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: zeroY)
            )
        )

        context.stroke(
            path,
            with: .color(Theme.mint.opacity(isEnabled ? 0.25 : 0.1)),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        context.stroke(
            path,
            with: .color(Theme.mint.opacity(isEnabled ? 0.95 : 0.35)),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
    }

    private func curvePoints(size: CGSize) -> [CGPoint] {
        let count = gains.count
        var points: [CGPoint] = []
        for index in 0..<count {
            let x = size.width * (CGFloat(index) + 0.5) / CGFloat(count)
            let y = yPosition(for: gains[index], height: size.height)
            points.append(CGPoint(x: x, y: y))
        }
        if let first = points.first {
            points.insert(CGPoint(x: 0, y: first.y), at: 0)
        }
        if let last = points.last {
            points.append(CGPoint(x: size.width, y: last.y))
        }
        return points
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func faders(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<bandCount, id: \.self) { index in
                let columnWidth = width / CGFloat(bandCount)
                let gain = gains.indices.contains(index) ? gains[index] : 0
                let y = yPosition(for: gain, height: height)

                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.045))
                        .frame(width: 4, height: height - 12)
                        .position(x: columnWidth / 2, y: height / 2)

                    Rectangle()
                        .fill(Theme.strokeStrong)
                        .frame(width: min(22, columnWidth - 10), height: 1)
                        .position(x: columnWidth / 2, y: yPosition(for: 0, height: height))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x3B3631), Color(hex: 0x1A1613)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: min(34, columnWidth - 8), height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Theme.mint.opacity(0.55), lineWidth: 1)
                        )
                        .shadow(color: Theme.mint.opacity(0.25), radius: 3, y: 1)
                        .position(x: columnWidth / 2, y: y)
                }
                .frame(width: columnWidth, height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let fraction = 1 - (gesture.location.y / height)
                            let value = range.lowerBound
                                + Double(fraction.clamped(to: 0...1)) * (range.upperBound - range.lowerBound)
                            model.setGraphicGain(index, value)
                        }
                )
                .help("\(GraphicEQSettings.labels[index]) Hz — \(String(format: "%+.1f", gain)) dB")
            }
        }
        .frame(height: height)
        .allowsHitTesting(isEnabled)
    }

    private func labels(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<bandCount, id: \.self) { index in
                Text(GraphicEQSettings.labels[index])
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .frame(width: width / CGFloat(bandCount))
            }
        }
    }
}
