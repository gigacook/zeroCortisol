#!/usr/bin/env bash
# zeroCortisol installer: clones, builds and drops ZeroCortisol.app into ~/Applications.
#   curl -fsSL https://raw.githubusercontent.com/gigacook/zeroCortisol/main/install.sh | bash
set -euo pipefail

command -v swift >/dev/null || { echo "Swift not found. Run: xcode-select --install" >&2; exit 1; }
command -v git   >/dev/null || { echo "git not found. Run: xcode-select --install" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "👁  Summoning the fathers…"
git clone --depth 1 https://github.com/gigacook/zeroCortisol.git "$TMP/zeroCortisol" >/dev/null 2>&1
"$TMP/zeroCortisol/scripts/build_app.sh" >/dev/null

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ZeroCortisol.app"
cp -R "$TMP/zeroCortisol/dist/ZeroCortisol.app" "$HOME/Applications/"

echo "🔺 Installed to ~/Applications/ZeroCortisol.app. Look up at your menu bar."
open "$HOME/Applications/ZeroCortisol.app"
