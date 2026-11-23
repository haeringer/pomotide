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
    private let ticker = TickPlayer()
    private let gong = GongPlayer()

    private(set) var phase: Phase = .idle
    private(set) var isPaused = false
    /// Completed focus sessions since the last long break (or since start).
    private(set) var completedFocus = 0
    private(set) var now = Date()

    private var phaseEnd = Date()
    private var phaseDuration: TimeInterval = 1
    private var pausedRemaining: TimeInterval = 0
    private var clock: Timer?

    init(settings: Settings) {
        self.settings = settings
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focus.turnOffBlocking() }
        }
        Task { await focus.refresh() }
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
        pausedRemaining = remaining
        isPaused = true
        ticker.stop()
        stopClock()
    }

    func resume() {
        guard phase != .idle, isPaused else { return }
        isPaused = false
        phaseEnd = Date().addingTimeInterval(pausedRemaining)
        startClock()
        applyEffects(phaseChanged: false)
    }

    func skip() {
        guard phase != .idle else { return }
        advance(completed: false)
    }

    func stop() {
        phase = .idle
        isPaused = false
        completedFocus = 0
        stopClock()
        ticker.stop()
        focus.set(false)
    }

    /// Called when settings change, so a running phase picks up sound and Focus changes.
    func settingsChanged() {
        ticker.volume = settings.tickVolume
        guard isRunning else { return }
        applyEffects(phaseChanged: false)
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
        // Gong at the start and the end of every break, not when the first focus starts.
        if settings.gongEnabled, previous != .idle, previous.isBreak != next.isBreak {
            gong.play(volume: settings.gongVolume)
        }
        applyEffects(phaseChanged: true)
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

    private func applyEffects(phaseChanged: Bool) {
        ticker.volume = settings.tickVolume
        if phase == .focus, !isPaused {
            ticker.start(settings.tickSound)
        } else {
            ticker.stop()
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
    }
}
