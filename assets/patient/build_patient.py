"""Builds a patient avatar (Patient[_variant].usdz + .json) with Blender + MPFB.

Run through assets/patient/build.sh [male|female|pregnant]. Everything the models are made of
comes from the MakeHuman "system assets" pack, which is CC0. See assets/patient/README.md.

Variants
  male      seated adult man on a stool (the original model, `Patient`)
  female    seated adult woman on a stool, same pose / rig / anchors (`Patient_female`)
  pregnant  woman, third trimester, semi-recumbent on an examination couch, abdomen bare,
            for the obstetric ultrasound scenario (`Patient_pregnant`)

Blender space: Z up, the character faces -Y, the character's left is +X.
Avatar space (sidecar JSON): metres, Y up, the patient faces +Z, origin on the floor, patient's
right is -X. avatar = (x, z, -y) of Blender space.
"""
import bpy, bmesh, json, os, sys, math
from mathutils import Vector, Euler, Matrix
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

VARIANT = os.environ.get("VARIANT", "male")
OUT = os.environ.get("OUT", "/tmp/patient")
os.makedirs(OUT, exist_ok=True)
U = LocationService.get_user_data()
def asset(*p): return os.path.join(U, *p)

SEATED_POSE = {
    "thigh_l": [0.16, -1, -0.06], "thigh_r": [-0.16, -1, -0.06],
    "calf_l": [0.0, -0.06, -1], "calf_r": [0.0, -0.06, -1],
    "foot_l": None, "foot_r": None,
    "upperarm_l": [0.10, -0.22, -1], "upperarm_r": [-0.10, -0.22, -1],
    "lowerarm_l": [-0.20, -1, -0.66], "lowerarm_r": [0.20, -1, -0.66],
    "hand_l": [-0.12, -1, -0.32], "hand_r": [0.12, -1, -0.32],
}

# Couch the pregnant variant lies on (also written to the sidecar for the app).
COUCH_H = 0.62            # top of the seat / leg rest above the floor, m
BACK_ANGLE = 40.0         # back-rest angle above horizontal, degrees
COUCH_WIDTH = 0.66

CONFIG = {
    "male": dict(
        name="Patient", gender=1.0, age=0.5, muscle=0.5, weight=0.45,
        skin="young_caucasian_male",
        assets=[("clothes", os.environ.get("SUIT", "male_casualsuit01"), "Clothes"), ("clothes", "shoes02", "Clothes"),
                ("hair", "short02", "Hair"), ("eyebrows", "eyebrow001", "Eyebrows"),
                ("eyelashes", "eyelashes01", "Eyelashes"), ("eyes", "low-poly", "Eyes")],
        hair="short02", pose=SEATED_POSE),
    "female": dict(
        name="Patient_female", gender=0.0, age=0.52, muscle=0.4, weight=0.45,   # age 0.5 = 25 y, 0.52 = ~28 y
        skin="young_caucasian_female",
        assets=[("clothes", os.environ.get("SUIT", "female_casualsuit01"), "Clothes"), ("clothes", "shoes01", "Clothes"),
                ("hair", os.environ.get("HAIR", "ponytail01"), "Hair"), ("eyebrows", "eyebrow001", "Eyebrows"),
                ("eyelashes", "eyelashes01", "Eyelashes"), ("eyes", "low-poly", "Eyes")],
        hair=os.environ.get("HAIR", "ponytail01"), shoe_cut=float(os.environ.get("SHOE_CUT", "0.10")),
        pose=dict(SEATED_POSE, thigh_l=[0.12, -1, -0.06], thigh_r=[-0.12, -1, -0.06])),
    "pregnant": dict(
        name="Patient_pregnant", gender=0.0, age=0.546, muscle=0.35, weight=0.5,  # ~31 y
        skin="young_caucasian_female",
        assets=[("clothes", os.environ.get("SUIT", "female_sportsuit01"),  "Clothes"),
                ("hair", os.environ.get("HAIR", "ponytail01"), "Hair"), ("eyebrows", "eyebrow001", "Eyebrows"),
                ("eyelashes", "eyelashes01", "Eyelashes"), ("eyes", "low-poly", "Eyes")],
        hair=os.environ.get("HAIR", "ponytail01"), pregnant=float(os.environ.get("PREG", "1.2")), pose=None),
}
CFG = CONFIG[VARIANT]
NAME = CFG["name"]

