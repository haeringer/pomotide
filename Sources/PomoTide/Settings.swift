import Foundation
import Observation

enum TickSound: String, CaseIterable, Identifiable {
    case wallClock, pocketWatch, grandfatherClock, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallClock: "Wall Clock"
        case .pocketWatch: "Pocket Watch"
        case .grandfatherClock: "Grandfather Clock"
        case .off: "Off"
        }
    }

    /// Playback-rate factor applied to the recorded ticks (> 1 is higher and shorter).
    var pitch: Float {
        switch self {
        case .wallClock: 1.0
        case .pocketWatch: 1.7
        case .grandfatherClock: 0.72
        case .off: 1.0
        }
    }

    /// Seconds between two ticks.
    var interval: Double {
        switch self {
        case .pocketWatch: 0.25
        default: 1.0
        }
    }

    var gain: Float {
        switch self {
        case .pocketWatch: 0.55
        default: 1.0
        }
    }
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
    var gongEnabled: Bool { didSet { defaults.set(gongEnabled, forKey: "gongEnabled") } }
    var gongVolume: Double { didSet { defaults.set(gongVolume, forKey: "gongVolume") } }
    var breakSound: BreakSound { didSet { defaults.set(breakSound.rawValue, forKey: "breakSound") } }
    var breakSoundVolume: Double { didSet { defaults.set(breakSoundVolume, forKey: "breakSoundVolume") } }

    var silenceDuringBreak: Bool { didSet { defaults.set(silenceDuringBreak, forKey: "silenceDuringBreak") } }
    var silenceDuringFocus: Bool { didSet { defaults.set(silenceDuringFocus, forKey: "silenceDuringFocus") } }

    var showTimeInMenuBar: Bool { didSet { defaults.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") } }

    init() {
        defaults.register(defaults: [
            "focusMinutes": 25,
            "breakMinutes": 5,
            "longBreakEnabled": false,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
            "tickSound": TickSound.wallClock.rawValue,
            "tickVolume": 0.5,
            "gongEnabled": true,
            "gongVolume": 0.7,
            "breakSound": BreakSound.off.rawValue,
            "breakSoundVolume": 0.5,
            "silenceDuringBreak": true,
            "silenceDuringFocus": false,
            "showTimeInMenuBar": true,
        ])
        focusMinutes = defaults.integer(forKey: "focusMinutes")
        breakMinutes = defaults.integer(forKey: "breakMinutes")
        longBreakEnabled = defaults.bool(forKey: "longBreakEnabled")
        longBreakMinutes = defaults.integer(forKey: "longBreakMinutes")
        longBreakEvery = defaults.integer(forKey: "longBreakEvery")
        tickSound = TickSound(rawValue: defaults.string(forKey: "tickSound") ?? "") ?? .wallClock
        tickVolume = defaults.double(forKey: "tickVolume")
        gongEnabled = defaults.bool(forKey: "gongEnabled")
        gongVolume = defaults.double(forKey: "gongVolume")
        breakSound = BreakSound(rawValue: defaults.string(forKey: "breakSound") ?? "") ?? .off
        breakSoundVolume = defaults.double(forKey: "breakSoundVolume")
        silenceDuringBreak = defaults.bool(forKey: "silenceDuringBreak")
        silenceDuringFocus = defaults.bool(forKey: "silenceDuringFocus")
        showTimeInMenuBar = defaults.bool(forKey: "showTimeInMenuBar")
    }
}
