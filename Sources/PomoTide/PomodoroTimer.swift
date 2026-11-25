import AppKit
import Observation

enum Phase: Equatable {
    case idle, focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .idle: "Ready"
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// The Pomodoro cycle. Focus and breaks follow each other automatically until stopped.
///
/// The time arithmetic lives in `PhaseClock`. A 1 Hz UI timer only runs while a phase is active.
@MainActor
@Observable
final class PomodoroTimer {
    let settings: Settings
    let focus = FocusController()
    let music = MusicController(app: .appleMusic)
    let spotify = MusicController(app: .spotify)
    private var players: [MusicController] { [music, spotify] }
    /// The music app chosen for focus, if any.
    private var activePlayer: MusicController? {
        switch settings.tickSound.musicApp {
        case .appleMusic: music
        case .spotify: spotify
        case nil: nil
        }
    }
    private let hotKey = HotKey()
    /// False if another app already uses the shortcut.
    private(set) var hotKeyAvailable = true
    private let ticker = TickPlayer()
    private let breakSound = BreakSoundPlayer()
    private let transition = TransitionPlayer()

    private(set) var phase: Phase = .idle
    /// Completed focus sessions since the last long break (or since start).
    private(set) var completedFocus = 0
    /// Refreshed every second while running, so views showing the time update.
    private(set) var now = Date()

    private var phaseClock = PhaseClock()
    private var clock: Timer?
    private var fadeOutTimer: Timer?
    /// Ticking, music or the break sound fades out over the last seconds of a phase, before the gong.
    private static let fadeOutDuration: TimeInterval = 5
    private var terminationSignal: DispatchSourceSignal?