bpy.ops.wm.read_factory_settings(use_empty=True)
macro = TargetService.get_default_macro_info_dict()
macro.update(gender=CFG["gender"], age=CFG["age"], muscle=CFG["muscle"], weight=CFG["weight"])
macro["race"] = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}
base = HumanService.create_human(scale=0.1, macro_detail_dict=macro)
if CFG.get("pregnant"):
    # a late second / third trimester bump; loaded before rig and clothes so they are fitted to it
    sk = TargetService.load_target(base, TargetService.target_full_path("stomach-pregnant-incr"), weight=0.0)
    sk.slider_max = max(1.0, CFG["pregnant"]); sk.value = CFG["pregnant"]
rig = HumanService.add_builtin_rig(base, "game_engine")
HumanService.set_character_skin(asset("skins", CFG["skin"], CFG["skin"] + ".mhmat"), base, skin_type="GAMEENGINE")
for kind, name, typ in CFG["assets"]:
    HumanService.add_mhclo_asset(asset(kind, name, name + ".mhclo"), base, asset_type=typ, subdiv_levels=0, material_type="GAMEENGINE")


def cut_belly(z_lo, z_hi):
    """Pregnant variant: removes the clothing between the bust and the (lowered) trouser waistband
    and un-hides the skin underneath, so the abdomen is bare (a lifted top over low-rise leggings)."""
    suit = CFG["assets"][0][1]
    clothes = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("." + suit))
    bm = bmesh.new(); bm.from_mesh(clothes.data)
    gone = [v for v in bm.verts if z_lo < (clothes.matrix_world @ v.co).z < z_hi]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(clothes.data); bm.free()
    # skin under the removed clothes: take it out of the mask group the suit added to the base mesh
    grp = base.vertex_groups.get("Delete." + suit)
    if grp:
        tmp = base.shape_key_add(name="tmp_mix", from_mix=True)
        idx = [i for i, d in enumerate(tmp.data) if z_lo < (base.matrix_world @ d.co).z < z_hi]
        base.shape_key_remove(tmp)
        grp.remove(idx)
    print("CUT clothes verts removed:", len(gone), "skin verts unmasked:", len(idx) if grp else 0)


def trim_shoes(z_max):
    """The MakeHuman shoes run up the shin (hidden under trousers by design); here they poke through
    the jeans hem with their unpainted texture, so the collar above the ankle is removed."""
    shoe = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith(".shoes01"))
    bm = bmesh.new(); bm.from_mesh(shoe.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if (shoe.matrix_world @ v.co).z > z_max], context="VERTS")
    bm.to_mesh(shoe.data); bm.free()

if CFG.get("shoe_cut"):
    trim_shoes(CFG["shoe_cut"])

if CFG.get("pregnant"):
    cut_belly(float(os.environ.get("CUT_LO", "0.80")), float(os.environ.get("CUT_HI", "1.10")))

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones

def aim(name, target, roll=0.0):
    b = pb[name]
    cur = (b.tail - b.head).normalized()
    q = cur.rotation_difference(Vector(target).normalized())
    head = b.head.copy()
    R = q.to_matrix().to_4x4()
    if roll:
        R = Matrix.Rotation(math.radians(roll), 4, Vector(target).normalized()) @ R
    b.matrix = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ b.matrix
    bpy.context.view_layer.update()

def tilt(name, deg):
    """Rotates a bone (and so its children) about the X axis through its head; negative leans back."""
    b = pb[name]
    head = b.head.copy()
    b.matrix = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, "X") @ Matrix.Translation(-head) @ b.matrix
    bpy.context.view_layer.update()

