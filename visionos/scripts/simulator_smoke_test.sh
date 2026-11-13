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
#   --app-args "..." extra launch arguments, e.g. "-scenario wrist_trauma_001 -mood nervous -avatar female".
#                   With "-dashboardOnly" the run shows the scenario dashboard only (no session) and
#                   the wrist checks are skipped.
#                   With "-scenario obstetric_ultrasound_001" the run is the obstetric ultrasound demo and the
#                   ultrasound checks replace the wrist checks.
#   --patient-offset X,Y,Z  shift the patient in metres (the simulator camera is fixed;
#                   e.g. 0,0,-1.2 pushes the patient back so the whole body is in frame)
#
# Needs: Xcode with the visionOS simulator runtime (xcodebuild -downloadPlatform visionOS),
# xcodegen, and backend/.venv (see README). Cannot test gaze+pinch, real audio output
# quality, hand tracking or passthrough: those need a person or the headset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KILL=0; BACKEND=1; MOCK_VOICE=0; PROCEDURAL=0; OFFSET=""; APP_ARGS=""; OUT="$ROOT/docs/screenshots"
while [ $# -gt 0 ]; do
  case "$1" in
    --kill-backend) KILL=1 ;;
    --no-backend) BACKEND=0 ;;
    --mock-voice) MOCK_VOICE=1 ;;
    --procedural) PROCEDURAL=1 ;;
    --out) OUT="$2"; shift ;;
    --patient-offset) OFFSET="$2"; shift ;;
    --app-args) APP_ARGS="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

BUNDLE=dev.medsimxr.app
DEVICE_NAME="${MEDSIM_SIM_DEVICE:-MedSimXR Vision Pro}"   # another name = a separate simulator, for parallel runs
# MEDSIM_SMOKE_PORT: run the test backend elsewhere when 8000 is taken (the app is told via a launch argument).
PORT="${MEDSIM_SMOKE_PORT:-8000}"
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
  (cd "$ROOT/backend" && exec .venv/bin/python -m uvicorn app.main:app --port "$PORT" >"$OUT/backend.log" 2>&1) &
  BACKEND_PID=$!
  for _ in $(seq 1 40); do curl -s -m 1 "localhost:$PORT/health" >/dev/null && break; sleep 0.25; done
  curl -s -m 1 "localhost:$PORT/health" >/dev/null || { echo "backend did not start, see $OUT/backend.log" >&2; exit 1; }
fi

echo "== boot + install"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl uninstall "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone $BUNDLE 2>/dev/null || true

ARGS=(-autoDemo -MEDSIM_BACKEND_HOST "localhost:$PORT")
[ $MOCK_VOICE = 1 ] && ARGS+=(-mockVoice)
[ $PROCEDURAL = 1 ] && ARGS+=(-proceduralAvatar)
[ -n "$OFFSET" ] && ARGS+=(-patientOffset "@$OFFSET")
# A LAN host in Config/Local.xcconfig must not decide whether the run is served by the local backend.
[ $BACKEND = 1 ] && ARGS+=(-MEDSIM_BACKEND_HOST localhost:8000)
DASH_ONLY=0; ULTRASOUND=0
if [ -n "$APP_ARGS" ]; then
  read -r -a EXTRA <<<"$APP_ARGS"   # split on spaces: launch arguments never contain any
  ARGS+=("${EXTRA[@]}")
  case " $APP_ARGS " in *" -dashboardOnly "*) DASH_ONLY=1 ;; esac
  case " $APP_ARGS " in *" -scenario obstetric_ultrasound_001 "*) ULTRASOUND=1 ;; esac
fi
echo "== launch ${ARGS[*]}"
xcrun simctl launch "$UDID" $BUNDLE "${ARGS[@]}"
LOG="$(xcrun simctl get_app_container "$UDID" $BUNDLE data)/Documents/smoke.log"

seen=0
for _ in $(seq 1 2400); do   # up to 10 min
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
expect "catalog loaded from the bundle"    "^catalog cases=\[.*wrist_trauma_001"
expect "dashboard was on screen first"     "^STEP 00-dashboard$"
if [ $DASH_ONLY = 1 ]; then
  expect "customize section shown"         "^STEP 00-dashboard-customize$"
  reject "no session started"              "^session "
  SERVICES=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
  if grep -q "$BUNDLE" <<<"$SERVICES"; then echo "  ok   app still running (no crash)"; else echo "  FAIL app is not running (crashed?)"; fail=1; fi
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  echo "screenshots and logs: $OUT"
  [ $fail = 0 ] && echo "SMOKE TEST PASSED (dashboard only)" || { echo "SMOKE TEST FAILED"; exit 1; }
  exit 0
