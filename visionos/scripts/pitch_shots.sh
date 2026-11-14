#!/bin/bash
# Pitch screenshots: builds MedSimXR, boots the Apple Vision Pro simulator and plays the staged
# pitch scenes (launch argument -pitch, Views/PitchScenes.swift), one case per launch, taking a
# screenshot at each scene.
#
#   visionos/scripts/pitch_shots.sh                      all scenes of all three cases
#   visionos/scripts/pitch_shots.sh --case us            one case: wrist | us | rt
#   visionos/scripts/pitch_shots.sh --hold wrist-04-xray stop at one scene and leave it on screen,
#                                                        to frame and screenshot by hand (Cmd+S in Simulator)
#   --no-build   reuse the last build      --out DIR   default docs/screenshots/pitch
#   --env forest  the road-trauma case on a forest trail (-pitchEnv forest); shots get a -forest suffix
#
# Scenes: wrist-01-in-your-room wrist-02-conversation wrist-03-pain-reaction wrist-04-xray
#         wrist-05-orthotics-lab wrist-06-notebook wrist-07-feedback wrist-08-replay-anatomy
#         us-01-greeting us-02-head-bpd us-03-heart us-04-overview us-05-feedback
#         rt-01-roadside rt-02-crew rt-03-splinted rt-04-ambulance rt-05-resus rt-06-xray
#         rt-07-team-log rt-08-feedback
#         adapt (heart-rate adaptive difficulty concept, -pitchAdaptive): adapt-01-steady adapt-02-harder
#                 adapt-03-easier adapt-04-debrief
#         studio (alias vp): vp-01-marketplace vp-02-download vp-03-scenario-detail vp-04-library-ready
# Runs offline with the scripted voice: no backend, no ElevenLabs credits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/screenshots/pitch"; ENV=""; SUFFIX=""; BUILD=1; HOLD=""; CASES="wrist us rt studio"
while [ $# -gt 0 ]; do
  case "$1" in
    --case) CASES="$2"; shift ;;
    --hold) HOLD="$2"; CASES="${2%%-*}"; shift ;;
    --out) OUT="$2"; shift ;;
    --no-build) BUILD=0 ;;
    --env) ENV="$2"; SUFFIX="-$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

BUNDLE=dev.medsimxr.app
DEVICE_NAME="${MEDSIM_SIM_DEVICE:-MedSimXR Vision Pro}"
DD="${MEDSIM_DERIVED_DATA:-$ROOT/visionos/build/smoke}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME (" | grep -v unavailable | head -1 | grep -oE "[0-9A-F-]{36}" || true)
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -E "^(visionOS|xrOS)" | grep -v unavailable | tail -1 | awk '{print $NF}')
  TYPE=$(xcrun simctl list devicetypes | grep -i "Apple Vision Pro" | head -1 | grep -oE "com\.apple[A-Za-z0-9.-]+")
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$TYPE" "$RUNTIME")
fi
if [ $BUILD = 1 ]; then
  echo "== build"
  (cd "$ROOT/visionos" && xcodegen >/dev/null && xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
    -destination "platform=visionOS Simulator,id=$UDID" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build)
fi
APP="$DD/Build/Products/Debug-xrsimulator/MedSimXR.app"
xcrun simctl bootstatus "$UDID" -b >/dev/null
[ -n "$HOLD" ] && { open -a Simulator --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true; }   # optional: screenshots work headless

for c in $CASES; do
  case "$c" in
    wrist) SCENARIO=wrist_trauma_001; OFFSET="-0.45,0.4,0" ;;   # centred (no main window), raised: the fixed camera looks level, the patient sits low
    us) SCENARIO=obstetric_ultrasound_001; OFFSET="0,0.15,0" ;;   # the couch has its own placement
    rt|adapt) SCENARIO=road_trauma_journey_001; OFFSET="-0.45,0.2,-0.3" ;;
    studio|vp) SCENARIO=wrist_trauma_001; OFFSET="0,0,0" ;;   # the Vision Pro Studio window, no immersive space
    *) echo "unknown case $c (wrist | us | rt | adapt | studio)" >&2; exit 2 ;;
  esac
  echo "== $c"
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  xcrun simctl uninstall "$UDID" $BUNDLE 2>/dev/null || true   # fresh app data: a clean smoke.log
  xcrun simctl install "$UDID" "$APP"
  ARGS=(-pitch -mockVoice -scenario "$SCENARIO" -mood calm -patientOffset "@$OFFSET" -MEDSIM_BACKEND_HOST 127.0.0.1:9)
  [ -n "$HOLD" ] && ARGS+=(-pitchHold "$HOLD")
  [ -n "$ENV" ] && ARGS+=(-pitchEnv "$ENV")
  case "$c" in studio|vp) ARGS+=(-pitchStudio) ;; adapt) ARGS+=(-pitchAdaptive) ;; esac
  xcrun simctl launch "$UDID" $BUNDLE "${ARGS[@]}" >/dev/null
  LOG="$(xcrun simctl get_app_container "$UDID" $BUNDLE data)/Documents/smoke.log"
  seen=0
  for _ in $(seq 1 1200); do   # up to 5 min per case
    if [ -f "$LOG" ]; then
      total=$(wc -l <"$LOG" | tr -d ' ')
      while [ "$seen" -lt "$total" ]; do
        seen=$((seen + 1)); line=$(sed -n "${seen}p" "$LOG")
        case "$line" in
          "STEP "*) name=${line#STEP }$SUFFIX; xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
                    sips -s format jpeg -s formatOptions 90 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null 2>&1 && rm "$OUT/$name.png"
                    echo "  $name.jpg" ;;
          "HOLD "*) echo "holding ${line#HOLD } in the Simulator: frame it and press Cmd+S. Ctrl+C here when done."; exit 0 ;;
          DONE) break 2 ;;
        esac
      done
    fi
    sleep 0.25
  done
done
echo "screenshots: $OUT"