if CFG["pose"] is not None:
    POSE = json.loads(os.environ.get("POSE", "{}")) or CFG["pose"]
    ROLL = json.loads(os.environ.get("ROLL", "{}"))
    for name, target in POSE.items():
        if target: aim(name, target, ROLL.get(name, 0.0))
else:
    # semi-recumbent on an examination couch: trunk reclined on the back-rest, legs forward on the
    # couch, arms relaxed at her sides, head turned a little towards the clinician at her right
    th = math.radians(BACK_ANGLE)
    tilt("pelvis", -(90.0 - BACK_ANGLE))
    POSE = json.loads(os.environ.get("POSE", "{}")) or {
        "thigh_l": [0.10, -1, 0.0], "thigh_r": [-0.10, -1, 0.0],
        "calf_l": [0.03, -1, -0.10], "calf_r": [-0.03, -1, -0.10],
        "foot_l": [0.20, -0.74, 0.67], "foot_r": [-0.20, -0.74, 0.67],
        "upperarm_l": [0.28, -0.72, -0.62], "upperarm_r": [-0.28, -0.72, -0.62],
        "lowerarm_l": [0.12, -0.80, -0.55], "lowerarm_r": [-0.12, -0.80, -0.55],
        "hand_l": [0.05, -0.85, -0.50], "hand_r": [-0.05, -0.85, -0.50],
        "neck_01": [0.0, 0.50, 0.87], "head": [0.0, 0.42, 0.91],
    }
    ROLL = json.loads(os.environ.get("ROLL") or '{"head": 14}')
    for name, target in POSE.items():
        if target: aim(name, target, ROLL.get(name, 0.0))
bpy.ops.object.mode_set(mode="OBJECT")


# ---- bake: shape keys + modifiers applied in the seated pose, pose becomes the rest pose
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    if o.data.shape_keys: bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE"); bpy.ops.pose.armature_apply(selected=False); bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")
body = bpy.data.objects["Human"]
bpy.context.view_layer.update()


def sample_belly():
    """Pregnant variant: landmarks measured on the skin (ray casts onto the posed body, before the
    clothes are joined in). Returns {name: (position, outward normal)} in world (Blender) space."""
    th = math.radians(BACK_ANGLE)
    u = Vector((0, math.cos(th), math.sin(th)))          # up the trunk
    n = Vector((0, -math.sin(th), math.cos(th)))         # out of the chest / belly
    origin = rig.matrix_world @ pb["pelvis"].head
    inv = body.matrix_world.inverted()
    mw = body.matrix_world
    def hit(s, x, offset=0.0):
        p = origin + u * s + Vector((x, 0, 0))
        o = p + n * 0.8
        ok, loc, nrm, idx = body.ray_cast(inv @ o, inv.to_3x3() @ (-n))
        return (mw @ loc, (mw.to_3x3() @ nrm).normalized()) if ok else (None, None)
    prof = []
    for i in range(-5, 90):
        s = i * 0.01
        loc, _ = hit(s, 0.0)
        if loc is not None: prof.append((s, (loc - origin).dot(n)))
    return origin, u, n, hit, prof


def smooth_normal(pos, radius=0.03):
    """Average of the skin vertex normals within `radius` of pos (world space)."""
    me = body.data; mw = body.matrix_world; acc = Vector()
    for v in me.vertices:
        if (mw @ v.co - pos).length < radius: acc += mw.to_3x3() @ v.normal
    return acc.normalized() if acc.length else acc


