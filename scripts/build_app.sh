#!/usr/bin/env bash
# Builds dist/ZeroCortisol.app from a clean clone (Command Line Tools are enough).
#
#   scripts/build_app.sh            # release build, assemble, ad-hoc sign
#   scripts/build_app.sh --icons    # also regenerate icons into app/Resources first
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ZeroCortisol"
BUNDLE_ID="com.gigacook.zerocortisol"
VERSION="1.0.0"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
RES_SRC="$ROOT/app/Resources"

step() { printf '\n==> %s\n' "$*"; }

# 1. Icons (committed; regenerated when missing or on request).
if [[ "${1:-}" == "--icons" || ! -f "$RES_SRC/AppIcon.icns" || ! -f "$RES_SRC/menubar_open@2x.png" ]]; then
  step "Generating icons"
  swift "$ROOT/scripts/make_icon.swift" "$RES_SRC"
fi

# 2. Release build.
step "swift build -c release"
swift build -c release --package-path "$ROOT/app"
BIN_DIR="$(swift build -c release --package-path "$ROOT/app" --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || { echo "binary not found in $BIN_DIR" >&2; exit 1; }

# 3. Assemble the bundle.
step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/data/quotes.json" "$ROOT/data/corpus_meta.json" "$ROOT/data/schema.sql" "$APP/Contents/Resources/"
cp "$ROOT/web/index.html" "$APP/Contents/Resources/web/index.html"
cp "$RES_SRC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$RES_SRC"/menubar_closed.png "$RES_SRC"/menubar_closed@2x.png \
   "$RES_SRC"/menubar_open.png "$RES_SRC"/menubar_open@2x.png "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>zeroCortisol</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# 4. Ad-hoc signature (not a Developer ID; required for arm64 binaries to launch).
step "codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

step "Done: $APP"
