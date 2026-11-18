import AppKit
import SwiftUI

// The window that shows what happened while the lid was closed, and the image it copies for a post.
// Both are drawn from the log, so they work for nights from before this window existed.

// MARK: Look

/// One set of colors for the window and the image. The blue is fixed, not the system accent, so
/// every posted image looks like LidAwake.
struct ReportTheme {
    let background: Color
    let ink: Color
    /// Secondary text. Checked at 4.5:1 or better on `background`.
    let soft: Color
    /// Lines and fills only, never text.
    let faint: Color
    let accent: Color
    let button: Color
    let warn: Color

    static func current(_ scheme: ColorScheme) -> ReportTheme { scheme == .dark ? dark : light }

    static let light: ReportTheme = {
        let ink = Color(red: 0.105, green: 0.105, blue: 0.118)
        return ReportTheme(
            background: Color(red: 0.984, green: 0.984, blue: 0.976),
            ink: ink, soft: ink.opacity(0.62), faint: ink.opacity(0.13),
            accent: Color(red: 0.122, green: 0.435, blue: 0.922),
            button: Color(red: 0.122, green: 0.435, blue: 0.922),
            warn: Color(red: 0.741, green: 0.329, blue: 0.0)
        )
    }()

    static let dark: ReportTheme = {
        let ink = Color(red: 0.957, green: 0.957, blue: 0.965)
        return ReportTheme(
            background: Color(red: 0.098, green: 0.098, blue: 0.106),
            ink: ink, soft: ink.opacity(0.64), faint: ink.opacity(0.16),
            accent: Color(red: 0.345, green: 0.612, blue: 1.0),
            button: Color(red: 0.122, green: 0.435, blue: 0.922),
            warn: Color(red: 1.0, green: 0.635, blue: 0.259)
        )
    }()
}

private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

