import AppKit
import Observation

/// A music app PomoTide can control through AppleScript.
enum MusicApp {
    case appleMusic, spotify

    var bundleID: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Name for AppleScript and messages.
    var name: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Seconds after launch before the app answers Apple Events reliably.
    var launchDelay: TimeInterval {
        switch self {
        case .appleMusic: 1.5
        case .spotify: 3
        }
    }
}

/// Plays Apple Music or Spotify during focus and pauses it during breaks, through AppleScript.
///
/// PomoTide only pauses playback it started itself: if music is already playing
/// when a focus session starts, it is left alone. After a break, the paused
/// track resumes where it stopped instead of restarting the playlist.
@MainActor
@Observable
final class MusicController {
    let app: MusicApp

    /// Apple Music playlists; Spotify does not expose its playlists to AppleScript.
    private(set) var playlists: [String] = []
    /// Last problem talking to the app, shown in settings.
    private(set) var problem: String?
    /// True when macOS refused PomoTide control over the app.
    private(set) var needsPermission = false

    /// True while the current playback was started (or resumed) by PomoTide.
    private var owned = false
    /// The app's own volume before a fade began; restored when the fade ends.
    /// Also kept in UserDefaults, so a fade cut short by quitting is undone on the next launch.
    private var baseVolume: Int? {
        didSet {
            if let baseVolume {
                UserDefaults.standard.set(baseVolume, forKey: pendingVolumeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: pendingVolumeKey)
            }
        }
    }
    private var pendingVolumeKey: String {
        app == .appleMusic ? "musicVolumeToRestore" : "spotifyVolumeToRestore"
    }
    private var lastSetVolume: Int?
    private var fadeInTimer: Timer?
    private var restoreTimer: Timer?

    init(app: MusicApp) {
        self.app = app
        restoreInterruptedFade()
    }

    /// Every AppleScript call is guarded by this: a script naming an app that is
    /// not installed would make macOS ask the user where the app is.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    /// Starts or resumes music for a focus phase.
    /// - Parameters:
    ///   - playlist: Apple Music playlist name or Spotify URI, or "" to continue whatever played last.
    ///   - fadeIn: seconds to swell in from silence; 0 starts at full volume.
    func play(playlist: String, shuffle: Bool, openIfNeeded: Bool, fadeIn: TimeInterval = 0) {
        if isRunning {
            playNow(playlist: playlist, shuffle: shuffle, fadeIn: fadeIn)
        } else if openIfNeeded {
            launch { [weak self] in self?.playNow(playlist: playlist, shuffle: shuffle, fadeIn: fadeIn) }
        }
    }

    /// Puts back the app's volume if PomoTide quit in the middle of a fade.
    private func restoreInterruptedFade() {
        guard baseVolume == nil, isRunning,
              UserDefaults.standard.object(forKey: pendingVolumeKey) != nil else { return }
        let volume = UserDefaults.standard.integer(forKey: pendingVolumeKey)
        Log.music.notice("\(self.app.name, privacy: .public): restoring volume \(volume) left over from an interrupted fade")
        setVolume(volume)
        if problem == nil { UserDefaults.standard.removeObject(forKey: pendingVolumeKey) }
    }

    /// Pauses music that PomoTide started; used for breaks and when the timer is paused.
    /// If a fade was in progress, the volume is restored once playback has really stopped.
    func pause() {
        if owned, isRunning, state == "playing" {
            Log.music.info("\(self.app.name, privacy: .public): pausing own playback")
            tell("pause")
            restoreVolumeWhenSilent()
        } else {
            endFade()
        }
    }

    /// Playback stops a moment after "pause" returns; restoring the volume right away
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
                // At least 0.5 s for the output buffer to drain, at most 3 s.
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

    /// Stops PomoTide's music before the app quits. Without this, music it started would
    /// keep playing, and the next launch would take it for the user's own and never pause it.
    func quit() {
        if owned, isRunning, state == "playing" {
            Log.music.info("\(self.app.name, privacy: .public): pausing own playback before quitting")
            tell("pause")
            // Let the output drain before the volume goes back up, as in `restoreVolumeWhenSilent`.
            if baseVolume != nil { Thread.sleep(forTimeInterval: 0.5) }
        }
        owned = false
        endFade()
    }

    /// Sets the app's volume to `level` (0...1) of its volume before the fade began.
    func setFadeLevel(_ level: Float) {
        guard owned, isRunning else { return }
        if baseVolume == nil {
            guard let v = tell("get sound volume").flatMap({ Int($0) }) else { return }
            Log.music.debug("\(self.app.name, privacy: .public): fade starts from volume \(v)")
            baseVolume = v
        }
        let target = Int((Float(baseVolume ?? 0) * max(0, min(1, level))).rounded())
        guard target != lastSetVolume else { return }
        tell("set sound volume to \(target)")
        lastSetVolume = target
    }

