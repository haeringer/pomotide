import AppKit
import Observation

/// Turns a macOS Focus on and off through two Shortcuts bundled with the app.
///
/// macOS has no public API for apps to change Focus, but Shortcuts can. The user
/// imports the two bundled shortcuts once; the app then runs them with
/// `/usr/bin/shortcuts run`.
@MainActor
@Observable
final class FocusController {
    static let onShortcut = "PomoTide Focus On"
    static let offShortcut = "PomoTide Focus Off"

    private(set) var shortcutsInstalled = false
    /// Whether PomoTide turned the Focus on and has not turned it off yet.
    private(set) var isOn = false

    func refresh() async {
        let output = await Self.run(["list"]) ?? ""
        let names = Set(output.split(separator: "\n").map(String.init))
        shortcutsInstalled = names.contains(Self.onShortcut) && names.contains(Self.offShortcut)
        if !shortcutsInstalled { Log.focus.notice("Focus shortcuts are not installed") }
    }

    func set(_ on: Bool) {
        guard on != isOn, shortcutsInstalled else { return }
        isOn = on
        let name = on ? Self.onShortcut : Self.offShortcut
        Log.focus.info("Running shortcut \(name, privacy: .public)")
        Task {
            if await Self.run(["run", name]) == nil { Log.focus.error("Shortcut \(name, privacy: .public) failed") }
        }
    }

    /// Synchronous variant for app termination, where an async task would not finish.
    func turnOffBlocking() {
        guard isOn else { return }
        isOn = false
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/shortcuts")
        p.arguments = ["run", Self.offShortcut]
        try? p.run()
        p.waitUntilExit()
    }

    /// Opens the bundled shortcut files; Shortcuts asks the user to add each one.
    func installShortcuts() {
        for name in [Self.onShortcut, Self.offShortcut] {
            if let url = Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private nonisolated static func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(filePath: "/usr/bin/shortcuts")
                p.arguments = arguments
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    Log.focus.error("Could not start shortcuts: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                continuation.resume(returning: p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}
