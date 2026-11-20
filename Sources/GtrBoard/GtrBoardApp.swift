//  GtrBoardApp.swift
//  GtrBoard
//
//  SwiftUI entry point, window chrome and menu commands.

import SwiftUI
import AppKit
import BoardCore

@main
struct GtrBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("GtrBoard", id: "main") {
            ContentView(model: model)
                .background(Theme.background)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Board") {
                Button("Save Preset…") { model.beginSavePreset() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Browse Presets…") { model.isShowingPresets = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Import Preset…") { model.importPresetFromPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Export Preset…") { model.exportCurrentPreset() }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                Toggle(
                    "Bypass",
                    isOn: Binding(
                        get: { model.isBypassed },
                        set: { model.setBypass($0) }
                    )
                )
                .keyboardShortcut("b", modifiers: .command)
                Button("Reset Graphic EQ") { model.resetGraphicEQ() }
                Divider()
                Button(model.isRecording ? "Stop Recording" : "Record Output") {
                    model.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button(model.isRunning ? "Stop Audio" : "Start Audio") {
                    model.togglePower()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("GtrBoard")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var spaceMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        styleWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.styleWindows()
        }
        installSpaceMonitor()
        scheduleSnapshotIfRequested()
        scheduleQuitIfRequested()
        runAudioProbeIfRequested()
        runCaptureIfRequested()
        runRecordTestIfRequested()
        runToneRecordTestIfRequested()
        renderMenuBarIconIfRequested()
        dumpStatusWindowsIfRequested()
    }

