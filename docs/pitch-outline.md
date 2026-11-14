# MedSim XR: 3-minute pitch outline

## Features summary

**Patient (easy scenario)**
- 3D patient, own room or virtual clinic
- Female or male appearance
- ElevenLabs voice agent, mood: calm, nervous, angry
- Physical exam with pain reaction, per-case susceptibility notes
- Natural-language reaction to pain or relief

**Examination room tools**
- Tape measure: drag onto wrist and forearm
- Wrist support: pick, drag on, fit

**Diagnostics**
- X-ray and MRI: order after diagnosis, view in a side panel in the same scene

**Ultrasound**
- Pregnant patient, probe on belly
- Sonogram-style images

**Three-place journey**
- Roadside → ambulance → rescue bay
- Same patient, same story throughout
- AI team: observations, bleeding control, other tasks
- Multi-user collaboration (planned)

**Notebook and scoring**
- Voice dictation, auto-summary into draft notes
- Full session log and transcript for students and examiners
- Notes scored against expected findings and checklist
- Score card at the end

**Adaptive difficulty (planned)**
- Driven by student heart rate
- Changes crowd distractions, noise, patient cooperativeness and consciousness

**MedSim Studio (browser)**
- Generate new scenarios or play random mode
- Difficulty: easy, medium, hard
- Crowd: number of people, bystanders (distracting, still, advising), equipment
- Mix and match places and assets
- Learning objectives: creator-defined, AI-assisted, or from certification guidelines
- Guideline import from organisations (planned), adjustable scoring

## Slide outline

Images are in `docs/screenshots/pitch/` unless a path is given. Status: **Built** = in the app and screenshotted, **Roadmap** = no code yet.

| # | Time | Slide | Images | On slide | Speaker notes | Status |
|---|---|---|---|---|---|---|
| 1 | 0:00–0:10 | Title | `hero-01-clinic` | MedSim XR · AI patients on Vision Pro · scenarios built in MedSim Studio | Hands-on clinical practice is scarce and hard to repeat. We put a patient in the room. | Built |
| 2 | 0:10–0:30 | A patient in your room | `wrist-01-in-your-room`, `wrist-02-conversation`, `../review/03-wrist-female-avatar` | 3D patient · own room or virtual clinic · female or male · ElevenLabs voice · mood: calm, nervous, angry | Talk normally, no menus. The patient's mood changes how they answer. | Built |
| 3 | 0:30–0:45 | Examination and pain | `wrist-03-pain-reaction` | Gaze + pinch to examine · patient flinches · spoken reaction to pain or relief · per-case susceptibility notes | Press the snuffbox and he pulls away: "That's exactly where it hurts." | Built |
| 4 | 0:45–1:00 | Examination room tools | `wrist-05-orthotics-lab`, `../demo/05-lab-1-measure-wrist.jpg` | Drag the tape to wrist and forearm · pick a wrist support, drag it on · fit and tighten | Wrong size or too tight, and the patient tells you. Same workflow as the clinic. | Built |
| 5 | 1:00–1:15 | Imaging: X-ray and MRI | `wrist-04-xray`, `../demo/10-mri-report.jpg` | Order after diagnosis, by voice or notebook · viewer panel next to patient · zoom | A normal X-ray doesn't rule out a scaphoid fracture. What does the student do next? | Built |
| 6 | 1:15–1:30 | Ultrasound | `us-03-heart`, `us-02-head-bpd` | Pregnant patient, 20-week scan · probe on belly, gel needed · live sonogram views: head, heart, spine | Move the probe and the image changes. Placing the probe is the skill. | Built |
| 7 | 1:30–1:55 | One patient, three places | `rt-01-roadside`, `rt-04-ambulance`, `rt-05-resus`, `rt-02-crew` | Roadside → ambulance → rescue bay · same patient, same story · AI team: observations, bleeding control | Real care is a team effort and a handover. You follow one patient from start to finish. | Built (AI team), Roadmap (multi-user) |
| 8 | 1:55–2:15 | Notebook, log, score | `wrist-06-notebook`, `rt-07-team-log`, `wrist-07-feedback` | Dictate notes · auto-summary into draft · full session log for student and examiner · checklist scoring · score card | Notes count only for things you actually did. Examiners see the full transcript. | Built |
| 9 | 2:15–2:25 | Adaptive difficulty | `rt-02-crew` (placeholder, needs a new image) | Student heart rate · more or fewer distractions · louder or quieter · patient more or less cooperative | Calm students get pushed harder. Overloaded students get room to work. | Roadmap (instructor can trigger events live today) |
| 10 | 2:25–2:50 | MedSim Studio (browser) | `studio-web-01-generator`, `studio-web-02-ai-author`, `studio-web-04-marketplace`, `vp-02-download-crop` | New scenarios or random mode · easy, medium, hard · bystanders: distracting, still, advising · equipment · mix and match places · objectives with AI help · adjustable scoring | Instructors build a case in minutes and publish it. Students download it to the headset. | Built (guideline import: Roadmap) |
| 11 | 2:50–3:00 | Close | `hero-02-roadside` or `hero-03-ultrasound` | Practice → score → review → repeat · ask / contact | Every case can be repeated, and every case is scored. | — |

## Gaps to close before the pitch

- Slide 9 has no real image. Shoot a mock-up or present it as roadmap.
- Slide 10: guideline import from certifying organisations is not built. Say "planned".
- Slide 7: multi-user is not built, only AI teammates. Say "planned".
- Forearm X-ray images are CC BY-SA: add a credit line on slide 5 or 7.
