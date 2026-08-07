#!/usr/bin/env bash
# Regenerate Distribution/AppIcon.icns from Distribution/AppIcon.svg.
#
# The .icns is committed so release builds stay hermetic and don't need
# librsvg on the CI runner. Run this after editing AppIcon.svg and commit
# both files together.
#
# Requires: librsvg (brew install librsvg) and iconutil (ships with Xcode).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
svg="$here/AppIcon.svg"
iconset="$(mktemp -d)/AppIcon.iconset"

command -v rsvg-convert >/dev/null || { echo "need rsvg-convert: brew install librsvg" >&2; exit 1; }
command -v iconutil >/dev/null || { echo "need iconutil (install Xcode)" >&2; exit 1; }

mkdir -p "$iconset"

# iconutil expects exactly these names; each @2x is the next power of two up.
render() { rsvg-convert -w "$1" -h "$1" "$svg" -o "$iconset/$2"; }
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns "$iconset" --output "$here/AppIcon.icns"
rm -rf "$(dirname "$iconset")"

echo "wrote $here/AppIcon.icns"
