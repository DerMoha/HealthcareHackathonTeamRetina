# Patient avatars

Three adult avatars are built with Blender and the
[MPFB](https://extensions.blender.org/add-ons/mpfb/) add-on (the MakeHuman generator). Each
is a `.usdz` plus a sidecar `.json` in `visionos/MedSimXR/Resources/`.

| Variant | Files | Pose | Used for |
|---|---|---|---|
| `male` (default) | `Patient.usdz`, `Patient.json` | seated on a stool, forearms forward | wrist-trauma case |
| `female` | `Patient_female.usdz`, `Patient_female.json` | same seated pose and anchors, woman ~28 | wrist-trauma case with a female patient |
| `pregnant` | `Patient_pregnant.usdz`, `Patient_pregnant.json` | woman ~31, third trimester, semi-recumbent on an examination couch, abdomen bare | obstetric ultrasound scenario |

All three share the MPFB `game_engine` skeleton (53 joints, identical names), so everything that
drives `Patient.usdz` through joint names (`spine_01`, `head`, `upperarm_r`, `lowerarm_r`,
`neck_01`, `hand_r`, `foot_l`, ...) also works on the other two. Preview renders are in
[previews/](previews/) (`Patient_<variant>_<view>.png`).

## Licence

Every mesh and texture in the models comes from the MakeHuman **system assets** pack
(`makehuman_system_assets_cc0.zip`: body, skins, clothes, shoes, hair, eyes, and the
`stomach-pregnant-incr` target), which is released under **CC0 1.0**: no attribution required,
commercial use allowed. MPFB itself is GPL-3.0, but it is only a build tool and is not shipped;
its output carries no GPL obligation. The models depict no real person.

| Variant | Skin | Clothes | Shoes | Hair |
|---|---|---|---|---|
| male | young_caucasian_male | male_casualsuit01 | shoes02 | short02 |
| female | young_caucasian_female | female_casualsuit01 | shoes01 (collar trimmed, see below) | ponytail01 |
| pregnant | young_caucasian_female | female_sportsuit01 (belly cut away) | barefoot | ponytail01 |

## Rebuild

```bash
brew install --cask blender
assets/patient/build.sh              # male  -> Patient.usdz / Patient.json
assets/patient/build.sh female       # Patient_female.usdz / .json
assets/patient/build.sh pregnant     # Patient_pregnant.usdz / .json
MEDSIM_INSTALL=0 assets/patient/build.sh female   # build into assets/patient/.cache only
```

The script installs MPFB and the asset pack on first run (about 330 MB, cached), then runs
`build_patient.py` with `VARIANT` set: generate the human, add the game-engine rig, pose it,
bake that pose as the rest pose, join everything into one skinned mesh, cap textures at 1024 px,
export USDZ, switch hair/brows/lashes to alpha cut-out, and validate with `usdchecker --arkit`.
It also writes the sidecar JSON and the preview renders (copied to `previews/`).

The male build is unchanged by the variant support: same macro settings, assets and pose, same
sidecar values and same mesh.

To change a pose, edit `SEATED_POSE` (or the `pregnant` pose block) in `build_patient.py` (bone ->
direction in Blender space: Z up, character faces -Y, character's left is +X). `POSE`, `ROLL`,
`HAIR`, `PREG` (pregnancy target weight), `CUT_LO` / `CUT_HI` (belly clothing cut, standing
height in metres) and `SHOE_CUT` can be overridden from the environment for experiments.

### Seated variants (`male`, `female`)

Sidecar: `seat_height` and the `right_wrist`, `right_forearm`, `left_wrist` anchors, measured
from the posed skeleton. The app places the examination zones on those anchors, so re-posing the
model moves the zones with it. The woman is smaller (seat height 0.371 m against 0.452 m), so
the app should build the stool from `seat_height` as it already does. The female shoes have a
collar that runs up the shin and shows through the jeans hem with unpainted texture, so the build
removes the shoe mesh above 0.10 m.

### `pregnant`

Built from `female` macro settings (age 0.546, about 31 y) plus `stomach-pregnant-incr` at
weight 1.2 (the target's usual maximum is 1.0; 1.2 reads as a late third trimester bump and the
mesh stays clean). The sports top is cut away between z 0.80 and 1.10 m (standing coordinates), so
it ends under the chest like a lifted top, and the leggings start below the bump. The skin under
the cut is unmasked. The shoes are left out.

Pose: trunk reclined 40 degrees above horizontal on the back-rest, legs extended forward on the
couch, arms relaxed at her sides, head on the back-rest with the neck slightly flexed and turned
about 14 degrees towards her right (the clinician's usual side). The lowest body point rests on
the couch top at 0.62 m.

Sidecar `Patient_pregnant.json` (avatar space: metres, Y up, the patient faces +Z, origin on the
floor, the patient's right is -X):

```json
{
  "_doc": "...",
  "seat_height": 0.62,
  "couch": {
    "seat_height": 0.62,
    "leg_rest_height": 0.62,
    "width": 0.66,
    "thickness": 0.12,
    "back_rest_angle_deg": 40.0,
    "back_rest_pivot": [0.0, 0.62, -0.045],
    "back_rest_length": 1.17,
    "seat_length": 1.04
  },
  "anchors": { "abdomen_fundus": [x, y, z], "...": "..." },
  "normals": { "abdomen_fundus": [nx, ny, nz], "...": "..." }
}
```

- `seat_height` is the couch top, kept for compatibility with the seated sidecars.
- `couch`: the seat and leg rest are one flat slab with its top at `seat_height`, `width` wide
  (X), `thickness` deep, running from `back_rest_pivot` forward (+Z) for `seat_length`. The
  back-rest is a slab of the same width and thickness whose top face contains the pivot and rises
  from it towards -Z (behind her) at `back_rest_angle_deg` above horizontal, `back_rest_length`
  long. The pivot is where the back plane (fitted to her back) meets the couch top, so the app
  can place the cushion directly from these numbers; the preview renders draw it that way.
- `anchors`: points on the skin surface, found by ray casts onto the posed body. `abdomen_center`
  is the middle of the most anterior plateau (navel level), `abdomen_fundus` the top of the bump,
  `abdomen_upper` halfway between those two, `abdomen_lower` the suprapubic point (first point at
  85 % of the maximum height), `abdomen_left` and `abdomen_right` the patient's sides of the bump
  at navel level, 9 cm either side of the midline. `head` is the middle of the head bone;
  `right_wrist` and `left_wrist` are the wrist joints.
- `normals`: outward unit surface normals at the abdomen anchors, the average of the skin vertex
  normals within 3 cm. Aim the probe along `-normal`.

## In the app

`Reality/PatientAvatar.swift` loads the model, builds a stool at the model's seat height and
drives pain reactions and idle motion through the skeleton's joints (`spine_01`, `head`,
`upperarm_r`, `lowerarm_r`, `neck_01`). If the model or its sidecar is missing, or the app is
launched with `-proceduralAvatar`, the primitive body is used instead; zones, findings and
audio are identical. The stand/sit animation assumes a seated rest pose; the pregnant model is
recumbent, so it should not be sent through it.
