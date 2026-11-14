"""Hero 02: roadside at dusk. Jordan (cyclist knocked off by a car) sits on a paramedic bag
guarding his right forearm; ambulance blue lights on wet asphalt, his bicycle on the road, two
bystanders. Renders hero-02-roadside (a) and hero-02-roadside-b.

    blender -b --python assets/pitch_hero/hero_roadside.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import hero_common as H, hero_pose as P
from mathutils import Vector

sc = H.reset(samples=160)
H.world_hdri("modern_evening_street", 0.32, rot_deg=110, bg_strength=0.4)
sc.view_settings.exposure = 0.2
rnd = random.Random(4)


def wet(m, puddles=0.55):
    """Puddles: a noise mask pulls roughness down to near-mirror and darkens the albedo a little."""
    nt = m.node_tree; N = nt.nodes; L = nt.links; b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord"); nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.35
    nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB"); ramp.color_ramp.elements[0].position = puddles - 0.06; ramp.color_ramp.elements[1].position = puddles + 0.04
    L.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    rl = next(l for l in nt.links if l.to_socket == b.inputs["Roughness"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "FLOAT"
    L.new(ramp.outputs["Color"], mx.inputs["Factor"]); L.new(rl.from_socket, mx.inputs["A"]); mx.inputs["B"].default_value = 0.03
    L.new(mx.outputs["Result"], b.inputs["Roughness"])
    return m


# ---- ground: road (x from -3.5 to 3.5 runs along Y), kerb and pavement on the left
road = wet(H.pbr("road", "asphalt_02", scale=0.4, rough_mul=0.55, value=0.7))
H.plane("road", (7.0, 80), (0.5, 20, 0), road)
pave = wet(H.pbr("pave", "concrete_pavement_02", scale=0.5, rough_mul=0.7), 0.62)
H.plane("pavement", (6, 80), (-6.0, 20, 0.12), pave)
H.box("kerb", (0.25, 80, 0.14), (-2.9, 20, 0.06), H.pbr("kerb", "concrete", scale=1.0), bevel=0.02)
H.plane("verge", (30, 80), (19, 20, -0.01), wet(H.pbr("verge", "asphalt_02", scale=0.3, value=0.5), 0.5))
paint = H.plain("paint", (0.85, 0.85, 0.82), rough=0.35)
for i in range(-2, 18):
    H.plane("dash", (0.12, 3.0), (0.5, i * 6.0, 0.002), paint)
H.plane("edge_line", (0.12, 80), (-2.6, 20, 0.002), paint)

# ---- patient on the paramedic bag
root, rig, body = H.patient("Patient")
P.guard_right_wrist(rig)
bag_red = H.pbr("bag", "Fabric030", scale=6, tint=(0.75, 0.08, 0.06), rough_mul=0.9)
H.box("bag", (0.62, 0.36, 0.44), (0, -0.02, 0.22), bag_red, bevel=0.05, segments=6)
H.box("bag_strap", (0.64, 0.06, 0.02), (0, -0.02, 0.442), H.plain("strap", (0.05, 0.05, 0.05), rough=0.7), bevel=0.005)
refl = H.plain("refl", (0.85, 0.85, 0.85), rough=0.2, metal=0.6)
H.box("bag_band", (0.63, 0.37, 0.04), (0, -0.02, 0.15), refl, bevel=0.01)
H.box("bag2", (0.5, 0.3, 0.3), (0.75, -0.45, 0.15), H.pbr("bag2", "Fabric030", scale=6, tint=(0.08, 0.35, 0.18)), bevel=0.04, rot=(0, 0, 0.5))
H.cylinder("o2", 0.05, 0.6, (0.62, -0.2, 0.05), H.plain("o2c", (0.95, 0.95, 0.95), rough=0.25), rot=(math.pi / 2, 0, 1.3))
H.gltf("medical_box", (-0.7, -0.5, 0), rot_z=30)

# ---- his bicycle lying on the road behind him
frame_m = H.plain("bike", (0.05, 0.25, 0.6), rough=0.25, metal=0.3, coat=1.0)
tyre = H.pbr("tyre", "Rubber004", scale=4)
bx, by = 0.9, 1.9
for wx in (-0.52, 0.52):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.33, minor_radius=0.018, location=(bx + wx, by, 0.02), major_segments=64, minor_segments=12)
    t = bpy.context.object; t.data.materials.append(tyre); t.rotation_euler = (0, 0, 0.35)
    for p in t.data.polygons: p.use_smooth = True
for a, b in (((-0.52, 0), (0.0, 0.0)), ((0.0, 0.0), (0.12, 0.5)), ((-0.52, 0), (0.12, 0.5)), ((0.12, 0.5), (0.55, 0.42)), ((0.55, 0.42), (0.52, 0.0)), ((0.0, 0.0), (0.05, 0.62))):
    A, B = Vector((bx + a[0], by + a[1] * 0.25, 0.04)), Vector((bx + b[0], by + b[1] * 0.25 + 0.02, 0.04))
    c = H.cylinder("tube", 0.016, (B - A).length, (A + B) / 2, frame_m, verts=16, bevel=0)
    c.rotation_euler = (B - A).to_track_quat("Z", "Y").to_euler()
H.box("saddle", (0.25, 0.1, 0.05), (bx + 0.05, by + 0.18, 0.04), H.plain("saddle", (0.03, 0.03, 0.03), rough=0.5))
H.cylinder("helmet", 0.13, 0.1, (bx - 1.2, by - 0.6, 0.05), H.plain("helmet", (0.95, 0.85, 0.1), rough=0.3, coat=1))

# ---- the car that hit him: dark estate, stopped askew, hazards on
paint_car = H.plain("carpaint", (0.12, 0.13, 0.15), rough=0.25, metal=0.6, coat=1.0)
glass = H.plain("carglass", (0.02, 0.02, 0.03), rough=0.05, metal=0.2, coat=1.0)
car = bpy.data.objects.new("car", None); H.link(car); car.location = (1.6, 7.5, 0); car.rotation_euler = (0, 0, math.radians(-18))
for n, s, l, m, bv in (("lower", (1.8, 4.5, 0.75), (0, 0, 0.55), paint_car, 0.12), ("cabin", (1.62, 2.6, 0.62), (0, 0.25, 1.2), glass, 0.15),
                       ("roof", (1.5, 2.3, 0.06), (0, 0.3, 1.52), paint_car, 0.03)):
    o = H.box("car_" + n, s, l, m, bevel=bv, segments=4); o.parent = car
for x in (-0.8, 0.8):
    for y in (-1.45, 1.45):
        w = H.cylinder("wheel", 0.33, 0.24, (x, y, 0.33), tyre, rot=(0, math.pi / 2, 0)); w.parent = car
    for y, col, e in ((-2.26, (1.0, 0.95, 0.85), 30), (2.26, (1.0, 0.05, 0.02), 20)):
        hl = H.box("lamp", (0.4, 0.04, 0.12), (x * 0.95, y, 0.8), H.plain("lampm", col, rough=0.2, emission=col, estrength=e)); hl.parent = car
    hz = H.point_light("hazard", (x * 0.95, -2.35, 0.8), 25, color=(1.0, 0.55, 0.1), radius=0.05); hz.parent = car

# ---- ambulance: box body, high-vis side band, blue light bar
amb = bpy.data.objects.new("ambulance", None); H.link(amb); amb.location = (-1.4, 6.0, 0); amb.rotation_euler = (0, 0, math.radians(8))
white = H.plain("ambwhite", (0.88, 0.88, 0.86), rough=0.3, coat=0.8)
chk = bpy.data.materials.new("battenburg"); chk.use_nodes = True
cn = chk.node_tree.nodes; ct = cn.new("ShaderNodeTexChecker"); ct.inputs["Color1"].default_value = (0.9, 0.85, 0.02, 1)
ct.inputs["Color2"].default_value = (0.02, 0.35, 0.08, 1); ct.inputs["Scale"].default_value = 1.0
tcc = cn.new("ShaderNodeTexCoord"); mpc = cn.new("ShaderNodeMapping"); mpc.inputs["Scale"].default_value = (2.5, 2.5, 2.5)
chk.node_tree.links.new(tcc.outputs["Object"], mpc.inputs["Vector"]); chk.node_tree.links.new(mpc.outputs["Vector"], ct.inputs["Vector"])
chk.node_tree.links.new(ct.outputs["Color"], cn["Principled BSDF"].inputs["Base Color"]); cn["Principled BSDF"].inputs["Roughness"].default_value = 0.35
for n, s, l, m, bv in (("box", (2.3, 4.0, 2.2), (0, 0.6, 1.55), white, 0.08), ("cab", (2.2, 1.6, 1.5), (0, -2.05, 1.1), white, 0.12),
                       ("band", (2.32, 5.4, 0.4), (0, -0.1, 1.05), chk, 0.02), ("wind", (2.0, 0.05, 0.7), (0, -2.86, 1.45), glass, 0.04),
                       ("frontband", (2.2, 0.03, 0.28), (0, -2.87, 0.62), chk, 0.01), ("cabband", (2.22, 1.62, 0.3), (0, -2.05, 0.95), chk, 0.02),
                       ("under", (2.1, 5.6, 0.35), (0, -0.2, 0.42), H.plain("dark", (0.05, 0.05, 0.05), rough=0.6), 0.04)):
    o = H.box("amb_" + n, s, l, m, bevel=bv, segments=4); o.parent = amb
for x in (-0.95, 0.95):
    for y in (-1.9, 1.6):
        w = H.cylinder("awheel", 0.38, 0.28, (x, y, 0.38), tyre, rot=(0, math.pi / 2, 0)); w.parent = amb
blue = (0.05, 0.25, 1.0)
for i, x in enumerate((-0.75, -0.25, 0.25, 0.75)):
    on = i in (0, 3)
    lb = H.box("lightbar", (0.42, 0.24, 0.12), (x, -2.2, 1.92), H.plain("lb%d" % i, blue, rough=0.15, emission=blue, estrength=22 if on else 3)); lb.parent = amb
    if on:
        pl = H.point_light("blue", (x, -2.35, 1.95), 5000, color=blue, radius=0.08); pl.parent = amb
for x in (-1.16, 1.16):  # grille / side strobes
    pl = H.point_light("blue_low", (x * 0.8, -2.95, 0.75), 1500, color=blue, radius=0.05); pl.parent = amb
    s = H.box("strobe", (0.18, 0.03, 0.06), (x * 0.8, -2.9, 0.75), H.plain("strobe", blue, emission=blue, estrength=15)); s.parent = amb
H.spot_light("scene_lamp", (-1.2, 2.6, 2.4), 450, (0, 0, 0.8), color=(1.0, 0.93, 0.82), angle=55, radius=0.25)

# ---- traffic cones, debris, barriers
cone_o = H.plain("cone", (1.0, 0.25, 0.02), rough=0.45)
for x, y in ((2.6, 0.5), (2.9, 3.0), (3.1, 5.5), (-0.6, -2.4)):
    H.lathe("cone", [(0.17, 0), (0.17, 0.03), (0.13, 0.03), (0.03, 0.72), (0.0, 0.73)], (x, y, 0), cone_o)
    H.lathe("cone_band", [(0.095, 0.3), (0.075, 0.42)], (x, y, 0), H.plain("band", (0.9, 0.9, 0.9), rough=0.2, metal=0.4))
shard = H.plain("shard", (0.8, 0.85, 0.9), rough=0.02, transmission=1.0, ior=1.5)
for i in range(70):
    H.box("shard", (rnd.uniform(0.01, 0.04),) * 2 + (0.004,), (rnd.gauss(1.2, 0.7), rnd.gauss(4.5, 1.2), 0.003), shard, bevel=0, rot=(0, 0, rnd.uniform(0, 3)))
for y in (10, 12, 14):
    H.gltf("concrete_road_barrier", (4.2, y, 0), rot_z=90)
H.gltf("utility_box_01", (-4.0, 3.0, 0.12), rot_z=90)

# ---- bystanders: a woman on the pavement on the phone, a man (the driver) by the car
froot, frig, fbody = H.patient("Patient_female")
P.stand(frig, froot, arms="phone", head_turn=-20)
froot.location.x, froot.location.y = -2.2, 1.6; froot.rotation_euler.z = math.radians(54)
mroot, mrig, mbody = H.patient("Patient")
P.tint_clothes(mbody, (0.07, 0.07, 0.08), mix=0.7)
P.stand(mrig, mroot, head_turn=10)
mroot.location.x, mroot.location.y = 1.9, 2.9; mroot.rotation_euler.z = math.radians(-33)
bpy.context.view_layer.update()


def shot(name, cam, target, lens, specs, fstop=2.8, focus=None):
    H.camera(cam, target, lens=lens, fstop=fstop, focus=focus)
    H.write_panels(H.screen_panels(specs), os.path.join(H.OUT, name + ".json"))
    H.render(name)


shot("hero-02-roadside", (0.55, -3.1, 1.55), (0.15, 1.0, 1.05), 32, [
    ("title", 0.0, 0.72, 3.4, 1.7, 0.34),
    ("bystander", -0.55, 0.2, 2.2, 0.66, 0.24),
    ("patient_rt", 0.5, 0.25, 2.2, 0.62, 0.2),
    ("abcde", 0.66, -0.45, 1.9, 0.42, 0.33),
], focus=3.0)
shot("hero-02-roadside-b", (-2.4, -2.2, 0.85), (0.4, 1.4, 1.1), 28, [
    ("title", 0.0, 0.72, 3.4, 1.9, 0.38),
    ("bystander", -0.6, 0.15, 2.2, 0.72, 0.26),
    ("patient_rt", -0.4, -0.45, 2.0, 0.66, 0.22),
], focus=2.6)
