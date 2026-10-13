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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        switch self {
        case let .lowBattery(percent, _): return "Stopped at \(percent)% battery, \(time)"
        case .hot: return "Stopped, Mac too hot, \(time)"
        }
    }

    var notStartedText: String {
        switch self {
        case let .lowBattery(percent, cutoff): return "Not started: battery \(percent)%, cutoff \(cutoff)%."
        case .hot: return "Not started: Mac too hot."
        }
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

    var onChange: (() -> Void)?

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

    func switchOff(reason: String) {
        guard isOn else { return }
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
        onChange?()
    }

    /// Safe to call more than once. Used by quit, signals and power off.
    func shutdown(reason: String) {
        guard !didShutdown else { return }
        didShutdown = true
        Log.write("shutting down (\(reason))")
        if isOn {
            switchOff(reason: reason)
        } else if Paths.markerExists {
            releaseLidLock(force: true)
        }
        Log.write("shutdown complete")
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
        guard isOn, let stop = safetyViolation() else { return }
        Log.write("automatic stop (\(trigger)): \(stop.logText)")
        switchOff(reason: "automatic stop")
        note = stop.stoppedText(at: Date())
        onChange?()
        Log.write("putting Mac to sleep: pmset sleepnow")
        let result = Pmset.sleepNow()
        if !result.ok {
            Log.write("error: pmset sleepnow failed (\(result.summary))")
        }
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
