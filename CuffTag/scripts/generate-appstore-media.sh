#!/usr/bin/env bash
# Captures App Store screenshots (6.9", 6.7", and 6.5" iPhone sizes) and records
# the App Preview walkthrough video (with required stereo AAC audio track) using
# CuffTag's `-appStoreDemo YES` showcase mode.
#
# Usage:
#   ./scripts/generate-appstore-media.sh              # Screenshots + App Preview video
#   ./scripts/generate-appstore-media.sh --shots-only # Only screenshots
#   ./scripts/generate-appstore-media.sh --video-only # Only App Preview video

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-all}"
case "$MODE" in
  all|--shots-only|--video-only) ;;
  *) echo "Usage: $0 [--shots-only|--video-only]" >&2; exit 1 ;;
esac
if [[ "$MODE" != "--shots-only" ]] && ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg is required for App Preview video. Use --shots-only to capture screenshots." >&2
  exit 1
fi
SCHEME="CuffTag"
PROJECT="CuffTag.xcodeproj"
SHOTS_TMP="/tmp/cufftag-appstore-shots"
SHOTS_DIR="$ROOT_DIR/AppStore/Screenshots"
VIDEO_DIR="$ROOT_DIR/AppStore/Video"

mkdir -p "$SHOTS_DIR/6.9-inch-1320x2868" \
         "$SHOTS_DIR/6.7-inch-1290x2796" \
         "$SHOTS_DIR/6.5-inch-1284x2778" \
         "$VIDEO_DIR"

# Find the best Pro Max / large iPhone simulator available on this machine
SIM_UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
preferred = ["iPhone 18 Pro Max", "iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 18 Pro", "iPhone 17"]
candidates = []
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if d.get("isAvailable"):
            candidates.append(d)
for name in preferred:
    for d in candidates:
        if d["name"] == name:
            print(d["udid"])
            sys.exit(0)
if candidates:
    print(candidates[0]["udid"])
')"

if [[ -z "$SIM_UDID" ]]; then
  echo "Error: No available iOS Simulator found." >&2
  exit 1
fi

SIM_NAME="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d.get('udid') == '$SIM_UDID':
            print(d['name'])
")"

echo "==> Booting simulator: $SIM_NAME ($SIM_UDID)"
xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b

echo "==> Applying clean Apple marketing status bar (9:41, full signal, 100% battery)"
xcrun simctl status_bar "$SIM_UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 || true

cleanup() {
  if [[ -n "${REC_PID:-}" ]]; then
    kill -INT "$REC_PID" 2>/dev/null || true
    wait "$REC_PID" 2>/dev/null || true
  fi
  xcrun simctl status_bar "$SIM_UDID" clear >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$MODE" != "--video-only" ]]; then
  echo "==> Capturing 8 App Store screenshots via DesignAccessibilityTests/testCaptureAppStoreScreenshots..."
  rm -rf "$SHOTS_TMP"
  mkdir -p "$SHOTS_TMP"

  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -only-testing:CuffTagUITests/DesignAccessibilityTests/testCaptureAppStoreScreenshots \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
    -quiet

  expected=(
    01-Jacket-Connected 02-Gestures-Profiles 03-Podcasts-Library 04-Podcast-Shortcuts
    05-Gesture-School 06-Onboarding-Welcome 07-Alerts-Shortcuts 08-Sleeve-Camera
  )
  for name in "${expected[@]}"; do
    if [[ ! -s "$SHOTS_TMP/$name.png" ]]; then
      echo "Error: Missing required screenshot: $name" >&2
      exit 1
    fi
  done
  echo "==> Exporting screenshots into AppStore/Screenshots/..."
  for src in "$SHOTS_TMP"/*.png; do
    [[ -e "$src" ]] || continue
    base="$(basename "$src")"
    cp "$src" "$SHOTS_DIR/$base"
    # Resize for App Store Connect 6.9", 6.7", and 6.5" display slots
    sips -z 2868 1320 "$src" --out "$SHOTS_DIR/6.9-inch-1320x2868/$base" >/dev/null
    sips -z 2796 1290 "$src" --out "$SHOTS_DIR/6.7-inch-1290x2796/$base" >/dev/null
    sips -z 2778 1284 "$src" --out "$SHOTS_DIR/6.5-inch-1284x2778/$base" >/dev/null
  done
  echo "    Saved 8 screenshots across native, 6.9\", 6.7\", and 6.5\" resolutions."
fi

if [[ "$MODE" != "--shots-only" ]]; then
  echo "==> Building test runner for App Preview video..."
  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

  RAW_MOV="/tmp/cufftag-preview-raw.mov"
  FINAL_MP4="$VIDEO_DIR/CuffTag-AppPreview-886x1920.mp4"
  FINAL_NATIVE_MP4="$VIDEO_DIR/CuffTag-AppPreview-Native.mp4"
  rm -f "$RAW_MOV" "$FINAL_MP4" "$FINAL_NATIVE_MP4"

  echo "==> Recording App Preview walkthrough..."
  xcrun simctl io "$SIM_UDID" recordVideo --codec=h264 --force "$RAW_MOV" &
  REC_PID=$!

  xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -only-testing:CuffTagUITests/DesignAccessibilityTests/testRecordAppPreviewWalkthrough \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
    -quiet

  kill -INT "$REC_PID" >/dev/null 2>&1 || true
  wait "$REC_PID" 2>/dev/null || true
  REC_PID=""

  if command -v ffmpeg >/dev/null 2>&1 && [[ -f "$RAW_MOV" ]]; then
    echo "==> Post-processing App Preview video (adding required stereo AAC audio track & scaling to 886x1920 @ 30fps)..."
    # Trim the first 1.5s of XCUITest launch banner and cap at 26s (App Store Connect requires 15s-30s)
    ffmpeg -y \
      -ss 1.5 -i "$RAW_MOV" \
      -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
      -t 24 \
      -vf "fps=30,scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=0x0E1630,format=yuv420p" \
      -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 10M \
      -c:a aac -b:a 192k -shortest \
      "$FINAL_MP4" >/dev/null 2>&1

    ffmpeg -y \
      -ss 1.5 -i "$RAW_MOV" \
      -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
      -t 24 \
      -vf "fps=30,format=yuv420p" \
      -c:v libx264 -profile:v high -pix_fmt yuv420p -b:v 12M \
      -c:a aac -b:a 192k -shortest \
      "$FINAL_NATIVE_MP4" >/dev/null 2>&1

    echo "    Saved App Store Connect preview: $FINAL_MP4"
    echo "    Saved native preview:            $FINAL_NATIVE_MP4"
  elif [[ -f "$RAW_MOV" ]]; then
    cp "$RAW_MOV" "$VIDEO_DIR/CuffTag-AppPreview.mov"
    echo "    Saved raw preview video: $VIDEO_DIR/CuffTag-AppPreview.mov"
  fi
fi

echo "==> All App Store media generated in $ROOT_DIR/AppStore/"
