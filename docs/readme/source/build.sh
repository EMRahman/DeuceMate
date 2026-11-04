#!/bin/bash
# build.sh — composites the README hero and theme strip, then exports every
# README image from a folder of captures. See docs/screenshots/README.md.
#
#   ./build.sh <iphone-shots-dir> <watch-shots-dir> <insights-png> <iphone-safari-png>
#
# Needs a Mac with Swift (DeuceMateWebSnapshot). WKWebView only reads files
# beside the HTML, so everything is staged flat in one temp directory.
set -euo pipefail
PHONE="$1"; WATCH="$2"; INSIGHTS="$3"; WEB="$4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(cd "$HERE/.." && pwd)"; DOCS="$(cd "$OUT/.." && pwd)"
PKG="$(cd "$DOCS/../DeuceMate/Packages/DeuceMateCore" && pwd)"
ST="$(mktemp -d)"; trap 'rm -rf "$ST"' EXIT

cp "$HERE"/*.html "$ST/"
cp "$PHONE/readme-momentum.png" "$ST/src-momentum.png"
cp "$PHONE/readme-trends.png" "$ST/src-trends.png"
cp "$DOCS/website/screenshots/04-watch-scoreboard.png" "$ST/src-watch.png"
# Crops keep the score rows only: a simulator has no heart rate or calories.
for t in default clayCourt grassCourt hardCourtDay hardCourtNight; do
  sips -c 200 416 --cropOffset 116 0 "$WATCH/readme-theme-$t.png" --out "$ST/t-$t.png" >/dev/null
done
sips -c 412 416 --cropOffset 84 0 "$WATCH/readme-watch-tag-point.png" --out "$ST/tag.png" >/dev/null
# Ends above Safari's floating address bar, which would show the local server.
sips -c 2590 1320 --cropOffset 1 0 "$WEB" --out "$ST/web.png" >/dev/null

( cd "$PKG"
  swift run -q DeuceMateWebSnapshot "$ST/hero.html" "$ST/o-hero" 1600 800 >/dev/null
  swift run -q DeuceMateWebSnapshot "$ST/themes.html" "$ST/o-themes" 1600 290 >/dev/null )

jpg() { sips -s format jpeg -s formatOptions "$4" --resampleWidth "$3" "$1" --out "$OUT/$2.jpg" >/dev/null; }
jpg "$ST/o-hero/00-default.png" hero 1600 88
jpg "$ST/o-themes/00-default.png" themes 1600 88
jpg "$ST/tag.png" watch-tag-point 416 90
for n in momentum stats pulse-zones trends head-to-head compare; do
  jpg "$PHONE/readme-$n.png" "$n" 780 84
done
jpg "$INSIGHTS" coaching-insights 780 84
jpg "$ST/web.png" web-report 780 84
echo "Done: $OUT"