fi
if [ $ULTRASOUND = 1 ]; then
  WANT_MOOD=$(sed -En "s/.*-mood ([A-Za-z0-9_]+).*/\\1/p" <<<" $APP_ARGS ")
  expect "session config logged"             "^session config case=obstetric_ultrasound_001 mood=${WANT_MOOD:-calm} avatar=female model=Patient_pregnant"
  expect "pregnant patient model loaded"     "^avatar variant=Patient_pregnant loaded=Patient_pregnant$"
  if [ $PROCEDURAL = 1 ]; then expect "primitive fallback avatar used" "^avatar procedural"; else expect "recumbent model with a skeleton" "^avatar usdz joints=[1-9]"; fi
  expect "immersive space opened"            "immersive opened=true"
  expect "ultrasound scene built with six regions" "^ultrasound scene built regions=\\[\"abdomen_fundus\", \"abdomen_upper\", \"abdomen_center\", \"abdomen_lower\", \"abdomen_left\", \"abdomen_right\"\\]"
  expect "session: six regions, no wrist zones, patient on the couch" "^session id=.+ regions=\\[.*abdomen_right\"\\] zones=0 state=seated_idle recumbent=true"
  expect "no stand/sit on the couch"         "^sit_down on the couch -> failure"
  expect "scripted greeting spoken"          "audio clip=us_greeting started=true"
  expect "tap with nothing in hand only hints" "^hint=Pick up the probe first.* probe=none"
  expect "dry probe: poor image, no view"    "^scan region=abdomen_upper view=none quality=poor image=none imageFound=false measurements=\\[\\] repeat=1 gel=false"
  expect "gel recorded, patient says cold"   "^gel applied repeat=1 response=\"Ooh, that's a bit cold!\""
  expect "overview image from the engine"    "^scan region=abdomen_center view=overview quality=good image=us_overview imageFound=true .*gel=true"
  expect "head view with the BPD"            "^scan region=abdomen_lower view=head_bpd quality=good image=us_head_bpd imageFound=true measurements=\\[\"BPD 4.61 cm\"\\]"
  expect "heart view"                        "^scan region=abdomen_upper view=heart_4ch quality=good image=us_heart_4ch imageFound=true"
  expect "spine view"                        "^scan region=abdomen_left view=spine quality=good image=us_spine imageFound=true"
  expect "femur view with the FL"            "^scan region=abdomen_right view=femur quality=good image=us_femur imageFound=true measurements=\\[\"FL 3.17 cm\"\\]"
  expect "placenta view"                     "^scan region=abdomen_fundus view=placenta quality=good image=us_placenta imageFound=true"
  expect "same region again cycles the view" "^cycled region=abdomen_fundus view=amniotic_fluid"
  expect "abdomen view with AC and EFW"      "^scan region=abdomen_upper view=abdomen_ac .*measurements=\\[\"AC 13.82 cm\", \"EFW 289 g\"\\]"
  expect "repeat of a view is counted"       "^scan region=abdomen_upper view=heart_4ch .*repeat=2 "
  expect "probe lifted: no contact"          "^probe up: contact=none"
  expect "notebook mutes the microphone"     "^notebook open=true tab=Examination .*mic=Muted"
  expect "scored from the scan record"       "^diagnosed score=95/100 verdict=correct categories=\\[\"communication:40\", \"scanning:35\", \"documentation:20\"\\]"
  expect "views obtained, extras listed"     "obtained=\\[\"head\", \"heart\", \"spine\", \"abdomen\", \"femur\", \"placenta\", \"liquor\""
  expect "no wrist scoring in this case"     "management=0 fitting=0"
  expect "notes checked against the scans"   "notes=\\[.*view_head:documented.*view_femur:documented.*\\]"
  reject "no wrist machinery ran"            "^(fit |standing examine|investigation |lab drop|measure )"
  reject "no missing audio clips"            "audio clip=.* MISSING"
  reject "no image file missing"             "imageFound=false measurements=\\[[^]]"
  reject "no engine errors"                  "error=[^n]"
  expect "demo stopped the session cleanly" "^STEP 07-us-stopped$"
  if [ $MOCK_VOICE = 1 ]; then expect "scripted voice connected, mic live" "^session .*voice=Connected mic=Live"; fi
  if [ $BACKEND = 1 ]; then expect "served by the backend" "^scan region=abdomen_center .*engine=Backend"; fi
  SERVICES=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
  if grep -q "$BUNDLE" <<<"$SERVICES"; then echo "  ok   app still running (no crash)"; else echo "  FAIL app is not running (crashed?)"; fail=1; fi
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  echo "screenshots and logs: $OUT"
  [ $fail = 0 ] && echo "SMOKE TEST PASSED (ultrasound)" || { echo "SMOKE TEST FAILED"; exit 1; }
  exit 0
fi
arg_of() { sed -En "s/.*$1 ([A-Za-z0-9_]+).*/\\1/p" <<<" $APP_ARGS "; }
WANT_CASE=$(arg_of -scenario); WANT_MOOD=$(arg_of -mood); WANT_AVATAR=$(arg_of -avatar)
expect "session config logged"             "^session config case=${WANT_CASE:-wrist_trauma_001} mood=${WANT_MOOD:-calm} avatar=${WANT_AVATAR:-male} model=Patient"
expect "avatar variant resolved or fell back" "^avatar variant=Patient(_female)? loaded=(Patient(_female)?|procedural)$"
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
expect "viewer opened on the result"         "^viewer open=right_wrist_xray"
expect "viewer closed"                        "^viewer closed=true"
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
expect "replay opens after submission"       "^replay started steps=$((EXAMS + 1)) events=.*right_anatomical_snuffbox:script"
expect "replay steps through the exams"      "^replay step=2/$((EXAMS + 1)) zone=(right_anatomical_snuffbox|left_wrist)"
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
