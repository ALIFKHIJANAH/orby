import AVFoundation
import AppKit
import NotchCore

/// 8-bit square-wave cues synthesized at launch, plus macOS and custom-folder themes.
@MainActor
final class SoundPlayer {
    private var chiptune: [SoundCue: Data] = [:]
    // One cue at a time: a new cue stops the previous one instead of layering on top of it.
    private var player: AVAudioPlayer?
    private var systemSound: NSSound?
    private var last: (cue: SoundCue, at: Date)?
    /// Events often arrive in bursts (several hooks for one turn); within this window only a more urgent cue gets through.
    private static let burstWindow: TimeInterval = 0.8
    private var screenLocked = false
    private var lockObservers: [NSObjectProtocol] = []

    init() {
        for cue in SoundCue.allCases { chiptune[cue] = Self.wav(notes: Self.melody(cue)) }
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenLocked = locked }
            })
        }
    }

    /// Nobody is there to hear it (screen locked), or the user asked for quiet at this hour.
    private var muted: Bool {
        if screenLocked && Prefs.bool(PrefKey.muteWhenLocked) { return true }
        guard Prefs.bool(PrefKey.quietHoursEnabled) else { return false }
        return QuietHours.contains(
            Date(), start: Prefs.defaults.integer(forKey: PrefKey.quietHoursStart), end: Prefs.defaults.integer(forKey: PrefKey.quietHoursEnd))
    }

    func play(_ cue: SoundCue, preview: Bool = false) {
        guard preview || Prefs.bool(PrefKey.soundEnabled(cue)) else { return }
        if (Prefs.soundTheme == .off || muted) && !preview { return }
        if !preview, let last, Date().timeIntervalSince(last.at) < Self.burstWindow,
           Self.priority(cue) <= Self.priority(last.cue) { return }
        stop()
        last = (cue, Date())
        let volume = Float(Prefs.double(PrefKey.soundVolume))
        switch Prefs.soundTheme {
        case .system:
            // NSSound(named:) is one shared instance per name; it refuses to play while already playing.
            guard let sound = NSSound(named: Self.systemSoundName(cue))?.copy() as? NSSound else { return }
            sound.volume = volume
            if !sound.play() { NSLog("Orby: system sound \(cue.rawValue) failed to play") }
            systemSound = sound
        case .custom:
            if let url = customFile(cue), let player = makePlayer(cue, { try AVAudioPlayer(contentsOf: url) }) {
                start(player, volume: volume)
            } else if let data = chiptune[cue], let player = makePlayer(cue, { try AVAudioPlayer(data: data) }) {
                start(player, volume: volume)
            }
        default:
            if let data = chiptune[cue], let player = makePlayer(cue, { try AVAudioPlayer(data: data) }) {
                start(player, volume: volume)
            }
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        systemSound?.stop()
        systemSound = nil
    }

    private func makePlayer(_ cue: SoundCue, _ make: () throws -> AVAudioPlayer) -> AVAudioPlayer? {
        do { return try make() } catch {
            NSLog("Orby: sound \(cue.rawValue) failed to load: \(error)")
            return nil
        }
    }

    private func start(_ player: AVAudioPlayer, volume: Float) {
        player.volume = volume
        player.prepareToPlay()
        self.player = player
        if !player.play() {
            // The output device can refuse a cold start (e.g. waking Bluetooth); try once more,
            // unless a newer cue has taken over in the meantime.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard self?.player === player else { return }
                if !player.play() { NSLog("Orby: sound failed to play") }
            }
        }
    }

    /// A custom pack is a folder with files named after cues: done.wav, approval.mp3, ...
    private func customFile(_ cue: SoundCue) -> URL? {
        guard let folder = Prefs.defaults.string(forKey: PrefKey.customSoundFolder) else { return nil }
        let base = URL(fileURLWithPath: folder)
        for ext in ["wav", "aiff", "aif", "mp3", "m4a", "caf"] {
            let url = base.appendingPathComponent("\(cue.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Cues that need the user's attention beat status chimes when they collide.
    private static func priority(_ cue: SoundCue) -> Int {
        switch cue {
        case .approval, .question, .plan, .error: 2
        case .done, .context: 1
        case .start: 0
        }
    }

    private static func systemSoundName(_ cue: SoundCue) -> String {
        switch cue {
        case .approval: "Ping"
        case .question: "Pop"
        case .plan: "Hero"
        case .done: "Glass"
        case .error: "Basso"
        case .start: "Tink"
        case .context: "Submarine"
        }
    }

    /// (frequency Hz, seconds); 0 Hz is a rest.
    private static func melody(_ cue: SoundCue) -> [(Double, Double)] {
        switch cue {
        case .approval: [(880, 0.07), (1175, 0.09), (0, 0.06), (880, 0.07), (1175, 0.12)]
        case .question: [(784, 0.08), (988, 0.08), (1319, 0.14)]
        case .plan: [(659, 0.09), (880, 0.09), (1109, 0.16)]
        case .done: [(523, 0.07), (659, 0.07), (784, 0.07), (1047, 0.18)]
        case .error: [(440, 0.11), (349, 0.11), (262, 0.22)]
        case .start: [(1047, 0.05), (1568, 0.08)]
        case .context: [(988, 0.08), (0, 0.05), (988, 0.08), (784, 0.16)]
        }
    }

    /// 16-bit mono PCM WAV of square-wave notes with a short decay envelope.
    /// The lead-in silence absorbs output-device wake-up, which would otherwise clip these short cues.
    static func wav(notes: [(Double, Double)], sampleRate: Int = 22050, leadIn: Double = 0.12) -> Data {
        var samples = [Int16](repeating: 0, count: Int(leadIn * Double(sampleRate)))
        for (freq, duration) in notes {
            let count = Int(duration * Double(sampleRate))
            for i in 0..<count {
                guard freq > 0 else { samples.append(0); continue }
                let t = Double(i) / Double(sampleRate)
                let phase = (t * freq).truncatingRemainder(dividingBy: 1)
                let square: Double = phase < 0.5 ? 1 : -1
                let attack = min(1, Double(i) / (0.004 * Double(sampleRate)))
                let decay = 1 - Double(i) / Double(count)
                samples.append(Int16(square * attack * (0.25 + 0.75 * decay) * 0.35 * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for s in samples { append(s) }
        return data
    }
}
