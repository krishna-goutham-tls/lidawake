import Foundation

/// One heartbeat line from the log.
struct MinuteSample {
    let time: Date
    let battery: Int?
    let thermal: String
    /// Agent id to the processor seconds per minute of its busiest session. An agent that was
    /// not running has no entry.
    let agents: [String: Double]
    /// macOS job id to processor seconds per minute.
    let system: [String: Double]
    /// False for heartbeats written before the app looked at processes.
    let tracked: Bool
}

/// One stretch with the lid closed while the switch was on, rebuilt from the log.
struct LidClose: Identifiable {
    /// The heartbeat comes every 60 s, so two missed in a row means the Mac was not running.
    static let gapLimit: TimeInterval = 150
    /// An agent that goes quiet for this many minutes inside a working stretch is waiting on its
    /// model, which uses almost no processor time.
    static let bridge = 3

    let closedAt: Date
    let endedAt: Date
    let samples: [MinuteSample]
    let stopText: String?

    let gaps: [(from: Date, to: Date)]
    let longestGap: TimeInterval
    let awake: TimeInterval
    let tracked: Bool
    /// Seconds each sample stands for.
    let weights: [TimeInterval]
    /// Agent id to one flag per sample: working in that minute.
    let working: [String: [Bool]]
    /// Agents that ran, the one that worked longest first.
    let agentOrder: [String]
    let systemActive: [Bool]

    var id: Date { closedAt }
    var duration: TimeInterval { endedAt.timeIntervalSince(closedAt) }
    var mayHaveSlept: Bool { !gaps.isEmpty }
    var batteryStart: Int? { samples.first { $0.battery != nil }?.battery }
    var batteryEnd: Int? { samples.last { $0.battery != nil }?.battery }

    init(closedAt: Date, endedAt: Date, samples: [MinuteSample], stopText: String?) {
        self.closedAt = closedAt
        self.endedAt = endedAt
        self.samples = samples
        self.stopText = stopText

        var gaps: [(from: Date, to: Date)] = []
        var previous = closedAt
        for time in samples.map(\.time) + [endedAt] {
            if time.timeIntervalSince(previous) > Self.gapLimit { gaps.append((previous, time)) }
            previous = time
        }
        self.gaps = gaps
        longestGap = gaps.map { $0.to.timeIntervalSince($0.from) }.max() ?? 0
        let lost = gaps.reduce(0) { $0 + $1.to.timeIntervalSince($1.from) - 60 }
        awake = max(0, endedAt.timeIntervalSince(closedAt) - lost)
        tracked = samples.contains { $0.tracked }

        var weights: [TimeInterval] = []
        previous = closedAt
        for sample in samples {
            let span = sample.time.timeIntervalSince(previous)
            weights.append(span > 0 && span <= 90 ? span : 60)
            previous = sample.time
        }
        self.weights = weights

        var ids = Set<String>()
        for sample in samples { ids.formUnion(sample.agents.keys) }
        var working: [String: [Bool]] = [:]
        for id in ids {
            var flags = samples.map { ($0.agents[id] ?? 0) >= ActivityCatalog.agentWorking }
            var lastWork: Int?
            for index in flags.indices where flags[index] {
                if let last = lastWork, index - last > 1, index - last <= Self.bridge + 1,
                   samples[index].time.timeIntervalSince(samples[last].time) <= Double(Self.bridge + 1) * 90 {
                    for between in (last + 1)..<index where samples[between].agents[id] != nil {
                        flags[between] = true
                    }
                }
                lastWork = index
            }
            working[id] = flags
        }
        self.working = working
        func seconds(_ flags: [Bool]) -> TimeInterval {
            zip(flags, weights).reduce(0) { $0 + ($1.0 ? $1.1 : 0) }
        }
        agentOrder = ids.sorted {
            let left = seconds(working[$0] ?? []), right = seconds(working[$1] ?? [])
            return left == right ? $0 < $1 : left > right
        }
        systemActive = samples.map { sample in
            sample.system.values.contains { $0 >= ActivityCatalog.systemWorking }
        }
    }

