import Foundation
import Testing
@testable import PomoTide

struct PhaseClockTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func countsDownFromStart() {
        let clock = PhaseClock(duration: 1500, start: start)
        #expect(clock.remaining(at: start) == 1500)
        #expect(clock.remaining(at: start + 100) == 1400)
        #expect(clock.progress(at: start + 750) == 0.5)
        #expect(clock.remaining(at: start + 2000) == 0)
    }

    /// The remaining time once showed the pause duration added for a second after resuming.
    @Test func pauseAndResumeKeepRemainingTime() {
        var clock = PhaseClock(duration: 1500, start: start)
        clock.pause(at: start + 10)
        #expect(clock.remaining(at: start + 610) == 1490)
        clock.resume(at: start + 610)
        #expect(clock.remaining(at: start + 610) == 1490)
        #expect(clock.remaining(at: start + 611) == 1489)
    }

    @Test func finishesOnlyWhileRunning() {
        var clock = PhaseClock(duration: 60, start: start)
        #expect(!clock.isFinished(at: start + 59))
        #expect(clock.isFinished(at: start + 60))
        clock.pause(at: start + 30)
        #expect(!clock.isFinished(at: start + 120))
    }

    @Test(arguments: [(0.5, 30.0), (0, 60), (1, 1), (1.5, 1), (-1, 60)])
    func seekKeepsAtLeastOneSecond(progress: Double, expected: TimeInterval) {
        var running = PhaseClock(duration: 60, start: start)
        running.seek(to: progress, at: start + 10)
        #expect(running.remaining(at: start + 10) == expected)

        var paused = PhaseClock(duration: 60, start: start)
        paused.pause(at: start + 10)
        paused.seek(to: progress, at: start + 20)
        #expect(paused.remaining(at: start + 500) == expected)
    }
}

struct PhaseCycleTests {
    @Test func longBreakAfterEveryNthCompletedFocus() {
        var phase = Phase.focus
        var done = 0
        var sequence: [Phase] = []
        for _ in 0..<8 {
            (phase, done) = phase.next(completed: true, completedFocus: done, longBreakEvery: 2)
            sequence.append(phase)
        }
        #expect(sequence == [.shortBreak, .focus, .longBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
    }

    @Test func skippedFocusDoesNotCount() {
        let next = Phase.focus.next(completed: false, completedFocus: 1, longBreakEvery: 2)
        #expect(next.phase == .shortBreak)
        #expect(next.completedFocus == 1)
    }

    @Test func noLongBreakWhenDisabled() {
        let next = Phase.focus.next(completed: true, completedFocus: 10, longBreakEvery: nil)
        #expect(next.phase == .shortBreak)
    }
}
