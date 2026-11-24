import Foundation
import Observation

/// What plays during focus: recorded ticking, a music app or nothing.
enum TickSound: String, CaseIterable, Identifiable {
    case wallClock, quartzClock, fastTicking, appleMusic, spotify, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallClock: "Wall Clock"
        case .quartzClock: "Tick Tock"
        case .fastTicking: "Ticking fast"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .off: "Off"
        }
    }

    /// File name prefix in Resources/Sounds.
    var filePrefix: String {
        switch self {
        case .wallClock: "wall"
        case .quartzClock: "quartz"
        case .fastTicking: "fast"
        case .appleMusic, .spotify, .off: ""
        }
    }

    /// Seconds between two ticks, as in the recording.
    var interval: TimeInterval {
        self == .fastTicking ? 0.264 : 1
    }

    var musicApp: MusicApp? {
        switch self {
        case .appleMusic: .appleMusic
        case .spotify: .spotify
        default: nil
        }
    }
}

enum TransitionSound: String, CaseIterable, Identifiable {
    case gong, bowl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gong: "Gong"
        case .bowl: "Singing Bowl"
        }
    }

    /// File name in Resources/Sounds, without the .wav extension.
    var fileName: String { rawValue }
}

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: "breakMinutes") } }
    var longBreakEnabled: Bool { didSet { defaults.set(longBreakEnabled, forKey: "longBreakEnabled") } }
    var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    var longBreakEvery: Int { didSet { defaults.set(longBreakEvery, forKey: "longBreakEvery") } }

    var tickSound: TickSound { didSet { defaults.set(tickSound.rawValue, forKey: "tickSound") } }
    var tickVolume: Double { didSet { defaults.set(tickVolume, forKey: "tickVolume") } }
    /// Playlist name; "" continues whatever Music played last.
    var musicPlaylist: String { didSet { defaults.set(musicPlaylist, forKey: "musicPlaylist") } }
    /// Spotify link as pasted; "" continues whatever Spotify played last.
    var spotifyLink: String { didSet { defaults.set(spotifyLink, forKey: "spotifyLink") } }
    /// Title of the linked playlist or album; "" until it has been looked up.
    var spotifyName: String { didSet { defaults.set(spotifyName, forKey: "spotifyName") } }
    /// Shuffle and open-if-needed apply to Apple Music and Spotify alike.
    var musicShuffle: Bool { didSet { defaults.set(musicShuffle, forKey: "musicShuffle") } }
    var musicOpenIfNeeded: Bool { didSet { defaults.set(musicOpenIfNeeded, forKey: "musicOpenIfNeeded") } }
    var transitionSound: TransitionSound { didSet { defaults.set(transitionSound.rawValue, forKey: "transitionSound") } }
    var transitionVolume: Double { didSet { defaults.set(transitionVolume, forKey: "transitionVolume") } }
    var breakSound: BreakSound { didSet { defaults.set(breakSound.rawValue, forKey: "breakSound") } }
    var breakSoundVolume: Double { didSet { defaults.set(breakSoundVolume, forKey: "breakSoundVolume") } }

    var silenceDuringBreak: Bool { didSet { defaults.set(silenceDuringBreak, forKey: "silenceDuringBreak") } }
    var silenceDuringFocus: Bool { didSet { defaults.set(silenceDuringFocus, forKey: "silenceDuringFocus") } }

    var showTimeInMenuBar: Bool { didSet { defaults.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") } }
    var globalShortcut: Bool { didSet { defaults.set(globalShortcut, forKey: "globalShortcut") } }

    init() {
        defaults.register(defaults: [
            "focusMinutes": 25,
            "breakMinutes": 5,
            "longBreakEnabled": false,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
            "tickSound": TickSound.wallClock.rawValue,
            "tickVolume": 0.5,
            "musicPlaylist": "",
            "spotifyLink": "",
            "spotifyName": "",
            "musicShuffle": false,
            "musicOpenIfNeeded": true,
            "transitionSound": TransitionSound.gong.rawValue,
            "transitionVolume": 0.7,
            "breakSound": BreakSound.off.rawValue,
            "breakSoundVolume": 0.5,
            "silenceDuringBreak": true,
            "silenceDuringFocus": false,
            "showTimeInMenuBar": true,
            "globalShortcut": true,
        ])
        focusMinutes = defaults.integer(forKey: "focusMinutes")
        breakMinutes = defaults.integer(forKey: "breakMinutes")
        longBreakEnabled = defaults.bool(forKey: "longBreakEnabled")
        longBreakMinutes = defaults.integer(forKey: "longBreakMinutes")
        longBreakEvery = defaults.integer(forKey: "longBreakEvery")
        tickSound = TickSound(rawValue: defaults.string(forKey: "tickSound") ?? "") ?? .wallClock
        tickVolume = defaults.double(forKey: "tickVolume")
        musicPlaylist = defaults.string(forKey: "musicPlaylist") ?? ""
        spotifyLink = defaults.string(forKey: "spotifyLink") ?? ""
        spotifyName = defaults.string(forKey: "spotifyName") ?? ""
        musicShuffle = defaults.bool(forKey: "musicShuffle")
        musicOpenIfNeeded = defaults.bool(forKey: "musicOpenIfNeeded")
        transitionSound = TransitionSound(rawValue: defaults.string(forKey: "transitionSound") ?? "") ?? .gong
        transitionVolume = defaults.double(forKey: "transitionVolume")
        breakSound = BreakSound(rawValue: defaults.string(forKey: "breakSound") ?? "") ?? .off
        breakSoundVolume = defaults.double(forKey: "breakSoundVolume")
        silenceDuringBreak = defaults.bool(forKey: "silenceDuringBreak")
        silenceDuringFocus = defaults.bool(forKey: "silenceDuringFocus")
        showTimeInMenuBar = defaults.bool(forKey: "showTimeInMenuBar")
        globalShortcut = defaults.bool(forKey: "globalShortcut")
    }
}
