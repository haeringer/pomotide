# PomoTide

A small Pomodoro timer that lives in the macOS menu bar. Features automatically turning on/off DoNotDisturb mode and playing/stopping playlists from Apple Music or Spotify.

<p align="center"><img src="docs/screenshot.png" width="340" alt="PomoTide popover during a focus session, showing the remaining time in a progress ring with stop, pause and skip buttons"></p>

## Features

- Adjustable focus and break length, optional long break after a set number of sessions
- Remaining time in the menu bar, controls in a popover, start and pause from anywhere with ⇧⌥⌘P
- Ticking during focus from real clock recordings, or Apple Music or Spotify instead: pick a playlist, music pauses during breaks and continues afterwards
- Gong or singing bowl at the start and end of every break
- Optional sound during breaks: ocean waves or white, pink or brown noise
- macOS Do Not Disturb mode during breaks or during focus
- Native Swift and SwiftUI, no dependencies, light on resources

## Requirements

macOS 26 or later.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask haeringer/pomotide/pomotide
```

PomoTide is not notarized by Apple (that needs a paid developer account). The Homebrew cask therefore removes the download quarantine, so macOS opens it without a warning. If you download the zip from [Releases](https://github.com/haeringer/pomotide/releases) instead, macOS blocks the first start; allow it under System Settings > Privacy & Security > **Open Anyway**.

### Build from source

You need the Xcode Command Line Tools (`xcode-select --install`) with Swift 6.2 or later.

```sh
git clone https://github.com/haeringer/pomotide.git
cd pomotide
./build.sh --install
open ~/Applications/PomoTide.app
```

`./build.sh` alone builds `build/PomoTide.app` without installing it.

To start PomoTide at login, turn on **Start at login** in its settings.

## Do Not Disturb setup

macOS has no public API for apps to switch Focus, but Shortcuts can. PomoTide ships two signed shortcuts, "PomoTide Focus On" and "PomoTide Focus Off", and runs them when a phase changes.

1. Open PomoTide from the menu bar and click **Set Up**.
2. Shortcuts opens twice; click **Add Shortcut** each time.

Settings shows "Shortcuts installed" once both are there. Without them the timer works normally, it just does not touch Do Not Disturb. To use your own Focus instead of Do Not Disturb, change the Focus in both shortcuts in the Shortcuts app.

## Development

| Path | Purpose |
|---|---|
| `Sources/PomoTide/` | App code |
| `Resources/Sounds/` | Bundled sounds |
| `Resources/Shortcuts/` | Signed Focus shortcuts |
| `tools/make_shortcuts.py` | Generates and signs the shortcuts (needs a Mac signed in to iCloud) |
| `tools/make_icon.swift` | Draws the app icon into `Resources/AppIcon.icns` |

The shortcuts and icon are committed, so a normal build needs neither tool.

To release, push a tag like `v0.1.0`. The release workflow builds a universal app, publishes `PomoTide-0.1.0.zip` with its SHA-256, and the cask in [haeringer/homebrew-pomotide](https://github.com/haeringer/homebrew-pomotide) then needs the new version and checksum.

## Sound credits

All bundled sounds are CC0 recordings, see [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE).
