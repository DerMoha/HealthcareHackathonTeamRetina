#!/bin/bash
# Scenario smoke test: launches a published MedSim Studio scenario in the Apple Vision Pro
# simulator and plays the instructor over the Live Director API while the app runs its
# scripted scenario demo (-scenarioDemo). Checks what the app itself logged, plus the
# acknowledgements the backend recorded.
#
#   visionos/scripts/scenario_smoke_test.sh [--variant walkin|clinic] [--out DIR] [--no-build]
#
#   walkin (default)  "Busy walk-in, limited kit (challenging)": no imaging, no medium support,
#                     anxious bystander, noise. Events: helper, noise, equipment delivery (sent
#                     twice with one event id), coaching, and one more while the app's link is down.
#   clinic            "Quiet clinic, full kit (guided)": the same case with everything available.
#   unknown           a launch code that does not exist: the session must not start.
#   offline           a valid code but no backend: the fixed default case must run offline, with a notice.
#   studio            the in-headset Studio window (-studioDemo): overview, marketplace, download a copy,
#                     launch the walk-in scenario from the marketplace, one director event, debrief page.
#
# The two variants are the seeded library entries, so their launch codes are fixed.
# Cannot test: what the room noise and the companion's voice sound like on the headset, whether
# the live voice agent copes with them, gaze and hand input. Those need the device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VARIANT=walkin; OUT=""; BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) VARIANT="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    --no-build) BUILD=0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
case "$VARIANT" in
  walkin) CODE=5344E7; EVENTS_A=4; EVENTS_B=1 ;;
  clinic) CODE=LKGLZX; EVENTS_A=1; EVENTS_B=0 ;;
  unknown) CODE=NOPE00; EVENTS_A=0; EVENTS_B=0 ;;
  offline) CODE=5344E7; EVENTS_A=0; EVENTS_B=0 ;;
  studio) CODE=5344E7; EVENTS_A=0; EVENTS_B=0 ;;
  *) echo "unknown variant $VARIANT" >&2; exit 2 ;;