enum ReportText {
    private static func format(_ pattern: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date).lowercased()
    }

    static func day(_ date: Date) -> String { format("EEE d MMM", date) }
    static func shortDay(_ date: Date) -> String { format("d MMM", date) }

    static func range(_ close: LidClose) -> String {
        if close.duration < 20 * 3_600 {
            return "\(day(close.closedAt)) · \(clockTime(close.closedAt)) → \(clockTime(close.endedAt))"
        }
        return "\(day(close.closedAt)) \(clockTime(close.closedAt)) → \(day(close.endedAt)) \(clockTime(close.endedAt))"
    }

    /// `8h 29m` as number and unit pairs, so the units can be set smaller.
    static func parts(_ seconds: TimeInterval) -> [(number: String, unit: String)] {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 60 { return [("\(minutes)", "min")] }
        return [("\(minutes / 60)", "h"), (String(format: "%02d", minutes % 60), "m")]
    }

    static func hours(_ seconds: TimeInterval) -> String {
        let hours = Int((seconds / 3_600).rounded())
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

// MARK: Chart data

struct ChartRow: Identifiable {
    enum Kind { case mac, agent, system }

    let id: String
    let name: String
    let value: String
    let kind: Kind
    /// One per line: 0 is nothing, 0.25 is running but quiet, 0.5 to 1 is working.
    let marks: [Float]
}

struct ChartData {
    /// With the Mac and macOS rows this keeps the chart at five rows.
    static let maxAgentRows = 3

    let rows: [ChartRow]
    let battery: [(x: CGFloat, percent: Int)]
    let ticks: [(x: CGFloat, text: String)]
    /// Bins where the Mac was not running.
    let asleep: [Bool]
    /// True when the log has no agent data for this close, and the Mac row stands alone.
    let single: Bool

    init(close: LidClose, plotWidth: CGFloat) {
        let duration = max(close.duration, 1)
        let minutes = max(1, Int((duration / 60).rounded(.up)))
        let columns = max(1, min(Int(plotWidth / 2), minutes))

        var bins = [[Int]](repeating: [], count: columns)
        for (index, sample) in close.samples.enumerated() {
            let position = sample.time.timeIntervalSince(close.closedAt) / duration
            bins[min(columns - 1, max(0, Int(position * Double(columns))))].append(index)
        }
        var asleep = [Bool](repeating: false, count: columns)
        for column in 0..<columns where bins[column].isEmpty {
            let middle = close.closedAt.addingTimeInterval((Double(column) + 0.5) / Double(columns) * duration)
            if let near = close.sample(near: middle) { bins[column] = [near.index] } else { asleep[column] = true }
        }
        self.asleep = asleep

        var rows = [ChartRow(
            id: "mac", name: "Mac", value: spanText(close.awake), kind: .mac,
            marks: asleep.map { $0 ? 0 : 1 }
        )]

        if close.tracked {
            let named = close.agentOrder.count > Self.maxAgentRows ? Self.maxAgentRows - 1 : Self.maxAgentRows
            var groups: [(id: String, name: String, ids: [String])] = close.agentOrder.prefix(named).map {
                ($0, ActivityCatalog.agentName($0), [$0])
            }
            let rest = Array(close.agentOrder.dropFirst(named))
            if !rest.isEmpty { groups.append(("other", "Other agents", rest)) }
            for group in groups {
                var working = [Bool](repeating: false, count: close.samples.count)
                for id in group.ids {
                    for (index, flag) in (close.working[id] ?? []).enumerated() where flag { working[index] = true }
                }
                let marks: [Float] = bins.map { indexes in
                    guard !indexes.isEmpty else { return 0 }
                    let busy = indexes.filter { working[$0] }.count
                    if busy > 0 { return 0.5 + 0.5 * Float(busy) / Float(indexes.count) }
                    let running = indexes.contains { index in group.ids.contains { close.samples[index].agents[$0] != nil } }
                    return running ? 0.25 : 0
                }
                let time = zip(working, close.weights).reduce(0) { $0 + ($1.0 ? $1.1 : 0) }
                rows.append(ChartRow(id: group.id, name: group.name, value: time >= 60 ? spanText(time) : "quiet", kind: .agent, marks: marks))
            }
            if close.systemTime >= 60 {
                let marks: [Float] = bins.map { indexes in indexes.contains { close.systemActive[$0] } ? 1 : 0 }
                rows.append(ChartRow(id: "macos", name: "macOS", value: spanText(close.systemTime), kind: .system, marks: marks))
            }
        }
        self.rows = rows
        single = rows.count == 1

        battery = close.samples.compactMap { sample in
            guard let percent = sample.battery else { return nil }
            return (CGFloat(sample.time.timeIntervalSince(close.closedAt) / duration), percent)
        }

        var ticks: [(x: CGFloat, text: String)] = [(0, clockTime(close.closedAt))]
        let hours = duration / 3_600
        if hours >= 1.5, let step = [1, 2, 3, 4, 6, 12, 24, 48].first(where: { hours / Double($0) <= 4.5 }) {
            let calendar = Calendar.current
            var parts = calendar.dateComponents([.year, .month, .day, .hour], from: close.closedAt)
            parts.hour = ((parts.hour ?? 0) / min(step, 24)) * min(step, 24)
            var mark = calendar.date(from: parts) ?? close.closedAt
            while mark < close.endedAt {
                let x = CGFloat(mark.timeIntervalSince(close.closedAt) / duration)
                if x > 0.2, x < 0.8 { ticks.append((x, clockTime(mark))) }
                mark = mark.addingTimeInterval(Double(step) * 3_600)
            }
        }
        ticks.append((1, clockTime(close.endedAt)))
        self.ticks = ticks
    }
}

struct ChartStyle {
    var labelWidth: CGFloat
    var valueWidth: CGFloat
    var plotWidth: CGFloat
    var gap: CGFloat = 14
    var rowHeight: CGFloat = 32
    var stripHeight: CGFloat = 20
    var singleHeight: CGFloat = 52
    var batteryHeight: CGFloat = 34
    var nameSize: CGFloat = 12
    var valueSize: CGFloat = 11.5

    static let window = ChartStyle(labelWidth: 92, valueWidth: 64, plotWidth: 427)
    static let card = ChartStyle(labelWidth: 100, valueWidth: 70, plotWidth: 502, gap: 16, rowHeight: 26, stripHeight: 17, singleHeight: 60, batteryHeight: 28)
    /// Five rows fit the image only at this height.
    static let cardCompact = ChartStyle(labelWidth: 100, valueWidth: 70, plotWidth: 502, gap: 16, rowHeight: 22, stripHeight: 15, batteryHeight: 24)
}

// MARK: Model and window

@MainActor
final class ReportModel: ObservableObject {
    @Published var history = LidHistory.empty
    @Published var selectedID: Date?
    @Published var loaded = false
    @Published var copied = false
    /// Changes when the chart should draw itself in again.
    @Published var drawToken = 0

    var logURL = Paths.logFile
    var animated = true
    var openLog: () -> Void = {}
    private var charts: [String: ChartData] = [:]

    var selected: LidClose? {
        history.closes.first { $0.id == selectedID } ?? history.closes.first
    }

    func reload() {
        let url = logURL
        Task { @MainActor in
            let history = await Task.detached(priority: .userInitiated) { HistoryReader.read(url) }.value
            self.apply(history)
        }
    }

    func apply(_ history: LidHistory) {
        charts = [:]
        self.history = history
        selectedID = history.closes.first?.id
        loaded = true
        drawToken += 1
    }

    func select(_ close: LidClose) {
        guard close.id != selected?.id else { return }
        selectedID = close.id
        drawToken += 1
    }

    func chart(for close: LidClose, style: ChartStyle) -> ChartData {
        let key = "\(close.id.timeIntervalSince1970)-\(style.plotWidth)"
        if let data = charts[key] { return data }
        let data = ChartData(close: close, plotWidth: style.plotWidth)
        charts[key] = data
        return data
    }

    /// Puts the image for a post on the clipboard, in the light or dark look of the window.
    func copyImage(scheme: ColorScheme) {
        guard let close = selected, let png = Self.cardPNG(close: close, scheme: scheme) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            self.copied = false
        }
    }

    static func cardPNG(close: LidClose, scheme: ColorScheme) -> Data? {
        let data = ChartData(close: close, plotWidth: ChartStyle.card.plotWidth)
        let card = ShareCard(close: close, data: data, theme: .current(scheme))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

@MainActor
final class ReportWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 920, height: 560)

    let model = ReportModel()
    private var window: NSWindow?
    var onClose: () -> Void = {}

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "While the lid was closed"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.delegate = self
            // The view draws under the title bar and leaves room for it, so the window is one surface.
            let host = NSHostingView(rootView: ReportView(model: model))
            host.safeAreaRegions = []
            window.contentView = host
            window.setContentSize(Self.size)
            window.center()
            self.window = window
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: Views

struct ReportView: View {
    @ObservedObject var model: ReportModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ReportTheme.current(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if let close = model.selected {
                        MainPane(model: model, close: close, theme: theme)
                    } else {
                        EmptyPane(theme: theme, loaded: model.loaded)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Rectangle().fill(theme.faint).frame(width: 1)
                Rail(model: model, theme: theme)
                    .frame(width: 236)
            }
            Rectangle().fill(theme.faint).frame(height: 1)
            FooterBar(model: model, theme: theme)
                .frame(height: 52)
        }
        .frame(width: ReportWindowController.size.width, height: ReportWindowController.size.height)
        .background(theme.background)
        .foregroundStyle(theme.ink)
    }
}

