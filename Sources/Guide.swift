import AppKit
import SwiftUI

/// Why the guide is open. It changes the words and what the main button does.
enum GuideIntent {
    /// First launch, or setup from the menu.
    case setUp
    /// The user clicked the icon to turn on before closed-lid mode was set up.
    case turnOn
    /// "How it works" from the menu.
    case info
}

enum GuidePhase: Equatable {
    case intro
    case waiting
    case success
    case failed(String)
}

@MainActor
final class GuideModel: ObservableObject {
    @Published var intent: GuideIntent = .setUp
    @Published var phase: GuidePhase = .intro
    @Published var helperReady = false
    @Published var cutoff = Session.defaultCutoff

    var runSetup: () -> SetupOutcome = { .cancelled }
    var switchOn: () -> Void = {}
    var close: () -> Void = {}
    var finish: () -> Void = {}

    var primaryTitle: String {
        if phase == .waiting { return "Waiting for your password…" }
        if helperReady { return intent == .turnOn ? "Turn on" : "Done" }
        return intent == .turnOn ? "Allow and turn on" : "Allow closed-lid mode"
    }

    func primary() {
        guard phase != .waiting else { return }
        if helperReady {
            if intent == .turnOn {
                switchOn()
                succeed()
            } else {
                close()
            }
            return
        }
        phase = .waiting
        // The admin prompt blocks the main thread, so let the waiting state draw first.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            switch self.runSetup() {
            case .done:
                self.helperReady = true
                if self.intent == .turnOn { self.switchOn() }
                self.succeed()
            case .cancelled:
                self.phase = .intro
            case let .failed(message):
                self.phase = .failed(message)
            }
        }
    }

    func succeed() {
        phase = .success
        finish()
    }
}

@MainActor
final class GuideWindowController: NSObject, NSWindowDelegate {
    let model = GuideModel()
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    override init() {
        super.init()
        model.close = { [weak self] in self?.fadeOut() }
        model.finish = { [weak self] in self?.scheduleDismiss() }
    }

    func show(_ intent: GuideIntent) {
        dismissTask?.cancel()
        model.intent = intent
        model.phase = .intro
        present()
    }

    /// Opens straight on the success state, for setup started from the menu.
    func showSuccess(_ intent: GuideIntent) {
        model.intent = intent
        model.helperReady = true
        model.phase = .success
        present()
        scheduleDismiss()
    }

    private func present() {
        let isNew = window == nil
        if isNew { window = makeWindow() }
        window?.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        if isNew { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        dismissTask?.cancel()
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { window.close() }
        })
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: GuideRoot(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "LidAwake"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        dismissTask?.cancel()
        window = nil
    }

