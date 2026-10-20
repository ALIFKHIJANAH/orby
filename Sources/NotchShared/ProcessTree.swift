import Darwin
import Foundation

public enum ProcessTree {
    public struct Info {
        public var pid: pid_t
        public var ppid: pid_t
        public var name: String
        public var tty: String?
    }

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "login"]

    public static func info(pid: pid_t) -> Info? {
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }

        let name = withUnsafePointer(to: kp.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
        var tty: String?
        let dev = kp.kp_eproc.e_tdev
        if dev != -1, let cName = devname(dev, S_IFCHR) {
            tty = "/dev/" + String(cString: cName)
        }
        return Info(pid: pid, ppid: kp.kp_eproc.e_ppid, name: name, tty: tty)
    }

    public static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Ancestors starting at `pid` (inclusive), nearest first, stopping before launchd.
    public static func chain(from pid: pid_t, maxDepth: Int = 32) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        var current = pid
        while current > 1, result.count < maxDepth, let info = info(pid: current) {
            result.append(ProcessEntry(pid: current, name: info.name, path: executablePath(pid: current)))
            if info.ppid == current { break }
            current = info.ppid
        }
        return result
    }

    /// The agent is the first ancestor that isn't a shell wrapper (`/bin/sh -c ...`).
    public static func agentProcess(in chain: [ProcessEntry]) -> ProcessEntry? {
        chain.first { entry in
            let base = (entry.path as NSString?)?.lastPathComponent ?? entry.name
            return !shells.contains(entry.name) && !shells.contains(base)
        }
    }

    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Outermost `.app` bundle in an executable path, e.g. the IDE rather than its helper app.
    public static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) else {
            return nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