private struct MainPane: View {
    @ObservedObject var model: ReportModel
    let close: LidClose
    let theme: ReportTheme
    @State private var hover: Date?
    @State private var reveal: CGFloat = 0

    var body: some View {
        let data = model.chart(for: close, style: .window)
        VStack(alignment: .leading, spacing: 0) {
            HeroBlock(close: close, theme: theme, heroSize: 92, titleSize: 17, noteSize: 13, eyebrowSize: 11.5)
            Spacer(minLength: 18)
            NightChart(close: close, data: data, theme: theme, style: .window, reveal: reveal) { hover = $0 }
            Text(hover.map { hoverLine(at: $0) } ?? factLine)
                .font(mono(11))
                .foregroundStyle(theme.soft)
                .lineLimit(1)
                .padding(.top, 16)
        }
        .padding(EdgeInsets(top: 46, leading: 40, bottom: 24, trailing: 32))
        .onAppear { draw() }
        .onChange(of: model.drawToken) { draw() }
    }

    private func draw() {
        hover = nil
        guard model.animated else {
            reveal = 1
            return
        }
        reveal = 0
        withAnimation(.easeOut(duration: 0.85)) { reveal = 1 }
    }

    private var factLine: String {
        var parts: [String] = []
        let checks = close.samples.count
        let missed = close.mayHaveSlept ? "longest gap \(spanText(close.longestGap))" : "none missed"
        parts.append("\(checks) check-in\(checks == 1 ? "" : "s"), \(missed)")
        if let heat = close.heat {
            parts.append("heat \(heat.state) for \(spanText(heat.time))")
        } else {
            parts.append("heat nominal")
        }
        return parts.joined(separator: " · ")
    }