belly = None
if CFG.get("pregnant"):
    origin, u, n, hit, prof = sample_belly()
    for s, h in prof: print("PROFILE %.2f %.3f" % (s, h))
    # Landmarks from the midline profile h(s) (surface height above the pelvis plane, s up the trunk):
    #  center  = middle of the plateau of the most anterior point (the navel level)
    #  fundus  = top of the bump: last point still 10 % of the bump height above the line joining
    #            the pubic region and the sternum
    #  lower   = suprapubic: first point reaching 85 % of the maximum height
    #  left / right = on the flank of the dome, where it has fallen 4 cm below the centre height
    s_pub, s_ster = float(os.environ.get("S_PUB", "0.02")), float(os.environ.get("S_STER", "0.60"))
    h_of = dict((round(s, 2), h) for s, h in prof)
    h_pub, h_ster = h_of[round(s_pub, 2)], h_of[round(s_ster, 2)]
    rel = [(s, h - (h_pub + (h_ster - h_pub) * (s - s_pub) / (s_ster - s_pub))) for s, h in prof if s_pub <= s <= s_ster]
    r_max = max(r for _, r in rel)
    s_fund = max(s for s, r in rel if r > 0.10 * r_max)
    abd = [(s, h) for s, h in prof if 0.0 <= s <= s_fund]
    h_max = max(h for _, h in abd)
    plateau = [s for s, h in abd if h >= h_max - 0.002]
    s_c = (min(plateau) + max(plateau)) / 2
    s_low = min(s for s, h in abd if h >= 0.85 * h_max)
    h_c = hit(s_c, 0.0)[0]
    h_c = (h_c - origin).dot(n)
    half = 0.0
    for i in range(1, 40):
        loc, _ = hit(s_c, i * 0.005)
        if loc is None or (loc - origin).dot(n) < h_c - 0.04: break
        half = i * 0.005
    print("BELLY s_center=%.3f s_fundus=%.3f s_lower=%.3f half_width=%.3f h_max=%.3f" % (s_c, s_fund, s_low, half, h_max))
    def pt(s, x=0.0): return hit(s, x)
    belly = {
        "abdomen_fundus": pt(s_fund), "abdomen_upper": pt((s_fund + s_c) / 2), "abdomen_center": pt(s_c),
        "abdomen_lower": pt(s_low),
        # patient's left is +X in Blender space
        "abdomen_left": pt(s_c, +half), "abdomen_right": pt(s_c, -half),
    }
    belly = {k: (p, smooth_normal(p)) for k, (p, _) in belly.items()}
    for k, (p, nn) in belly.items(): print("BELLYPT", k, [round(c, 3) for c in p], [round(c, 3) for c in nn])

bpy.ops.object.select_all(action="DESELECT")
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.modifiers.new("Armature", "ARMATURE").object = rig
# floor: lowest evaluated vertex -> z = 0
dg = bpy.context.evaluated_depsgraph_get()
def verts(obj):
    e = obj.evaluated_get(dg); m = e.to_mesh()
    out = [e.matrix_world @ v.co for v in m.vertices]; e.to_mesh_clear(); return out
meshes = [body]
zmin = min(v.z for o in meshes for v in verts(o))
if CFG.get("pregnant"):
    # the lowest body point rests on the couch top
    rig.location.z += COUCH_H - zmin
    shift = COUCH_H - zmin
else:
    rig.location.z -= zmin
    shift = -zmin
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
seat = min(v.z for o in meshes for v in verts(o) if abs(v.x) < 0.2 and -0.12 < v.y < 0.15 and v.z > 0.25) if not CFG.get("pregnant") else COUCH_H
info = {"seat_height": round(seat, 3)}
for j in ["hand_r", "lowerarm_r", "hand_l", "lowerarm_l", "upperarm_r", "head", "pelvis"]:
    h = rig.matrix_world @ pb[j].head; t = rig.matrix_world @ pb[j].tail
    info[j] = {"head": [round(c, 3) for c in h], "tail": [round(c, 3) for c in t]}
