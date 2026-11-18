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
    case "report", "report-slept", "report-stopped":
        let closed = ISO8601DateFormatter().date(from: "2026-10-13T17:24:00Z")!
        let report = LidReport(
            closedAt: closed, endedAt: closed.addingTimeInterval(name == "report-stopped" ? 5 * 3600 + 18 * 60 : 8 * 3600 + 31 * 60),
            batteryStart: 80, batteryEnd: name == "report-stopped" ? 20 : 68,
            longestGap: name == "report-slept" ? 41 * 60 : 31,
            stop: name == "report-stopped" ? .lowBattery(percent: 20, cutoff: 20) : nil
        )
        screen = .feedback(Feedback(on: name == "report", title: report.title, detail: report.detail, hold: 20))
        print(report.menuLine)
        print(report.logText)
    default: screen = .setUp(turnOn: false)
    }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        snapshotPanel(screen, dark: arguments.contains("--dark"), cutoff: Session.defaultCutoff, to: path)
    }
    exit(0)
}

/// The activity window, with no switch and no session. Both modes only read a log file.
/// Usage: LidAwake --preview-report out.png [--dark] [--card] [--log file] [--pick n]
///        LidAwake --report [--log file]
///        LidAwake --sample-activity
func reportLog() -> URL {
    if let index = arguments.firstIndex(of: "--log"), arguments.count > index + 1 {
        return URL(fileURLWithPath: arguments[index + 1])
    }
    return Paths.logFile
}

/// Looks at the process table twice, 21 s apart, and prints the fields a heartbeat would log.
if arguments.contains("--sample-activity") {
    let fields: String? = MainActor.assumeIsolated {
        let monitor = ActivityMonitor()
        _ = monitor.sample()
        Thread.sleep(forTimeInterval: 21)
        return monitor.sample()
    }
    print(fields ?? "could not read the process table")
    exit(fields == nil ? 1 : 0)
}

if let index = arguments.firstIndex(of: "--preview-report") {
    let path = arguments.count > index + 1 ? arguments[index + 1] : "/tmp/report.png"
    var pick = 0
    if let at = arguments.firstIndex(of: "--pick"), arguments.count > at + 1 { pick = Int(arguments[at + 1]) ?? 0 }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        snapshotReport(log: reportLog(), pick: pick, dark: arguments.contains("--dark"), card: arguments.contains("--card"), to: path)
    }
    exit(0)
}

if arguments.contains("--report") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = ReportWindowController()
        controller.model.logURL = reportLog()
        controller.model.openLog = { NSWorkspace.shared.open(controller.model.logURL) }
        controller.onClose = { exit(0) }
        controller.show()
        withExtendedLifetime(controller) {
            app.run()
        }
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

if let status = Updater.commandLineTest(CommandLine.arguments) {
    exit(status)
}

/// Usage: --preview-update out.png available|checking|uptodate|downloading|failed [--dark]
if let index = CommandLine.arguments.firstIndex(of: "--preview-update"), CommandLine.arguments.count > index + 2 {
    let path = CommandLine.arguments[index + 1]
    let sample = UpdateRelease(
        version: "9.9.0", notes: "What changed\n- A window that shows what ran while the lid was closed\n- Updates install from the menu",
        download: URL(string: "https://example.com/App.dmg")!, page: URL(string: "https://example.com")!)
    let phase: Updater.Phase
    switch CommandLine.arguments[index + 2] {
    case "checking": phase = .checking
    case "uptodate": phase = .upToDate
    case "downloading": phase = .downloading(sample)
    case "failed": phase = .failed("The update did not install. The new app is not signed by thelaunch.space, so it was not installed.", sample)
    default: phase = .available(sample)
    }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        Updater.snapshot(phase, dark: CommandLine.arguments.contains("--dark"), to: path)
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
