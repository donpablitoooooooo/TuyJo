#!/usr/bin/env bash
# ============================================================
# Tuijo — App Store Screenshot Pipeline
# ============================================================
#
# This script does two things:
#   1. (Optional) Captures raw screenshots via Flutter integration test
#   2. Frames raw screenshots with device mockup + localized text
#
# Usage:
#   ./run.sh                  # frame only (raw PNGs must exist)
#   ./run.sh --capture        # capture + frame (needs simulator)
#   ./run.sh --locale en,it   # frame only specific locales
#   ./run.sh --size 6.5       # target iPhone 6.5" instead of 6.7"
#
# Prerequisites:
#   - Python 3 + Pillow: pip3 install Pillow
#   - Raw screenshots in screenshots/raw/ (or use --capture)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_DIR/flutter-app"
RAW_DIR="$SCRIPT_DIR/raw"

LOCALE_ARG=""
SIZE_ARG=""
DO_CAPTURE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --capture)  DO_CAPTURE=true; shift ;;
    --locale)   LOCALE_ARG="--locale $2"; shift 2 ;;
    --size)     SIZE_ARG="--size $2"; shift 2 ;;
    *)          echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ---- Step 1: Capture (optional) ------------------------------------------
if $DO_CAPTURE; then
  echo "=== Capturing screenshots via Flutter integration test ==="
  echo ""
  cd "$FLUTTER_DIR"
  flutter test integration_test/screenshot_test.dart \
    --no-pub \
    || echo "Warning: some tests may have failed. Check raw/ for partial results."
  echo ""
fi

# ---- Step 2: Check raw screenshots exist ----------------------------------
echo "=== Raw screenshots ==="
EXPECTED_FILES=(
  "01_chat.png"
  "02_voice_call.png"
  "03_location.png"
  "04_todo_calendar.png"
  "05_pairing.png"
  "06_media_gallery.png"
)

ok=0
miss=0
for f in "${EXPECTED_FILES[@]}"; do
  if [[ -f "$RAW_DIR/$f" ]]; then
    echo "  [OK]   $f"
    ((ok++))
  else
    echo "  [MISS] $f"
    ((miss++))
  fi
done
echo ""

if [[ $ok -eq 0 ]]; then
  echo "No raw screenshots found in $RAW_DIR"
  echo ""
  echo "Either:"
  echo "  1. Take screenshots manually on a simulator and save them as:"
  for f in "${EXPECTED_FILES[@]}"; do
    echo "       screenshots/raw/$f"
  done
  echo ""
  echo "  2. Run with --capture to use the Flutter integration test:"
  echo "       ./run.sh --capture"
  exit 1
fi

# ---- Step 3: Frame --------------------------------------------------------
echo "=== Generating framed App Store screenshots ==="
echo ""
python3 "$SCRIPT_DIR/frame_screenshots.py" $LOCALE_ARG $SIZE_ARG
echo ""
echo "=== Output ==="
find "$SCRIPT_DIR/output" -name "*.png" -type f | sort
echo ""
echo "Done! Upload these to App Store Connect."
