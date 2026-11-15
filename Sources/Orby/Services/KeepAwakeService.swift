import Foundation
import IOKit.pwr_mgt
import NotchCore

/// Holds a PreventUserIdleSystemSleep assertion while `KeepAwakePolicy` says so. The display may
/// still sleep; the Mac doesn't, so long agent runs aren't cut off by idle sleep.
@MainActor
final class KeepAwakeService {
    private var policy = KeepAwakePolicy()
    private var assertion: IOPMAssertionID = 0

    func update(mode: KeepAwakePolicy.Mode, anyWorking: Bool) {
        perform(policy.update(mode: mode, anyWorking: anyWorking))
    }

    func stop() { perform(policy.stop()) }

    private func perform(_ action: KeepAwakePolicy.Action?) {
        switch action {
        case .take:
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Orby: an AI coding agent is working" as CFString, &assertion)
            if result != kIOReturnSuccess { NSLog("Orby: keep-awake assertion failed: \(result)") }
        case .release:
            if assertion != 0 { IOPMAssertionRelease(assertion) }
            assertion = 0
        case nil:
            break
        }
    }
}