    private func hoverLine(at time: Date) -> String {
        guard let found = close.sample(near: time) else { return "\(clockTime(time)) · no check-in" }
        var parts = [clockTime(time)]
        if close.tracked {
            let working = close.agentOrder.filter { close.working[$0]?[found.index] == true }
            if working.isEmpty {
                parts.append(found.sample.agents.isEmpty ? "no agent running" : "agents quiet")
            } else {
                parts.append(contentsOf: working.map { "\(ActivityCatalog.agentName($0)) working" })
            }
            let jobs = ActivityCatalog.system.filter { (found.sample.system[$0.id] ?? 0) >= ActivityCatalog.systemWorking }
            parts.append(contentsOf: jobs.map(\.name))
        } else {
            parts.append("awake")
        }
        if let battery = found.sample.battery { parts.append("battery \(battery)%") }
        return parts.joined(separator: " · ")
    }
}

/// The date, the big number and the one or two sentences under it.
struct HeroBlock: View {
    let close: LidClose
    let theme: ReportTheme
    let heroSize: CGFloat
    let titleSize: CGFloat
    let noteSize: CGFloat
    let eyebrowSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ReportText.range(close))
                .font(mono(eyebrowSize))
                .foregroundStyle(theme.soft)

            number
                .padding(.top, heroSize * 0.02)
                .padding(.leading, -heroSize * 0.035)

            Text("awake with the lid closed.")
                .font(.system(size: titleSize, weight: .semibold))
                .padding(.top, -heroSize * 0.02)

            if let note {
                note
                    .font(.system(size: noteSize))
                    .padding(.top, titleSize * 0.22)
            }
        }
    }

    private var number: Text {
        var text = Text("")
        for (index, part) in ReportText.parts(close.awake).enumerated() {
            if index > 0 { text = text + Text(" ").font(.system(size: heroSize * 0.26)) }
            text = text
                + Text(part.number)
                    .font(.system(size: heroSize, weight: .semibold))
                    .tracking(-heroSize * 0.035)
                + Text(part.unit)
                    .font(.system(size: heroSize * 0.42, weight: .medium))
                    .foregroundColor(theme.soft)
        }
        return text
    }

    private var note: Text? {
        if let stop = close.stopText {
            return Text(stop).foregroundColor(theme.warn)
        }
        if close.mayHaveSlept {
            return Text("It may have slept. No check-in for \(spanText(close.longestGap)).").foregroundColor(theme.warn)
        }
        guard close.tracked else { return nil }
        let time = close.agentWorkTime
        guard time >= 60 else {
            return Text(close.agentOrder.isEmpty ? "No agent was running." : "Your agents were quiet.").foregroundColor(theme.soft)
        }
        let workers = close.agentOrder.filter { close.workTime(of: $0) >= 60 }
        let who = workers.count == 1 ? ActivityCatalog.agentName(workers[0]) : "Your agents"
        return Text("\(who) worked ").foregroundColor(theme.soft)
            + Text(spanText(time)).fontWeight(.semibold).foregroundColor(theme.ink)
            + Text(" of it.").foregroundColor(theme.soft)
    }
}

