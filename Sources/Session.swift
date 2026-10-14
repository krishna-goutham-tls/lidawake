import Foundation
import IOKit.ps
import IOKit.pwr_mgt

enum SafetyStop {
    case lowBattery(percent: Int, cutoff: Int)
    case hot(state: String, forced: Bool)

    var logText: String {
        switch self {
        case let .lowBattery(percent, cutoff):
            return "battery \(percent)% is at or below cutoff \(cutoff)% while on battery"
        case let .hot(state, forced):
            return "thermal state \(state)\(forced ? " (debugForceThermal override)" : "")"
        }
    }

    func stoppedText(at date: Date) -> String {
        let time = clockTime(date)
        switch self {
        case let .lowBattery(percent, _): return "Stopped at \(percent)% battery, \(time)"
        case .hot: return "Stopped on a heat warning, \(time)"
        }
    }

    var notStartedText: String {
        switch self {
        case let .lowBattery(percent, cutoff): return "Not started: battery \(percent)%, cutoff \(cutoff)%."
        case .hot: return "Not started: macOS reports serious heat."
        }
    }
}

func clockTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

func spanText(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
}

/// What happened while the lid was closed, built from the app's own 30 s checks. If the Mac
/// slept, the checks stop, so a long gap between two of them is the evidence.
struct LidReport {
    static let gapLimit: TimeInterval = 90

    let closedAt: Date
    let endedAt: Date
    let batteryStart: Int?
    let batteryEnd: Int?
    let longestGap: TimeInterval
    let stop: SafetyStop?

    var duration: TimeInterval { endedAt.timeIntervalSince(closedAt) }
    var mayHaveSlept: Bool { longestGap > Self.gapLimit }

    var title: String {
        if mayHaveSlept { return "Your Mac may have slept with the lid closed." }
        switch stop {
        case let .lowBattery(percent, _)?:
            return "Stopped at \(percent)% battery at \(clockTime(endedAt)) and put your Mac to sleep."
        case .hot?:
            return "Stopped on a heat warning at \(clockTime(endedAt)) and put your Mac to sleep."
        case nil:
            return "Your Mac stayed awake \(spanText(duration)) with the lid closed."
        }
    }

    var detail: String {
        if mayHaveSlept { return "no check-in for \(spanText(longestGap)) · see the log" }
        if stop != nil { return "awake \(spanText(duration)) with the lid closed before that" }
        var parts = ["\(clockTime(closedAt)) to \(clockTime(endedAt))"]
        if let start = batteryStart, let end = batteryEnd { parts.append("battery \(start)% to \(end)%") }
        return parts.joined(separator: " · ")
    }

    var menuLine: String {
        let what: String
        if mayHaveSlept {
            what = "may have slept, see log"
        } else if let stop {
            what = stop.stoppedText(at: endedAt).lowercased()
        } else {
            what = "awake \(spanText(duration)), \(clockTime(closedAt)) to \(clockTime(endedAt))"
        }
        return "last lid close: \(what)"
    }

    var logText: String {
        let battery = "\(batteryStart.map { "\($0)%" } ?? "none") to \(batteryEnd.map { "\($0)%" } ?? "none")"
        return "lid closed \(spanText(duration)), longest gap between checks \(Int(longestGap)) s, battery \(battery)"
            + (stop.map { ", ended by automatic stop: \($0.logText)" } ?? "")
    }
}

@MainActor
final class Session: NSObject {
    static let cutoffChoices = [10, 20, 30, 50]
    static let defaultCutoff = 20
    private static let cutoffKey = "batteryCutoff"

    private(set) var isOn = false
    private(set) var lidLockActive = false
    private(set) var helperInstalled = false
    /// Shown in the status line while off, e.g. why an automatic stop happened.
    private(set) var note: String?
    private(set) var startedAt: Date?
    private(set) var lastReport: LidReport?

    var onChange: (() -> Void)?
    var onReport: ((LidReport) -> Void)?

    /// Shorter closes are not worth a panel; they are still logged.
    static let minReportDuration: TimeInterval = 5 * 60
    private struct LidWatch {
        let closedAt: Date
        let batteryStart: Int?
        var lastCheck: Date
        var longestGap: TimeInterval
    }
    private var lidWatch: LidWatch?

    private var assertionID: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?
    private var safetyTimer: Timer?
    private var heartbeatTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var thermalObserver: NSObjectProtocol?
    private var didShutdown = false

