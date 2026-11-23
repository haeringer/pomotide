import SwiftUI

struct PopoverView: View {
    @Environment(PomodoroTimer.self) private var timer
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(close: { showSettings = false })
            } else {
                TimerView(openSettings: { showSettings = true })
            }
        }
        .frame(width: 300)
        .task { await timer.focus.refresh() }
    }
}

struct TimerView: View {
    @Environment(PomodoroTimer.self) private var timer
    @Environment(Settings.self) private var settings
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(timer.phase.title)
                    .font(.headline)
                Spacer()
                if settings.longBreakEnabled {
                    RoundDots(done: timer.completedFocus, total: settings.longBreakEvery)
                }
            }

            ProgressRing(progress: timer.progress, tint: timer.phase.isBreak ? .teal : .accentColor) {
                VStack(spacing: 2) {
                    Text(timer.remainingText)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    if timer.isPaused {
                        Text("Paused").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 180, height: 180)

            HStack(spacing: 12) {
                Button(action: timer.stop) {
                    Image(systemName: "stop.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .disabled(timer.phase == .idle)
                .help("Stop")

                Button(action: timer.toggle) {
                    Label(timer.isRunning ? "Pause" : (timer.phase == .idle ? "Start" : "Resume"),
                          systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 100, height: 22)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.space, modifiers: [])

                Button(action: timer.skip) {
                    Image(systemName: "forward.end.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .disabled(timer.phase == .idle)
                .help("Skip to next phase")
            }
            .controlSize(.large)

            if needsFocusSetup {
                FocusSetupHint()
            }

            HStack {
                Button("Settings", systemImage: "gearshape", action: openSettings)
                Spacer()
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var needsFocusSetup: Bool {
        (settings.silenceDuringBreak || settings.silenceDuringFocus) && !timer.focus.shortcutsInstalled
    }
}

struct FocusSetupHint: View {
    @Environment(PomodoroTimer.self) private var timer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Do Not Disturb needs a one-time setup", systemImage: "moon")
                .font(.callout.weight(.medium))
            Text("Add the two PomoTide shortcuts. Shortcuts will ask you twice.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Set Up") { timer.focus.installShortcuts() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 12))
    }
}

struct ProgressRing<Content: View>: View {
    let progress: Double
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            content
        }
        .padding(4)
    }
}

struct RoundDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, total), id: \.self) { i in
                Circle()
                    .fill(i < done ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(done) of \(total) sessions until long break")
    }
}
