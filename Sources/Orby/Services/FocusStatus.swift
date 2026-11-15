import Foundation
import Intents

/// Reads whether a macOS Focus is on. Never asks for permission by itself: until the user grants
/// it from Settings, the Focus state is unknown (nil) and quiet rules ignore it.
@MainActor
enum FocusStatus {
    static var authorization: INFocusStatusAuthorizationStatus { INFocusStatusCenter.default.authorizationStatus }

    static var isFocused: Bool? {
        guard authorization == .authorized else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    /// The system refuses (or crashes) without a usage string, e.g. when run with `swift run`.
    static var canAsk: Bool { Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") != nil }

    static func requestAccess(_ done: @escaping @MainActor (INFocusStatusAuthorizationStatus) -> Void) {
        guard canAsk, authorization == .notDetermined else { return done(authorization) }
        INFocusStatusCenter.default.requestAuthorization { status in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(status) } }
        }
    }
}
