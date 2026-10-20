import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts via Carbon hot keys (no Accessibility permission needed).
/// Registered only while a request is on screen so ⌘Y/⌘N aren't stolen otherwise.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private let signature: OSType = 0x4E_49_53_4C  // 'NISL'

    func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[id] = action
        guard refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        if RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
            let ref
        {
            refs[id] = ref
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, nil)
    }
}

private func hotKeyCallback(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &id)
    let hotKey = id.id
    DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.fire(hotKey) } }
    return noErr
}

enum HotKeyID {
    static let allow: UInt32 = 1
    static let deny: UInt32 = 2
    /// ⌘1…⌘9 pick question options; ids 11…19.
    static func option(_ index: Int) -> UInt32 { UInt32(11 + index) }
}

enum KeyCodes {
    static let y = kVK_ANSI_Y
    static let n = kVK_ANSI_N
    static let command = cmdKey
    static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
}