    private func seconds(_ flags: [Bool]) -> TimeInterval {
        zip(flags, weights).reduce(0) { $0 + ($1.0 ? $1.1 : 0) }
    }

    func workTime(of agent: String) -> TimeInterval {
        seconds(working[agent] ?? [])
    }

    /// Time in which at least one agent worked.
    var agentWorkTime: TimeInterval {
        var flags = [Bool](repeating: false, count: samples.count)
        for list in working.values {
            for index in list.indices where list[index] { flags[index] = true }
        }
        return seconds(flags)
    }

    var systemTime: TimeInterval { seconds(systemActive) }

    /// The worst heat state macOS reported, and for how long. Nil when it stayed nominal.
    var heat: (state: String, time: TimeInterval)? {
        let order = ["fair", "serious", "critical"]
        var worst = -1
        for sample in samples {
            if let rank = order.firstIndex(of: sample.thermal) { worst = max(worst, rank) }
        }
        guard worst >= 0 else { return nil }
        let flags = samples.map { order.firstIndex(of: $0.thermal) != nil }
        return (order[worst], seconds(flags))
    }

    /// The heartbeat nearest to a moment, unless the Mac was not running then.
    func sample(near time: Date) -> (index: Int, sample: MinuteSample)? {
        guard !samples.isEmpty else { return nil }
        if gaps.contains(where: { time > $0.from.addingTimeInterval(45) && time < $0.to.addingTimeInterval(-45) }) {
            return nil
        }
        var low = 0, high = samples.count - 1
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time < time { low = middle + 1 } else { high = middle }
        }
        if low > 0, abs(samples[low - 1].time.timeIntervalSince(time)) < abs(samples[low].time.timeIntervalSince(time)) {
            low -= 1
        }
        return (low, samples[low])
    }
}

struct LidHistory {
    /// Shorter closes are in the log only, the same as the lid report.
    static let minDuration: TimeInterval = 5 * 60

    /// Newest first.
    let closes: [LidClose]
    let since: Date?

    var totalAwake: TimeInterval { closes.reduce(0) { $0 + $1.awake } }

    static let empty = LidHistory(closes: [], since: nil)
}

