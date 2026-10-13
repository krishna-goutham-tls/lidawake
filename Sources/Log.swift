import Foundation

enum Log {
    static func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let flat = message.replacingOccurrences(of: "\n", with: " | ")
        let line = "\(formatter.string(from: Date())) [app] \(flat)\n"

        ensureFile()
        guard let handle = try? FileHandle(forWritingTo: Paths.logFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    static func ensureFile() {
        let fm = FileManager.default
        let url = Paths.logFile
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
    }
}
