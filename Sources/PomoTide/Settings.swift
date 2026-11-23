import Foundation
import Observation

enum TickSound: String, CaseIterable, Identifiable {
    case wallClock, quartzClock, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallClock: "Wall Clock"
        case .quartzClock: "Quartz Clock"
        case .off: "Off"
        }
    }

    /// File name prefix in Resources/Sounds.
    var filePrefix: String {
        switch self {
        case .wallClock: "wall"
        case .quartzClock: "quartz"
        case .off: ""
        }
    }

    var gain: Float { 1.0 }
}

enum TransitionSound: String, CaseIterable, Identifiable {
    case none, gong, bowl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .gong: "Gong"
        case .bowl: "Singing Bowl"
        }
    }

    var file: (name: String, ext: String)? {
        switch self {
        case .none: nil
        case .gong: ("gong", "wav")
        case .bowl: ("bowl", "wav")
        }
    }

    var gain: Float { 1.0 }
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
    var transitionSound: TransitionSound { didSet { defaults.set(transitionSound.rawValue, forKey: "transitionSound") } }
    var transitionVolume: Double { didSet { defaults.set(transitionVolume, forKey: "transitionVolume") } }
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
            "transitionSound": TransitionSound.gong.rawValue,
            "transitionVolume": 0.7,
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
        transitionSound = TransitionSound(rawValue: defaults.string(forKey: "transitionSound") ?? "") ?? .gong
        transitionVolume = defaults.double(forKey: "transitionVolume")
        breakSound = BreakSound(rawValue: defaults.string(forKey: "breakSound") ?? "") ?? .off
        breakSoundVolume = defaults.double(forKey: "breakSoundVolume")
        silenceDuringBreak = defaults.bool(forKey: "silenceDuringBreak")
        silenceDuringFocus = defaults.bool(forKey: "silenceDuringFocus")
        showTimeInMenuBar = defaults.bool(forKey: "showTimeInMenuBar")
    }
}
