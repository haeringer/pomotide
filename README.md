<h1><img src="docs/icon.png" width="40" alt=""> PomoTide</h1>

Pomodoro timer for the macOS menu bar that switches Do Not Disturb on and off for you and plays your Apple Music or Spotify playlist while you focus.

## Features

<img src="docs/screenshot.png" align="right" width="300" alt="PomoTide popover during a focus session, showing the remaining time in a progress ring with stop, pause and skip buttons">

- Focus and break run back to back, with an optional long break after a set number of sessions
- Do Not Disturb during breaks, or during focus if you prefer
- While you focus: ticking from real clock recordings, or an Apple Music or Spotify playlist that pauses during breaks
- During breaks: a gong or singing bowl, plus ocean waves or white, pink or brown noise that swells and ebbs like surf
- Remaining time in the menu bar, drag the ring to shorten a phase, ⇧⌥⌘P to start and pause from anywhere
- Native SwiftUI, no dependencies

<br clear="right">

## Install

```sh
brew install --cask haeringer/pomotide/pomotide
```

Or download the zip from [Releases](https://github.com/haeringer/pomotide/releases/latest). PomoTide is not notarized, so macOS blocks the first launch of the zip version; allow it under System Settings > Privacy & Security > **Open Anyway**. Homebrew takes care of this for you.

## Do Not Disturb

Apps can only switch Focus through Shortcuts, so PomoTide comes with two signed shortcuts. Click **Set Up** in the popover and add both. To use a different Focus than Do Not Disturb, change it in both shortcuts in the Shortcuts app.

## Development

Needs the Xcode Command Line Tools with Swift 6.2 or later.

```sh
git clone https://github.com/haeringer/pomotide.git && cd pomotide
./build.sh             # builds build/PomoTide.app, --install copies it to ~/Applications
./test.sh              # runs the unit tests
log stream --predicate 'subsystem == "io.github.haeringer.pomotide"' --level info
```

`tools/` has the scripts that generate the bundled shortcuts and the app icon; both results are committed. To release, push a tag like `v1.2.3`; the workflow publishes the zip and updates the cask in [haeringer/homebrew-pomotide](https://github.com/haeringer/homebrew-pomotide).

## License

MIT, see [LICENSE](LICENSE). The bundled sounds are CC0 recordings, see [CREDITS.md](CREDITS.md).
