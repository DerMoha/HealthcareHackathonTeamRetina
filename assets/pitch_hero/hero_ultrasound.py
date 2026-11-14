"""Hero 03: antenatal scan room. Sarah (20 weeks) semi-recumbent on the couch, probe on her
abdomen, the machine monitor showing the real transthalamic BPD view. Renders hero-03-ultrasound
(a) and hero-03-ultrasound-b. Run `python3 composite.py --us-screen` first (monitor image).

    blender -b --python assets/pitch_hero/hero_ultrasound.py
"""
import os, sys, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import hero_common as H
from mathutils import Vector

sc = H.reset(samples=160)
H.world_hdri("small_empty_room_3", 0.25)
sc.view_settings.exposure = -0.45
meta = json.load(open(os.path.join(H.RES, "Patient_pregnant.json")))


def av(p):
    """Avatar space (Y up, faces +Z) -> Blender (Z up, faces -Y)."""
    return Vector((p[0], -p[2], p[1]))


# ---- room (dim, warm; scan rooms are kept dark for the screen)
X0, X1, Y0, Y1, CH = -2.9, 2.6, -3.6, 1.9, 2.7
H.plane("floor", (X1 - X0, Y1 - Y0), ((X0 + X1) / 2, (Y0 + Y1) / 2, 0), H.pbr("floor", "Terrazzo018", scale=2.2, rough_mul=0.6, sat=0.2, value=0.7))
wall = H.pbr("wall", "plastered_wall_04", scale=0.5, tint=(0.86, 0.82, 0.86))
H.plane("ceiling", (X1 - X0, Y1 - Y0), ((X0 + X1) / 2, (Y0 + Y1) / 2, CH), H.pbr("ceil", "OfficeCeiling005", scale=0.5), rot=(math.pi, 0, 0))
H.box("wall_back", (X1 - X0, 0.1, CH), (0, Y1 + 0.05, CH / 2), wall, bevel=0)
H.box("wall_left", (0.1, Y1 - Y0, CH), (X0 - 0.05, (Y0 + Y1) / 2, CH / 2), wall, bevel=0)
H.box("wall_right", (0.1, Y1 - Y0, CH), (X1 + 0.05, (Y0 + Y1) / 2, CH / 2), wall, bevel=0)
H.box("wall_front", (X1 - X0, 0.1, CH), (0, Y0 - 0.05, CH / 2), wall, bevel=0)
H.box("skirt", (X1 - X0, 0.02, 0.1), (0, Y1 - 0.01, 0.05), H.plain("trim", (0.8, 0.8, 0.82), rough=0.4), bevel=0.004)

# ---- couch from the avatar's couch description
c = meta["couch"]; pv = av(c["back_rest_pivot"]); top = c["seat_height"]
leather = H.pbr("leather", "fabric_leather_02", scale=2.0, tint=(0.33, 0.36, 0.42), rough_mul=0.8)
steel = H.pbr("steel", "Metal032", scale=2.0, metal=1.0, rough_mul=0.6)
t = c["thickness"]
H.box("seat", (c["width"], c["seat_length"], t), (0, pv.y - c["seat_length"] / 2, top - t / 2), leather, bevel=0.035, segments=5)
a = math.radians(c["back_rest_angle_deg"]); L = c["back_rest_length"]
mid = Vector((0, pv.y + math.cos(a) * L / 2 + math.sin(a) * t / 2, top + math.sin(a) * L / 2 - math.cos(a) * t / 2))
H.box("backrest", (c["width"], L, t), mid, leather, bevel=0.035, segments=5, rot=(a, 0, 0))
H.box("base", (0.5, 1.5, 0.42), (0, pv.y - 0.2, 0.26), H.plain("basecol", (0.86, 0.86, 0.88), rough=0.35), bevel=0.03)
H.box("foot", (0.62, 1.7, 0.06), (0, pv.y - 0.2, 0.03), steel, bevel=0.01)
paper = H.pbr("paper", "Fabric030", scale=3.0, value=1.35, tint=(1, 1, 1))
H.box("roll", (0.5, 0.9, 0.004), (0, pv.y - 0.5, top + 0.002), paper, bevel=0)

