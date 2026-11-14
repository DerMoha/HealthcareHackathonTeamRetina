"""Hero 01: clinic consultation. Alex sits on a stool cradling his right wrist; the learner stands
in front of him. Renders hero-01-clinic (a) and hero-01-clinic-b, plus panel quads for composite.py.

    blender -b --python assets/pitch_hero/hero_clinic.py
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import hero_common as H, hero_pose as P
from mathutils import Vector

sc = H.reset(samples=160)
sc.view_settings.exposure = -0.9
H.world_hdri("hospital_room_2", 0.35)

# ---- room: 5.6 x 5.2 m, 2.8 m ceiling. Patient at origin facing -Y (towards the camera).
X0, X1, Y0, Y1, CH = -2.8, 2.8, -3.4, 1.9, 2.8
floor = H.pbr("floor", "Terrazzo018", scale=2.2, rough_mul=0.6, sat=0.25, value=0.8)
wall = H.pbr("wall", "painted_plaster_wall", scale=0.5, tint=(0.93, 0.95, 0.96))
accent = H.pbr("accent", "painted_plaster_wall", scale=0.5, tint=(0.55, 0.74, 0.76))
ceil = H.pbr("ceil", "OfficeCeiling005", scale=0.5)
H.plane("floor", (X1 - X0, Y1 - Y0), ((X0 + X1) / 2, (Y0 + Y1) / 2, 0), floor)
H.plane("ceiling", (X1 - X0, Y1 - Y0), ((X0 + X1) / 2, (Y0 + Y1) / 2, CH), ceil, rot=(math.pi, 0, 0))
H.box("wall_back", (X1 - X0, 0.1, CH), (0, Y1 + 0.05, CH / 2), accent, bevel=0)
H.box("wall_left", (0.1, Y1 - Y0, CH), (X0 - 0.05, (Y0 + Y1) / 2, CH / 2), wall, bevel=0)
H.box("wall_right", (0.1, Y1 - Y0, CH), (X1 + 0.05, (Y0 + Y1) / 2, CH / 2), wall, bevel=0)
H.box("wall_front", (X1 - X0, 0.1, CH), (0, Y0 - 0.05, CH / 2), wall, bevel=0)
trim = H.plain("trim", (0.85, 0.87, 0.88), rough=0.35)
for n, s, l in (("skirt_b", (X1 - X0, 0.02, 0.1), (0, Y1 - 0.01, 0.05)), ("skirt_l", (0.02, Y1 - Y0, 0.1), (X0 + 0.01, (Y0 + Y1) / 2, 0.05)),
                ("skirt_r", (0.02, Y1 - Y0, 0.1), (X1 - 0.01, (Y0 + Y1) / 2, 0.05)), ("rail_b", (X1 - X0, 0.03, 0.06), (0, Y1 - 0.015, 0.95)),
                ("rail_l", (0.03, Y1 - Y0, 0.06), (X0 + 0.015, (Y0 + Y1) / 2, 0.95))):
    H.box(n, s, l, trim, bevel=0.005)

# ceiling light panels (emissive diffusers + matching area lights for soft shadows)
diff = H.plain("diffuser", (1, 1, 1), rough=0.6, emission=(1.0, 0.97, 0.92), estrength=6.0)
for x, y in ((-1.2, -1.2), (1.2, -1.2), (-1.2, 0.8), (1.2, 0.8)):
    H.box("lamp", (1.2, 0.6, 0.02), (x, y, CH - 0.012), diff, bevel=0.002)
    H.area_light("ceil_l", (x, y, CH - 0.04), 1.1, 140, color=(1.0, 0.96, 0.9), size_y=0.55)
# window light from camera-right (window off frame on the right wall)
H.area_light("window", (X1 - 0.1, -0.6, 1.6), 2.4, 520, color=(0.86, 0.92, 1.0), target=(0, -0.2, 1.0), size_y=1.6)
H.area_light("fill", (-1.0, -3.0, 2.0), 2.0, 70, color=(1.0, 0.93, 0.85), target=(0, 0, 1.0))
H.area_light("face_key", (0.9, -1.5, 1.9), 0.6, 45, color=(1.0, 0.8, 0.6), target=(0, 0, 1.25))  # warm key for contrast on Alex

# ---- patient
root, rig, body = H.patient("Patient")
P.guard_right_wrist(rig)
H.gltf("metal_stool_02", (0, -0.03, 0))

# ---- props
desk = H.gltf("metal_office_desk", (1.75, 1.35, 0), rot_z=180)
H.gltf("classic_laptop", (1.55, 1.3, 0.79), rot_z=200)
H.gltf("office_notepads", (2.25, 1.35, 0.79), rot_z=10, scale=0.5)
H.gltf("clipboard", (1.1, 1.25, 0.79), rot_z=-15)
H.gltf("SchoolChair_01", (1.6, 0.6, 0), rot_z=160)
H.gltf("drawer_cabinet", (-2.15, 1.6, 0), rot_z=180)
H.gltf("medical_box", (-2.15, 1.55, 1.885), rot_z=180)
H.gltf("potted_plant_02", (2.45, -0.4, 0), rot_z=40)
H.gltf("vintage_crutches_01", (-2.62, 0.4, 0), rot_z=90)
H.gltf("korean_fire_extinguisher_01", (-2.6, -1.4, 0.0), rot_z=90)


# examination couch along the left wall (leatherette top, steel frame)
leather = H.pbr("leather", "fabric_leather_02", scale=2.0, tint=(0.35, 0.62, 0.66), rough_mul=0.8, sat=0.0)
steel = H.pbr("steel", "Metal032", scale=2.0, metal=1.0, rough_mul=0.6)
H.box("couch_top", (0.68, 1.9, 0.1), (-2.2, -0.3, 0.68), leather, bevel=0.03, segments=5)
H.box("couch_pillow", (0.5, 0.35, 0.08), (-2.2, 0.38, 0.77), leather, bevel=0.035, segments=5)
for dx in (-0.28, 0.28):
    for dy in (-1.1, 0.5):
        H.box("couch_leg", (0.05, 0.05, 0.62), (-2.2 + dx, -0.3 + dy, 0.31), steel, bevel=0.004)
H.box("couch_rail", (0.6, 0.04, 0.04), (-2.2, -1.1, 0.12), steel)
paper = H.pbr("paper", "Fabric030", scale=3.0, tint=(1, 1, 1), value=1.3)
H.box("couch_paper", (0.5, 1.6, 0.004), (-2.2, -0.35, 0.733), paper, bevel=0.0)

# X-ray light box on the back wall showing the PA wrist film
xr = os.path.join(H.RES, "Radiology", "wrist_xray_pa.jpg")
H.box("viewer_frame", (0.62, 0.04, 0.72), (-0.95, Y1 - 0.02, 1.55), H.plain("frame", (0.9, 0.9, 0.9), rough=0.3), bevel=0.01)
H.plane("viewer_img", (0.5, 0.6), (-0.95, Y1 - 0.045, 1.55), H.image_emit("xray", xr, strength=2.2), rot=(math.radians(90), 0, math.radians(180)))
# hand-hygiene dispenser + poster frame
H.box("dispenser", (0.12, 0.1, 0.24), (0.95, Y1 - 0.05, 1.3), H.plain("disp", (0.95, 0.95, 0.95), rough=0.25), bevel=0.01)
H.box("poster", (0.5, 0.02, 0.7), (2.3, Y1 - 0.01, 1.6), H.pbr("poster", "Fabric030", scale=4, tint=(0.75, 0.86, 0.9)), bevel=0.003)

# ---- cameras + panel quads (panels live in the learner's space between camera and patient)
def shot(name, cam, target, lens, specs, fstop=4.0, focus=None):
    H.camera(cam, target, lens=lens, fstop=fstop, focus=focus)
    H.write_panels(H.screen_panels(specs), os.path.join(H.OUT, name + ".json"))
    H.render(name)


shot("hero-01-clinic", (0.62, -2.45, 1.6), (0.0, 0, 1.15), 32, [
    ("conversation", -0.6, 0.5, 1.9, 0.58, 0.322),
    ("score", -0.62, -0.12, 1.9, 0.38, 0.2),
    ("notebook", 0.62, 0.05, 1.7, 0.5, 0.61),
], focus=2.5)
shot("hero-01-clinic-b", (-1.55, -1.9, 1.4), (0.1, -0.2, 1.15), 40, [
    ("conversation", 0.55, 0.5, 1.9, 0.6, 0.33),
    ("score", 0.64, -0.12, 1.9, 0.36, 0.19),
    ("notebook", -0.62, 0.05, 1.6, 0.42, 0.51),
], fstop=2.8, focus=2.4)
