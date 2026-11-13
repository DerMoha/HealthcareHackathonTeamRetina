# Patient avatar

`visionos/MedSimXR/Resources/Patient.usdz` is a seated adult built with Blender and the
[MPFB](https://extensions.blender.org/add-ons/mpfb/) add-on (the MakeHuman generator).

## Licence

Every mesh and texture in the model comes from the MakeHuman **system assets** pack
(`makehuman_system_assets_cc0.zip`, body, skin, clothes, shoes, hair, eyes), which is released
under **CC0 1.0**: no attribution required, commercial use allowed. MPFB itself is GPL-3.0, but
it is only a build tool and is not shipped; its output carries no GPL obligation.
The model depicts no real person.

## Rebuild

```bash
brew install --cask blender
assets/patient/build.sh
```

The script installs MPFB and the asset pack on first run (about 330 MB, cached), then runs
`build_patient.py`: generate the human, add the game-engine rig, pose it seated, bake that
pose as the rest pose, join everything into one skinned mesh, cap textures at 1024 px, export
USDZ, switch hair/brows/lashes to alpha cut-out, and validate with `usdchecker --arkit`.

It also writes `Patient.json`: seat height and the positions of the `right_wrist`,
`right_forearm` and `left_wrist` anchors, measured from the posed skeleton. The app places the
examination zones on those anchors, so re-posing the model moves the zones with it.

To change the pose, edit `POSE` in `build_patient.py` (bone → direction in Blender space:
Z up, character faces -Y, character's left is +X).

## In the app

`Reality/PatientAvatar.swift` loads the model, builds a stool at the model's seat height and
drives pain reactions and idle motion through the skeleton's joints (`spine_01`, `head`,
`upperarm_r`, `lowerarm_r`, `neck_01`). If the model or its sidecar is missing, or the app is
launched with `-proceduralAvatar`, the primitive body is used instead; zones, findings and
audio are identical.
