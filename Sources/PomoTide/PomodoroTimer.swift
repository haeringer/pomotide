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
/// Time is tracked as an end date rather than a counter, so sleep or a busy main
/// thread cannot make the timer drift. A 1 Hz UI timer only runs while a phase is active.
@MainActor
@Observable
final class PomodoroTimer {
    let settings: Settings
    let focus = FocusController()
    let music = MusicController()
    private let hotKey = HotKey()
    /// False if another app already uses the shortcut.
    private(set) var hotKeyAvailable = true
    private let ticker = TickPlayer()
    private let breakSound = BreakSoundPlayer()
    private let transition = TransitionPlayer()

    private(set) var phase: Phase = .idle
    private(set) var isPaused = false
    /// Completed focus sessions since the last long break (or since start).
    private(set) var completedFocus = 0
    private(set) var now = Date()

    private var phaseEnd = Date()
    private var phaseDuration: TimeInterval = 1
    private var pausedRemaining: TimeInterval = 0
    private var clock: Timer?
    private var fadeOutTimer: Timer?
    /// Ticking or music fades out over the last seconds of a focus phase, before the gong.
    private static let fadeOutDuration: TimeInterval = 5
    private var terminationSignal: DispatchSourceSignal?

    init(settings: Settings) {
        self.settings = settings
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.music.endFade()
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
        } else {
            hotKey.unregister()
            hotKeyAvailable = true
        }
    }

    // MARK: State

    var remaining: TimeInterval {
        switch phase {
        case .idle: TimeInterval(settings.focusMinutes * 60)
        default: isPaused ? pausedRemaining : max(0, phaseEnd.timeIntervalSince(now))
        }
    }

    /// 0 at the start of a phase, 1 at its end.
    var progress: Double {
        phase == .idle ? 0 : 1 - remaining / phaseDuration
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
        // Measure against the current time, not `now`, which may be up to a second old.
        pausedRemaining = max(0, phaseEnd.timeIntervalSinceNow)
        isPaused = true
        ticker.stop()
        breakSound.stop()
        music.pause()
        endFadeOut()
        stopClock()
    }

    func resume() {
        guard phase != .idle, isPaused else { return }
        // `now` stood still during the pause; update it together with the end date,
        // or the first second after resuming shows the pause added to the remaining time.
        now = Date()
        phaseEnd = now.addingTimeInterval(pausedRemaining)
        isPaused = false
        startClock()
        applyEffects()
    }

    func skip() {
        guard phase != .idle else { return }
        advance(completed: false)
    }

    /// Moves the current phase to `progress` (0 = start, 1 = end), e.g. from dragging the ring.
    /// Works while running and while paused; the phase length itself stays the same.
    func seek(to progress: Double) {
        guard phase != .idle else { return }
        // Keep at least a second, so dragging to the very end does not switch phases mid-drag.
        let left = max(1, phaseDuration * (1 - min(1, max(0, progress))))
        now = Date()
        if isPaused {
            pausedRemaining = left
        } else {
            phaseEnd = now.addingTimeInterval(left)
            updateFadeOut()
        }
    }

    func stop() {
        phase = .idle
        isPaused = false
        completedFocus = 0
        stopClock()
        ticker.stop()
        breakSound.stop()
        music.stop()
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
        isPaused = false
        let minutes = switch next {
        case .focus: settings.focusMinutes
        case .shortBreak: settings.breakMinutes
        case .longBreak: settings.longBreakMinutes
        case .idle: 0
        }
        phaseDuration = TimeInterval(max(1, minutes) * 60)
        now = Date()
        phaseEnd = now.addingTimeInterval(phaseDuration)
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
        switch phase {
        case .focus:
            if completed { completedFocus += 1 }
            if settings.longBreakEnabled, completedFocus >= max(1, settings.longBreakEvery) {
                completedFocus = 0
                enter(.longBreak)
            } else {
                enter(.shortBreak)
            }
        case .shortBreak, .longBreak:
            enter(.focus)
        case .idle:
            break
        }
    }

    private func applyEffects(tickFadeIn: TimeInterval = 0) {
        ticker.volume = settings.tickVolume
        breakSound.volume = settings.breakSoundVolume
        let focusing = phase == .focus && !isPaused
        if focusing, settings.tickSound != .appleMusic {
            ticker.start(settings.tickSound, fadeIn: tickFadeIn)
        } else {
            ticker.stop()
        }
        if focusing, settings.tickSound == .appleMusic {
            music.play(playlist: settings.musicPlaylist, shuffle: settings.musicShuffle,
                       openIfNeeded: settings.musicOpenIfNeeded, fadeIn: tickFadeIn)
        } else {
            music.pause()
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
        if !isPaused, now >= phaseEnd { advance(completed: true) }
        updateFadeOut()
    }

    // MARK: Fade-out

    private func updateFadeOut() {
        let left = phaseEnd.timeIntervalSinceNow
        guard phase == .focus, !isPaused, left <= Self.fadeOutDuration else { return endFadeOut() }
        if fadeOutTimer == nil {
            // Finer steps than the 1 Hz clock, which matters for music.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFadeOut() }
            }
            RunLoop.main.add(timer, forMode: .common)
            fadeOutTimer = timer
        }
        let level = Float(max(0, left) / Self.fadeOutDuration)
        ticker.level = level
        if settings.tickSound == .appleMusic { music.setFadeLevel(level) }
    }

    /// Stops a running fade-out. Music's volume is restored by `music.pause()` or here.
    private func endFadeOut() {
        guard fadeOutTimer != nil else { return }
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        ticker.level = 1
        if phase == .focus, !isPaused { music.endFade() }
    }
}
