import Foundation

/// An output device as CoreAudio describes it, reduced to what decides "headphones connected".
public struct AudioDeviceInfo: Equatable, Sendable {
    public enum Transport: Sendable { case bluetooth, bluetoothLE, usb, builtIn, other }

    public let uid: String
    public let name: String
    public let transport: Transport
    public let hasOutput: Bool

    public init(uid: String, name: String, transport: Transport, hasOutput: Bool) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.hasOutput = hasOutput
    }

    public var isBluetooth: Bool { transport == .bluetooth || transport == .bluetoothLE }

    /// Bluetooth devices carry their address in the UID ("08-E4-DF-D2-8D-2D:output").
    public var bluetoothAddress: String? {
        let head = uid.prefix(17)
        guard head.count == 17, head.filter({ $0 == "-" || $0 == ":" }).count == 5 else { return nil }
        return BluetoothReport.normalize(String(head))
    }

    /// Bluetooth and USB outputs count whenever they show up. A built-in output only counts when
    /// it appears while running: that's the "External Headphones" device Apple Silicon adds when
    /// something is plugged into the jack (the speakers are there from the start).
    public func isHeadphone(appearedAfterLaunch: Bool) -> Bool {
        guard hasOutput else { return false }
        switch transport {
        case .bluetooth, .bluetoothLE, .usb: return true
        case .builtIn: return appearedAfterLaunch
        case .other: return false
        }
    }
}

/// Battery levels in percent, as far as the device reports them.
public struct HeadphoneBattery: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var main: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, main: Int? = nil) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.main = main
    }

    /// The one number to show: the emptier bud, or the headset's single level.
    public var summary: Int? { [left, right].compactMap { $0 }.min() ?? main }
}

/// Reads battery levels out of `system_profiler SPBluetoothDataType -json`.
public enum BluetoothReport {
    public static func battery(json: Data, address: String?, name: String) -> HeadphoneBattery? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }
        let wanted = address.map(normalize)
        var byName: [String: Any]?
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (deviceName, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    if let wanted, let a = props["device_address"] as? String, normalize(a) == wanted {
                        return levels(props)
                    }
                    if deviceName == name { byName = props }
                }
            }
        }
        return byName.flatMap(levels)
    }

    static func normalize(_ address: String) -> String {
        address.replacingOccurrences(of: "-", with: ":").uppercased()
    }

    private static func levels(_ props: [String: Any]) -> HeadphoneBattery? {
        func percent(_ key: String) -> Int? {
            (props[key] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        }
        let b = HeadphoneBattery(
            left: percent("device_batteryLevelLeft"), right: percent("device_batteryLevelRight"),
            caseLevel: percent("device_batteryLevelCase"), main: percent("device_batteryLevelMain"))
        return b == HeadphoneBattery() ? nil : b
    }
}

/// Reads accessory batteries out of `pmset -g accps`. Headsets that report their level over the
/// hands-free profile show up here even when the Bluetooth report has no battery for them:
///   -KiiP TH60 (id=1222644877)	70%; discharging present: true
public enum PowerSourceReport {
    public static func battery(pmset output: String, name: String) -> HeadphoneBattery? {
        for line in output.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.hasPrefix("-"), let idRange = trimmed.range(of: " (id=") else { continue }
            guard trimmed[trimmed.index(after: trimmed.startIndex)..<idRange.lowerBound] == name[...] else { continue }
            let rest = trimmed[idRange.upperBound...]
            guard let tab = rest.firstIndex(of: "\t"), let pct = rest[tab...].firstIndex(of: "%"),
                let level = Int(rest[rest.index(after: tab)..<pct].trimmingCharacters(in: .whitespaces))
            else { continue }
            return HeadphoneBattery(main: level)
        }
        return nil
    }
}
