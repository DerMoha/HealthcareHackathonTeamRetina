# Pitch dressing

Pitch-only places for the `-pitch` screenshot run (`visionos/scripts/pitch_shots.sh`). Nothing here runs in the normal app.

## Hook

`EnvironmentSet.show()` calls `PitchDressing.build(kind, into: set, seat:, avatarRoot:)` when `SmokeLog.pitch` is true.
It calls one function per place, each in its own file:

| Kind | File | Shots |
|---|---|---|
| clinic | PitchClinic.swift | wrist-* |
| antenatal | PitchAntenatal.swift | us-* |
| roadside, roadsideNight | PitchRoadside.swift (`night:`) | rt-01..03 |
| ambulance | PitchAmbulance.swift | rt-04 |
| traumaBay | PitchTraumaBay.swift | rt-05..08 |

- Return `false` to keep the procedural place (that's the default).
- Return `true` and you have built the whole place, the patient's seat included: EnvironmentSet then skips its builder and `buildSeat`. For roadside, ambulance and resus that means the seat/stretcher at height `seat`. The clinic and antenatal rooms get no extra seat, because the patient brings its own stool / scan couch.
- `set` is an empty entity in avatar space: patient at the origin facing +Z, wearer about 1.7 m in front at +Z, camera at standing eye height looking at the patient. 1 unit = 1 m. It is removed on the next place change.
- `avatarRoot` is the patient's root (the parent of the place). Put the IBL on it with `PitchKit.light` so the patient, the place and the 3D props are all lit by the same HDRI. PitchDressing clears the previous place's light before each build.
- wrist-01 hides the place for mixed reality. The light stays on the patient.
- The ambience sound still plays (EnvironmentSet handles it).

## PitchKit (all synchronous, @MainActor)

```swift
PitchKit.model("clinic_cart")                                   // Entity? clone of clinic_cart.usdz (cached)
PitchKit.place("clinic_cart", in: set, at: [1.2, 0, -1.5],      // bottom on at.y, x/z centred, yaw about +Y,
               yaw: -0.4, fit: 1.0, shadow: true)               // largest edge scaled to `fit` m, contact blob
PitchKit.material("clinic_floor", tiling: [4, 4.5],             // PhysicallyBasedMaterial from clinic_floor_diff/_nor/_rough.jpg
                  tint: .white, roughness: 1, metallic: 0)      // (+ _ao/_metal if present); roughness scales the map
PitchKit.texture("clinic_poster.jpg", semantic: .color)         // TextureResource? (.raw for data maps)
PitchKit.light(avatarRoot, hdri: "clinic_ibl", intensity: 0, yaw: 0) // IBL from clinic_ibl.hdr; intensity in EV stops
PitchKit.showShadows(on: floor)                                 // floor opts out of IBL so it can show light shadows
PitchKit.sun(set, from: [1.5, 3, 1], to: [0, 0, -1], intensity: 3000)  // directional light with shadows
PitchKit.spot(set, at: [0, 2.8, 0.5], target: [0, 0, 0], intensity: 20000, angle: 60)  // spot with shadows
PitchKit.contactShadow(set, at: [0, 0, 0], size: [0.5, 0.5], opacity: 0.55)  // soft dark blob on the floor
```

Example (the end-to-end test that was run and screenshotted):

```swift
static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
    let floor = ModelEntity(mesh: .generatePlane(width: 8, depth: 9),
                            materials: [PitchKit.material("clinic_floor", tiling: [4, 4.5])])
    set.addChild(floor)
    PitchKit.place("clinic_chair", in: set, at: [1.0, 0, -0.6], yaw: -0.6, fit: 1.1)
    PitchKit.contactShadow(set, at: [0, 0, -0.05], size: [0.5, 0.5])   // under the patient's stool
    PitchKit.light(avatarRoot, hdri: "clinic_ibl")
    PitchKit.showShadows(on: floor)
    PitchKit.sun(set, from: [1.5, 3, 1], to: [0, 0, -1])
    return true
}
```

## Assets: visionos/scripts/pitch_assets.py

Use the system `python3` (needs Pillow). For models it also needs Blender (`/opt/homebrew/bin/blender`, or set the `BLENDER` env var). Output goes to `visionos/MedSimXR/Resources/Pitch/` and a credit line is appended to `assets/pitch/CREDITS-<key>.md` (the key is the name up to its first `_`, or `--key`). Then run `cd visionos && xcodegen` (pitch_shots.sh does this when it builds).

```sh
python3 -I visionos/scripts/pitch_assets.py texture   wood_floor_deck clinic_floor [--res 1k|2k] [--size 1024]
python3 -I visionos/scripts/pitch_assets.py ambientcg Tiles101 clinic_tiles  [--res 1K|2K] [--size 1024]
python3 -I visionos/scripts/pitch_assets.py hdri      hospital_room clinic_ibl   [--res 1k|2k]
python3 -I visionos/scripts/pitch_assets.py model     WoodenChair_01 clinic_chair [--res 1k] [--decimate 0.5] [--tex 1024]
```

The IDs are Poly Haven slugs (`polyhaven.com/a/<id>`) and ambientCG IDs (`ambientcg.com/view?id=<id>`). A texture set produces `<prefix>_diff/_nor/_rough.jpg`, plus `_ao/_metal` when the set has them.

## People: PitchCrowd and the baked poses

Bystanders, crew, police, hikers and resus staff are the patient avatars (Patient.usdz / Patient_female.usdz)
in poses baked in Blender: `crowd_<pose>_<m|f>.usdz`, made by `visionos/scripts/pitch_crowd_poses.py`
(`/opt/homebrew/bin/blender -b --python visionos/scripts/pitch_crowd_poses.py -- [pose ...] [--g m|f] [--preview DIR]`).

```swift
PitchCrowd.person(.kneelWork, .m, outfit: "paramedic_m", in: e, at: [-0.8, 0, -0.06], facing: [0, 0, 0.1], hair: .gray)
PitchCrowd.body(of: holder)        // the avatar mesh (material 1 = clothes), e.g. to put scrubs on
PitchCrowd.headAnchor(of: holder)  // entity at the head joint, turned with the head (caps, masks)
```

- Poses: stand_relaxed, stand_worried (hand at the mouth), arms_crossed, phone_filming (phone in the file),
  pointing, kneel_work (on the right knee, hands forward at a seated casualty's arm), stand_lean_work (bending in,
  right hand forward, left on the thigh), stand_hands_front. Each for m and f, ~0.7-0.8 MB a file.
- The files are static meshes (no skeleton): the original mesh prim with posed points/normals, same UVs and the
  same seven material subsets, but no textures. `person` swaps in the original avatar's materials (loaded once),
  then `dress` puts the outfit texture on material 1 and tints hair (3) and skin (0).
- Origin on the floor under the pelvis, faces +Z, 1 unit = 1 m, so `at` is where the person stands.
- `PitchKit.model` caches each file: one load per pose file, every person is a clone sharing the mesh.
- No baked file: falls back to the rigged clone posed at runtime (`PitchCrowd.Pose`, the old stiff look).
- Lena in the ambulance seat keeps the avatar's own seated rest pose.

## Gotchas (all seen in the visionOS 26 simulator)

- **IBL works**: an equirect Radiance `.hdr` goes CGImageSource -> `EnvironmentResource(equirectangular:)` -> `ImageBasedLightComponent` + `ImageBasedLightReceiverComponent` on avatarRoot. Without it, the procedural rooms are lit only by point lights and the dim system default. The 1k HDRI (about 1.3 MB) is enough.
- `VirtualEnvironmentProbeComponent` did nothing in this (progressive) immersion style.
- **IBL receivers show no light shadows.** Sun/spot shadows only land on surfaces that are not IBL receivers. `showShadows(on:)` gives a surface its own receiver pointing at an empty entity (a child's receiver overrides the inherited one). That surface is then lit by your sun/spot plus the system light, so give it enough light or it reads darker than the IBL-lit props. Casters (patient, props) can stay IBL-lit and still cast.
- **`GroundingShadowComponent` draws nothing on virtual floors in the simulator.** Use `contactShadow` blobs (opacity-texture plane) and/or sun shadows.
- **Blender USDZ goes black** when one UsdUVTexture feeds two inputs (Poly Haven's packed ARM map -> roughness + metallic). pitch_assets.py splits these nodes after export. If a model you made another way renders black, that's the cause.
- Models load with the deprecated synchronous `Entity.load(contentsOf:)`, which is fine here. Async loading made no visual difference.
- Generated boxes stretch the whole texture over each face: tile per face size, or use planes.
- Bundle files are flattened: always prefix names with your key.
- A missing asset logs `SMOKE pitch asset missing <name>` and returns nil / an untextured material instead of crashing.
- Build plus wrist run: about 35 s incremental.
