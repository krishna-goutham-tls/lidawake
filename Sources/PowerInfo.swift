import Foundation
import IOKit
import IOKit.ps

struct PowerSnapshot {
    let batteryPercent: Int?
    let onBattery: Bool
}

enum PowerInfo {
    static func snapshot() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(batteryPercent: nil, onBattery: false)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = providing == kIOPSBatteryPowerValue

        var percent: Int?
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
                if let type = desc[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType { continue }
                if let current = desc[kIOPSCurrentCapacityKey] as? Int,
                   let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    percent = Int((Double(current) / Double(max) * 100).rounded())
                    break
                }
            }
        }
        return PowerSnapshot(batteryPercent: percent, onBattery: onBattery)
    }

    /// nil on Macs without a lid or when the property is missing.
    static func lidClosed() -> Bool? {
        rootDomainFlag("AppleClamshellState")
    }

    /// Whether closing the lid sleeps the Mac under the normal rules. False in clamshell mode with
    /// an external display.
    static func clamshellCausesSleep() -> Bool? {
        rootDomainFlag("AppleClamshellCausesSleep")
    }

    private static func rootDomainFlag(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? Bool
    }

    static func lidName(_ closed: Bool?) -> String {
        switch closed {
        case .some(true): return "closed"
        case .some(false): return "open"
        case .none: return "unknown"
        }
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Test hook: `defaults write space.thelaunch.lidawake debugForceThermal -string serious`.
    static func thermalOverride() -> ProcessInfo.ThermalState? {
        switch UserDefaults.standard.string(forKey: "debugForceThermal")?.lowercased() {
        case "nominal": return .nominal
        case "fair": return .fair
        case "serious": return .serious
        case "critical": return .critical
        default: return nil
        }
    }

    static func effectiveThermal() -> (state: ProcessInfo.ThermalState, forced: Bool) {
        if let forced = thermalOverride() { return (forced, true) }
        return (ProcessInfo.processInfo.thermalState, false)
    }
}