/// Battery on top, then one row per worker, on one time axis.
struct NightChart: View {
    let close: LidClose
    let data: ChartData
    let theme: ReportTheme
    let style: ChartStyle
    var reveal: CGFloat = 1
    var onHover: ((Date?) -> Void)?
    @State private var cursor: CGFloat?

    private var rowHeight: CGFloat { data.single ? style.singleHeight + 10 : style.rowHeight }
    private var stripHeight: CGFloat { data.single ? style.singleHeight : style.stripHeight }
    private var plotHeight: CGFloat { style.batteryHeight + CGFloat(data.rows.count) * rowHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: style.gap) {
                VStack(alignment: .leading, spacing: 0) {
                    label("Battery").frame(height: style.batteryHeight)
                    ForEach(data.rows) { row in label(row.name).frame(height: rowHeight) }
                }
                .frame(width: style.labelWidth, alignment: .leading)

                plot
                    .frame(width: style.plotWidth, height: plotHeight)

                VStack(alignment: .trailing, spacing: 0) {
                    value(batteryText).frame(height: style.batteryHeight)
                    ForEach(data.rows) { row in value(row.value).frame(height: rowHeight) }
                }
                .frame(width: style.valueWidth, alignment: .trailing)
            }

            axis
                .frame(width: style.plotWidth, height: 14)
                .padding(.leading, style.labelWidth + style.gap)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: style.nameSize, weight: .medium))
            .lineLimit(1)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(mono(style.valueSize))
            .foregroundStyle(theme.soft)
            .lineLimit(1)
            .fixedSize()
    }

    private var batteryText: String {
        guard let start = close.batteryStart, let end = close.batteryEnd else { return "none" }
        return "\(start) → \(end)%"
    }

    private var plot: some View {
        Canvas { context, size in
            drawBattery(&context, CGRect(x: 0, y: 0, width: size.width, height: style.batteryHeight))
            var top = style.batteryHeight
            for row in data.rows {
                let rect = CGRect(x: 0, y: top + (rowHeight - stripHeight) / 2, width: size.width, height: stripHeight)
                drawMarks(&context, row, rect)
                top += rowHeight
            }
        }
        .mask(alignment: .leading) {
            Rectangle().frame(width: max(0, style.plotWidth * reveal))
        }
        .overlay(alignment: .topLeading) {
            if let cursor {
                Rectangle()
                    .fill(theme.ink.opacity(0.45))
                    .frame(width: 1, height: plotHeight)
                    .offset(x: cursor)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard let onHover else { return }
            switch phase {
            case let .active(point):
                let x = min(max(point.x, 0), style.plotWidth)
                cursor = x
                onHover(close.closedAt.addingTimeInterval(Double(x / style.plotWidth) * close.duration))
            case .ended:
                cursor = nil
                onHover(nil)
            }
        }
    }

    private func drawMarks(_ context: inout GraphicsContext, _ row: ChartRow, _ rect: CGRect) {
        let count = row.marks.count
        guard count > 0 else { return }
        let pitch = rect.width / CGFloat(count)
        let width = min(max(pitch * 0.5, 1), 3)
        let color: Color
        switch row.kind {
        // Blue always means an agent at work, so the Mac row stays neutral even when it stands alone.
        case .mac: color = theme.ink.opacity(0.82)
        case .agent: color = theme.accent
        case .system: color = theme.ink.opacity(0.5)
        }
        context.fill(Path(CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1)), with: .color(theme.faint))
        for (index, mark) in row.marks.enumerated() {
            let x = ((rect.minX + (CGFloat(index) + 0.5) * pitch - width / 2) * 2).rounded() / 2
            if mark <= 0 {
                if row.kind == .mac, data.asleep[index] {
                    context.fill(Path(CGRect(x: x, y: rect.maxY - 2, width: max(width, pitch), height: 2)), with: .color(theme.warn))
                }
                continue
            }
            let working = mark >= 0.5
            let height = working ? rect.height : max(3, (rect.height * 0.22).rounded())
            let opacity = working ? 0.4 + 0.6 * Double((mark - 0.5) * 2) : 0.45
            let line = CGRect(x: x, y: rect.maxY - height, width: width, height: height)
            context.fill(Path(line), with: .color(color.opacity(opacity)))
        }
    }

    private func drawBattery(_ context: inout GraphicsContext, _ rect: CGRect) {
        guard data.battery.count > 1 else { return }
        let low = data.battery.map(\.percent).min() ?? 0
        let high = data.battery.map(\.percent).max() ?? 100
        let band = rect.insetBy(dx: 2.5, dy: 9)
        func point(_ entry: (x: CGFloat, percent: Int)) -> CGPoint {
            let level = high - low < 3 ? 0.5 : CGFloat(entry.percent - low) / CGFloat(high - low)
            return CGPoint(x: band.minX + entry.x * band.width, y: band.maxY - level * band.height)
        }
        var path = Path()
        path.move(to: point(data.battery[0]))
        for entry in data.battery.dropFirst() { path.addLine(to: point(entry)) }
        context.stroke(path, with: .color(theme.soft), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        for entry in [data.battery[0], data.battery[data.battery.count - 1]] {
            let center = point(entry)
            let dot = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: dot), with: .color(theme.background))
            context.stroke(Path(ellipseIn: dot), with: .color(theme.soft), lineWidth: 1.25)
        }
    }

    private var axis: some View {
        // The first label starts at the left edge of the plot, the last one ends at the right edge.
        ZStack(alignment: .topLeading) {
            ForEach(Array(data.ticks.enumerated()), id: \.offset) { _, tick in
                let first = tick.x <= 0, last = tick.x >= 1
                Text(tick.text)
                    .font(mono(10.5))
                    .foregroundStyle(theme.soft)
                    .frame(width: 70, alignment: first ? .leading : (last ? .trailing : .center))
                    .offset(x: tick.x * style.plotWidth - (first ? 0 : (last ? 70 : 35)))
            }
        }
        .frame(width: style.plotWidth, alignment: .topLeading)
    }
}

