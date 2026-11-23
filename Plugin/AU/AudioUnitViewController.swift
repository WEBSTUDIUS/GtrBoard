//  AudioUnitViewController.swift
//  GtrBoardAU
//
//  Custom UI entry point for the AUv3. The audio unit owns the DSP; this view
//  controller only builds a SwiftUI board around it.

import AppKit
import CoreAudioKit
import SwiftUI

@MainActor
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: GtrBoardAudioUnit?
    private var model: PluginModel?
    private var hosting: NSHostingController<PluginBoardView>?

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1_120, height: 620))
        preferredContentSize = NSSize(width: 1_120, height: 620)
    }

    nonisolated public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        try DispatchQueue.main.sync {
            let unit = try GtrBoardAudioUnit(
                componentDescription: componentDescription,
                options: []
            )
            audioUnit = unit
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model = PluginModel(audioUnit: unit)
                self.installBoard()
            }
            return unit
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        installBoard()
    }

    private func installBoard() {
        guard isViewLoaded, let model, hosting == nil else { return }
        let host = NSHostingController(rootView: PluginBoardView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
        hosting = host
        preferredContentSize = NSSize(width: 1_120, height: 620)
    }
}
