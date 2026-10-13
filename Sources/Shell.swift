import Foundation

struct ShellResult {
    let status: Int32
    let output: String

    var ok: Bool { status == 0 }
    var summary: String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "exit \(status)" : "exit \(status): \(trimmed)"
    }
}

enum Shell {
    /// Runs an executable with an explicit argv. Never goes through a shell.
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: "could not launch \(path): \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

/// Every call that touches power settings. The sudo argv must match the sudoers rule exactly.
enum Pmset {
    static let sudo = "/usr/bin/sudo"
    static let pmset = "/usr/bin/pmset"

    static func setDisableSleep(_ on: Bool) -> ShellResult {
        Shell.run(sudo, ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
    }

    static let sudoersRule = "/etc/sudoers.d/lidawake"

    /// `sudo -n -l` alone can pass without our rule when the user has some other NOPASSWD entry
    /// (sudo then lists without a password and the admin ALL rule matches), so require the file too.
    static func helperInstalled() -> Bool {
        FileManager.default.fileExists(atPath: sudoersRule)
            && Shell.run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "1"]).ok
    }

    /// `pmset -g` lists `SleepDisabled 1` only while the lid lock is on. Absent means 0.
    /// Returns nil when pmset itself fails.
    static func sleepDisabled() -> Bool? {
        let result = Shell.run(pmset, ["-g"])
        guard result.ok else { return nil }
        for line in result.output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return false
    }

    static func sleepNow() -> ShellResult {
        Shell.run(pmset, ["sleepnow"])
    }
}
