import Foundation

/// `LidAwake --selftest`: prints what the app sees on this Mac and exits. Changes nothing.
enum SelfTest {
    static func run() -> Int32 {
        let power = PowerInfo.snapshot()
        let thermal = ProcessInfo.processInfo.thermalState
        let sleepDisabled: String
        switch Pmset.sleepDisabled() {
        case .some(true): sleepDisabled = "1"
        case .some(false): sleepDisabled = "0"
        case .none: sleepDisabled = "unknown"
        }

        print("LidAwake \(Paths.version) selftest")
        print("battery: \(power.batteryPercent.map { "\($0)%" } ?? "none")")
        print("power: \(power.onBattery ? "battery" : "ac")")
        print("thermal: \(PowerInfo.thermalName(thermal))")
        if let forced = PowerInfo.thermalOverride() {
            print("thermal override: \(PowerInfo.thermalName(forced))")
        }
        print("lid: \(PowerInfo.lidName(PowerInfo.lidClosed()))")
        print("lid close sleeps the Mac: \(PowerInfo.clamshellCausesSleep().map { $0 ? "yes" : "no" } ?? "unknown")")
        print("helper installed: \(Pmset.helperInstalled() ? "yes" : "no")")
        print("SleepDisabled: \(sleepDisabled)")
        print("marker: \(Paths.markerExists ? "present" : "absent") (\(Paths.marker.path))")
        print("log: \(Paths.logFile.path)")
        let problems = historyProblems()
        print("log reader: \(problems.isEmpty ? "ok" : problems.joined(separator: "; "))")
        return problems.isEmpty ? 0 : 1
    }

    /// The activity window is only as good as its reading of the log, so read a known one.
    /// Claude works for minutes 0 to 3 and 5, with one quiet minute between that counts as work.
    /// Then the checks stop for 12 minutes, which must read as "may have slept".
    static func historyProblems() -> [String] {
        func line(_ minute: Int, _ second: Int, _ message: String) -> String {
            String(format: "2026-11-17T23:%02d:%02d+0530 [app] %@", minute, second, message)
        }
        var lines = [line(0, 0, "lid closed while on")]
        let claude = [1.2, 0.9, 2.0, 1.1, 0.1, 1.0, 0.1, 0.1]
        for (index, used) in claude.enumerated() {
            let agents = String(format: "agents=claude:1:%.2f:%.2f macos=%@", used, used, index == 6 ? "backup:12.0" : "idle")
            lines.append(line(index, 30, "heartbeat lid=closed battery=\(62 - index)% power=battery thermal=nominal sleepDisabled=1 \(agents)"))
        }
        lines.append(line(20, 0, "lid record: lid closed 20 min, longest gap between checks 750 s, battery 62% to 55%"))
        lines.append(line(20, 30, "heartbeat lid=open battery=55% power=battery thermal=nominal sleepDisabled=1 agents=none macos=idle"))
        let history = HistoryReader.parse(lines.joined(separator: "\n") + "\n")

        var problems: [String] = []
        guard history.closes.count == 1, let close = history.closes.first else {
            return ["expected 1 lid close, found \(history.closes.count)"]
        }
        if Int(close.duration) != 20 * 60 { problems.append("duration \(Int(close.duration)) s, expected 1200") }
        if close.samples.count != 8 { problems.append("\(close.samples.count) heartbeats, expected 8") }
        if !close.mayHaveSlept { problems.append("a 12 minute gap did not read as a sleep") }
        if !close.tracked { problems.append("agent fields were not read") }
        // Six heartbeats count as work. The first stands for the 30 s since the lid closed.
        if Int(close.workTime(of: "claude")) != 330 { problems.append("claude worked \(Int(close.workTime(of: "claude"))) s, expected 330") }
        if Int(close.systemTime) != 60 { problems.append("macOS jobs \(Int(close.systemTime)) s, expected 60") }
        if close.batteryStart != 62 || close.batteryEnd != 55 { problems.append("battery \(String(describing: close.batteryStart)) to \(String(describing: close.batteryEnd))") }
        return problems
    }
}