enum HistoryReader {
    static func read(_ url: URL) -> LidHistory {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return .empty }
        return parse([UInt8](data))
    }

    static func parse(_ text: String) -> LidHistory {
        parse(Array(text.utf8))
    }

    static func parse(_ bytes: [UInt8]) -> LidHistory {
        var builder = Builder()
        let count = bytes.count
        let tag = Array("[app] ".utf8)
        var start = 0
        while start < count {
            var end = start
            while end < count, bytes[end] != 10 { end += 1 }
            defer { start = end + 1 }
            guard end - start > 31, let time = timestamp(bytes, start) else { continue }
            if builder.since == nil { builder.since = time }
            guard bytes[(start + 25)..<(start + 31)].elementsEqual(tag) else { continue }
            // heartbeat, lid, switched off or shutting down, LidAwake started, automatic stop
            switch bytes[start + 31] {
            case 104, 108, 115, 76, 97:
                builder.handle(time, String(decoding: bytes[(start + 31)..<end], as: UTF8.self))
            default:
                break
            }
        }
        return builder.finish()
    }

    /// `2026-10-13T22:45:51+0530`, the format `Log.write` uses.
    private static func timestamp(_ bytes: [UInt8], _ start: Int) -> Date? {
        func number(_ offset: Int, _ length: Int) -> Int? {
            var value = 0
            for index in 0..<length {
                let digit = Int(bytes[start + offset + index]) - 48
                guard digit >= 0, digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard bytes[start + 4] == 45, bytes[start + 10] == 84,
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              let zoneHours = number(20, 2), let zoneMinutes = number(22, 2) else { return nil }
        let sign = bytes[start + 19] == 45 ? -1 : 1
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - sign * (zoneHours * 3_600 + zoneMinutes * 60)
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private struct Builder {
        var since: Date?
        private var closes: [LidClose] = []
        private var closedAt: Date?
        private var samples: [MinuteSample] = []
        private var pendingClose: Date?
        private var pendingStop: String?

        mutating func handle(_ time: Date, _ message: String) {
            if message.hasPrefix("heartbeat ") {
                heartbeat(time, message)
            } else if message == "lid closed while on" {
                pendingClose = time
            } else if message.hasPrefix("lid record:") {
                end(at: time, stop: Self.stopText(in: message, at: time))
                pendingClose = nil
            } else if message.hasPrefix("automatic stop (") {
                pendingStop = Self.stopText(in: message, at: time)
            } else if message.hasPrefix("switched off") || message.hasPrefix("shutting down") {
                end(at: time, stop: pendingStop)
                pendingStop = nil
            } else if message.hasPrefix("LidAwake "), message.contains(" started") {
                // The app died with the lid closed. The last heartbeat is the last thing known.
                end(at: samples.last?.time ?? time, stop: nil)
                pendingStop = nil
            }
        }

        private mutating func heartbeat(_ time: Date, _ message: String) {
            var lid = ""
            var battery: Int?
            var thermal = "nominal"
            var agents: [String: Double] = [:]
            var system: [String: Double] = [:]
            var tracked = false
            for token in message.split(separator: " ").dropFirst() {
                guard let equals = token.firstIndex(of: "=") else { continue }
                let value = token[token.index(after: equals)...]
                switch token[..<equals] {
                case "lid": lid = String(value)
                case "battery": battery = Int(value.dropLast())
                case "thermal": thermal = String(value)
                case "agents":
                    tracked = true
                    for part in value.split(separator: ",") {
                        let fields = part.split(separator: ":")
                        if fields.count >= 3, let busiest = Double(fields[2]) { agents[String(fields[0])] = busiest }
                    }
                case "macos":
                    for part in value.split(separator: ",") {
                        let fields = part.split(separator: ":")
                        if fields.count == 2, let used = Double(fields[1]) { system[String(fields[0])] = used }
                    }
                default: break
                }
            }
            guard lid == "closed" else {
                end(at: time, stop: nil)
                pendingClose = nil
                return
            }
            if closedAt == nil {
                if let pending = pendingClose, time.timeIntervalSince(pending) >= 0, time.timeIntervalSince(pending) < 120 {
                    closedAt = pending
                } else {
                    closedAt = time
                }
                pendingClose = nil
            }
            samples.append(MinuteSample(time: time, battery: battery, thermal: thermal, agents: agents, system: system, tracked: tracked))
        }

        private mutating func end(at time: Date, stop: String?) {
            guard let start = closedAt else { return }
            let last = samples.last?.time ?? start
            closes.append(LidClose(closedAt: start, endedAt: max(time, last), samples: samples, stopText: stop))
            closedAt = nil
            samples = []
        }

        mutating func finish() -> LidHistory {
            // The log can end in the middle of a close, when the window is opened in clamshell mode.
            if let last = samples.last?.time { end(at: last, stop: nil) }
            let kept = closes.filter { $0.duration >= LidHistory.minDuration }
            return LidHistory(closes: kept.reversed(), since: since)
        }

        private static func stopText(in message: String, at time: Date) -> String? {
            guard let range = message.range(of: "automatic stop") else { return nil }
            let tail = message[range.upperBound...]
            if tail.contains("thermal state") { return "Stopped on a heat warning, \(clockTime(time))." }
            guard let battery = tail.range(of: "battery ") else { return nil }
            let digits = tail[battery.upperBound...].prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return "Stopped at \(digits)% battery, \(clockTime(time))."
        }
    }
}
