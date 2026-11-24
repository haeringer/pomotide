import Foundation

/// Remaining time of one phase. Time is tracked as an end date rather than a counter,
/// so sleep or a busy main thread cannot make it drift. Every call takes the current
/// time explicitly, which keeps the arithmetic free of hidden clock reads.
struct PhaseClock: Equatable {
    private(set) var duration: TimeInterval = 1
    private var end = Date()
    /// Set while paused; the end date is meaningless then.
    private var pausedRemaining: TimeInterval?

    init() {}

    init(duration: TimeInterval, start: Date) {
        self.duration = max(1, duration)
        end = start.addingTimeInterval(self.duration)
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        pausedRemaining ?? max(0, end.timeIntervalSince(now))
    }

    /// 0 at the start of the phase, 1 at its end.
    func progress(at now: Date) -> Double {
        1 - remaining(at: now) / duration
    }

    func isFinished(at now: Date) -> Bool {
        !isPaused && now >= end
    }

    mutating func pause(at now: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    mutating func resume(at now: Date) {
        guard let left = pausedRemaining else { return }
        end = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    /// Moves the phase to `progress` (0 = start, 1 = end); the length stays the same.
    /// At least a second is kept, so dragging to the very end does not switch phases mid-drag.
    mutating func seek(to progress: Double, at now: Date) {
        let left = max(1, duration * (1 - min(1, max(0, progress))))
        if isPaused {
            pausedRemaining = left
        } else {
            end = now.addingTimeInterval(left)
        }
    }
}

extension Phase {
    /// The phase that follows this one, and the number of completed focus sessions to carry on.
    /// - Parameters:
    ///   - completed: false when the phase was skipped; a skipped focus does not count.
    ///   - longBreakEvery: focus sessions before a long break, or nil without long breaks.
    func next(completed: Bool, completedFocus: Int, longBreakEvery: Int?) -> (phase: Phase, completedFocus: Int) {
        switch self {
        case .focus:
            let done = completedFocus + (completed ? 1 : 0)
            if let every = longBreakEvery, done >= max(1, every) { return (.longBreak, 0) }
            return (.shortBreak, done)
        case .shortBreak, .longBreak:
            return (.focus, completedFocus)
        case .idle:
            return (.idle, completedFocus)
        }
    }
}
