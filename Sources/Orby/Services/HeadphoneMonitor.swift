import CoreAudio
import Foundation
import NotchCore

struct HeadphoneEvent: Equatable {
    /// CoreAudio device UID.
    let id: String
    let name: String
    var battery: HeadphoneBattery?
}

/// Reports headphones as they connect: Bluetooth, USB or the headphone jack. Uses CoreAudio's
/// device list, so it needs no Bluetooth permission. Devices already there at launch stay quiet.
@MainActor
final class HeadphoneMonitor {
    private let onConnect: (HeadphoneEvent) -> Void
    private let onBattery: (String, HeadphoneBattery) -> Void
    private var known: Set<String> = []
    private var jackWatched: Set<AudioObjectID> = []
    private var lastShown: [String: Date] = [:]
    private var started = false

    init(onConnect: @escaping (HeadphoneEvent) -> Void, onBattery: @escaping (String, HeadphoneBattery) -> Void) {
        self.onConnect = onConnect
        self.onBattery = onBattery
    }

    func start() {
        guard !started else { return }
        started = true
        let devices = Self.devices()
        known = Set(devices.map(\.info.uid))
        for d in devices { watchJack(d) }
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            MainActor.assumeIsolated { [weak self] in self?.devicesChanged() }
        }
    }

    private func devicesChanged() {
        let devices = Self.devices()
        for d in devices where !known.contains(d.info.uid) {
            watchJack(d)
            if d.info.isHeadphone(appearedAfterLaunch: true) { connected(d.info) }
        }
        known = Set(devices.map(\.info.uid))
        jackWatched.formIntersection(devices.map(\.id))
    }

    /// Intel Macs keep one built-in output and switch its data source to headphones on plug-in.
    private func watchJack(_ d: (id: AudioObjectID, info: AudioDeviceInfo)) {
        guard d.info.transport == .builtIn, d.info.hasOutput, !jackWatched.contains(d.id) else { return }
        var address = Self.address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(d.id, &address) else { return }
        jackWatched.insert(d.id)
        let id = d.id
        AudioObjectAddPropertyListenerBlock(id, &address, .main) { _, _ in
            MainActor.assumeIsolated { [weak self] in
                guard Self.uint32(id, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput) == 0x6864_706E  // 'hdpn'
                else { return }
                self?.connected(AudioDeviceInfo(uid: "jack-\(id)", name: "Headphones", transport: .builtIn, hasOutput: true))
            }
        }
    }

    private func connected(_ info: AudioDeviceInfo) {
        // One device can come and go a couple of times while it settles (profile switches).
        if let last = lastShown[info.name], Date().timeIntervalSince(last) < 5 { return }
        lastShown[info.name] = Date()
        onConnect(HeadphoneEvent(id: info.uid, name: info.name))
        if info.isBluetooth { fetchBattery(info) }
    }

    /// Levels usually arrive a second or two after the device connects (AirPods, hands-free
    /// battery reports), so look a few times. The Bluetooth report has AirPods' per-bud levels;
    /// other headsets often only show up in the power-source list.
    private func fetchBattery(_ info: AudioDeviceInfo) {
        let (id, address, name) = (info.uid, info.bluetoothAddress, info.name)
        Task.detached(priority: .utility) {
            for delay in [0.3, 1.0, 1.5] {
                try? await Task.sleep(for: .seconds(delay))
                let battery = Self.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
                    .flatMap { BluetoothReport.battery(json: $0, address: address, name: name) }
                    ?? Self.run("/usr/bin/pmset", ["-g", "accps"])
                    .flatMap { PowerSourceReport.battery(pmset: String(decoding: $0, as: UTF8.self), name: name) }
                if let battery {
                    await MainActor.run { [weak self] in self?.onBattery(id, battery) }
                    return
                }
            }
        }
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timeout.cancel()
        return p.terminationStatus == 0 ? data : nil
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func devices() -> [(id: AudioObjectID, info: AudioDeviceInfo)] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var list = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &list, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id -> (id: AudioObjectID, info: AudioDeviceInfo)? in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            let hasOutput = AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr && streamsSize > 0
            let info = AudioDeviceInfo(
                uid: uid, name: string(id, kAudioObjectPropertyName) ?? "Headphones",
                transport: transport(uint32(id, kAudioDevicePropertyTransportType)), hasOutput: hasOutput)
            return (id, info)
        }
    }

    private static func transport(_ raw: UInt32?) -> AudioDeviceInfo.Transport {
        switch raw {
        case kAudioDeviceTransportTypeBluetooth: .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        default: .other
        }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
