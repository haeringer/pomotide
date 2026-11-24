import ServiceManagement
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
                    } else if settings.tickSound == .spotify {
                        SpotifySettings()
                    } else if settings.tickSound != .off {
                        Slider(value: $settings.tickVolume, in: 0...1) { Text("Volume") }
                    }
                    Picker("Start and end of break", selection: $settings.transitionSound) {
                        ForEach(TransitionSound.allCases) { Text($0.title).tag($0) }
                    }
                    Slider(value: $settings.transitionVolume, in: 0...1) { Text("Volume") }
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

                Section("General") {
                    StartAtLoginToggle()
                    Toggle("Start and pause with \(HotKey.displayName)", isOn: $settings.globalShortcut)
                    if settings.globalShortcut, !timer.hotKeyAvailable {
                        Label("\(HotKey.displayName) is already used by another app.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
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
        .onChange(of: settings.globalShortcut) { timer.settingsChanged() }
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
        PlayerStatus(player: timer.music)
            .task { if timer.music.playlists.isEmpty, timer.music.isRunning { timer.music.loadPlaylists() } }
    }
}

private struct SpotifySettings: View {
    @Environment(PomodoroTimer.self) private var timer
    @Environment(Settings.self) private var settings
    @State private var clipboardProblem = false

    var body: some View {
        @Bindable var settings = settings
        // Spotify does not list its playlists for other apps, so it takes a link from its Share menu.
        let uri = SpotifyLink.uri(from: settings.spotifyLink)
        LabeledContent("Playlist") {
            HStack(spacing: 6) {
                Text(uri.map { settings.spotifyName.isEmpty ? SpotifyLink.kind(of: $0) : settings.spotifyName }
                     ?? "Continue last played")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(uri == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if uri != nil {
                    Button { setLink("") } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Continue last played instead")
                } else {
                    Text("or").foregroundStyle(.secondary)
                }
                Button("Paste Link") { pasteLink() }
            }
        }
        .task(id: settings.spotifyLink) {
            guard let uri, settings.spotifyName.isEmpty, let name = await SpotifyLink.title(for: uri),
                  SpotifyLink.uri(from: settings.spotifyLink) == uri else { return }
            settings.spotifyName = name
        }
        Text("In Spotify, right-click a playlist or album and choose Share > Copy link to playlist (or album), then click Paste Link.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if clipboardProblem {
            Label("The clipboard holds no Spotify link.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        if uri != nil {
            Toggle("Shuffle", isOn: $settings.musicShuffle)
        }
        Toggle("Open Spotify if it is not running", isOn: $settings.musicOpenIfNeeded)
        PlayerStatus(player: timer.spotify)
    }

    private func pasteLink() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        clipboardProblem = SpotifyLink.uri(from: text) == nil
        if !clipboardProblem { setLink(text) }
    }

    private func setLink(_ text: String) {
        settings.spotifyName = ""
        settings.spotifyLink = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Problem with the music app, if any, and how PomoTide treats playback.
private struct PlayerStatus: View {
    let player: MusicController

    var body: some View {
        if !player.isInstalled {
            Label("\(player.app.name) is not installed.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if let problem = player.problem {
            VStack(alignment: .leading, spacing: 4) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if player.needsPermission {
                    Button("Open Automation Settings…") { player.openAutomationSettings() }
                }
            }
        }
        if player.app == .appleMusic {
            Text("Music pauses during breaks and continues where it stopped. Music you started yourself is left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Login item via SMAppService. The system holds the state, so it is read from there
/// rather than stored in UserDefaults; the user can also change it in System Settings.
private struct StartAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var problem: String?

    var body: some View {
        // A plain @State binding plus onChange: passing a method as Binding setter
        // crashes the Swift 6.3 compiler (Xcode 26) in IRGen.
        Toggle("Start at login", isOn: $enabled)
            .onAppear { enabled = SMAppService.mainApp.status == .enabled }
            .onChange(of: enabled) { _, on in apply(on) }
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func apply(_ on: Bool) {
        guard on != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = SMAppService.mainApp.status == .requiresApproval
                ? "Allow PomoTide under System Settings > General > Login Items & Extensions."
                : nil
        } catch {
            Log.app.error("Changing the login item failed: \(error.localizedDescription, privacy: .public)")
            problem = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
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