root, rig, body = H.patient("Patient_pregnant")

# ---- ultrasound machine on her right (-X), monitor angled to the sonographer and to her
mx, my = -0.95, -0.05
cart = H.plain("cart", (0.9, 0.9, 0.92), rough=0.3, coat=0.5)
dark = H.plain("darkplastic", (0.08, 0.09, 0.1), rough=0.45)
H.box("cart_base", (0.62, 0.7, 0.12), (mx, my, 0.12), dark, bevel=0.03)
for dx in (-0.25, 0.25):
    for dy in (-0.28, 0.28):
        H.cylinder("caster", 0.05, 0.04, (mx + dx, my + dy, 0.05), dark, rot=(0, math.pi / 2, 0))
H.box("cart_col", (0.22, 0.26, 0.62), (mx, my + 0.08, 0.5), cart, bevel=0.03)
H.box("console", (0.6, 0.52, 0.09), (mx, my - 0.05, 0.86), cart, bevel=0.03, rot=(math.radians(-8), 0, 0))
H.box("keys", (0.46, 0.3, 0.012), (mx, my - 0.08, 0.91), H.plain("keys", (0.15, 0.17, 0.2), rough=0.35, emission=(0.2, 0.5, 0.9), estrength=0.4), bevel=0.004, rot=(math.radians(-8), 0, 0))
H.cylinder("trackball", 0.035, 0.02, (mx, my - 0.2, 0.92), H.plain("tb", (0.2, 0.2, 0.22), rough=0.1, coat=1.0))
H.cylinder("arm", 0.025, 0.42, (mx, my + 0.12, 1.1), steel)
mon = bpy.data.objects.new("monitor", None); H.link(mon); mon.location = (mx + 0.05, my + 0.1, 1.42)
facing = Vector((-1.9, -2.6, 1.4)) - mon.location; mon.rotation_euler = (0, 0, math.atan2(facing.y, facing.x) + math.pi / 2)
o = H.box("mon_body", (0.62, 0.05, 0.42), (0, 0.0, 0), dark, bevel=0.012); o.parent = mon
o = H.plane("mon_screen", (0.58, 0.3625), (0, -0.027, 0.005), H.image_emit("screen", os.path.join(H.OUT, "us_screen.png"), strength=1.6, gloss_coat=0.0, rough=0.6), rot=(math.radians(90), 0, 0)); o.parent = mon
gel = H.plain("gel", (0.15, 0.45, 0.9), rough=0.2, transmission=0.6)
H.cylinder("gel", 0.03, 0.18, (mx + 0.24, my + 0.18, 0.99), gel)
H.cylinder("gel_cap", 0.012, 0.04, (mx + 0.24, my + 0.18, 1.1), H.plain("cap", (0.95, 0.95, 0.95), rough=0.3))

# probe on the abdomen (normal from the avatar's anchors), cable to the machine
pc = av(meta["anchors"]["abdomen_right"]) * 0.4 + av(meta["anchors"]["abdomen_center"]) * 0.6
n = av(meta["normals"]["abdomen_center"]).normalized()
probe = H.box("probe", (0.055, 0.03, 0.15), pc + n * 0.075, H.plain("probe", (0.92, 0.92, 0.93), rough=0.25, coat=0.6), bevel=0.012, segments=5)
probe.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
cab = bpy.data.curves.new("cable", "CURVE"); cab.dimensions = "3D"; cab.bevel_depth = 0.006
sp = cab.splines.new("BEZIER"); pts = [pc + n * 0.15, Vector((-0.35, -0.35, 0.75)), Vector((mx + 0.2, my - 0.2, 0.7)), Vector((mx + 0.25, my - 0.05, 0.9))]
sp.bezier_points.add(len(pts) - 1)
for bp, p in zip(sp.bezier_points, pts): bp.co = p; bp.handle_left_type = bp.handle_right_type = "AUTO"
co = H.link(bpy.data.objects.new("cable", cab)); cab.materials.append(dark)

