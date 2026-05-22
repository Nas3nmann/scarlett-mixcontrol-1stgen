#!/usr/bin/env bash
#
# Assemble a proper macOS .app bundle around the Swift Package executable.
# Run from the repo root:
#
#   ./scripts/make-app.sh         (release build)
#   ./scripts/make-app.sh --debug (debug build)
#
# Outputs:  build/Scarlett MixControl.app
#
# To launch from Finder: open "build/Scarlett MixControl.app"

set -euo pipefail

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/build"
APP_NAME="Scarlett MixControl"
APP_DIR="$BUILD_ROOT/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
BUNDLE_ID="dev.marekkramar.ScarlettMixControl"
EXE_NAME="ScarlettMixControl"
ICON_SRC="$REPO_ROOT/Sources/ScarlettApp/Resources/AppIcon.png"
ICONSET_DIR="$BUILD_ROOT/AppIcon.iconset"
ICNS_FILE="$RESOURCES_DIR/AppIcon.icns"

echo "→ Building swift-package executable ($CONFIG)…"
swift build -c "$CONFIG" --product scarlett-app

# SwiftPM places the binary + its resource bundle here.
SPM_BIN_DIR="$REPO_ROOT/.build/$CONFIG"

# --- Clean previous bundle ---------------------------------------------------
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# --- Copy binary -------------------------------------------------------------
echo "→ Copying binary → MacOS/$EXE_NAME"
cp "$SPM_BIN_DIR/scarlett-app" "$MACOS_DIR/$EXE_NAME"
chmod +x "$MACOS_DIR/$EXE_NAME"

# We deliberately do NOT copy the SwiftPM resource bundle into the .app.
# The .app already has Resources/AppIcon.icns (which Finder/Dock use for
# the icon via the Info.plist's CFBundleIconFile key) so we don't need
# the runtime `NSApp.applicationIconImage = …` path that loads AppIcon
# .png via `Bundle.module`.  Skipping the inner bundle also dodges a
# codesign error: SwiftPM's resource bundles are "flat" directories
# without an Info.plist, which `codesign` rejects when it tries to sign
# them as a sub-component of the .app.

# --- Build .icns from the source PNG ----------------------------------------
echo "→ Generating AppIcon.icns from $(basename "$ICON_SRC")"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
# macOS .iconset expects these specific sizes.  We resize the master PNG
# (which is 2048²) down with `sips` for each one.
for size in 16 32 64 128 256 512 1024; do
  out="$ICONSET_DIR/icon_${size}x${size}.png"
  sips -z "$size" "$size" "$ICON_SRC" --out "$out" >/dev/null
done
# Apple also wants @2x retina variants.
cp "$ICONSET_DIR/icon_32x32.png"      "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png"      "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/icon_256x256.png"    "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png"    "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png"  "$ICONSET_DIR/icon_512x512@2x.png"
rm "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"
iconutil --convert icns "$ICONSET_DIR" --output "$ICNS_FILE"
rm -rf "$ICONSET_DIR"

# --- Write Info.plist --------------------------------------------------------
echo "→ Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>           <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>     <string>$EXE_NAME</string>
    <key>CFBundleIdentifier</key>     <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>0.1</string>
    <key>CFBundleVersion</key>        <string>1</string>
    <key>LSMinimumSystemVersion</key> <string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key>       <string>NSApplication</string>
</dict>
</plist>
EOF

# --- Code-sign with an ad-hoc signature so Gatekeeper doesn't flag it -------
# We use ad-hoc (no identity) — fine for local installation, would need a
# real Developer ID cert for distribution.
echo "→ Ad-hoc codesigning"
codesign --force --sign - "$APP_DIR"

echo
echo "✓ Bundle ready:  $APP_DIR"
echo "  Launch with:   open \"$APP_DIR\""
