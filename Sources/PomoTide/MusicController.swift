import AppKit
import Observation

/// Plays Apple Music during focus and pauses it during breaks, through AppleScript.
///
/// PomoTide only pauses playback it started itself: if music is already playing
/// when a focus session starts, it is left alone. After a break, the paused
/// track resumes where it stopped instead of restarting the playlist.
@MainActor
@Observable
final class MusicController {
    private static let bundleID = "com.apple.Music"

    private(set) var playlists: [String] = []
    /// Last problem talking to Music, shown in settings.
    private(set) var problem: String?
    /// True when macOS refused PomoTide control over Music.
    private(set) var needsPermission = false

    /// True while the current playback was started (or resumed) by PomoTide.
    private var owned = false
    /// Music's own volume before a fade began; restored when the fade ends.
    /// Also kept in UserDefaults, so a fade cut short by quitting is undone on the next launch.
    private var baseVolume: Int? {
        didSet {
            if let baseVolume {
                UserDefaults.standard.set(baseVolume, forKey: Self.pendingVolumeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingVolumeKey)
            }
        }
    }
    private static let pendingVolumeKey = "musicVolumeToRestore"
    private var lastSetVolume: Int?
    private var fadeInTimer: Timer?
    private var restoreTimer: Timer?

    init() {
        restoreInterruptedFade()
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Starts or resumes music for a focus phase.
    /// - Parameters:
    ///   - playlist: playlist name, or "" to continue whatever Music played last.
    ///   - fadeIn: seconds to swell in from silence; 0 starts at full volume.
    func play(playlist: String, shuffle: Bool, openIfNeeded: Bool, fadeIn: TimeInterval = 0) {
        if isRunning {
            playNow(playlist: playlist, shuffle: shuffle, fadeIn: fadeIn)
        } else if openIfNeeded {
            launch { [weak self] in self?.playNow(playlist: playlist, shuffle: shuffle, fadeIn: fadeIn) }
        }
    }

    /// Puts back Music's volume if PomoTide quit in the middle of a fade.
    private func restoreInterruptedFade() {
        guard baseVolume == nil, isRunning,
              UserDefaults.standard.object(forKey: Self.pendingVolumeKey) != nil else { return }
        let v = UserDefaults.standard.integer(forKey: Self.pendingVolumeKey)
        run("tell application \"Music\" to set sound volume to \(v)")
        if problem == nil { UserDefaults.standard.removeObject(forKey: Self.pendingVolumeKey) }
    }

    /// Pauses music that PomoTide started; used for breaks and when the timer is paused.
    /// If a fade was in progress, Music's volume is restored once playback has really stopped.
    func pause() {
        if owned, isRunning, state == "playing" {
            run("tell application \"Music\" to pause")
            restoreVolumeWhenSilent()
        } else {
            endFade()
        }
    }

    /// Music stops a moment after "pause" returns; restoring the volume right away
    /// would let the last fraction of a second play at full volume.
    private func restoreVolumeWhenSilent() {
        fadeInTimer?.invalidate()
        fadeInTimer = nil
        guard baseVolume != nil else { return }
        restoreTimer?.invalidate()
        let start = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                // At least 0.5 s for Music's output buffer to drain, at most 3 s.
                guard elapsed >= 0.5, self.state != "playing" || elapsed >= 3 else { return }
                self.endFade()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        restoreTimer = timer
    }

    /// Pauses PomoTide's music and forgets it, so the next session starts the playlist anew.
    func stop() {
        pause()
        owned = false
    }

    /// Sets Music's volume to `level` (0...1) of its volume before the fade began.
    func setFadeLevel(_ level: Float) {
        guard owned, isRunning else { return }
        if baseVolume == nil {
            guard let v = run("tell application \"Music\" to get sound volume").flatMap({ Int($0) }) else { return }
            baseVolume = v
        }
        let target = Int((Float(baseVolume ?? 0) * max(0, min(1, level))).rounded())
        guard target != lastSetVolume else { return }
        run("tell application \"Music\" to set sound volume to \(target)")
        lastSetVolume = target
    }

    /// Ends a fade and puts Music's volume back where it was.
    func endFade() {
        fadeInTimer?.invalidate()
        fadeInTimer = nil
        restoreTimer?.invalidate()
        restoreTimer = nil
        guard let v = baseVolume else { return }
        baseVolume = nil
        lastSetVolume = nil
        if isRunning { run("tell application \"Music\" to set sound volume to \(v)") }
    }

    func loadPlaylists() {
        guard isRunning else {
            launch { [weak self] in self?.loadPlaylists() }
            return
        }
        // Music rejects "whose special kind is none", so fetch all names in one call
        // and drop playlist folders, which are user playlists too but cannot be played.
        guard let names = run("tell application \"Music\" to get name of every user playlist") else {
            playlists = []
            return
        }
        let folders = Set(run("tell application \"Music\" to get name of every folder playlist", reportErrors: false)?.split(separator: "\n").map(String.init) ?? [])
        playlists = names.split(separator: "\n").map(String.init).filter { !folders.contains($0) }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private var state: String? {
        run("tell application \"Music\" to get player state as string")
    }

    private func playNow(playlist: String, shuffle: Bool, fadeIn: TimeInterval) {
        restoreInterruptedFade()
        let current = state
        if current == "playing" {
            // Either the user's own music (leave it) or ours (already fine).
            return
        }
        let resuming = owned && current == "paused"
        // Start silent, so the first moment does not cover the ringing gong.
        if fadeIn > 0 {
            owned = true
            setFadeLevel(0)
        }
        if resuming || playlist.isEmpty {
            run("tell application \"Music\" to play")
        } else {
            run("""
                tell application "Music"
                    set shuffle enabled to \(shuffle)
                    play playlist "\(Self.escape(playlist))"
                end tell
                """)
        }
        owned = problem == nil
        guard owned else { return endFade() }
        if fadeIn > 0 { startFadeIn(over: fadeIn) }
    }

    private func startFadeIn(over seconds: TimeInterval) {
        let start = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = min(1, Float(Date().timeIntervalSince(start) / seconds))
                self.setFadeLevel(p * p)  // same curve as the ticking
                if p >= 1 { self.endFade() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeInTimer = timer
    }

    private func launch(then action: @escaping @MainActor () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            guard error == nil else { return }
            // Music needs a moment after launch before it answers Apple Events reliably.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated { action() }
            }
        }
    }

    /// Runs AppleScript on the main thread, as NSAppleScript requires. Calls to a running Music take milliseconds.
    @discardableResult
    private func run(_ source: String, reportErrors: Bool = true) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            guard reportErrors else { return nil }
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            needsPermission = code == -1743
            problem = needsPermission
                ? "PomoTide is not allowed to control Music."
                : (error[NSAppleScript.errorMessage] as? String ?? "Music did not respond.")
            return nil
        }
        if reportErrors {
            problem = nil
            needsPermission = false
        }
        guard let result else { return nil }
        if result.descriptorType == typeAEList {
            guard result.numberOfItems > 0 else { return "" }
            return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.joined(separator: "\n")
        }
        return result.stringValue
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
