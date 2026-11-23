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
        default: "figure.mind.and.body"
        }
        if timer.phase != .idle, timer.settings.showTimeInMenuBar {
            Image(nsImage: Self.pill(symbol: symbol, text: timer.remainingText))
        } else {
            Image(systemName: symbol)
        }
    }

    /// Symbol and remaining time on a soft rounded background.
    ///
    /// SwiftUI ignores backgrounds in menu bar labels, so this draws a template
    /// image: only alpha counts, and macOS tints it to match the menu bar.
    /// The background is drawn at low alpha, symbol and text at full alpha.
    static func pill(symbol: String, text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium, scale: .medium)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let iconSize = icon?.size ?? .zero
        let textSize = label.size()
        let padding: CGFloat = 6, gap: CGFloat = 4, height: CGFloat = 18
        let width = ceil(padding + iconSize.width + gap + textSize.width + padding)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            if let icon {
                icon.draw(in: NSRect(x: padding, y: (height - iconSize.height) / 2,
                                     width: iconSize.width, height: iconSize.height))
            }
            label.draw(at: NSPoint(x: padding + iconSize.width + gap, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = text
        return image
    }
}
