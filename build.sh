#!/bin/zsh
# Builds PomoTide.app into ./build and, with --install, copies it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

VERSION="${VERSION:-0.1.0}"
APP="build/PomoTide.app"

# The macOS 27 SDK in the Command Line Tools ships SwiftUI macros without their
# compiler plugin, so build against the macOS 26 SDK when only the Command Line
# Tools are in use. With Xcode (as on CI) the default SDK is fine.
SDK26=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
if [[ $(xcode-select -p) == /Library/Developer/CommandLineTools && -d $SDK26 && -z ${SDKROOT:-} ]]; then
    export SDKROOT=$SDK26
fi

FLAGS=(-c release --arch arm64 --arch x86_64 ${=SWIFT_BUILD_FLAGS:-})
swift build $FLAGS
BIN="$(swift build $FLAGS --show-bin-path)/PomoTide"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp -R Resources/Sounds Resources/Shortcuts Resources/AppIcon.icns "$APP/Contents/Resources/"
chmod 644 "$APP"/Contents/Resources/Shortcuts/*

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PomoTide</string>
    <key>CFBundleDisplayName</key><string>PomoTide</string>
    <key>CFBundleIdentifier</key><string>io.github.haeringer.pomotide</string>
    <key>CFBundleExecutable</key><string>PomoTide</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSAppleEventsUsageDescription</key><string>PomoTide starts Apple Music during focus sessions and pauses it during breaks.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ ${1:-} == --install ]]; then
    mkdir -p ~/Applications
    pkill -x PomoTide 2>/dev/null || true
    rm -rf ~/Applications/PomoTide.app
    cp -R "$APP" ~/Applications/
    echo "Installed ~/Applications/PomoTide.app"
fi
