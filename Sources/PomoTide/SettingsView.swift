import SwiftUI

struct SettingsView: View {
    @Environment(PomodoroTimer.self) private var timer
    @Environment(Settings.self) private var settings
    let close: () -> Void

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Form {
                Section("Timer") {
                    MinutesStepper(title: "Focus", value: $settings.focusMinutes, range: 1...120)
                    MinutesStepper(title: "Break", value: $settings.breakMinutes, range: 1...60)
                    Toggle("Long break", isOn: $settings.longBreakEnabled)
                    if settings.longBreakEnabled {
                        MinutesStepper(title: "Long break", value: $settings.longBreakMinutes, range: 1...60)
                        Stepper("Every \(settings.longBreakEvery) sessions", value: $settings.longBreakEvery, in: 2...8)
                    }
                }

                Section("Sound") {
                    Picker("During focus", selection: $settings.tickSound) {
                        ForEach(TickSound.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.tickSound == .appleMusic {
                        MusicSettings()
                    } else if settings.tickSound != .off {
                        Slider(value: $settings.tickVolume, in: 0...1) { Text("Volume") }
                    }
                    Picker("Start and end of break", selection: $settings.transitionSound) {
                        ForEach(TransitionSound.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.transitionSound != .none {
                        Slider(value: $settings.transitionVolume, in: 0...1) { Text("Volume") }
                    }
                    Picker("During break", selection: $settings.breakSound) {
                        ForEach(BreakSound.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.breakSound != .off {
                        Slider(value: $settings.breakSoundVolume, in: 0...1) { Text("Volume") }
                    }
                }

                Section {
                    Toggle("During breaks", isOn: $settings.silenceDuringBreak)
                    Toggle("During focus", isOn: $settings.silenceDuringFocus)
                    if timer.focus.shortcutsInstalled {
                        Label("Shortcuts installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Install Shortcuts…") { timer.focus.installShortcuts() }
                    }
                } header: {
                    Text("Do Not Disturb")
                } footer: {
                    Text("To use your own Focus instead, change the Focus in the two PomoTide shortcuts in the Shortcuts app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Show time in menu bar", isOn: $settings.showTimeInMenuBar)
                }
            }
            .formStyle(.grouped)
            .frame(height: 520)
        }
        .onChange(of: settings.tickSound) {
            if settings.tickSound == .appleMusic { timer.music.loadPlaylists() }
            timer.settingsChanged()
        }
        .onChange(of: settings.tickVolume) { timer.settingsChanged() }
        .onChange(of: settings.breakSound) { timer.settingsChanged() }
        .onChange(of: settings.breakSoundVolume) { timer.settingsChanged() }
        .onChange(of: settings.silenceDuringBreak) { timer.settingsChanged() }
        .onChange(of: settings.silenceDuringFocus) { timer.settingsChanged() }
    }
}

private struct MusicSettings: View {
    @Environment(PomodoroTimer.self) private var timer
    @Environment(Settings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Picker("Playlist", selection: $settings.musicPlaylist) {
            Text("Continue last played").tag("")
            if !settings.musicPlaylist.isEmpty, !timer.music.playlists.contains(settings.musicPlaylist) {
                Text(settings.musicPlaylist).tag(settings.musicPlaylist)
            }
            ForEach(timer.music.playlists, id: \.self) { Text($0).tag($0) }
        }
        if !settings.musicPlaylist.isEmpty {
            Toggle("Shuffle", isOn: $settings.musicShuffle)
        }
        Toggle("Open Music if it is not running", isOn: $settings.musicOpenIfNeeded)
        if let problem = timer.music.problem {
            VStack(alignment: .leading, spacing: 4) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Open Automation Settings…") { timer.music.openAutomationSettings() }
            }
        }
        Text("Music pauses during breaks and continues where it stopped. Music you started yourself is left alone.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .task { if timer.music.playlists.isEmpty, timer.music.isRunning { timer.music.loadPlaylists() } }
    }
}

/// Minutes as a text field plus stepper arrows. Typed values are clamped to the range.
private struct MinutesStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 44)
                Text("min").foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}
