# Interaction verification record

Updated 2026-11-13. Three levels, never to be mixed up:

- **Manual**: a person operated it (simulator pointer or headset hands).
- **Scripted**: `-autoDemo` called the app's functions and the result was checked in logs and screenshots. This proves the logic behind a gesture, not the gesture.
- **Unit**: backend tests / Swift engine checks only.

Nothing in this project has been operated by a person so far. The development environment has no permission to generate pointer input (`AXIsProcessTrusted() == false`), so taps, pinches and drags could not be simulated either.

| Feature | Manual | Scripted | Notes |
|---|---|---|---|
| Start/stop session, recenter | No | Yes | |
| Patient sits, extends/relaxes arms, indicates wrist | No | Yes | via action hook and scripted mock voice |
| Live ElevenLabs voice, client tools | No | No | no credentials |
| Examination by gaze + pinch on a zone | **No** | Engine call only | the tap handler itself has never run |
| Examination by fingertip (experimental) | No | No | needs hand tracking |
| Notebook: typing, dictation, tabs | No | Values set in code | |
| Order investigation, viewer, zoom buttons | No | Yes | pinch-zoom never run |
| Tray: pinch to select an item | **No** | Selection state set in code | handler never run |
| Place by second pinch on the forearm | **No** | Same placement call (`via=pinch`), point given in code | conversion from pinch location to forearm coordinates never run |
| Place by drag and drop | **No** | Same snap logic | drag handler never run |
| Cancel selection, panel adjust buttons | No | Functions called | |
| Debug fallback placement buttons | No | Same command path | |
| Unprompted fit remarks, debounced | No | Yes | audio not listened to |
| Spatial Clinical Replay: open, step, anatomy, exit | No | Yes | button taps never run |
| Anything on a physical headset | No | No | |

To move a row to Manual: run the app in the simulator (click = pinch, click-drag = drag) or on the headset, follow `docs/tomorrow-headset-checklist.md`, and edit this table.

Fastest manual check of the new placement path in the simulator: Start Session → Debug → "Sit Down" → click a support on the tray (it lifts, base lights up, forearm glows) → click the patient's right forearm.