    init(settings: Settings) {
        self.settings = settings
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.players.forEach { $0.quit() }
                self?.focus.turnOffBlocking()
            }
        }
        // `kill`, `pkill` and logout send SIGTERM, which would end the app without the
        // cleanup above. Turn it into a normal quit instead.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
        updateHotKey()
        Task { await focus.refresh() }
    }

    private func updateHotKey() {
        if settings.globalShortcut {
            hotKeyAvailable = hotKey.register { [weak self] in self?.toggle() }
            if !hotKeyAvailable { Log.app.notice("\(HotKey.displayName, privacy: .public) is already used by another app") }
        } else {
            hotKey.unregister()
            hotKeyAvailable = true
        }
    }

    // MARK: State

    var isPaused: Bool { phase != .idle && phaseClock.isPaused }

    var remaining: TimeInterval {
        phase == .idle ? TimeInterval(settings.focusMinutes * 60) : phaseClock.remaining(at: now)
    }

    /// 0 at the start of a phase, 1 at its end.
    var progress: Double {
        phase == .idle ? 0 : phaseClock.progress(at: now)
    }

    var remainingText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var isRunning: Bool { phase != .idle && !isPaused }

    // MARK: Controls

    func toggle() {
        switch (phase, isPaused) {
        case (.idle, _): enter(.focus)
        case (_, false): pause()
        case (_, true): resume()
        }
    }

    func pause() {
        guard isRunning else { return }
        // `now` may be up to a second old; measure against the current time.
        now = Date()
        phaseClock.pause(at: now)
        Log.timer.info("Paused \(self.phase.title, privacy: .public) with \(Int(self.remaining)) s left")
        ticker.stop()
        breakSound.stop()
        players.forEach { $0.pause() }
        endFadeOut()
        stopClock()
    }

    func resume() {
        guard isPaused else { return }
        // `now` stood still during the pause; update it together with the end date,
        // or the first second after resuming shows the pause added to the remaining time.
        now = Date()
        phaseClock.resume(at: now)
        Log.timer.info("Resumed \(self.phase.title, privacy: .public)")
        startClock()
        applyEffects()
    }

    func skip() {
        guard phase != .idle else { return }
        Log.timer.info("Skipped \(self.phase.title, privacy: .public) with \(Int(self.remaining)) s left")
        advance(completed: false)
    }

    /// Moves the current phase to `progress` (0 = start, 1 = end), e.g. from dragging the ring.
    /// Works while running and while paused; the phase length itself stays the same.
    func seek(to progress: Double) {
        guard phase != .idle else { return }
        now = Date()
        phaseClock.seek(to: progress, at: now)
        if !isPaused { updateFadeOut() }
    }

    /// Logged once per drag; `seek` runs for every pointer movement.
    func seekEnded() {
        guard phase != .idle else { return }
        Log.timer.info("Moved \(self.phase.title, privacy: .public) to \(Int(self.remaining)) s left")
    }

    func stop() {
        Log.timer.info("Stopped")
        phase = .idle
        phaseClock = PhaseClock()
        completedFocus = 0
        stopClock()
        ticker.stop()
        breakSound.stop()
        players.forEach { $0.stop() }
        endFadeOut()
        focus.set(false)
    }

    /// Called when settings change, so a running phase picks up sound and Focus changes.
    func settingsChanged() {
        updateHotKey()
        ticker.volume = settings.tickVolume
        breakSound.volume = settings.breakSoundVolume
        guard isRunning else { return }
        applyEffects()
    }

    // MARK: Cycle

    private func enter(_ next: Phase) {
        let previous = phase
        phase = next
        let minutes = switch next {
        case .focus: settings.focusMinutes
        case .shortBreak: settings.breakMinutes
        case .longBreak: settings.longBreakMinutes
        case .idle: 0
        }
        now = Date()
        phaseClock = PhaseClock(duration: TimeInterval(max(1, minutes) * 60), start: now)
        Log.timer.info("Entered \(next.title, privacy: .public) for \(max(1, minutes)) min")
        startClock()
        // Transition sound at the start and the end of every break, not when the first focus starts.
        var tickFadeIn: TimeInterval = 0
        if previous != .idle, previous.isBreak != next.isBreak {
            transition.play(settings.transitionSound, volume: settings.transitionVolume)
            // Let the ticking swell in while the gong or bowl rings out (both last about 6 s).
            if next == .focus { tickFadeIn = 6 }
        }
        endFadeOut()
        applyEffects(tickFadeIn: tickFadeIn)
    }

    private func advance(completed: Bool) {
        guard phase != .idle else { return }
        let (next, done) = phase.next(completed: completed, completedFocus: completedFocus,
                                      longBreakEvery: settings.longBreakEnabled ? settings.longBreakEvery : nil)
        completedFocus = done
        enter(next)
    }

    private func applyEffects(tickFadeIn: TimeInterval = 0) {
        ticker.volume = settings.tickVolume
        breakSound.volume = settings.breakSoundVolume
        let focusing = phase == .focus && !isPaused
        if focusing, settings.tickSound.musicApp == nil {
            ticker.start(settings.tickSound, fadeIn: tickFadeIn)
        } else {
            ticker.stop()
        }
        let player = focusing ? activePlayer : nil
        for p in players where p !== player { p.pause() }
        if let player {
            let playlist = player.app == .spotify ? SpotifyLink.uri(from: settings.spotifyLink) ?? "" : settings.musicPlaylist
            player.play(playlist: playlist, shuffle: settings.musicShuffle,
                        openIfNeeded: settings.musicOpenIfNeeded, fadeIn: tickFadeIn)
        }
        if phase.isBreak, !isPaused {
            breakSound.start(settings.breakSound)
        } else {
            breakSound.stop()
        }
        let silence = (phase == .focus && settings.silenceDuringFocus) || (phase.isBreak && settings.silenceDuringBreak)
        focus.set(silence)
    }

    private func startClock() {
        stopClock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func tick() {
        now = Date()
        if phaseClock.isFinished(at: now) { advance(completed: true) }
        updateFadeOut()
    }

    // MARK: Fade-out

    private func updateFadeOut() {
        let left = phaseClock.remaining(at: Date())
        guard phase != .idle, !isPaused, left <= Self.fadeOutDuration else { return endFadeOut() }
        if fadeOutTimer == nil {
            // Finer steps than the 1 Hz clock, which matters for music.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFadeOut() }
            }
            RunLoop.main.add(timer, forMode: .common)
            fadeOutTimer = timer
        }
        let level = Float(max(0, left) / Self.fadeOutDuration)
        if phase.isBreak {
            breakSound.level = level
        } else {
            ticker.level = level
            activePlayer?.setFadeLevel(level)
        }
    }

    /// Stops a running fade-out. The music volume is restored by `pause()` or here.
    /// A break sound that faded out stays silent while it stops, so the gong rings alone.
    private func endFadeOut() {
        guard fadeOutTimer != nil else { return }
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        ticker.level = 1
        if phase.isBreak, !isPaused { breakSound.level = 1 }
        if phase == .focus, !isPaused { players.forEach { $0.endFade() } }
    }
}