esac
OUT="${OUT:-$ROOT/docs/screenshots/scenario-$VARIANT}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT"/*.jpg "$OUT"/*.png "$OUT"/*.log "$OUT"/*.json

BUNDLE=dev.medsimxr.app
DEVICE_NAME="${MEDSIM_SIM_DEVICE:-MedSimXR Vision Pro}"   # another name = a separate simulator, for parallel runs
DD="${MEDSIM_DERIVED_DATA:-$ROOT/visionos/build/smoke}"
# MEDSIM_SMOKE_PORT: run the test backend elsewhere when 8000 is taken (the app is told via a launch argument).
PORT="${MEDSIM_SMOKE_PORT:-8000}"
API=http://localhost:$PORT

RUNTIME=$(xcrun simctl list runtimes | grep -E "^(visionOS|xrOS)" | grep -v unavailable | tail -1 | awk '{print $NF}')
[ -n "$RUNTIME" ] || { echo "No visionOS simulator runtime. Install: xcodebuild -downloadPlatform visionOS" >&2; exit 1; }
UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME (" | grep -v unavailable | head -1 | grep -oE "[0-9A-F-]{36}" || true)
if [ -z "$UDID" ]; then
  TYPE=$(xcrun simctl list devicetypes | grep -i "Apple Vision Pro" | head -1 | grep -oE "com\.apple[A-Za-z0-9.-]+")
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$TYPE" "$RUNTIME")
fi

if [ $BUILD = 1 ]; then
  echo "== build"
  (cd "$ROOT/visionos" && xcodegen >/dev/null && xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
    -destination "platform=visionOS Simulator,id=$UDID" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build)
fi
APP="$DD/Build/Products/Debug-xrsimulator/MedSimXR.app"

echo "== backend (fresh scenario library)"
BACKEND_PID=""
cleanup() { [ -n "$BACKEND_PID" ] && kill -9 "$BACKEND_PID" 2>/dev/null || true; }
trap cleanup EXIT
if [ $VARIANT != offline ]; then
  (cd "$ROOT/backend" && MEDSIM_STUDIO_DB="$OUT/library.json" exec .venv/bin/python -m uvicorn app.main:app --port "$PORT" >"$OUT/backend.log" 2>&1) &
  BACKEND_PID=$!
  for _ in $(seq 1 40); do curl -s -m 1 $API/health >/dev/null && break; sleep 0.25; done
  [ $VARIANT = unknown ] || curl -s -m 1 "$API/scenarios/launch/$CODE" | grep -q "\"code\":\"$CODE\"" \
    || { echo "scenario $CODE is not published, see $OUT/backend.log" >&2; exit 1; }
fi

echo "== boot + install"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl uninstall "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone $BUNDLE 2>/dev/null || true
ARGS=(-scenarioDemo -mockVoice -MEDSIM_SCENARIO_CODE "$CODE" -eventsA $EVENTS_A -eventsB $EVENTS_B -patientOffset "@0,0,-1.2")
# The Studio picks the scenario itself, so no launch code is passed.
if [ $VARIANT = studio ]; then ARGS=(-studioDemo -mockVoice -patientOffset "@0,0,-1.2"); fi
ARGS+=(-MEDSIM_BACKEND_HOST "localhost:$PORT")
echo "== launch ${ARGS[*]}"
xcrun simctl launch "$UDID" $BUNDLE "${ARGS[@]}"
LOG="$(xcrun simctl get_app_container "$UDID" $BUNDLE data)/Documents/smoke.log"

fail=0
# The instructor: one director event over HTTP; prints and checks the status code.
send() { # send <expected http status> <kind> [event_id] [item]
  local want="$1" kind="$2" id="${3:-}" item="${4:-}" body
  body="{\"kind\":\"$kind\",\"params\":{${item:+\"item\":\"$item\"}}${id:+,\"event_id\":\"$id\"}}"
  local got
  got=$(curl -s -o "$OUT/last-event.json" -w "%{http_code}" -X POST "$API/sessions/$SID/director/events" -H 'content-type: application/json' -d "$body")
  if [ "$got" = "$want" ]; then echo "  ok   instructor: $kind ${item} -> HTTP $got $(head -c 110 "$OUT/last-event.json")"
  else echo "  FAIL instructor: $kind ${item} -> HTTP $got, expected $want"; fail=1; fi
}

SID=""
seen=0
for _ in $(seq 1 800); do
  if [ -f "$LOG" ]; then
    total=$(wc -l <"$LOG" | tr -d ' ')
    while [ "$seen" -lt "$total" ]; do
      seen=$((seen + 1))
      line=$(sed -n "${seen}p" "$LOG")
      echo "  $line"
      case "$line" in
        "session id="*) SID=$(sed -E 's/^session id=([^ ]+).*/\1/' <<<"$line") ;;
        "STEP s03-await-director")
          xcrun simctl io "$UDID" screenshot "$OUT/s03-before-events.png" >/dev/null 2>&1
          if [ $VARIANT = walkin ]; then
            send 409 bystander_anxious                       # already anxious in this scenario
            send 409 deliver_equipment "" imaging_mri        # this clinic has no imaging
            send 409 patient_deteriorates                    # not a predefined event
            send 200 helper_arrives
            send 200 crowd_noise_up
            send 200 deliver_equipment delivery-1 wrist_support_medium
            send 200 deliver_equipment delivery-1 wrist_support_medium   # same event id again
            send 200 enable_coaching
          elif [ $VARIANT = clinic ]; then
            send 409 bystander_anxious                       # there is no bystander
            send 200 crowd_noise_up
          fi ;;
        "STEP t06-await-director")
          send 200 helper_arrives ;;
        "STEP s05-link-dropped")
          sleep 1; send 200 crowd_noise_up while-down-1 ;;   # the app is disconnected right now
        STEP*) xcrun simctl io "$UDID" screenshot "$OUT/${line#STEP }.png" >/dev/null 2>&1 ;;
        DONE) break 2 ;;
      esac
    done
  fi
  sleep 0.25
done
cp "$LOG" "$OUT/smoke.log" 2>/dev/null || true
if [ -n "$BACKEND_PID" ] && [ -n "$SID" ] && [ "$SID" != none ]; then
  curl -s "$API/sessions/$SID/director" >"$OUT/director-state.json" || true
  curl -s "$API/sessions/$SID/debrief" >"$OUT/debrief.json" || true
  if [ $VARIANT = studio ]; then curl -s "$API/studio/scenarios" >"$OUT/library-rows.json" || true; fi
