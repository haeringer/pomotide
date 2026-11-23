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

    /// True while the current playback was started (or resumed) by PomoTide.
    private var owned = false

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Starts or resumes music for a focus phase.
    /// - Parameter playlist: playlist name, or "" to continue whatever Music played last.
    func play(playlist: String, shuffle: Bool, openIfNeeded: Bool) {
        if isRunning {
            playNow(playlist: playlist, shuffle: shuffle)
        } else if openIfNeeded {
            launch { [weak self] in self?.playNow(playlist: playlist, shuffle: shuffle) }
        }
    }

    /// Pauses music that PomoTide started; used for breaks and when the timer is paused.
    func pause() {
        guard owned, isRunning, state == "playing" else { return }
        run("tell application \"Music\" to pause")
    }

    /// Pauses PomoTide's music and forgets it, so the next session starts the playlist anew.
    func stop() {
        pause()
        owned = false
    }

    func loadPlaylists() {
        guard isRunning else {
            launch { [weak self] in self?.loadPlaylists() }
            return
        }
        let names = run("tell application \"Music\" to get name of every user playlist whose special kind is none")
        playlists = names.map { $0.split(separator: "\n").map(String.init) } ?? []
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

    private func playNow(playlist: String, shuffle: Bool) {
        let current = state
        if current == "playing" {
            // Either the user's own music (leave it) or ours (already fine).
            return
        }
        if owned, current == "paused" {
            run("tell application \"Music\" to play")
            return
        }
        if playlist.isEmpty {
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
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            problem = code == -1743
                ? "PomoTide is not allowed to control Music."
                : (error[NSAppleScript.errorMessage] as? String ?? "Music did not respond.")
            return nil
        }
        problem = nil
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