# ---- wall screen for the mother (mirror of the scan), cabinet, clock, plant
ws = bpy.data.objects.new("wallscreen", None); H.link(ws); ws.location = (1.4, Y1 - 0.04, 1.65)
o = H.box("ws_body", (1.0, 0.04, 0.6), (0, 0, 0), dark, bevel=0.01); o.parent = ws
o = H.plane("ws_img", (0.96, 0.6), (0, -0.022, 0), H.image_emit("screen2", os.path.join(H.OUT, "us_screen.png"), strength=1.2, gloss_coat=0.0, rough=0.6), rot=(math.radians(90), 0, 0)); o.parent = ws
H.gltf("drawer_cabinet", (-2.2, 1.62, 0), rot_z=180, scale=0.75)
H.gltf("wall_clock", (-1.7, Y1 - 0.005, 2.0), rot_z=180)
H.gltf("potted_plant_04", (2.2, 0.2, 0), rot_z=20)
H.gltf("metal_stool_02", (-0.75, -0.75, 0), scale=1.15)
H.gltf("side_table_01", (0.75, 0.4, 0), rot_z=10)
H.box("tissues", (0.24, 0.12, 0.09), (0.75, 0.4, 0.6), H.plain("tbox", (0.75, 0.85, 0.9), rough=0.4), bevel=0.01)
H.box("curtain_rail", (0.04, 3.2, 0.04), (1.2, 0.2, 2.45), steel)
curt = H.pbr("curtain", "Fabric030", scale=2.0, tint=(0.62, 0.72, 0.8))
for i in range(14):
    H.box("pleat", (0.06, 0.2, 2.0), (1.2 + 0.035 * (i % 2), -1.2 + i * 0.13, 1.42), curt, bevel=0.025)

# ---- light: warm dim ceiling spots + soft key, screen glow does the rest
H.area_light("key", (0.6, -1.4, 2.6), 1.4, 120, color=(1.0, 0.86, 0.7), target=(0, 0, 0.9))
H.area_light("back", (-1.6, 1.4, 2.5), 1.0, 60, color=(1.0, 0.82, 0.66), target=(0, 0.3, 1.0))
H.area_light("monglow", (mx + 0.25, my - 0.25, 1.4), 0.4, 12, color=(0.75, 0.85, 1.0), target=(0, -0.1, 0.95))
for x, y in ((-1.2, -1.6), (1.0, 1.0), (-1.4, 1.2)):
    H.cylinder("downlight", 0.08, 0.01, (x, y, CH - 0.005), H.plain("dl", (1, 1, 1), emission=(1.0, 0.85, 0.65), estrength=40))
    H.spot_light("spot", (x, y, CH - 0.05), 90, (x, y, 0), color=(1.0, 0.85, 0.65), angle=70, radius=0.06)


def shot(name, cam, target, lens, specs, fstop=3.2, focus=None):
    H.camera(cam, target, lens=lens, fstop=fstop, focus=focus)
    H.write_panels(H.screen_panels(specs), os.path.join(H.OUT, name + ".json"))
    H.render(name)


shot("hero-03-ultrasound", (0.9, -2.6, 1.6), (-0.35, 0.05, 1.1), 30, [
    ("checklist", 0.64, 0.0, 1.8, 0.5, 0.66),
    ("patient_us", -0.05, 0.68, 2.4, 0.66, 0.2),
], focus=2.75)
shot("hero-03-ultrasound-b", (-1.9, -1.55, 1.5), (-0.3, 0.2, 1.1), 38, [
    ("checklist", 0.64, 0.0, 1.8, 0.44, 0.58),
    ("patient_us", 0.1, 0.7, 2.4, 0.6, 0.183),
], fstop=2.8, focus=2.0)
