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
H.box("bag", (0.62, 0.36, 0.44), (0, -0.02, 0.22), bag_red, bevel=0.09, segments=8)
strap = H.plain("strap", (0.04, 0.04, 0.045), rough=0.7)
refl = H.plain("refl", (0.85, 0.85, 0.85), rough=0.2, metal=0.6)
H.box("bag_band", (0.6, 0.365, 0.025), (0, -0.02, 0.16), refl, bevel=0.008)
H.box("bag_pocket", (0.46, 0.05, 0.2), (0, -0.215, 0.2), bag_red, bevel=0.03, segments=4)
H.box("bag_zip", (0.44, 0.012, 0.012), (0, -0.242, 0.29), strap, bevel=0.003)
for x in (-0.36, 0.36):  # carry straps down the ends
    H.box("bag_strap", (0.02, 0.07, 0.4), (x * 0.86, -0.02, 0.22), strap, bevel=0.004)
H.gltf("medical_box", (-0.75, -0.45, 0), rot_z=30)

# ---- his cycle helmet, knocked off, on the road
dome = [(0.0, 0.17)] + [(0.16 * math.sin(math.radians(a)), 0.17 * math.cos(math.radians(a))) for a in range(12, 91, 6)] + [(0.15, 0.0)]
hm = H.lathe("helmet", dome[::-1], (0.95, -0.9, 0.0), H.plain("helmet", (0.92, 0.92, 0.9), rough=0.3, coat=1))
hm.scale = (1.0, 1.35, 0.85); hm.rotation_euler = (0, math.radians(18), 0.7)
tyre = H.pbr("tyre", "Rubber004", scale=4)
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
H.point_light("rim_blue", (-0.7, 1.1, 1.7), 420, color=blue, radius=0.1).data.specular_factor = 0.0  # no glint in the windscreen
H.spot_light("strobe_pool", (-1.2, 3.2, 2.0), 9000, (0.6, -0.8, 0), color=blue, angle=40, radius=0.05)
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
P.stand(mrig, mroot, arms="phone", head_turn=0)
mroot.location.x, mroot.location.y = 2.2, 3.4; mroot.rotation_euler.z = math.radians(155)
bpy.context.view_layer.update()


def shot(name, cam, target, lens, specs, fstop=2.8, focus=None):
    H.camera(cam, target, lens=lens, fstop=fstop, focus=focus)
    H.write_panels(H.screen_panels(specs), os.path.join(H.OUT, name + ".json"))
    H.render(name)


shot("hero-02-roadside", (0.55, -3.1, 1.55), (0.15, 1.0, 1.05), 32, [
    ("title", 0.0, 0.72, 3.4, 1.7, 0.34),
    ("bystander", -0.43, 0.28, 2.2, 0.66, 0.24, (-2.12, 1.5, 1.22)),
    ("patient_rt", 0.42, 0.2, 2.2, 0.62, 0.2, (0.12, -0.1, 1.02)),
    ("abcde", 0.66, -0.43, 1.9, 0.42, 0.47),
], focus=3.0)
shot("hero-02-roadside-b", (-1.0, -2.7, 0.8), (0.3, 3.0, 1.15), 28, [
    ("title", 0.0, 0.72, 3.4, 1.9, 0.38),
    ("bystander", -0.5, 0.3, 2.4, 0.72, 0.26, (-2.12, 1.5, 1.22)),
    ("patient_rt", 0.69, -0.3, 2.0, 0.66, 0.22, (0.2, -0.08, 0.98)),
], focus=2.9)
