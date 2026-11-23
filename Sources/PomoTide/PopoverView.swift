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

            ProgressRing(progress: timer.progress, tint: timer.phase.isBreak ? .teal : .accentColor,
                         onSeek: timer.phase == .idle ? nil : { timer.seek(to: $0) }) {
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
                Button("Quit PomoTide", systemImage: "xmark.circle") { NSApp.terminate(nil) }
                    .help("Quit PomoTide")
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
    /// Called with the new progress (0...1) while the ring is dragged; nil makes the ring static.
    var onSeek: ((Double) -> Void)?
    @ViewBuilder let content: Content

    @State private var dragging = false
    @State private var lastProgress: Double = 0
    @State private var hovering = false

    private let lineWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            // `stroke` centers the line on the circle's outline, i.e. at half the size.
            let radius = size / 2
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Follow the pointer directly while dragging; glide with the clock otherwise.
                    .animation(dragging ? nil : .linear(duration: 1), value: progress)
                if onSeek != nil, hovering || dragging {
                    // Handle at the end of the arc, so the ring reads as draggable.
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: radius * sin(progress * 2 * .pi), y: -radius * cos(progress * 2 * .pi))
                        .animation(dragging ? nil : .linear(duration: 1), value: progress)
                }
                content
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .gesture(seekGesture(center: CGPoint(x: size / 2, y: size / 2), radius: radius))
        }
        .padding(4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent elapsed")
    }

    private func seekGesture(center: CGPoint, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onSeek else { return }
                if !dragging {
                    // Only grab on the ring itself, not in the middle where the time is.
                    let d = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                    guard abs(d - radius) <= 22 else { return }
                    dragging = true
                    lastProgress = progress
                }
                // Angle from the top, clockwise, as 0...1.
                let angle = atan2(value.location.x - center.x, center.y - value.location.y)
                var p = angle >= 0 ? angle / (2 * .pi) : 1 + angle / (2 * .pi)
                // Crossing the top would jump between start and end; stop at the nearer end instead.
                if abs(p - lastProgress) > 0.5 { p = lastProgress > 0.5 ? 1 : 0 }
                lastProgress = p
                onSeek(p)
            }
            .onEnded { _ in dragging = false }
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
