#!/bin/zsh
# Runs the unit tests. Extra arguments go to `swift test`.
set -euo pipefail
cd "${0:A:h}"

# Same SDK choice as build.sh. The Command Line Tools also do not load the Swift
# Testing macro plugin on their own, so point the compiler at it.
SDK26=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
FLAGS=()
if [[ $(xcode-select -p) == /Library/Developer/CommandLineTools ]]; then
    [[ -d $SDK26 && -z ${SDKROOT:-} ]] && export SDKROOT=$SDK26
    PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
    [[ -f $PLUGIN ]] && FLAGS=(-Xswiftc -load-plugin-library -Xswiftc $PLUGIN)
fi

swift test $FLAGS "$@"