def avatar(v): return [round(v[0], 3) + 0.0, round(v[2], 3) + 0.0, round(-v[1], 3) + 0.0]
wr, el = Vector(info["hand_r"]["head"]), Vector(info["lowerarm_r"]["head"])
if not CFG.get("pregnant"):
    sidecar = {
        "_doc": "Avatar space: metres, Y up, patient faces +Z, origin on the floor. Written by build_patient.py.",
        "seat_height": info["seat_height"],
        "anchors": {
            # thumb side is up in this pose: nudge the wrist anchor onto the radial side
            "right_wrist": avatar(wr + Vector((0.0, -0.01, 0.02))),
            "right_forearm": avatar(el.lerp(wr, 0.45)),
            "left_wrist": avatar(Vector(info["hand_l"]["head"]) + Vector((0.0, -0.01, 0.02))),
        },
    }
else:
    sh = Vector((0, 0, shift))
    def av_dir(d): return [round(d[0], 3) + 0.0, round(d[2], 3) + 0.0, round(-d[1], 3) + 0.0]
    th = math.radians(BACK_ANGLE)
    n_bl = Vector((0, -math.sin(th), math.cos(th)))
    allv = verts(body)
    # back-rest plane: touches the back (trunk rear surface), pivot where it meets the couch top
    o_w = origin + sh
    u_bl = Vector((0, math.cos(th), math.sin(th)))
    back = [v for v in allv if abs(v.x) < 0.18 and float(os.environ.get("BACK_LO", "0.02")) < (v - o_w).dot(u_bl) < 0.55
            and (v - o_w).dot(n_bl) < 0.1]
    d_plane = min(v.dot(n_bl) for v in back)
    y_pivot = (math.cos(th) * COUCH_H - d_plane) / math.sin(th)
    foot_end = min(v.y for v in allv)                    # most forward point (toes), Blender -Y
    head_top = max(v.z for v in allv)
    anchors = {k: avatar(p + sh) for k, (p, _) in belly.items()}
    anchors["head"] = avatar(((rig.matrix_world @ pb["head"].head) + (rig.matrix_world @ pb["head"].tail)) * 0.5)
    anchors["right_wrist"] = avatar(wr)
    anchors["left_wrist"] = avatar(Vector(info["hand_l"]["head"]))
    sidecar = {
        "_doc": "Avatar space: metres, Y up, patient faces +Z, origin on the floor, patient's right is -X. "
                "Semi-recumbent on an examination couch: `seat_height` is the couch top (seat and leg rest). "
                "`couch.back_rest_pivot` is where the back-rest plane meets the couch top; the back-rest rises from "
                "it towards -Z at `back_rest_angle_deg` above horizontal, the leg rest extends towards +Z. "
                "`anchors` lie on the skin surface; `normals` are the outward surface normals. Written by build_patient.py.",
        "seat_height": round(COUCH_H, 3),
        "couch": {
            "seat_height": round(COUCH_H, 3),
            "leg_rest_height": round(COUCH_H, 3),
            "width": COUCH_WIDTH,
            "thickness": 0.12,
            "back_rest_angle_deg": BACK_ANGLE,
            "back_rest_pivot": [0.0, round(COUCH_H, 3), round(-y_pivot, 3)],
            "back_rest_length": round((head_top - COUCH_H) / math.sin(th) + 0.10, 2),
            "seat_length": round(-foot_end + y_pivot + 0.10, 2),
        },
        "anchors": anchors,
        "normals": {k: av_dir(nn) for k, (_, nn) in belly.items()},
    }
    print("COUCH plane d=%.3f foot_end=%.3f head_top=%.3f" % (d_plane, foot_end, head_top))
print("SIDECAR", json.dumps(sidecar))
json.dump(sidecar, open(os.path.join(OUT, NAME + ".json"), "w"), indent=2)
# material name pattern build.sh uses for the alpha cut-out of hair, brows and lashes
open(os.path.join(OUT, NAME + ".alpha"), "w").write("%s|eyebrow|eyelash" % CFG["hair"])


# ---- export USDZ (textures capped at 1024 px)
tex = os.path.join(OUT, "tex"); os.makedirs(tex, exist_ok=True)
for img in bpy.data.images:
    if img.size[0] == 0: continue
    if max(img.size) > 1024: img.scale(1024, 1024)
    img.filepath_raw = os.path.join(tex, os.path.splitext(os.path.basename(img.filepath or img.name))[0] + ".png")
    img.file_format = "PNG"; img.save()