private struct Rail: View {
    @ObservedObject var model: ReportModel
    let theme: ReportTheme

    private var scale: TimeInterval {
        min(24 * 3_600, model.history.closes.map(\.duration).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("lid closes")
                .font(mono(10.5))
                .foregroundStyle(theme.soft)
                .padding(.leading, 20)
                .padding(.bottom, 8)
                .opacity(model.history.closes.isEmpty ? 0 : 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(model.history.closes) { close in
                        RailRow(close: close, selected: close.id == model.selected?.id, scale: scale, theme: theme) {
                            model.select(close)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))

            if !model.history.closes.isEmpty {
                Rectangle().fill(theme.faint).frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReportText.hours(model.history.totalAwake))
                        .font(.system(size: 22, weight: .semibold))
                    Text("lid closed" + (model.history.since.map { ", since \(ReportText.shortDay($0))" } ?? ""))
                        .font(mono(10.5))
                        .foregroundStyle(theme.soft)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 46)
    }
}

private struct RailRow: View {
    let close: LidClose
    let selected: Bool
    let scale: TimeInterval
    let theme: ReportTheme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(ReportText.shortDay(close.closedAt))
                    .font(mono(11.5))
                    .frame(width: 46, alignment: .leading)
                GeometryReader { proxy in
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(3, proxy.size.width * min(1, close.duration / scale)), height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                Text(spanText(close.awake))
                    .font(mono(11.5))
                    .frame(width: 58, alignment: .trailing)
            }
            .foregroundStyle(selected ? theme.ink : theme.soft)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.ink.opacity(selected ? 0.075 : (hovering ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var barColor: Color {
        if close.mayHaveSlept || close.stopText != nil { return theme.warn.opacity(selected ? 1 : 0.7) }
        return selected ? theme.accent : theme.ink.opacity(0.24)
    }
}

private struct FooterBar: View {
    @ObservedObject var model: ReportModel
    let theme: ReportTheme
    @Environment(\.colorScheme) private var scheme
    @State private var overLog = false

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                Text("LidAwake")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Button("Open log") { model.openLog() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.soft)
                .underline(overLog)
                .onHover { overLog = $0 }
            Button { model.copyImage(scheme: scheme) } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.copied ? "checkmark" : "square.on.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(model.copied ? "Copied" : "Copy image")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 28)
                .background(Capsule().fill(theme.button))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selected == nil)
            .opacity(model.selected == nil ? 0.45 : 1)
        }
        .padding(.leading, 40)
        .padding(.trailing, 20)
    }
}

