#!/bin/bash
# Simulator smoke test: builds MedSimXR, boots an Apple Vision Pro simulator, runs the
# app's scripted demo (-autoDemo) against a local backend, captures screenshots at each
# step and checks the runtime evidence the app writes to Documents/smoke.log.
#
#   visionos/scripts/simulator_smoke_test.sh [--kill-backend] [--no-backend] [--mock-voice] [--out DIR]
#
#   --kill-backend  kill the backend mid-session; the run must finish on the offline engine
#   --no-backend    never start a backend (pure offline run)
#   --mock-voice    use the deterministic scripted voice instead of ElevenLabs
#   --out DIR       screenshot/log directory (default docs/screenshots)
#   --patient-offset X,Y,Z  shift the patient in metres (the simulator camera is fixed;
#                   e.g. 0,0,-1.2 pushes the patient back so the whole body is in frame)
#
# Needs: Xcode with the visionOS simulator runtime (xcodebuild -downloadPlatform visionOS),
# xcodegen, and backend/.venv (see README). Cannot test gaze+pinch, real audio output
# quality, hand tracking or passthrough: those need a person or the headset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KILL=0; BACKEND=1; MOCK_VOICE=0; OFFSET=""; OUT="$ROOT/docs/screenshots"
while [ $# -gt 0 ]; do
  case "$1" in
    --kill-backend) KILL=1 ;;
    --no-backend) BACKEND=0 ;;
    --mock-voice) MOCK_VOICE=1 ;;
    --out) OUT="$2"; shift ;;
    --patient-offset) OFFSET="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

BUNDLE=dev.medsimxr.app
DEVICE_NAME="MedSimXR Vision Pro"
DD="${MEDSIM_DERIVED_DATA:-$ROOT/visionos/build/smoke}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"   # absolute: later steps run from other directories

RUNTIME=$(xcrun simctl list runtimes | grep -E "^(visionOS|xrOS)" | grep -v unavailable | tail -1 | awk '{print $NF}')
[ -n "$RUNTIME" ] || { echo "No visionOS simulator runtime. Install: xcodebuild -downloadPlatform visionOS" >&2; exit 1; }

UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME (" | grep -v unavailable | head -1 | grep -oE "[0-9A-F-]{36}" || true)
if [ -z "$UDID" ]; then
  TYPE=$(xcrun simctl list devicetypes | grep -i "Apple Vision Pro" | head -1 | grep -oE "com\.apple[A-Za-z0-9.-]+")
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$TYPE" "$RUNTIME")
fi
echo "runtime $RUNTIME, device $UDID"

echo "== build"
(cd "$ROOT/visionos" && xcodegen >/dev/null && xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
  -destination "platform=visionOS Simulator,id=$UDID" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build)
APP="$DD/Build/Products/Debug-xrsimulator/MedSimXR.app"

BACKEND_PID=""
cleanup() { [ -n "$BACKEND_PID" ] && kill -9 "$BACKEND_PID" 2>/dev/null || true; }
trap cleanup EXIT
if [ $BACKEND = 1 ]; then
  echo "== backend"
  (cd "$ROOT/backend" && exec .venv/bin/python -m uvicorn app.main:app --port 8000 >"$OUT/backend.log" 2>&1) &
  BACKEND_PID=$!
  for _ in $(seq 1 40); do curl -s -m 1 localhost:8000/health >/dev/null && break; sleep 0.25; done
  curl -s -m 1 localhost:8000/health >/dev/null || { echo "backend did not start, see $OUT/backend.log" >&2; exit 1; }
fi

echo "== boot + install"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl uninstall "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone $BUNDLE 2>/dev/null || true

ARGS=(-autoDemo)
[ $MOCK_VOICE = 1 ] && ARGS+=(-mockVoice)
[ -n "$OFFSET" ] && ARGS+=(-patientOffset "@$OFFSET")
echo "== launch ${ARGS[*]}"
xcrun simctl launch "$UDID" $BUNDLE "${ARGS[@]}"
LOG="$(xcrun simctl get_app_container "$UDID" $BUNDLE data)/Documents/smoke.log"

seen=0
for _ in $(seq 1 480); do   # up to 120 s
  if [ -f "$LOG" ]; then
    total=$(wc -l <"$LOG" | tr -d ' ')
    while [ "$seen" -lt "$total" ]; do
      seen=$((seen + 1))
      line=$(sed -n "${seen}p" "$LOG")
      echo "  $line"
      case "$line" in
        "STEP 04-pain")
          # the flinch peaks within ~0.8 s of the examination that follows this cue
          for i in 1 2 3 4; do xcrun simctl io "$UDID" screenshot "$OUT/04-pain-$i.png" >/dev/null 2>&1; done ;;
        "STEP 05-killwindow")
          xcrun simctl io "$UDID" screenshot "$OUT/05-killwindow.png" >/dev/null 2>&1
          if [ $KILL = 1 ] && [ -n "$BACKEND_PID" ]; then kill -9 "$BACKEND_PID"; BACKEND_PID=""; echo "  (backend killed)"; fi ;;
        STEP*) xcrun simctl io "$UDID" screenshot "$OUT/${line#STEP }.png" >/dev/null 2>&1 ;;
        DONE) break 2 ;;
      esac
    done
  fi
  sleep 0.25
