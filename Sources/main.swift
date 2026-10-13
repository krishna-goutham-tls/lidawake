import AppKit
import SwiftUI

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(SelfTest.run())
}

/// Shows one guide state with no session, so it never touches sleep settings or the marker.
/// Usage: LidAwake --preview-guide setUp|turnOn|info|success|successOn|waiting [--helper-ready] [--snapshot out.png]
///        LidAwake --preview-hud on|off --snapshot out.png
if let index = arguments.firstIndex(of: "--preview-guide") ?? arguments.firstIndex(of: "--preview-hud") {
    let isHUD = arguments[index] == "--preview-hud"
    let name = arguments.count > index + 1 ? arguments[index + 1] : ""
    let snapshotPath: String? = arguments.firstIndex(of: "--snapshot").flatMap {
        arguments.count > $0 + 1 ? arguments[$0 + 1] : nil
    }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var keepAlive: AnyObject?
        var capture: () -> Void = {}

        if isHUD {
            let on = name != "off"
            let view = HUDView(on: on, title: on ? "Awake" : "Off", detail: on ? "Safe to close the lid." : "Your Mac sleeps normally.")
            let host = NSHostingView(rootView: view.background(Color.white))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            keepAlive = window
            capture = { writePNG(of: host, to: snapshotPath ?? "/tmp/hud.png") }
        } else {
            let guide = GuideWindowController()
            keepAlive = guide
            guide.model.helperReady = arguments.contains("--helper-ready")
            guide.model.runSetup = { .cancelled }
            switch name {
            case "turnOn": guide.show(.turnOn)
            case "info": guide.show(.info)
            case "success": guide.showSuccess(.setUp)
            case "successOn": guide.showSuccess(.turnOn)
            case "waiting":
                guide.show(.setUp)
                guide.model.phase = .waiting
            default: guide.show(.setUp)
            }
            capture = { guide.snapshot(to: snapshotPath ?? "/tmp/guide.png") }
        }

        if snapshotPath != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                capture()
                exit(0)
            }
        }
        withExtendedLifetime(keepAlive) { app.run() }
    }
    exit(0)
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
