import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = Session()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Keep Mac awake", action: nil, keyEquivalent: "")
    private let cutoffItem = NSMenuItem(title: "Stop at battery", action: nil, keyEquivalent: "")
    private let cutoffMenu = NSMenu()
    private let setupItem = NSMenuItem(title: "Set up closed-lid mode…", action: nil, keyEquivalent: "")
    private let removeItem = NSMenuItem(title: "Remove closed-lid permission", action: nil, keyEquivalent: "")
    private var signalSources: [DispatchSourceSignal] = []
    private let guide = GuideWindowController()
    private let hud = StatusHUD()
    private static let welcomeSeenKey = "hasSeenWelcome"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("LidAwake \(Paths.version) started (pid \(ProcessInfo.processInfo.processIdentifier))")
        installSignalHandlers()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification, object: nil
        )

        session.recoverOnLaunch()
        session.onChange = { [weak self] in self?.refreshUI() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshUI()

        guide.model.runSetup = { [weak self] in self?.performSetup() ?? .cancelled }
        guide.model.switchOn = { [weak self] in self?.session.switchOn() }
        if !UserDefaults.standard.bool(forKey: Self.welcomeSeenKey) {
            UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
            showGuide(.setUp)
        }
    }

    private func showGuide(_ intent: GuideIntent) {
        syncGuide()
        guide.show(intent)
    }

    private func syncGuide() {
        guide.model.helperReady = session.helperInstalled
        guide.model.cutoff = session.cutoff
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown(reason: "quit")
    }

    @objc private func willPowerOff(_ notification: Notification) {
        session.shutdown(reason: "logout, restart or shutdown")
    }

    private func installSignalHandlers() {
        let signals: [(Int32, String)] = [(SIGTERM, "SIGTERM"), (SIGINT, "SIGINT"), (SIGHUP, "SIGHUP")]
        for (number, name) in signals {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.session.shutdown(reason: name)
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Status item

    /// Click toggles. Right-click, or Control-click, opens the menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = menu
            sender.performClick(nil)
        } else {
            primaryToggle()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        statusItem.menu = nil
    }

    private func primaryToggle() {
        if !session.isOn {
            session.refreshHelper()
            if !session.helperInstalled {
                showGuide(.turnOn)
                return
            }
        }
        session.toggle()
        showHUD()
    }

    private func showHUD() {
        guard let button = statusItem.button else { return }
        if session.isOn {
            hud.show(
                from: button, on: true, title: "Awake",
                detail: session.lidLockActive ? "Safe to close the lid." : "Keep the lid open."
            )
        } else if let note = session.note {
            hud.show(from: button, on: false, title: "Not started", detail: note.replacingOccurrences(of: "Not started: ", with: ""))
        } else {
            hud.show(from: button, on: false, title: "Off", detail: "Your Mac sleeps normally.")
        }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(menuToggle)
        menu.addItem(toggleItem)

        cutoffMenu.autoenablesItems = false
        for value in Session.cutoffChoices {
            let item = NSMenuItem(title: "\(value)%", action: #selector(chooseCutoff(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            cutoffMenu.addItem(item)
        }
        cutoffItem.submenu = cutoffMenu
        menu.addItem(cutoffItem)
        menu.addItem(.separator())

        let howItem = NSMenuItem(title: "How it works", action: #selector(showHowItWorks), keyEquivalent: "")
        howItem.target = self
        menu.addItem(howItem)

        setupItem.target = self
        setupItem.action = #selector(setUpClosedLid)
        menu.addItem(setupItem)
        removeItem.target = self
        removeItem.action = #selector(removeClosedLid)
        menu.addItem(removeItem)

        let logItem = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LidAwake", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        session.refreshHelper()
        refreshUI()
    }

    private func refreshUI() {
        statusLine.title = statusText()
        toggleItem.state = session.isOn ? .on : .off
        for item in cutoffMenu.items {
            item.state = item.tag == session.cutoff ? .on : .off
        }
        setupItem.isHidden = session.helperInstalled
        removeItem.isHidden = !session.helperInstalled
        updateIcon()
    }

    private func statusText() -> String {
        if session.isOn {
            return session.lidLockActive
                ? "Awake. Safe to close the lid."
                : "Awake, lid open only."
        }
        return session.note ?? "Off. Your Mac sleeps normally."
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let fallback: String
        let description: String
        if session.isOn {
            symbol = session.lidLockActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves"
            fallback = "cup.and.saucer.fill"
            description = session.lidLockActive ? "LidAwake: awake, safe to close the lid" : "LidAwake: awake, lid open only"
        } else {
            symbol = "cup.and.saucer"
            fallback = "cup.and.saucer"
            description = "LidAwake: off. Click to keep your Mac awake, right-click for settings"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: description)
        if let image {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = session.isOn ? "Awake" : "Zz"
        }
        button.toolTip = description
    }

    // MARK: Actions

    @objc private func menuToggle() {
        primaryToggle()
    }

    @objc private func showHowItWorks() {
        showGuide(.info)
    }

    /// Runs setup and applies it to a running session. The caller shows the outcome.
    private func performSetup() -> SetupOutcome {
        Log.write("closed-lid setup requested")
        let outcome = HelperSetup.install()
        switch outcome {
        case .done: Log.write("closed-lid setup finished")
        case .cancelled: break
        case let .failed(message): Log.write("closed-lid setup failed: \(message)")
        }
        session.refreshHelper()
        session.engageLidLock()
        refreshUI()
        return outcome
    }

    @objc private func chooseCutoff(_ sender: NSMenuItem) {
        session.cutoff = sender.tag
    }

    @objc private func setUpClosedLid() {
        switch performSetup() {
        case .done:
            syncGuide()
            guide.showSuccess(.setUp)
        case .cancelled:
            break
        case let .failed(message):
            showAlert(title: "Closed-lid setup did not finish", message: message)
        }
    }

    @objc private func removeClosedLid() {
        Log.write("closed-lid removal requested")
        let wasLocked = session.lidLockActive
        if wasLocked {
            Log.write("switching to lid-open-only before removal")
            session.releaseLidLock(force: false)
        }
        switch HelperSetup.remove() {
        case .done:
            Log.write("closed-lid permission removed")
        case .cancelled:
            break
        case let .failed(message):
            Log.write("closed-lid removal failed: \(message)")
            showAlert(title: "Removal did not finish", message: message)
        }
        session.refreshHelper()
        if wasLocked && session.helperInstalled {
            session.engageLidLock()
        }
        refreshUI()
    }

    @objc private func openLog() {
        Log.ensureFile()
        NSWorkspace.shared.open(Paths.logFile)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message + "\n\nDetails are in the log."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