    /// Ends a fade and puts the app's volume back where it was.
    func endFade() {
        fadeInTimer?.invalidate()
        fadeInTimer = nil
        restoreTimer?.invalidate()
        restoreTimer = nil
        guard let v = baseVolume else { return }
        baseVolume = nil
        lastSetVolume = nil
        Log.music.debug("\(self.app.name, privacy: .public): fade ended, restoring volume \(v)")
        if isRunning { setVolume(v) }
    }

    func loadPlaylists() {
        guard app == .appleMusic else { return }
        guard isRunning else {
            launch { [weak self] in self?.loadPlaylists() }
            return
        }
        // Music rejects "whose special kind is none", so fetch all names in one call
        // and drop playlist folders, which are user playlists too but cannot be played.
        guard let names = tell("get name of every user playlist") else {
            playlists = []
            return
        }
        let folders = Set(tell("get name of every folder playlist", reportErrors: false)?.split(separator: "\n").map(String.init) ?? [])
        playlists = names.split(separator: "\n").map(String.init).filter { !folders.contains($0) }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private var state: String? {
        tell("get player state as string")
    }

    /// Spotify may set one less than asked, which would lower the volume a little
    /// with every restored fade; a second call corrects that.
    private func setVolume(_ v: Int) {
        tell("set sound volume to \(v)")
        if app == .spotify, let actual = tell("get sound volume").flatMap({ Int($0) }), actual < v {
            tell("set sound volume to \(v + (v - actual))")
        }
    }

    private func playNow(playlist: String, shuffle: Bool, fadeIn: TimeInterval) {
        restoreInterruptedFade()
        let current = state
        if current == "playing" {
            // Either the user's own music (leave it) or ours (already fine).
            if !owned { Log.music.info("\(self.app.name, privacy: .public): already playing music the user started, leaving it alone") }
            return
        }
        let resuming = owned && current == "paused"
        // Start silent, so the first moment does not cover the ringing gong.
        if fadeIn > 0 {
            owned = true
            setFadeLevel(0)
        }
        Log.music.info("\(self.app.name, privacy: .public): \(resuming ? "resuming" : playlist.isEmpty ? "continuing last played" : "starting playlist", privacy: .public), fade-in \(fadeIn, format: .fixed(precision: 0)) s")
        if resuming || playlist.isEmpty {
            tell("play")
        } else {
            switch app {
            case .appleMusic:
                tell("set shuffle enabled to \(shuffle)\nplay playlist \"\(Self.escape(playlist))\"")
            case .spotify:
                tell("set shuffling to \(shuffle)\nplay track \"\(Self.escape(playlist))\"")
            }
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            problem = "\(app.name) is not installed."
            Log.music.error("\(self.app.name, privacy: .public) is not installed")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        let delay = app.launchDelay
        Log.music.info("\(self.app.name, privacy: .public): launching")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                Log.music.error("Launching \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { action() }
            }
        }
    }

    /// Runs AppleScript commands inside a `tell` block for the app, on the main thread
    /// as NSAppleScript requires. Calls to a running app take milliseconds.
    @discardableResult
    private func tell(_ commands: String, reportErrors: Bool = true) -> String? {
        var error: NSDictionary?
        let source = "tell application \"\(app.name)\"\n\(commands)\nend tell"
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            guard reportErrors else { return nil }
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String
            Log.music.error("\(self.app.name, privacy: .public): AppleScript error \(code): \(message ?? "no message", privacy: .public), script: \(commands)")
            needsPermission = code == -1743
            problem = needsPermission
                ? "PomoTide is not allowed to control \(app.name)."
                : (message ?? "\(app.name) did not respond.")
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

/// Turns a link from Spotify's Share menu into a URI that AppleScript can play.
enum SpotifyLink {
    private static let kinds: Set<String> = ["playlist", "album", "artist", "track", "show", "episode"]

    /// Accepts `https://open.spotify.com/playlist/<id>?si=…` (also with an `intl-xx` path
    /// segment) and `spotify:playlist:<id>`. Returns nil for anything else.
    static func uri(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:") {
            let parts = s.split(separator: ":")
            return parts.count == 3 && kinds.contains(String(parts[1])) && isID(parts[2]) ? s : nil
        }
        guard let url = URL(string: s), url.host() == "open.spotify.com" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard path.count >= 2, kinds.contains(path[0]), isID(path[1]) else { return nil }
        return "spotify:\(path[0]):\(path[1])"
    }

    private static func isID(_ s: some StringProtocol) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
