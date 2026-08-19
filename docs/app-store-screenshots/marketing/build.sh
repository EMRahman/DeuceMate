#!/bin/bash
# build.sh — render the three App Store advertisement frames.
#
#   ./build.sh
#
# Writes 1320x2868 PNGs with no alpha channel into ../iphone-6.9-marketing/.
# Requires a Mac with the Swift toolchain (for DeuceMateWebSnapshot) and
# Python's Pillow (for the alpha flatten). Both are host-only build tools; the
# app itself still has zero third-party dependencies.
#
# Four constraints this script exists to handle — see README.md for why:
#   1. DeuceMateWebSnapshot renders at the display's 2x backing scale, so we
#      ask for 660x1434 and get 1320x2868.
#   2. Its PNGs carry an alpha channel; App Store Connect rejects those.
#   3. WKWebView's file read access is scoped to the HTML's own directory, so
#      every image is staged flat beside the markup.
#   4. Sources live in two different directories and at three different sizes;
#      staging normalises that away.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOTS="$(cd "$HERE/.." && pwd)"          # docs/app-store-screenshots
DOCS="$(cd "$SHOTS/.." && pwd)"          # docs
PKG="$(cd "$DOCS/../DeuceMate/Packages/DeuceMateCore" && pwd)"
OUT="$SHOTS/iphone-6.9-marketing"

WIDTH=660                                 # x2 => 1320
HEIGHT=1434                               # x2 => 2868
EXPECT_W=1320
EXPECT_H=2868

command -v swift >/dev/null || { echo "error: swift not found — needs a Mac with Xcode"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "error: Pillow not installed (pip3 install Pillow)"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging sources in $STAGE"
cp "$HERE/ad.css" "$STAGE/"
cp "$HERE"/ad-*.html "$STAGE/"
cp "$SHOTS/watch-45mm/03-watch-live-scoreboard.png" "$STAGE/src-watch-live.png"
cp "$SHOTS/iphone-6.9/05-match-archive.png"         "$STAGE/src-iphone-archive.png"
cp "$DOCS/screenshots/09-ai-coach-launcher.png"     "$STAGE/src-iphone-aicoach.png"
# Ad 2 uses a dark-mode capture that exists only for these frames — see
# sources/README-note in marketing/README.md. It is deliberately NOT the raw
# iphone-6.9/02-points-momentum.png, which stays the light 1320x2868 upload.
cp "$HERE/sources/points-graph-dark.png"            "$STAGE/src-iphone-graph.png"

mkdir -p "$OUT"

render() {
  local html="$1" name="$2"
  echo "==> Rendering $name"
  local shotdir="$STAGE/out-$name"
  mkdir -p "$shotdir"

  ( cd "$PKG" && swift run -q DeuceMateWebSnapshot "$STAGE/$html" "$shotdir" "$WIDTH" "$HEIGHT" >/dev/null )

  local raw="$shotdir/00-default.png"
  [ -f "$raw" ] || { echo "error: $name produced no snapshot"; exit 1; }

  # Flatten: drop the alpha channel App Store Connect refuses.
  python3 - "$raw" "$OUT/$name.png" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
Image.open(src).convert("RGB").save(dst, "PNG", optimize=True)
PY

  # Assert the two ways this silently goes wrong.
  local w h a
  w=$(sips -g pixelWidth  "$OUT/$name.png" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$OUT/$name.png" | awk '/pixelHeight/{print $2}')
  a=$(sips -g hasAlpha    "$OUT/$name.png" | awk '/hasAlpha/{print $2}')
  if [ "$w" != "$EXPECT_W" ] || [ "$h" != "$EXPECT_H" ]; then
    echo "error: $name is ${w}x${h}, expected ${EXPECT_W}x${EXPECT_H}"; exit 1
  fi
  if [ "$a" != "no" ]; then
    echo "error: $name still has an alpha channel"; exit 1
  fi
  echo "    ok  $name.png  ${w}x${h}  hasAlpha:${a}"
}

render ad-1-watch-iphone.html 01-watch-and-iphone
render ad-2-analysis.html     02-match-analysis
render ad-3-ai-coach.html     03-ai-coach

echo
echo "Done — $OUT"
ls -la "$OUT"