done
cp "$LOG" "$OUT/smoke.log" 2>/dev/null || true
# 4K PNGs are ~6 MB each: keep reviewable JPEGs instead
for f in "$OUT"/*.png; do
  [ -e "$f" ] || continue
  sips -s format jpeg -s formatOptions 80 -Z 1920 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 && rm "$f"
done

echo "== checks"
fail=0
expect() { if grep -qE "$2" "$OUT/smoke.log"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
reject() { if grep -qE "$2" "$OUT/smoke.log"; then echo "  FAIL $1"; fail=1; else echo "  ok   $1"; fi; }
expect "demo ran to the end"               "^DONE$"
expect "immersive space opened"            "immersive opened=true"
expect "patient scene built with 3 zones"  "immersive scene built zones=3|zones rebuilt .*right_anatomical_snuffbox"
expect "session created with 3 zones"      "^session id=.+ zones=\[\"right_anatomical_snuffbox\", \"right_distal_forearm\", \"left_wrist\"\]"
expect "left wrist: normal, no animation"  "examined left_wrist finding=normal pain=0 animation=none"
expect "snuffbox: tenderness + withdrawal" "examined right_anatomical_snuffbox finding=marked_tenderness pain=8 animation=arm_withdrawal"
expect "arm withdrawal animation started"  "^animation arm_withdrawal"
expect "an audio clip actually started"    "audio clip=.* started=true"
expect "examined zone flashed red"         "zone flash right_anatomical_snuffbox painful=true"
reject "no missing audio clips"            "audio clip=.* MISSING"
expect "feedback locked before diagnosis"  "pre-diagnosis feedback verdict=not_submitted criteria=\[0, 0, 0, 0\]"
expect "diagnosis scored as correct"       "diagnosed score=[0-9]+/100 verdict=correct"
expect "reset cleared the session"         "reset feedback=cleared .*exams=0 turns=0"
reject "no engine errors"                  "error=[^n]"
if [ $MOCK_VOICE = 1 ]; then
  expect "scripted voice connected, mic live" "^session .*voice=Connected mic=Live"
  expect "exam reaction left to the agent"    "examined right_anatomical_snuffbox .*speakLocally=false"
  expect "pain clip played instantly"         "audio clip=ouch started=true"
fi
if [ $KILL = 1 ]; then
  expect "fell back to offline after kill" "examined right_distal_forearm .*engine=Offline .*exams=3 "
elif [ $BACKEND = 1 ]; then
  expect "served by the backend"           "examined right_distal_forearm .*engine=Backend"
fi
# capture first: with pipefail, `grep -q` closing the pipe early would read as a failure
SERVICES=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
if grep -q "$BUNDLE" <<<"$SERVICES"; then echo "  ok   app still running (no crash)"; else echo "  FAIL app is not running (crashed?)"; fail=1; fi
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true

echo "screenshots and logs: $OUT"
[ $fail = 0 ] && echo "SMOKE TEST PASSED" || { echo "SMOKE TEST FAILED"; exit 1; }
