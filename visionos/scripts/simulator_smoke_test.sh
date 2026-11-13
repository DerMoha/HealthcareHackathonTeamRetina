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
#   --procedural    force the primitive fallback avatar instead of Patient.usdz
#   --out DIR       screenshot/log directory (default docs/screenshots)
#   --patient-offset X,Y,Z  shift the patient in metres (the simulator camera is fixed;
#                   e.g. 0,0,-1.2 pushes the patient back so the whole body is in frame)
#
# Needs: Xcode with the visionOS simulator runtime (xcodebuild -downloadPlatform visionOS),
# xcodegen, and backend/.venv (see README). Cannot test gaze+pinch, real audio output
# quality, hand tracking or passthrough: those need a person or the headset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KILL=0; BACKEND=1; MOCK_VOICE=0; PROCEDURAL=0; OFFSET=""; OUT="$ROOT/docs/screenshots"
while [ $# -gt 0 ]; do
  case "$1" in
    --kill-backend) KILL=1 ;;
    --no-backend) BACKEND=0 ;;
    --mock-voice) MOCK_VOICE=1 ;;
    --procedural) PROCEDURAL=1 ;;
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
[ $PROCEDURAL = 1 ] && ARGS+=(-proceduralAvatar)
[ -n "$OFFSET" ] && ARGS+=(-patientOffset "@$OFFSET")
echo "== launch ${ARGS[*]}"
xcrun simctl launch "$UDID" $BUNDLE "${ARGS[@]}"
LOG="$(xcrun simctl get_app_container "$UDID" $BUNDLE data)/Documents/smoke.log"

seen=0
for _ in $(seq 1 1000); do   # up to 250 s
  if [ -f "$LOG" ]; then
    total=$(wc -l <"$LOG" | tr -d ' ')
    while [ "$seen" -lt "$total" ]; do
      seen=$((seen + 1))
      line=$(sed -n "${seen}p" "$LOG")
      echo "  $line"
      case "$line" in
        "STEP 04-pain"|"STEP 03-sitting")
          # a burst: the flinch peaks within ~0.8 s, sitting down takes ~1.8 s
          for i in 1 2 3 4; do xcrun simctl io "$UDID" screenshot "$OUT/${line#STEP }-$i.png" >/dev/null 2>&1; done ;;
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
if [ $PROCEDURAL = 1 ]; then expect "primitive fallback avatar used" "^avatar procedural"; else expect "realistic patient model loaded" "^avatar usdz joints=[1-9]"; fi
expect "notebook opened"                   "^notebook open=true"
expect "notes checked against the record"  "notes=\[.*examined_snuffbox:documented.*\]"
expect "unsupported note flagged"          "notes=\[.*associated_symptoms:unsupported.*\]"
expect "diagnosis scored as correct"       "diagnosed score=[0-9]+/100 verdict=correct"
expect "reset cleared session and notes"    "reset feedback=cleared notes=blank .*exams=0 turns=[01] "
expect "new encounter starts the body over"  "^behavior reset state=(standing_idle|seated_idle)"
if [ $PROCEDURAL = 1 ]; then
  expect "fallback body: arm pose fails honestly" "^action extend_both_arms -> failure"
else
  expect "no examination while standing"     "^standing examine state=standing_idle .*exams=0 "
  expect "sat down on request"               "^behavior sitting_down -> seated_idle"
  expect "repeated sit request is a no-op"   "^action sit_down -> success: Alex is already seated"
  expect "movement is not an examination"    "^action extend_both_arms -> success.* exams=0 "
  expect "interrupted extension recovered"   "^behavior returning_to_rest -> extending_arms"
  expect "arms extended"                     "^behavior extending_arms -> arms_extended"
  expect "zones followed the wrist"          "^pose arms_extended right_wrist moved=0\.[1-9]"
  expect "indicated the wrist, then returned" "^behavior indicating_wrist -> returning_to_rest"
  expect "recoil from the examination pose"  "^behavior arms_extended -> pain_recoil"
  expect "examination pose restored, one exam recorded per touch" "^after recoil state=arms_extended .*exams=2 "
