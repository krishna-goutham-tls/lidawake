import Foundation

enum SetupOutcome {
    case done
    case cancelled
    case failed(String)
}

@MainActor
enum HelperSetup {
    private static let usernamePattern = "^[a-z_][a-z0-9_.-]*$"

    private static func validUsername() -> String? {
        let user = NSUserName()
        return user.range(of: usernamePattern, options: .regularExpression) != nil ? user : nil
    }

    static func install() -> SetupOutcome {
        guard let user = validUsername() else {
            Log.write("error: username \(NSUserName()) failed validation; setup not run")
            return .failed("Username \"\(NSUserName())\" has characters setup does not accept.")
        }
        switch runAsAdmin(script: "install-helper.sh", argument: user) {
        case .done: break
        case let other: return other
        }
        let watchdog = runAsUser(script: "install-watchdog.sh")
        guard watchdog.ok else {
            return .failed("Closed-lid permission was added, but the watchdog did not install (\(watchdog.summary)).")
        }
        return .done
    }

    static func remove() -> SetupOutcome {
        // The username is optional for this script; without it, it cannot write to the user's log.
        switch runAsAdmin(script: "uninstall-helper.sh", argument: validUsername()) {
        case .done: break
        case let other: return other
        }
        let watchdog = runAsUser(script: "uninstall-watchdog.sh")
        guard watchdog.ok else {
            return .failed("Closed-lid permission was removed, but the watchdog did not uninstall (\(watchdog.summary)).")
        }
        return .done
    }

    private static func resourcePath(_ name: String) -> String? {
        guard let path = Bundle.main.resourceURL?.appendingPathComponent(name).path,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    /// AppleScript string literal. Rejects control characters so nothing can break out of the literal.
    private static func appleScriptLiteral(_ value: String) -> String? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func runAsAdmin(script name: String, argument: String?) -> SetupOutcome {
        guard let path = resourcePath(name) else {
            Log.write("error: \(name) is missing from the app bundle")
            return .failed("\(name) is missing from the app bundle.")
        }
        guard let pathLiteral = appleScriptLiteral(path) else {
            return .failed("The app's location contains characters setup cannot handle.")
        }
        // `quoted form of` does the shell quoting, so neither value is interpolated into a shell string raw.
        var command = "\"/bin/sh \" & (quoted form of \(pathLiteral))"
        if let argument {
            guard let argLiteral = appleScriptLiteral(argument) else {
                return .failed("Invalid argument for \(name).")
            }
            command += " & \" \" & (quoted form of \(argLiteral))"
        }
        let source = "do shell script \(command) with administrator privileges"

        Log.write("running \(name) with administrator privileges")
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not prepare the admin prompt.")
        }
        _ = script.executeAndReturnError(&errorInfo)
        if errorInfo == nil {
            Log.write("\(name) finished")
            return .done
        }
        let code = errorInfo?[NSAppleScript.errorNumber] as? Int ?? 0
        let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown error"
        if code == -128 {
            Log.write("\(name) cancelled at the password prompt; nothing changed")
            return .cancelled
        }
        Log.write("error: \(name) failed (\(code)): \(message)")
        return .failed(message)
    }

    private static func runAsUser(script name: String) -> ShellResult {
        guard let path = resourcePath(name) else {
            Log.write("error: \(name) is missing from the app bundle")
            return ShellResult(status: -1, output: "\(name) is missing from the app bundle")
        }
        let result = Shell.run("/bin/sh", [path])
        Log.write("\(name) \(result.ok ? "finished" : "failed") (\(result.summary))")
        return result
    }
}