for m in bpy.data.materials:
    if not m.node_tree or any(k in m.name for k in (CFG["hair"], "eyebrow", "eyelash")): continue
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    for link in list(bsdf.inputs["Alpha"].links): m.node_tree.links.remove(link)
    bsdf.inputs["Alpha"].default_value = 1.0
print("MATERIALS", [(m.name, [n.type for n in m.node_tree.nodes]) for m in bpy.data.materials if m.node_tree])
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); rig.select_set(True)
bpy.ops.wm.usd_export(filepath=os.path.join(OUT, NAME + ".usdz"), selected_objects_only=True,
                      export_animation=False, export_armatures=True, export_materials=True)
# preview render
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
RES = 900 if VARIANT == "male" else 800
scene.render.resolution_x, scene.render.resolution_y = RES, RES
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30)); scene.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
def shot(name, loc, look=(0, -0.2, 0.75)):
    cam.location = loc
    d = Vector(look) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, name); bpy.ops.render.render(write_still=True)
if VARIANT == "pregnant":
    # preview only (not exported): the couch drawn from the sidecar values, and the anchors
    c = sidecar["couch"]; th = math.radians(BACK_ANGLE)
    def box(name, size, center, rot=0.0, color=(0.2, 0.35, 0.55, 1)):
        bpy.ops.mesh.primitive_cube_add(size=1); o = bpy.context.object; o.name = name
        o.scale = size; o.location = center; o.rotation_euler = (rot, 0, 0)
        mat = bpy.data.materials.new(name); mat.diffuse_color = color; o.data.materials.append(mat)
        mat.use_nodes = True; mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = color
        return o
    px, py, pz = c["back_rest_pivot"]; yb = -pz                         # pivot in Blender coordinates
    seat_len = c["seat_length"]; t = c["thickness"]
    box("seat", (c["width"], seat_len, t), (0, yb - seat_len / 2, c["seat_height"] - t / 2))
    br = c["back_rest_length"]
    box("back", (c["width"], br, t), (0, 0, 0))
    bk = bpy.data.objects["back"]
    # back-rest: slab whose top face lies on the plane through the pivot, inclined BACK_ANGLE
    bk.rotation_euler = (th, 0, 0)        # long axis (Y) tilts up towards +Y (behind her)
    nrm = Vector((0, -math.sin(th), math.cos(th)))
    ctr = Vector((0, yb, c["seat_height"])) + Vector((0, math.cos(th), math.sin(th))) * (br / 2) - nrm * (t / 2)
    bk.location = ctr
    for k, p in sidecar["anchors"].items():
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, location=(p[0], -p[2], p[1]))
        sp = bpy.context.object; mat = bpy.data.materials.new(k)
        mat.use_nodes = True; mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0.1, 0.1, 1)
        sp.data.materials.append(mat)
    shot("front.png", (0.0, -3.2, 1.6), look=(0, -0.2, 0.9))
    shot("threequarter.png", (1.9, -2.2, 1.7), look=(0, -0.3, 0.9))
    shot("side.png", (-3.2, -0.4, 1.3), look=(0, -0.3, 0.9))
    shot("top.png", (0.0, -0.6, 3.2), look=(0, -0.5, 0.8))
    shot("head.png", (0.7, -0.5, 1.75), look=(0, 0.48, 1.2))
elif VARIANT == "female":
    shot("front.png", (0.9, -2.6, 1.3))
    shot("threequarter.png", (1.8, -2.0, 1.4))
    shot("side.png", (-2.6, -0.6, 1.0))
else:
    shot("front.png", (0.9, -2.6, 1.3))
    shot("side.png", (-2.6, -0.6, 1.0))
    shot("top.png", (-0.35, -1.0, 1.7), look=(-0.2, -0.35, 0.6))
