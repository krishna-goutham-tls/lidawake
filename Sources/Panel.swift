import AppKit
import SwiftUI

/// What the panel under the menu bar icon is showing.
enum PanelScreen: Equatable {
    /// First launch, or a click on the icon before closed-lid mode was allowed.
    case setUp(turnOn: Bool)
    case waiting(turnOn: Bool)
    case failed(turnOn: Bool, message: String)
    case ready
    case info
    case feedback(Feedback)

    var turnOn: Bool {
        switch self {
        case let .setUp(value), let .waiting(value), let .failed(value, _): return value
        default: return false
        }
    }
}

struct Feedback: Equatable {
    let on: Bool
    let title: String
    let detail: String?
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var screen: PanelScreen = .setUp(turnOn: false)
    @Published var cutoff = Session.defaultCutoff
    /// The popover keeps its view tree after closing, and a repeating symbol effect in it
    /// keeps rendering offscreen at about 10% CPU. Animations run only while it is shown.
    @Published var shown = false

    var runSetup: () -> SetupOutcome = { .cancelled }
    var switchOn: () -> Void = {}
    var close: () -> Void = {}

    var safetyLine: String { "stops at \(cutoff)% battery · stops if hot" }

    func allow() {
        if case .waiting = screen { return }
        let turnOn = screen.turnOn
        screen = .waiting(turnOn: turnOn)
        // The admin prompt blocks the main thread, so let the waiting state draw first.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            switch self.runSetup() {
            case .done:
                if turnOn {
                    self.switchOn()
                } else {
                    self.screen = .ready
                }
            case .cancelled:
                self.screen = .setUp(turnOn: turnOn)
            case let .failed(message):
                self.screen = .failed(turnOn: turnOn, message: message)
            }
        }
    }
}

/// One popover, anchored to the menu bar icon, so every message points at the switch it talks about.
@MainActor
final class PanelController: NSObject, NSPopoverDelegate {
    let model = PanelModel()
    private let popover = NSPopover()
    private var closeTask: Task<Void, Never>?
    private var hovering = false

    override init() {
        super.init()
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(model: model) { [weak self] in
            self?.hovering = $0
        })
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        model.close = { [weak self] in self?.close() }
    }

    var isShowingGuide: Bool {
        guard popover.isShown else { return false }
        if case .feedback = model.screen { return false }
        return true
    }

    func show(_ screen: PanelScreen, from button: NSStatusBarButton) {
        closeTask?.cancel()
        model.screen = screen

        switch screen {
        case .setUp, .waiting, .failed:
            // The password prompt takes focus; a transient popover would close under it.
            popover.behavior = .applicationDefined
        default:
            popover.behavior = .transient
        }

        if !popover.isShown {
            if case .feedback = screen {} else { NSApp.activate(ignoringOtherApps: true) }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        switch screen {
        case .ready: scheduleClose(after: 6)
        case .feedback: scheduleClose(after: 1.8)
        default: break
        }
    }

    func close() {
        closeTask?.cancel()
        popover.performClose(nil)
    }

    private func scheduleClose(after seconds: Double) {
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // Someone reading with the pointer on the panel keeps it open.
            while self?.hovering == true, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.popover.performClose(nil)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        model.shown = true
    }

    func popoverDidClose(_ notification: Notification) {
        closeTask?.cancel()
        hovering = false
        model.shown = false
    }
}

// MARK: Views

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        Group {
            switch model.screen {
            case let .feedback(feedback):
                FeedbackView(feedback: feedback)
            default:
                GuideView(model: model)
                    .frame(width: 300)
            }
        }
        .onHover(perform: onHover)
        .environment(\.cupAnimates, model.shown)
    }
}

private struct CupAnimatesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var cupAnimates: Bool {
        get { self[CupAnimatesKey.self] }
        set { self[CupAnimatesKey.self] = newValue }
    }
}

/// The cup from the menu bar, larger. Its steam rises while the Mac is being kept awake.
struct CupMark: View {
    let on: Bool
    var size: CGFloat = 26
    @Environment(\.cupAnimates) private var animates

    var body: some View {
        Image(systemName: on ? "cup.and.heat.waves.fill" : "cup.and.saucer")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeating, isActive: on && animates)
            .frame(height: size * 1.25, alignment: .bottomLeading)
    }
}

struct MonoLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

private struct GuideView: View {
    @ObservedObject var model: PanelModel

    private var waiting: Bool {
        if case .waiting = model.screen { return true }
        return false
    }

    private var title: String {
        model.screen == .ready ? "Ready. This icon is your switch." : "Close the lid. Keep working."
    }

    private var message: String {
        switch model.screen {
        case .ready: return "Click it to turn on or off.\nRight-click for settings."
        case .info: return "Click the cup to turn it on or off.\nRight-click for settings."
        default: return "Your Mac stays awake\nso your agents can finish."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CupMark(on: true)
                .padding(.bottom, 12)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            if case let .failed(_, error) = model.screen {
                Text("Setup did not finish. \(error)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            actions
                .padding(.top, 18)

            Divider()
                .padding(.top, 16)

            MonoLine(text: model.safetyLine)
                .padding(.top, 10)
        }
        .padding(20)
    }

    @ViewBuilder private var actions: some View {
        switch model.screen {
        case .ready:
            HStack(spacing: 8) {
                Spacer()
                Button("Later") { model.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Turn on now") { model.switchOn() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryStyle())
            }
            .controlSize(.large)
        case .info:
            HStack {
                Spacer()
                Button("Done") { model.close() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryStyle())
            }
            .controlSize(.large)
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text(waiting ? "Enter your password in the macOS window." : "macOS asks for your password once.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Spacer()
                    if !waiting {
                        Button("Not now") { model.close() }
                            .keyboardShortcut(.cancelAction)
                    }
                    Button { model.allow() } label: {
                        if waiting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).environment(\.colorScheme, .dark)
                                Text("Waiting…")
                            }
                        } else {
                            Text(model.screen.turnOn ? "Allow and turn on" : "Allow once")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryStyle())
                }
                .controlSize(.large)
            }
        }
    }
}

private struct FeedbackView: View {
    let feedback: Feedback

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            CupMark(on: feedback.on, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = feedback.detail {
                    MonoLine(text: detail)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .fixedSize()
    }
}

/// Solid accent capsule sized like a large native button. The native prominent style turns gray
/// whenever the popover is not key, which happens while the password prompt is up.
private struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 28)
                .background(Capsule().fill(Color.accentColor))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.55)
                .contentShape(Capsule())
        }
    }
}

// MARK: Previews

/// Draws a panel screen into a PNG without a popover, for design review.
@MainActor
func snapshotPanel(_ screen: PanelScreen, dark: Bool, cutoff: Int, to path: String) {
    let model = PanelModel()
    model.screen = screen
    model.cutoff = cutoff
    let host = NSHostingView(rootView: PanelView(model: model)
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    // Prominent buttons only draw in the accent color in the key window of the active app.
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    host.display()
    writePNG(of: host, to: path)
}

@MainActor
func writePNG(of view: NSView, to path: String) {
    let bounds = view.bounds
    guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
    view.cacheDisplay(in: bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}