    /// Space is the performance control: switch A/B when both banks are
    /// assigned, otherwise bypass. Text fields, sheets and menus keep their
    /// normal space behaviour.
    private func installSpaceMonitor() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == 49, !event.isARepeat else { return event }
            let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard event.modifierFlags.intersection(modifiers).isEmpty else { return event }
            guard let window = NSApp.keyWindow, window.attachedSheet == nil else { return event }
            if window.firstResponder is NSTextView || window.firstResponder is NSTextField {
                return event
            }
            AppModel.shared.handleSpace()
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let spaceMonitor {
            NSEvent.removeMonitor(spaceMonitor)
        }
        AppModel.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            AppModel.shared.openWindowAction?()
        }
        return true
    }

    /// Hidden `--snapshot <path>` flag: renders the window to a PNG and exits.
    /// Used to verify layout without screen-recording permission.
    private func scheduleSnapshotIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"),
              arguments.indices.contains(index + 1) else { return }
        let path = arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.attemptSnapshot(path: path, attempts: 0)
        }
    }

    private func attemptSnapshot(path: String, attempts: Int) {
        guard attempts < 40 else {
            FileHandle.standardError.write(Data("snapshot: no window after retries\n".utf8))
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let windows = NSApp.windows.filter { $0.isVisible || $0.canBecomeMain }
            FileHandle.standardError.write(Data("snapshot attempt \(attempts): windows=\(NSApp.windows.count) usable=\(windows.count) sizes=\(windows.map { $0.frame.size })\n".utf8))
            let sheet = NSApp.keyWindow?.attachedSheet ?? NSApp.windows.first(where: { $0.isSheet })
            let target = sheet ?? windows.first(where: { $0.contentView != nil && $0.frame.width > 200 })
            guard let window = target,
                  let view = window.contentView,
                  view.bounds.width > 200 else {
                self.attemptSnapshot(path: path, attempts: attempts + 1)
                return
            }
            let bounds = view.bounds
            guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
                NSApp.terminate(nil)
                return
            }
            view.cacheDisplay(in: bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("snapshot written to \(path)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }

    /// Hidden `--capture <seconds> <prefix>` flag: records the raw input
    /// (both channels) and the processed output for offline analysis.
    private func runCaptureIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--capture"),
              arguments.indices.contains(index + 1),
              let seconds = Int(arguments[index + 1]) else { return }
        let prefix = arguments.indices.contains(index + 2)
            ? arguments[index + 2]
            : "/tmp/gtrboard-capture"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let model = AppModel.shared
            if !model.engine.state.isRunning {
                model.startEngine()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard model.engine.beginCapture(seconds: seconds) else {
                    print("capture: engine is not running")
                    NSApp.terminate(nil)
                    return
                }
                self.pollCapture(model: model, prefix: prefix, sampleRate: model.format?.sampleRate ?? 48_000, attempts: 0)
            }
        }
    }

    private func pollCapture(model: AppModel, prefix: String, sampleRate: Double, attempts: Int) {
        if model.engine.captureDidFinish {
            let data = model.engine.finishCapture()
            let inputURL = URL(fileURLWithPath: prefix + "-input.wav")
            let outputURL = URL(fileURLWithPath: prefix + "-output.wav")
            WAVWriter.writeStereo(left: data.inL, right: data.inR, sampleRate: sampleRate, to: inputURL)
            WAVWriter.writeStereo(left: data.outL, right: data.outR, sampleRate: sampleRate, to: outputURL)
            print("capture: \(data.frames) frames at \(sampleRate) Hz -> \(prefix)-input.wav / -output.wav")
            NSApp.terminate(nil)
            return
        }
        guard attempts < 200 else {
            print("capture: timeout")
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pollCapture(model: model, prefix: prefix, sampleRate: sampleRate, attempts: attempts + 1)
        }
    }

    /// Hidden `--status-dump <prefix>` flag: prints and captures the small
    /// status-level windows used by the menu-bar extra.
    private func dumpStatusWindowsIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--status-dump"),
              arguments.indices.contains(index + 1) else { return }
        let prefix = arguments[index + 1]

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            for (offset, window) in NSApp.windows.enumerated() {
                let className = String(describing: type(of: window))
                let background = window.backgroundColor.description
                print("window \(offset) \(className) frame=\(window.frame) level=\(window.level.rawValue) opaque=\(window.isOpaque) bg=\(background)")

                guard window.frame.width < 200, window.frame.height < 200,
                      let view = window.contentView, view.bounds.width > 1 else { continue }
                guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: representation)
                let path = "\(prefix)-\(offset).png"
                try? representation.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
                print("  captured \(path) contentFrame=\(view.frame) bg=\(window.backgroundColor)")
            }
            NSApp.terminate(nil)
        }
    }

    /// Hidden `--icon-preview <path>` flag: renders the template menu-bar icon
    /// at 8x on a grey background for visual inspection.
    private func renderMenuBarIconIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--icon-preview"),
              arguments.indices.contains(index + 1) else { return }
        let path = arguments[index + 1]
        let pixels = 144
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            NSApp.terminate(nil)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        MenuBarIcon.image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        try? representation.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
        NSApp.terminate(nil)
    }

    /// Hidden `--tone-record <seconds>` flag: records a 440 Hz test tone
    /// through the board so recorder/engine dropouts can be measured.
    private func runToneRecordTestIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--tone-record"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let model = AppModel.shared
            model.engine.testToneFrequency = 440
            if !model.isRunning { model.startEngine() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                model.toggleRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1.0) {
                    model.toggleRecording()
                    if let url = model.lastRecordingURL {
                        print("tone recorded: \(url.path) drops=\(model.recorder.droppedFrames)")
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Hidden `--record <seconds>` flag: starts audio, records the processed
    /// output, stops and prints the path. Used to smoke-test the recorder.
    private func runRecordTestIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--record"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let model = AppModel.shared
            if !model.isRunning { model.startEngine() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                model.toggleRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1.0) {
                    model.toggleRecording()
                    if let url = model.lastRecordingURL {
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                        print("recorded: \(url.path) bytes=\(size ?? 0)")
                    } else {
                        print("recorded: no file")
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Hidden `--probe-audio` flag: configures the default input/output pair
    /// and the HAL unit without starting I/O, prints the result and exits.
    private func runAudioProbeIfRequested() {
        guard CommandLine.arguments.contains("--probe-audio") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let input = AudioDevices.defaultInput(),
                  let output = AudioDevices.defaultOutput() else {
                print("probe: no default devices")
                NSApp.terminate(nil)
                return
            }
            print("probe: \(input.name) -> \(output.name)")
            let report = AppModel.shared.engine.probe(input: input, output: output, bufferSize: 128)
            print(report)
            NSApp.terminate(nil)
        }
    }

    /// Hidden `--quit-after <seconds>` flag for automated launches.
    private func scheduleQuitIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--quit-after"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            NSApp.terminate(nil)
        }
    }

    private func styleWindows() {
        for window in NSApp.windows {
            window.backgroundColor = .appBackground
            window.isOpaque = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 1_080, height: 740)
            if window.canBecomeMain {
                window.appearance = NSAppearance(named: .darkAqua)
            }
            // The menu-bar extra lives in a status-level window. On a light
            // menu bar a forced dark appearance used to paint that window
            // black; make the host transparent and let the menu bar show
            // through.
            if window.level == .statusBar {
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = false
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
}