    /// Preview-only PNG. ImageRenderer draws blur and shadows, which cacheDisplay skips.
    func snapshot(to path: String) {
        let renderer = ImageRenderer(content: GuideRoot(model: model))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

@MainActor
func writePNG(of view: NSView, to path: String) {
    let bounds = view.bounds
    guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
    view.cacheDisplay(in: bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: Palette

enum Palette {
    static let sky = Color(red: 0.36, green: 0.62, blue: 0.99)
    static let ocean = Color(red: 0.16, green: 0.43, blue: 0.92)
    static let teal = Color(red: 0.30, green: 0.79, blue: 0.82)
    static let mint = Color(red: 0.52, green: 0.86, blue: 0.72)
    static let leaf = Color(red: 0.20, green: 0.68, blue: 0.52)
    static let ink = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let mist = Color(red: 0.43, green: 0.46, blue: 0.52)
}

// MARK: Root

struct GuideRoot: View {
    @ObservedObject var model: GuideModel

    private var success: Bool { model.phase == .success }

    var body: some View {
        ZStack(alignment: .top) {
            FluidBackground(calm: success)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Orb(success: success, symbol: success && model.intent != .turnOn ? "checkmark" : "cup.and.heat.waves.fill")
                    .padding(.top, 34)

                if success {
                    SuccessContent(model: model)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else {
                    IntroContent(model: model)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .light)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.helperReady)
        .contentShape(Rectangle())
        .onTapGesture { if success { model.close() } }
    }
}

private struct IntroContent: View {
    @ObservedObject var model: GuideModel

    private var title: String {
        switch model.intent {
        case .turnOn where !model.helperReady: return "One step first"
        default: return "Close the lid. Keep working."
        }
    }

    private var subtitle: String {
        switch model.intent {
        case .turnOn where !model.helperReady: return "Allow closed-lid mode, and your Mac keeps running with the lid shut."
        default: return "Your Mac keeps running, so your agents can finish."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .padding(.top, 6)

            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 6)

            StepsRow(helperReady: model.helperReady)
                .padding(.top, 28)

            PillButton(title: model.primaryTitle, busy: model.phase == .waiting) { model.primary() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 30)

            if case let .failed(message) = model.phase {
                Text("Setup did not finish. \(message)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
            }

            if !model.helperReady {
                QuietButton(title: "Not now") { model.close() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.phase == .waiting)
                    .padding(.top, 8)
            }

            HStack(spacing: 6) {
                Image(systemName: "leaf")
                    .foregroundStyle(Palette.leaf.opacity(0.8))
                Text("Stops at \(model.cutoff)% battery or if it runs hot. Best on a desk.")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.mist.opacity(0.85))
            .padding(.top, model.helperReady ? 22 : 14)
            .padding(.bottom, 22)
        }
    }
}

private struct SuccessContent: View {
    @ObservedObject var model: GuideModel

    private var turnedOn: Bool { model.intent == .turnOn }

    var body: some View {
        VStack(spacing: 0) {
            Text(turnedOn ? "Awake" : "You're all set")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .padding(.top, 6)

            Group {
                if turnedOn {
                    Text("Safe to close the lid now.")
                } else {
                    Text("Click \(Image(systemName: "cup.and.saucer")) in the menu bar to turn it on.")
                }
            }
            .font(.system(size: 13.5))
            .foregroundStyle(Palette.mist)
            .padding(.top, 6)

            Text(turnedOn ? "Click the cup again to turn it off." : "Right-click it for settings.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.mist.opacity(0.75))
                .padding(.top, 4)
                .padding(.bottom, 40)
        }
    }
}

// MARK: Pieces

/// A slow, soft wash of blue and mint on white.
private struct FluidBackground: View {
    let calm: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Color.white
                Circle()
                    .fill(Palette.sky.opacity(calm ? 0.16 : 0.24))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: -100 + 26 * sin(t / 7), y: -150 + 18 * cos(t / 9))
                Circle()
                    .fill(Palette.teal.opacity(0.20))
                    .frame(width: 250, height: 250)
                    .blur(radius: 75)
                    .offset(x: 115 + 22 * cos(t / 8), y: -120 + 22 * sin(t / 6))
                Circle()
                    .fill(Palette.mint.opacity(calm ? 0.26 : 0.14))
                    .frame(width: 230, height: 230)
                    .blur(radius: 80)
                    .offset(x: 18 * sin(t / 5), y: -30 + 16 * cos(t / 7))
            }
        }
    }
}

/// The hero. Rings drift outward like slow sound waves.
private struct Orb: View {
    let success: Bool
    let symbol: String

    private var colors: [Color] { success ? [Palette.mint, Palette.leaf] : [Palette.sky, Palette.ocean] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (t / 4.0 + Double(index) / 3.0).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke((colors.first ?? .blue).opacity(0.32 * (1 - phase)), lineWidth: 1)
                        .frame(width: 78 + phase * 70, height: 78 + phase * 70)
                }

                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: (colors.last ?? .blue).opacity(0.35), radius: 18, y: 8)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                        startPoint: .top, endPoint: .center
                    ))
                    .frame(width: 76, height: 76)

                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 150, height: 150)
            .scaleEffect(1 + 0.012 * sin(t * 1.2))
        }
    }
}

private struct StepsRow: View {
    let helperReady: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            StepTile(icon: "lock.open", label: "Allow once", done: helperReady)
            Connector()
            StepTile(icon: "cup.and.saucer", label: "Click the cup")
            Connector()
            StepTile(icon: "laptopcomputer", label: "Close the lid")
        }
    }
}

private struct StepTile: View {
    let icon: String
    let label: String
    var done = false

    var body: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(color: Palette.ocean.opacity(0.10), radius: 10, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(LinearGradient(
                                colors: [Palette.sky, Palette.ocean],
                                startPoint: .top, endPoint: .bottom
                            ))
                    )

                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white, Palette.leaf)
                        .background(Circle().fill(.white).padding(1))
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.mist)
        }
        .frame(width: 92)
    }
}

private struct Connector: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Palette.sky.opacity(0.0), Palette.sky.opacity(0.35), Palette.sky.opacity(0.0)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(width: 22, height: 1.5)
            .padding(.top, 25)
    }
}

private struct PillButton: View {
    let title: String
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    Spinner()
                }
                Text(title)
            }
        }
        .buttonStyle(PillStyle())
        .disabled(busy)
    }
}

private struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 230)
                .frame(height: 42)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [Palette.sky, Palette.ocean],
                        startPoint: .top, endPoint: .bottom
                    ))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Palette.ocean.opacity(hovering ? 0.38 : 0.28), radius: hovering ? 16 : 12, y: 6)
                .scaleEffect(configuration.isPressed ? 0.98 : (hovering && isEnabled ? 1.01 : 1))
                .opacity(isEnabled ? 1 : 0.85)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

private struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .trim(from: 0.1, to: 0.8)
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(angle))
        }
    }
}

private struct QuietButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.mist.opacity(hovering ? 1 : 0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