fi
for f in "$OUT"/*.png; do
  [ -e "$f" ] || continue
  sips -s format jpeg -s formatOptions 80 -Z 1920 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 && rm "$f"
done
rm -f "$OUT/last-event.json" "$OUT/library.json"

echo "== checks ($VARIANT)"
expect() { if grep -qE "$2" "$OUT/smoke.log"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
reject() { if grep -qE "$2" "$OUT/smoke.log"; then echo "  FAIL $1"; fail=1; else echo "  ok   $1"; fi; }
count() { if [ "$(grep -cE "$2" "$OUT/smoke.log")" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (expected $3)"; fail=1; fi; }
state() { if python3 -c "import json,sys; d=json.load(open('$OUT/$2')); sys.exit(0 if ($3) else 1)" 2>/dev/null; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }

expect "demo ran to the end"                 "^DONE$"
if [ $VARIANT = studio ]; then expect "immersive space opened" "immersive=true"; else expect "immersive space opened" "immersive opened=true"; fi
if [ $VARIANT = unknown ]; then
  expect "unknown code is an error"          "^scenario code=NOPE00 unknown, session not started"
  expect "no session, not the default case"  "^session id=none scenario=none phase=idle notice=none error=No published scenario with code NOPE00"
  reject "nothing was examined"              "^examined "
elif [ $VARIANT = studio ]; then
  expect "Studio window opened on the overview" "^studio window shown tab=overview"
  expect "Studio read library and marketplace" "^studio opened library=2 market=.*5344E7.* error=none"
  expect "marketplace copy is a draft in Downloaded" "^studio downloaded tab=downloaded copy=[a-z0-9_]+ state=draft published=false inMine=false"
  expect "launched from the Studio"          "^studio launch code=5344E7 phase=running scenario=5344E7 error=none"
  expect "Studio shows the session page"     "^studio switched to session tab"
  expect "session runs the chosen scenario"  "^session id=.+ scenario=5344E7 phase=running immersive=true error=none"
  expect "director link connected"           "^director link connected"
  expect "event applied in the app"          "^director applied seq=[0-9]+ kind=helper_arrives .*helper=true"
  expect "the event reached the app"         "^director events seen=1 "
  expect "score computed"                    "^diagnosed score=[0-9]+/100"
  expect "Studio debrief shows the session"  "^studio debrief shown code=5344E7 interventions=1 acknowledged=1 score=[0-9]+/100 resources=[0-9]+"
  reject "no engine errors"                  "error=[^n]"
  state  "backend: the download is an unpublished draft" library-rows.json "any((r['origin'] or {}).get('code')=='5344E7' and r['review_state']=='draft' and r['published_version'] is None for r in d)"
  state  "backend recorded the acknowledged event" director-state.json "len(d['interventions'])==1 and d['interventions'][0]['acknowledged']"
elif [ $VARIANT = offline ]; then
  expect "default case runs offline, with a notice" "^session id=.+ scenario=none phase=running notice=Scenario 5344E7 needs the backend, which is not reachable. Running the fixed default case offline. error=none"
  expect "same finding from the offline engine" "^examined right_anatomical_snuffbox finding=marked_tenderness pain=8 engine=Offline"
  expect "default case keeps its full kit"   "^order right_wrist_xray -> success.* results=1"
  expect "scored offline"                    "^diagnosed score=[0-9]+/100 "
  reject "no scenario features pretended"    "^(scenario code|director link connected|hint policy)"
  expect "no scenario debrief offline"       "^debrief loaded=false"
else
expect "session runs the selected scenario"  "^session id=.+ scenario=$CODE phase=running notice=none error=none"
expect "same finding as the default case"    "^examined right_anatomical_snuffbox finding=marked_tenderness pain=8 engine=Backend"
expect "director link connected"             "^director link connected"
expect "score computed"                      "^diagnosed score=[0-9]+/100 "
expect "debrief loaded in the app"           "^debrief loaded=true"
reject "no engine errors"                    "error=[^n]"
fi
if [ $VARIANT = walkin ]; then
  expect "scenario shaped the session"       "^scenario code=5344E7 .*env=community_clinic difficulty=challenging hints=off noise=0.60 bystander=anxious helper=false crowd=4 sizes=\[\"small\", \"large\"\] tape=true investigations=\[\] engine=Backend"
  expect "room built from the scenario"      "^stage sign=community_clinic figures=5 bystander=anxious helper=false noise=0.60 noisePlaying=true"
  expect "bystander spoke up unprompted"     "^scene line speaker=Sam shown=true"
  expect "imaging cannot be ordered here"    "^order right_wrist_xray -> failure: Unknown investigation.* results=0"
  expect "no coaching before the instructor allows it" "^hint before events=none"
  expect "event: helper in the room"         "^director applied seq=[0-9]+ kind=helper_arrives .*helper=true"
  expect "helper announced themselves"       "^scene line speaker=Kim shown=true"
  expect "event: louder, more people"        "^director applied seq=[0-9]+ kind=crowd_noise_up .*figures=7 .*noise=0.85 noisePlaying=true"
  expect "event: medium support on the tray" "^director applied seq=[0-9]+ kind=deliver_equipment .*sizes=\[\"small\", \"medium\", \"large\"\]"
  count  "repeated event id applied once"    "^director applied .*kind=deliver_equipment" 1
  expect "event: coaching on request"        "^director applied seq=[0-9]+ kind=enable_coaching .*hints=on_request"
  expect "all four events reached the app"   "^director events seen=4 expected=4"
  expect "coaching available afterwards"     "^hint after events=[A-Z]"
  expect "events changed no examination"     "^director applied .*kind=enable_coaching .*exams=1 "
  expect "link dropped"                      "^director link lost"
  count  "link reconnected on its own"       "^director link connected" 2
  expect "event sent while down arrived after reconnect" "^director applied seq=[0-9]+ kind=crowd_noise_up event=while-down-1 .*noise=1.00"
  expect "five events in total"              "^director events seen=5 expected=5"
  expect "delivered support could be fitted" "^fitted medium "
  expect "debrief: interventions and hints"  "^debrief loaded=true interventions=5 acknowledged=5 hints=1 "
  expect "debrief: score read against constraints" "^debrief note: Investigation and management: [0-9]+ of 11 achievable points"
  expect "debrief: not clinician-reviewed"   "^debrief note: This scenario is experimental, not clinician-reviewed"
  state  "backend recorded 5 acknowledged interventions" director-state.json "len(d['interventions'])==5 and all(i['acknowledged'] and i['ack_detail'].startswith('applied: sign=') for i in d['interventions'])"
  state  "backend debrief lists the delivered support as used" debrief.json "[r for r in d['resources'] if r['id']=='wrist_support_medium'][0]['used'] and [r for r in d['resources'] if r['id']=='wrist_support_medium'][0]['delivered_at_seq']"
elif [ $VARIANT = clinic ]; then
  expect "scenario shaped the session"       "^scenario code=LKGLZX .*env=outpatient_clinic difficulty=guided hints=auto noise=0.00 bystander=none helper=false crowd=0 sizes=\[\"small\", \"medium\", \"large\"\] tape=true investigations=\[\"right_wrist_xray\", \"right_wrist_mri\", \"right_wrist_ct\"\] engine=Backend"
  expect "quiet room, nobody else"           "^stage sign=outpatient_clinic figures=0 bystander=none helper=false noise=0.00 noisePlaying=false"
  reject "no companion lines"                "^scene line"
  expect "imaging can be ordered"            "^order right_wrist_xray -> success.* results=1"
  expect "guided: coaching from the start"   "^hint policy=auto text=\"Start by introducing yourself"
  expect "event: noise starts"               "^director applied seq=[0-9]+ kind=crowd_noise_up .*noise=0.25 noisePlaying=true"
  expect "the event reached the app"         "^director events seen=1 expected=1"
  expect "full kit: medium support fitted"   "^fitted medium "
  expect "debrief: one intervention"         "^debrief loaded=true interventions=1 acknowledged=1 "
  state  "backend: nothing unassessable"     debrief.json "d['scores']['management']['achievable_max']==20 and d['scores']['fitting']['achievable_max']==20"
fi
SERVICES=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
if grep -q "$BUNDLE" <<<"$SERVICES"; then echo "  ok   app still running (no crash)"; else echo "  FAIL app is not running (crashed?)"; fail=1; fi
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true

echo "screenshots and logs: $OUT"
[ $fail = 0 ] && rm -f "$OUT/backend.log"   # only worth keeping when something failed
[ $fail = 0 ] && echo "SCENARIO SMOKE TEST PASSED ($VARIANT)" || { echo "SCENARIO SMOKE TEST FAILED ($VARIANT)"; exit 1; }
