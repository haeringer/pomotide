import os

/// Unified logging. Show it with
/// `log stream --predicate 'subsystem == "io.github.haeringer.pomotide"' --level debug`.
enum Log {
    private static let subsystem = "io.github.haeringer.pomotide"

    static let timer = Logger(subsystem: subsystem, category: "timer")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let sound = Logger(subsystem: subsystem, category: "sound")
    static let app = Logger(subsystem: subsystem, category: "app")
}
