import AppKit
import AVFoundation
import CoreAudioKit
import SwiftUI

@main
struct GtrBoardPluginHostApp: App {
    var body: some Scene {
        WindowGroup("Awesonic GtrBoard") {
            HostView()
                .frame(minWidth: 520, minHeight: 360)
        }
        .windowResizability(.contentSize)
    }
}

struct HostView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Awesonic GtrBoard")
                .font(.system(size: 24, weight: .bold))
            Text("The GtrBoard AUv3 effect is installed with this app.\nLaunch it once, then restart Logic or GarageBand and look for GtrBoard under Audio Units → Effects.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Audio Components Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components"))
                }
                Button("Open Applications") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
            }
            Text("If the plug-in does not appear, quit and reopen the DAW after launching this app once.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(24)
    }
}