private struct EmptyPane: View {
    let theme: ReportTheme
    let loaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loaded {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.soft)
                    .padding(.bottom, 14)
                Text("Nothing yet.")
                    .font(.system(size: 17, weight: .semibold))
                Text("Turn it on, close the lid, and come back.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.soft)
                    .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 46, leading: 40, bottom: 24, trailing: 32))
    }
}

/// The image `Copy image` makes: 800 x 450 points, drawn at 2x. It names no file, folder or project.
struct ShareCard: View {
    let close: LidClose
    let data: ChartData
    let theme: ReportTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroBlock(close: close, theme: theme, heroSize: 96, titleSize: 25, noteSize: 17, eyebrowSize: 12.5)
            Spacer(minLength: 10)
            NightChart(close: close, data: data, theme: theme, style: data.rows.count >= 5 ? .cardCompact : .card)
            HStack(spacing: 8) {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                Text("LidAwake")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("thelaunch.space/lidawake")
                    .font(mono(12))
                    .foregroundStyle(theme.soft)
            }
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 36, leading: 48, bottom: 28, trailing: 48))
        .frame(width: 800, height: 450, alignment: .topLeading)
        .background(theme.background)
        .foregroundStyle(theme.ink)
    }
}

// MARK: Previews

/// Draws the window or the image to a PNG from any log file, for design review. Reads only.
@MainActor
func snapshotReport(log: URL, pick: Int, dark: Bool, card: Bool, to path: String) {
    let history = HistoryReader.read(log)
    let scheme: ColorScheme = dark ? .dark : .light
    let closes = history.closes
    if card {
        guard !closes.isEmpty else { return }
        let png = ReportModel.cardPNG(close: closes[min(max(pick, 0), closes.count - 1)], scheme: scheme)
        try? png?.write(to: URL(fileURLWithPath: path))
        return
    }
    let model = ReportModel()
    model.animated = false
    model.apply(history)
    if !closes.isEmpty { model.selectedID = closes[min(max(pick, 0), closes.count - 1)].id }
    let host = NSHostingView(rootView: ReportView(model: model).environment(\.colorScheme, scheme))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(origin: .zero, size: ReportWindowController.size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    NSApp.setActivationPolicy(.accessory)
    window.orderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    host.layoutSubtreeIfNeeded()
    host.display()
    writePNG(of: host, to: path)
}
