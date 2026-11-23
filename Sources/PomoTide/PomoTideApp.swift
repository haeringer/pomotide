import SwiftUI

@main
struct PomoTideApp: App {
    @State private var timer = PomodoroTimer(settings: Settings())

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(timer)
                .environment(timer.settings)
        } label: {
            MenuBarLabel(timer: timer)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let timer: PomodoroTimer

    var body: some View {
        let symbol = switch (timer.phase, timer.isPaused) {
        case (.idle, _): "timer"
        case (_, true): "pause.circle"
        case (.focus, _): "timer"
        default: "cup.and.saucer"
        }
        if timer.phase != .idle, timer.settings.showTimeInMenuBar {
            Text("\(Image(systemName: symbol)) \(timer.remainingText)")
                .monospacedDigit()
        } else {
            Image(systemName: symbol)
        }
    }
}