fi
expect "X-ray result came from the engine"   "^investigation right_wrist_xray impression=\"No definite fracture visible.\" image=wrist_xray_pa imageFound=true"
expect "viewer opened on the result"         "^viewer open=right_wrist_xray notebook=true"
expect "back to notebook, Investigations tab" "^viewer closed=true tab=Investigations"
expect "management scored separately"        "diagnosed score=[0-9]+/100 .*management=20/20"
expect "MRI is a labelled report without image" "^investigation right_wrist_mri .*image=none imageFound=false"
reject "X-ray order reveals nothing else"    "^investigation right_wrist_xray .*(scaphoid|MRI)"
expect "wrist girth from case data"          "^measure right_wrist_circumference value=16.8 source=case"
expect "forearm length from the skeleton"    "^measure right_forearm_length value=[1-3][0-9]\.[0-9] source=avatar"
expect "far drop does not snap"              "^lab drop orthosis_large .*snapped=false"
expect "far drop fits nothing"               "^missed drop fit=none"
expect "near drop snaps to the forearm"      "^lab drop orthosis_large .*snapped=true"
expect "too large: patient says it slides"   "^check comfort phase=after comfortable=false response=\"It's loose. It slides"
expect "after adjusting: comfortable"        "^check comfort phase=after comfortable=true"
# the fallback body starts seated, so its early examination attempt counts too
if [ $PROCEDURAL = 1 ]; then EXAMS=4; else EXAMS=3; fi
expect "fitting changed no examinations"     "^fitted medium snug thumb_radial .*exams=$EXAMS "
expect "fitting scored separately"           "diagnosed score=[0-9]+/100 .*fitting=20/20"
expect "pinch placement snaps to the forearm" "^lab drop orthosis_large via=pinch .*snapped=true"
expect "patient speaks up unprompted: too large" "^fit reaction unprompted response=\"It's loose. It slides"
expect "patient speaks up unprompted: too tight" "^fit reaction unprompted response=\"That's too tight"
# three different problems (too large, loose straps, too tight) over seven adjustments: three remarks
if [ "$(grep -c '^fit reaction unprompted' "$OUT/smoke.log")" = 3 ]; then echo "  ok   one remark per problem, none repeated while adjusting"; else echo "  FAIL unprompted remarks: expected exactly 3"; fail=1; fi
expect "replay opens after submission"       "^replay started steps=4 events=.*right_anatomical_snuffbox:script"
expect "replay steps through the exams"      "^replay step=2/4 zone=right_anatomical_snuffbox"
expect "replay ends on the support, with reference" "^teaching anatomy=false reference=medium"
expect "anatomy overlay on request"          "^teaching anatomy=true reference=medium"
expect "replay can be left"                  "^replay exited teaching=false notebook=true"
reject "no engine errors"                  "error=[^n]"
if [ $MOCK_VOICE = 1 ]; then
  expect "scripted voice connected, mic live" "^session .*voice=Connected mic=Live"
  expect "exam reaction left to the agent"    "examined right_anatomical_snuffbox .*speakLocally=false"
  expect "pain clip played instantly"         "audio clip=ouch started=true"
  expect "notebook mutes the microphone"      "^notebook open=true .*mic=Muted"
  expect "spoken order reached the engine"    "^heard \"I would like to order an X-ray of his right wrist.\" order=right_wrist_xray result=success"
  [ $PROCEDURAL = 1 ] || expect "spoken request triggered the action" "^heard \"Please have a seat.\" action=sit_down result=success"
fi
if [ $KILL = 1 ]; then
  expect "fell back to offline after kill" "examined right_distal_forearm .*engine=Offline .*exams=3 "
  expect "fitting served offline"          "^fit size=medium .*engine=Offline"
  expect "investigation served offline"    "^investigation right_wrist_xray .*engine=Offline"
elif [ $BACKEND = 1 ]; then
  expect "served by the backend"           "examined right_distal_forearm .*engine=Backend"
fi
# capture first: with pipefail, `grep -q` closing the pipe early would read as a failure
SERVICES=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
if grep -q "$BUNDLE" <<<"$SERVICES"; then echo "  ok   app still running (no crash)"; else echo "  FAIL app is not running (crashed?)"; fail=1; fi
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true

echo "screenshots and logs: $OUT"
[ $fail = 0 ] && echo "SMOKE TEST PASSED" || { echo "SMOKE TEST FAILED"; exit 1; }
