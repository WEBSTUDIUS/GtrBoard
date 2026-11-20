//  ContentView.swift
//  GtrBoard
//
//  Root window layout: header, pedalboard, graphic EQ and footer, plus the
//  preset sheets, the microphone alert and transient toasts.

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Theme.background
            backgroundGlow

            VStack(spacing: 0) {
                HeaderBar(model: model)

                BoardView(model: model)
                    .frame(maxHeight: .infinity)

                GraphicEQPanel(model: model)
                    .padding(.bottom, 10)

                FooterBar(model: model)
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 72)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 1_080, minHeight: 740)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .sheet(isPresented: $model.isShowingPresets) {
            PresetBrowserView(model: model)
        }
        .sheet(isPresented: $model.isShowingSavePreset) {
            SavePresetSheet(model: model)
        }
        .alert("Microphone access needed", isPresented: $model.isShowingMicrophoneHelp) {
            Button("Open Settings") { model.openMicrophoneSettings() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("GtrBoard processes your guitar locally and never records it. Allow microphone access in System Settings → Privacy & Security → Microphone, then press the power button again.")
        }
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDevices()
        }
    }

    private var backgroundGlow: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.accent.opacity(0.07), .clear],
                center: UnitPoint(x: 0.86, y: -0.02),
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [Theme.mint.opacity(0.035), .clear],
                center: UnitPoint(x: 0.08, y: 1.02),
                startRadius: 10,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
