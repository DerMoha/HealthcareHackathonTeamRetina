# Pitch screenshots

All images are 3840×2160 (web Studio: 2880×1800). Files without a suffix are the recommended pick; `-b`, `-forest`, `-nohand` and `-crop` are alternatives for the same slide, so a weak image can be swapped without re-shooting anything.

## By pitch point

| Pitch point | Recommended | Alternatives |
|---|---|---|
| Title slides (Blender renders) | `hero-01-clinic`, `hero-02-roadside`, `hero-03-ultrasound` | `hero-0N-*-b` (other camera) |
| You talk to the patient by voice | `wrist-02-conversation`, `wrist-03-pain-reaction` | `us-01-greeting`, `us-03-heart`, `rt-01-roadside` |
| Your own notebook | `wrist-06-notebook` | `us-04b-notebook`, `rt-07-team-log` |
| Scored against what the case expects | `wrist-07-feedback` (OSCE station mark scheme, 78/100) | `us-05-feedback` (mid-trimester anomaly-scan checklist, 74/100), `rt-08-feedback` (<C>ABCDE + ATMIST + open-fracture standard + "Under distraction", 79/100) |
| Crowd, stress, interruptions | `rt-02-crew` | `rt-01-roadside`, `rt-03-splinted`, `rt-04-ambulance` |
| Heart-rate adaptive difficulty (concept, staged) | `adapt-02-harder`, `adapt-03-easier` | `adapt-01-steady` (baseline), `adapt-04-debrief` (heart rate over the case), `adapt-collage.png` (the four heart-rate panels cut out, 2×2, on the deck's background) |
| Mix and match: same case, other place | `rt-01-roadside-forest` | `rt-02-crew-forest`, `rt-03-splinted-forest` |
| Scenario generator (browser) | `studio-web-01-generator` | `-b` |
| AI scenario author (browser) | `studio-web-02-ai-author` | `-b` |
| Publish (browser) | `studio-web-03-publish` | `-b` |
| Marketplace (browser) | `studio-web-04-marketplace` | `-b` |
| Marketplace on Vision Pro | `vp-01-marketplace-crop` | `vp-01-marketplace` (whole room) |
| Download to the headset | `vp-02-download-crop` | `vp-02-download` |
| Scenario mix and scoring on the headset | `vp-03-scenario-detail-crop` | `vp-03-scenario-detail` |
| Ready to play in the library | `vp-04-library-ready-crop` | `vp-04-library-ready` |

## By case

- **Alex, 28, wrist after a bicycle fall (fracture clinic):** `wrist-01` in your own room (mixed reality) → `02` conversation → `03` pain on snuffbox palpation → `04` X-ray → `05` splint fitting → `06` notebook → `07` debrief → `08` spatial replay with anatomy.
- **Sarah, 31, 20-week anomaly scan:** `us-01` greeting and ID check → `02` head/BPD → `03` four-chamber heart → `04` overview → `04b` notebook with the scan checklist → `05` debrief. `-nohand` versions show the probe without the learner's gloved hand.
- **Jordan, 34, cyclist with an open forearm fracture (3-stage journey):** `rt-01..03` at the roadside with bystanders and crew → `04` in the ambulance (`04-ambulance-b`: no EMT in the seat) → `05..08` resus bay: team, X-ray, team log, debrief. The same case on a forest trail with hikers: `rt-0N-*-forest`.

- **Heart-rate adaptive difficulty (concept, Jordan at the roadside):** `adapt-01` in the zone (104 bpm, the scene as designed) → `02` too easy, so the sim pushes (72 bpm: three more bystanders shouting, Jordan slumped and drifting off, louder scene, "Crowd 7 · Distraction max") → `03` overloaded, so it eases off (148 bpm: EMT Lena gives a hint, police move two bystanders back, quieter, Jordan holds still) → `04` debrief with the heart rate over 12 minutes and where the sim adjusted. Nothing reads a watch: all numbers are staged, so label these "Concept" in the deck.

## Re-shooting one scene

From the repo root, with Xcode and the visionOS simulator installed. Nothing needs a backend or voice credits.

```sh
visionos/scripts/pitch_shots.sh --case wrist            # one case: wrist | us | rt | studio  (2–5 min)
visionos/scripts/pitch_shots.sh --case rt --env forest  # forest variant, writes rt-*-forest.jpg
visionos/scripts/pitch_shots.sh --case adapt            # heart-rate adaptive difficulty concept, adapt-01..04
SIMCTL_CHILD_PITCH_HAND=off visionos/scripts/pitch_shots.sh --case us --out /tmp/nohand   # probe without the hand
visionos/scripts/pitch_shots.sh --hold wrist-07-feedback  # stop at one scene and leave it on screen to frame by hand
cd studio && node scripts/pitch_shots.mjs marketplace   # web Studio pages (refreshes their cover images from this folder first)
assets/pitch_hero/render_heroes.sh clinic               # Blender title renders (slow; composite.py alone redraws the panels)
```

Add `--no-build` to reuse the last build. Output goes here unless you pass `--out`.

## Where each scene lives

| Scene | Code |
|---|---|
| Staged scene order and the lines spoken | `visionos/MedSimXR/Views/PitchScenes.swift` |
| Clinic | `visionos/MedSimXR/Reality/Pitch/PitchClinic.swift` |
| Scan room, probe and hand | `Reality/Pitch/PitchAntenatal.swift`, `Reality/UltrasoundScene.swift` |
| Roadside, forest trail, bystanders | `Reality/Pitch/PitchRoadside.swift`, `Reality/Pitch/PitchCrowd.swift` |
| Ambulance | `Reality/Pitch/PitchAmbulance.swift` (`withEMT` toggles Lena) |
| Resus bay | `Reality/Pitch/PitchTraumaBay.swift` |
| Notebook and debriefs | `Views/NotebookView.swift`, `Views/FeedbackView.swift` |
| X-ray and ultrasound screens | `Views/RadiologyViewer.swift`, `Views/UltrasoundMonitorView.swift` |
| Stage card | `Reality/ScenarioStage.swift` |
| Studio on Vision Pro | `Views/PitchStudioScenes.swift` (covers: `Resources/Pitch/vpstudio_cover_*.jpg`) |
| Studio in the browser | `studio/src/pitch/PitchStudio.tsx` |
| Blender title renders | `assets/pitch_hero/` |

Everything above runs only with the `-pitch` launch argument; the normal app is unchanged. Asset credits (CC0 / CC BY-SA) are in `assets/pitch/CREDITS-*.md` and `assets/ultrasound/README.md`; the forearm X-ray images are CC BY-SA and need a credit line in the deck if used.
