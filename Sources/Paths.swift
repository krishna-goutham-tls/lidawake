import Foundation

enum Paths {
    static let bundleID = "space.thelaunch.lidawake"
    /// From Info.plist, which build.sh writes. "dev" when run outside the app bundle.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var supportDir: URL {
        home.appendingPathComponent("Library/Application Support/LidAwake", isDirectory: true)
    }
    static var marker: URL { supportDir.appendingPathComponent("lid-session-active") }
    static var logFile: URL { home.appendingPathComponent("Library/Logs/LidAwake.log") }

    static var markerExists: Bool { FileManager.default.fileExists(atPath: marker.path) }
}
