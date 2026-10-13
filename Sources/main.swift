import AppKit
import SwiftUI

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(SelfTest.run())
}

/// Draws one panel screen to a PNG with no session, so it never touches sleep settings or the marker.
/// Usage: LidAwake --preview-panel setUp|turnOn|waiting|failed|ready|info|on|off out.png [--dark]
///        LidAwake --render-iconset dir.iconset
if let index = arguments.firstIndex(of: "--preview-panel") {
    let name = arguments.count > index + 1 ? arguments[index + 1] : ""
    let path = arguments.count > index + 2 ? arguments[index + 2] : "/tmp/panel.png"
    let screen: PanelScreen
    switch name {
    case "turnOn": screen = .setUp(turnOn: true)
    case "waiting": screen = .waiting(turnOn: false)
    case "failed": screen = .failed(turnOn: false, message: "The password prompt was closed.")
    case "ready": screen = .ready
    case "info": screen = .info
    case "on": screen = .feedback(Feedback(on: true, title: "On. Close the lid any time.", detail: "stops at 20% · 81% now"))
    case "off": screen = .feedback(Feedback(on: false, title: "Off. Your Mac sleeps normally.", detail: nil))
    default: screen = .setUp(turnOn: false)
    }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        snapshotPanel(screen, dark: arguments.contains("--dark"), cutoff: Session.defaultCutoff, to: path)
    }
    exit(0)
}

if let index = arguments.firstIndex(of: "--render-iconset") {
    let path = arguments.count > index + 1 ? arguments[index + 1] : "/tmp/AppIcon.iconset"
    let ok = MainActor.assumeIsolated {
        _ = NSApplication.shared
        return renderIconset(to: path)
    }
    exit(ok ? 0 : 1)
}

// A second copy would read the first copy's session marker as a crash leftover and reset sleep.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: Paths.bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if let running = others.first {
    Log.write("another LidAwake is already running (pid \(running.processIdentifier)); this copy exits")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
