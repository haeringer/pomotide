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
        // nil: the app's own ring and wave, before the start and during focus.
        let symbol: String? = switch (timer.phase, timer.isPaused) {
        case (.idle, _): nil
        case (_, true): "pause.circle"
        case (.focus, _): nil
        default: "figure.mind.and.body"
        }
        if timer.phase != .idle, timer.settings.showTimeInMenuBar {
            Image(nsImage: Self.pill(icon: Self.icon(symbol, size: 13), text: timer.remainingText))
        } else {
            Image(nsImage: Self.icon(symbol, size: 16))
        }
    }

    private static func icon(_ symbol: String?, size: CGFloat) -> NSImage {
        guard let symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(
                  // Same sizes and weights the symbols had before: 13 pt regular alone, 12 pt medium in the pill.
                  size > 14 ? NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                      : NSImage.SymbolConfiguration(pointSize: 12, weight: .medium, scale: .medium))
        else { return MenuBarIcon.image(size: size) }
        image.isTemplate = true
        return image
    }

    /// Icon and remaining time on a soft rounded background.
    ///
    /// SwiftUI ignores backgrounds in menu bar labels, so this draws a template
    /// image: only alpha counts, and macOS tints it to match the menu bar.
    /// The background is drawn at low alpha, icon and text at full alpha.
    static func pill(icon: NSImage, text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let iconSize = icon.size
        let textSize = label.size()
        let padding: CGFloat = 6, gap: CGFloat = 4, height: CGFloat = 18
        let width = ceil(padding + iconSize.width + gap + textSize.width + padding)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            icon.draw(in: NSRect(x: padding, y: (height - iconSize.height) / 2,
                                 width: iconSize.width, height: iconSize.height))
            label.draw(at: NSPoint(x: padding + iconSize.width + gap, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = text
        return image
    }
}
