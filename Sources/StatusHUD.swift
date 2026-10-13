import AppKit
import SwiftUI

/// A small bubble under the menu bar icon that confirms a one-click toggle, then fades.
@MainActor
final class StatusHUD {
    private var popover: NSPopover?
    private var hideTask: Task<Void, Never>?

    func show(from button: NSStatusBarButton, on: Bool, title: String, detail: String) {
        hideTask?.cancel()
        popover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        let host = NSHostingController(rootView: HUDView(on: on, title: title, detail: detail))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.popover?.performClose(nil)
            self?.popover = nil
        }
    }
}

struct HUDView: View {
    let on: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: on ? [Palette.sky, Palette.ocean] : [Color(white: 0.86), Color(white: 0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: (on ? Palette.ocean : .black).opacity(on ? 0.3 : 0.08), radius: 6, y: 3)
                Image(systemName: on ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.mist)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .fixedSize()
        .environment(\.colorScheme, .light)
    }
}
