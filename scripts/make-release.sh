#!/usr/bin/env bash
#
# Build a release-ready zipped .app for upload to GitHub.
#
# Outputs:  build/Scarlett.MixControl.app.zip
#
# After running this, create the GitHub release (manually or via `gh release
# create`) and attach the zip as a binary asset.
#
# Usage:    ./scripts/make-release.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$REPO_ROOT/build/Scarlett MixControl.app"
ZIP_PATH="$REPO_ROOT/build/Scarlett.MixControl.app.zip"

# 1. Build the .app.
"$REPO_ROOT/scripts/make-app.sh"

# 2. Zip it.  We use `ditto -c -k --sequesterRsrc` because that's what
#    Apple's notarization tooling expects (and it correctly preserves the
#    extended attributes a .app needs).  `zip` will work too but ditto is
#    the official answer for bundling .app directories on macOS.
echo "→ Zipping → $(basename "$ZIP_PATH")"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# 3. Print size + sha256 so the release notes can reference both.
size_kb=$(($(stat -f '%z' "$ZIP_PATH") / 1024))
hash=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

echo
echo "✓ Release artifact ready:"
echo "    $ZIP_PATH"
echo "    size:   ${size_kb} KB"
echo "    sha256: $hash"
echo
echo "Next:"
echo "  1. Tag this commit:        git tag v0.1.0 && git push origin v0.1.0"
echo "  2. Create GitHub release:  gh release create v0.1.0 \"$ZIP_PATH\" --generate-notes"
echo "     (or upload manually via https://github.com/MarecekW/scarlett-mixcontrol-1stgen/releases/new)"