    var cutoff: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Self.cutoffKey)
            return Self.cutoffChoices.contains(value) ? value : Self.defaultCutoff
        }
        set {
            guard Self.cutoffChoices.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: Self.cutoffKey)
            Log.write("battery cutoff set to \(newValue)%")
            safetyCheck(trigger: "cutoff change")
            onChange?()
        }
    }

    // MARK: Helper state

    func refreshHelper() {
        let installed = Pmset.helperInstalled()
        if installed != helperInstalled {
            Log.write("closed-lid helper \(installed ? "installed" : "not installed")")
        }
        helperInstalled = installed
    }

    // MARK: Launch recovery

    func recoverOnLaunch() {
        refreshHelper()
        let sleepDisabled = Pmset.sleepDisabled()
        if Paths.markerExists {
            Log.write("marker found at launch (previous session did not end cleanly), SleepDisabled=\(flag(sleepDisabled)); resetting")
            releaseLidLock(force: true)
        } else if sleepDisabled == true {
            Log.write("warning: SleepDisabled is 1 but no LidAwake marker exists; something else set it, leaving it alone")
        }
    }

    // MARK: On and off

    func toggle() {
        if isOn {
            note = nil
            switchOff(reason: "user switched off")
        } else {
            switchOn()
        }
    }

    func switchOn() {
        guard !isOn else { return }
        if let stop = safetyViolation() {
            note = stop.notStartedText
            Log.write("not switching on: \(stop.logText)")
            onChange?()
            return
        }

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LidAwake keeping agents running" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.write("error: could not create power assertion (IOReturn \(result))")
            note = "Could not switch on. See log."
            onChange?()
            return
        }
        assertionID = id
        // Keeps timers running on schedule; App Nap would otherwise throttle a background app.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "LidAwake session"
        )
        isOn = true
        startedAt = Date()
        note = nil
        Log.write("switched on: idle-sleep assertion created (id \(id))")

        refreshHelper()
        engageLidLock()
        if !lidLockActive {
            Log.write("lid-open-only mode: closing the lid will still sleep the Mac")
        }

        startMonitoring()
        heartbeat()
        onChange?()
    }

    func switchOff(reason: String, sleepIfLidShut: Bool = true) {
        guard isOn else { return }
        finishLidWatch(at: Date(), stop: nil)
        stopMonitoring()
        releaseLidLock(force: false)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        isOn = false
        startedAt = nil
        Log.write("switched off (\(reason)): assertion released")
        if sleepIfLidShut { sleepIfLidIsShut(after: reason) }
        onChange?()
    }

    /// Safe to call more than once. Used by quit, signals and power off.
    /// `allowSleep` is false while macOS is logging out or shutting down.
    func shutdown(reason: String, allowSleep: Bool = true) {
        guard !didShutdown else { return }
        didShutdown = true
        Log.write("shutting down (\(reason))")
        if isOn {
            switchOff(reason: reason, sleepIfLidShut: allowSleep)
        } else if Paths.markerExists {
            releaseLidLock(force: true)
        }
        Log.write("shutdown complete")
    }

    /// With the lid already shut, macOS keeps running after `disablesleep 0` until the lid opens again.
    /// Sleep the Mac the way the lid close would have. An external display keeps a closed Mac in
    /// clamshell mode, and then AppleClamshellCausesSleep is false, so it is left awake.
    private func sleepIfLidIsShut(after reason: String) {
        guard PowerInfo.lidClosed() == true, PowerInfo.clamshellCausesSleep() == true else { return }
        Log.write("lid is closed after \(reason): putting Mac to sleep: pmset sleepnow")
        let result = Pmset.sleepNow()
        if !result.ok {
            Log.write("error: pmset sleepnow failed (\(result.summary))")
        }
    }

    // MARK: Lid record

    /// Called on every safety check and when the displays sleep or wake.
    func checkLid() {
        guard isOn else { return }
        let now = Date()
        let closed = PowerInfo.lidClosed() == true
        if var watch = lidWatch {
            watch.longestGap = max(watch.longestGap, now.timeIntervalSince(watch.lastCheck))
            watch.lastCheck = now
            lidWatch = watch
            if !closed { finishLidWatch(at: now, stop: nil) }
        } else if closed && lidLockActive {
            lidWatch = LidWatch(closedAt: now, batteryStart: PowerInfo.snapshot().batteryPercent, lastCheck: now, longestGap: 0)
            Log.write("lid closed while on")
        }
    }

    private func finishLidWatch(at date: Date, stop: SafetyStop?) {
        guard let watch = lidWatch else { return }
        lidWatch = nil
        let gap = max(watch.longestGap, date.timeIntervalSince(watch.lastCheck))
        let report = LidReport(
            closedAt: watch.closedAt, endedAt: date,
            batteryStart: watch.batteryStart, batteryEnd: PowerInfo.snapshot().batteryPercent,
            longestGap: gap, stop: stop
        )
        Log.write("lid record: \(report.logText)")
        guard report.duration >= Self.minReportDuration else { return }
        lastReport = report
        onReport?(report)
    }

    // MARK: Lid lock (pmset disablesleep)

    /// The idle-sleep assertion cannot stop lid-close sleep; only `disablesleep 1` can,
    /// and it persists across reboots, so the marker is written first for crash recovery.
    func engageLidLock() {
        guard isOn, helperInstalled, !lidLockActive else { return }
        do {
            try FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
            try Data().write(to: Paths.marker)
        } catch {
            Log.write("error: could not write marker, not disabling lid sleep: \(error.localizedDescription)")
            return
        }
        let result = Pmset.setDisableSleep(true)
        if result.ok {
            lidLockActive = true
            Log.write("closed-lid mode on: sudo -n pmset -a disablesleep 1 succeeded")
        } else {
            Log.write("error: sudo -n pmset -a disablesleep 1 failed (\(result.summary))")
            if Pmset.sleepDisabled() != true {
                try? FileManager.default.removeItem(at: Paths.marker)
            }
        }
        onChange?()
    }

    /// Sets disablesleep back to 0 and removes the marker once pmset confirms normal sleep.
    /// `force` runs the reset whenever the marker exists, even if the helper looks missing.
    func releaseLidLock(force: Bool) {
        let markerExists = Paths.markerExists
        var shouldReset = lidLockActive || helperInstalled
        if !shouldReset && markerExists {
            shouldReset = force || Pmset.sleepDisabled() == true
        }
        var resetOK = false
        if shouldReset {
            let result = Pmset.setDisableSleep(false)
            resetOK = result.ok
            Log.write(result.ok
                ? "normal lid sleep restored: sudo -n pmset -a disablesleep 0 succeeded"
                : "error: sudo -n pmset -a disablesleep 0 failed (\(result.summary))")
        }
        lidLockActive = false

        if markerExists {
            let stillDisabled = Pmset.sleepDisabled()
            if resetOK || stillDisabled == false {
                try? FileManager.default.removeItem(at: Paths.marker)
                Log.write("marker removed")
            } else {
                note = "Lid sleep may still be off. See log."
                Log.write("warning: SleepDisabled=\(flag(stillDisabled)) after reset attempt; marker kept so the watchdog retries")
            }
        }
    }

    // MARK: Safety monitor

    private func startMonitoring() {
        let safety = Timer(timeInterval: 30, target: self, selector: #selector(safetyTimerFired), userInfo: nil, repeats: true)
        safety.tolerance = 3
        RunLoop.main.add(safety, forMode: .common)
        safetyTimer = safety

        let beat = Timer(timeInterval: 60, target: self, selector: #selector(heartbeatTimerFired), userInfo: nil, repeats: true)
        beat.tolerance = 5
        RunLoop.main.add(beat, forMode: .common)
        heartbeatTimer = beat

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let session = Unmanaged<Session>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { session.safetyCheck(trigger: "power change") }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyCheck(trigger: "thermal change") }
        }
    }

    private func stopMonitoring() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
            self.powerSource = nil
        }
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    @objc private func safetyTimerFired() { safetyCheck(trigger: "timer") }
    @objc private func heartbeatTimerFired() { heartbeat() }

    func safetyViolation() -> SafetyStop? {
        let thermal = PowerInfo.effectiveThermal()
        if thermal.state == .serious || thermal.state == .critical {
            return .hot(state: PowerInfo.thermalName(thermal.state), forced: thermal.forced)
        }
        let power = PowerInfo.snapshot()
        if power.onBattery, let percent = power.batteryPercent, percent <= cutoff {
            return .lowBattery(percent: percent, cutoff: cutoff)
        }
        return nil
    }

    func safetyCheck(trigger: String) {
        guard isOn else { return }
        checkLid()
        if trigger == "timer" { confirmLidLock() }
        guard let stop = safetyViolation() else { return }
        Log.write("automatic stop (\(trigger)): \(stop.logText)")
        if PowerInfo.lidClosed() == true { finishLidWatch(at: Date(), stop: stop) }
        switchOff(reason: "automatic stop", sleepIfLidShut: false)
        note = stop.stoppedText(at: Date())
        onChange?()
        Log.write("putting Mac to sleep: pmset sleepnow")
        let result = Pmset.sleepNow()
        if !result.ok {
            Log.write("error: pmset sleepnow failed (\(result.summary))")
        }
    }

    /// The cup must not say "safe to close the lid" when it is not. Another tool, or a reset,
    /// can turn `disablesleep` back to 0 behind the app's back.
    private func confirmLidLock() {
        guard lidLockActive, Pmset.sleepDisabled() == false else { return }
        Log.write("warning: SleepDisabled is 0 while closed-lid mode should be on; turning it on again")
        lidLockActive = false
        engageLidLock()
        if !lidLockActive {
            Log.write("closed-lid mode could not be restored: closing the lid will sleep the Mac")
        }
        onChange?()
    }

    private func heartbeat() {
        guard isOn else { return }
        let power = PowerInfo.snapshot()
        let battery = power.batteryPercent.map { "\($0)%" } ?? "none"
        let thermal = PowerInfo.thermalName(PowerInfo.effectiveThermal().state)
        Log.write("heartbeat lid=\(PowerInfo.lidName(PowerInfo.lidClosed())) battery=\(battery) power=\(power.onBattery ? "battery" : "ac") thermal=\(thermal) sleepDisabled=\(flag(Pmset.sleepDisabled()))")
    }

    private func flag(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "1"
        case .some(false): return "0"
        case .none: return "unknown"
        }
    }
}
