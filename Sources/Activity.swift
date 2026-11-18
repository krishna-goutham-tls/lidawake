import Darwin
import Foundation

/// The agents and macOS jobs the activity window can name. Ids go in the log, names go on screen.
enum ActivityCatalog {
    /// A minute counts as work when the busiest session of an agent used this many processor
    /// seconds. Measured on Claude Code for 14 minutes: a session in a turn used 0.54 to 1.4, idle ones 0.1 to 0.45.
    static let agentWorking = 0.5
    /// macOS jobs idle at well under a second a minute.
    static let systemWorking = 3.0

    static let agents: [(id: String, name: String, executables: [String])] = [
        ("claude", "Claude Code", ["claude", "claude-code"]),
        ("codex", "Codex", ["codex"]),
        ("droid", "Droid", ["droid"]),
        ("gemini", "Gemini CLI", ["gemini", "gemini-cli"]),
        ("cursor", "Cursor Agent", ["cursor-agent"]),
        ("opencode", "opencode", ["opencode"]),
        ("aider", "Aider", ["aider"]),
        ("amp", "Amp", ["amp"]),
        ("copilot", "Copilot CLI", ["copilot"]),
        ("goose", "Goose", ["goose"]),
    ]

    static let system: [(id: String, name: String, executables: [String])] = [
        ("backup", "Time Machine backup", ["backupd", "backupd-helper"]),
        ("spotlight", "Spotlight indexing", ["mds", "mds_stores", "mdworker", "mdworker_shared", "mdsync"]),
        ("update", "software update", ["softwareupdated", "mobileassetd"]),
        ("icloud", "iCloud sync", ["bird", "cloudd", "fileproviderd"]),
        ("photos", "Photos analysis", ["photoanalysisd", "photolibraryd", "mediaanalysisd"]),
    ]

    /// Agents written in JavaScript or Python run inside one of these, so their arguments name them.
    static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]

    static let agentByExecutable: [String: String] = {
        var map: [String: String] = [:]
        for agent in agents { for name in agent.executables { map[name] = agent.id } }
        return map
    }()

    static let systemByExecutable: [String: String] = {
        var map: [String: String] = [:]
        for job in system { for name in job.executables { map[name] = job.id } }
        return map
    }()

    static func agentName(_ id: String) -> String {
        agents.first { $0.id == id }?.name ?? id
    }

    static func systemName(_ id: String) -> String {
        system.first { $0.id == id }?.name ?? id
    }
}

/// Reads the process table once a minute, with the heartbeat, and says how much processor time
/// each agent and each macOS job used since the last look. Process names and times only: it never
/// reads a file, and the arguments of an interpreter are checked in memory and not kept.
@MainActor
final class ActivityMonitor {
    private struct Process {
        let pid: Int32
        let parent: Int32
        let cpu: Double
        let executable: String
    }

    private var lastTime: Date?
    private var lastCPU: [Int32: Double] = [:]
    private var interpreterAgents: [Int32: String?] = [:]

    func reset() {
        lastTime = nil
        lastCPU = [:]
        interpreterAgents = [:]
    }

    /// Fields for the heartbeat line, or nil for the first look and when the table cannot be read.
    func sample() -> String? {
        let now = Date()
        let result = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,time=,comm="])
        guard result.ok else { return nil }
        let table = Self.parse(result.output)
        guard !table.isEmpty else { return nil }

        var cpuNow: [Int32: Double] = [:]
        for process in table { cpuNow[process.pid] = process.cpu }
        defer {
            lastTime = now
            lastCPU = cpuNow
            interpreterAgents = interpreterAgents.filter { cpuNow[$0.key] != nil }
        }
        guard let lastTime else { return nil }
        let elapsed = now.timeIntervalSince(lastTime)
        // After a sleep the times no longer describe one minute.
        guard elapsed >= 20, elapsed <= 300 else { return nil }
        let perMinute = 60 / elapsed

        var byPID: [Int32: Process] = [:]
        for process in table { byPID[process.pid] = process }
        var agentOf: [Int32: String] = [:]
        for process in table {
            if let id = agentID(of: process) { agentOf[process.pid] = id }
        }

        var sessions: [Int32: Double] = [:]
        var system: [String: Double] = [:]
        for process in table {
            let before = lastCPU[process.pid] ?? 0
            let used = (process.cpu >= before ? process.cpu - before : process.cpu) * perMinute
            if let job = ActivityCatalog.systemByExecutable[process.executable] {
                system[job, default: 0] += used
            }
            if let root = Self.session(of: process.pid, byPID: byPID, agentOf: agentOf) {
                sessions[root, default: 0] += used
            }
        }

        var counts: [String: Int] = [:]
        var busiest: [String: Double] = [:]
        var totals: [String: Double] = [:]
        for (root, used) in sessions {
            guard let id = agentOf[root] else { continue }
            counts[id, default: 0] += 1
            busiest[id] = max(busiest[id] ?? 0, used)
            totals[id, default: 0] += used
        }

        let agentText = ActivityCatalog.agents.compactMap { agent -> String? in
            guard let count = counts[agent.id] else { return nil }
            return String(format: "%@:%d:%.2f:%.2f", agent.id, count, busiest[agent.id] ?? 0, totals[agent.id] ?? 0)
        }.joined(separator: ",")
        let systemText = ActivityCatalog.system.compactMap { job -> String? in
            guard let used = system[job.id], used >= 0.5 else { return nil }
            return String(format: "%@:%.1f", job.id, used)
        }.joined(separator: ",")
        return "agents=\(agentText.isEmpty ? "none" : agentText) macos=\(systemText.isEmpty ? "idle" : systemText)"
    }

    private func agentID(of process: Process) -> String? {
        if let id = ActivityCatalog.agentByExecutable[process.executable] { return id }
        guard ActivityCatalog.interpreters.contains(process.executable)
            || process.executable.hasPrefix("python3.") else { return nil }
        if let known = interpreterAgents[process.pid] { return known }
        var found: String?
        for argument in Self.arguments(of: process.pid).dropFirst() where !argument.hasPrefix("-") {
            for part in argument.split(separator: "/") {
                let name = part.split(separator: ".").first.map(String.init) ?? String(part)
                if let id = ActivityCatalog.agentByExecutable[name] { found = id }
            }
            break
        }
        interpreterAgents[process.pid] = found
        return found
    }

    /// The agent session a process belongs to: its nearest agent ancestor, then up through
    /// ancestors of the same agent, so a launcher and the binary it starts count as one session.
    private static func session(of pid: Int32, byPID: [Int32: Process], agentOf: [Int32: String]) -> Int32? {
        var current = pid
        var root: Int32?
        var steps = 0
        while let process = byPID[current], steps < 64 {
            if let id = agentOf[current] {
                if let found = root {
                    if agentOf[found] == id { root = current }
                } else {
                    root = current
                }
            }
            if process.parent == current || process.parent <= 1 { break }
            current = process.parent
            steps += 1
        }
        return root
    }

    private static func parse(_ output: String) -> [Process] {
        var table: [Process] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            var cpu = 0.0
            for part in fields[2].split(separator: ":") {
                guard let value = Double(part) else { cpu = -1; break }
                cpu = cpu * 60 + value
            }
            guard cpu >= 0 else { continue }
            let path = fields[3]
            let executable = path.split(separator: "/").last.map(String.init) ?? String(path)
            table.append(Process(pid: pid, parent: parent, cpu: cpu, executable: executable))
        }
        return table
    }

    /// The first arguments of one of this user's processes, read from the kernel.
    private static func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < size, arguments.count < min(Int(count), 4) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
