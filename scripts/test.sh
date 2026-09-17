#!/usr/bin/env bash
# Runs the Swift Testing suite for app/.
# On machines with only the Command Line Tools (no Xcode), Testing.framework is not on
# SwiftPM's default search paths, so the framework and rpath flags are passed explicitly.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLT_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
FLAGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* && -d "$CLT_FW/Testing.framework" ]]; then
  FLAGS=(-Xswiftc -F -Xswiftc "$CLT_FW"
         -Xlinker -rpath -Xlinker "$CLT_FW"
         -Xlinker -rpath -Xlinker "$CLT_LIB")
fi
cd "$ROOT/app"
exec swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
