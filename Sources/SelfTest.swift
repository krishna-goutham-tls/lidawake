import Foundation

/// `LidAwake --selftest`: prints what the app sees on this Mac and exits. Changes nothing.
enum SelfTest {
    static func run() -> Int32 {
        let power = PowerInfo.snapshot()
        let thermal = ProcessInfo.processInfo.thermalState
        let sleepDisabled: String
        switch Pmset.sleepDisabled() {
        case .some(true): sleepDisabled = "1"
        case .some(false): sleepDisabled = "0"
        case .none: sleepDisabled = "unknown"
        }

        print("LidAwake \(Paths.version) selftest")
        print("battery: \(power.batteryPercent.map { "\($0)%" } ?? "none")")
        print("power: \(power.onBattery ? "battery" : "ac")")
        print("thermal: \(PowerInfo.thermalName(thermal))")
        if let forced = PowerInfo.thermalOverride() {
            print("thermal override: \(PowerInfo.thermalName(forced))")
        }
        print("lid: \(PowerInfo.lidName(PowerInfo.lidClosed()))")
        print("helper installed: \(Pmset.helperInstalled() ? "yes" : "no")")
        print("SleepDisabled: \(sleepDisabled)")
        print("marker: \(Paths.markerExists ? "present" : "absent") (\(Paths.marker.path))")
        print("log: \(Paths.logFile.path)")
        return 0
    }
}
