"""Builds the seated patient avatar (Patient.usdz + Patient.json) with Blender + MPFB.

Run through assets/patient/build.sh. Everything the model is made of comes from the
MakeHuman "system assets" pack, which is CC0. See assets/patient/README.md.

Blender space: Z up, the character faces -Y, the character's left is +X.
"""
import bpy, json, os, sys, math
from mathutils import Vector, Euler, Matrix
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

OUT = os.environ.get("OUT", "/tmp/patient")
os.makedirs(OUT, exist_ok=True)
U = LocationService.get_user_data()
def asset(*p): return os.path.join(U, *p)

bpy.ops.wm.read_factory_settings(use_empty=True)
macro = TargetService.get_default_macro_info_dict()
macro.update(gender=1.0, age=0.5, muscle=0.5, weight=0.45)
macro["race"] = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}
base = HumanService.create_human(scale=0.1, macro_detail_dict=macro)
rig = HumanService.add_builtin_rig(base, "game_engine")
HumanService.set_character_skin(asset("skins", "young_caucasian_male", "young_caucasian_male.mhmat"), base, skin_type="GAMEENGINE")
for kind, name, typ in [("clothes", os.environ.get("SUIT", "male_casualsuit01"), "Clothes"), ("clothes", "shoes02", "Clothes"),
                        ("hair", "short02", "Hair"), ("eyebrows", "eyebrow001", "Eyebrows"),
                        ("eyelashes", "eyelashes01", "Eyelashes"), ("eyes", "low-poly", "Eyes")]:
    HumanService.add_mhclo_asset(asset(kind, name, name + ".mhclo"), base, asset_type=typ, subdiv_levels=0, material_type="GAMEENGINE")
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

POSE = json.loads(os.environ.get("POSE", "{}")) or {
    "thigh_l": [0.16, -1, -0.06], "thigh_r": [-0.16, -1, -0.06],
    "calf_l": [0.0, -0.06, -1], "calf_r": [0.0, -0.06, -1],
    "foot_l": None, "foot_r": None,
    "upperarm_l": [0.10, -0.22, -1], "upperarm_r": [-0.10, -0.22, -1],
    "lowerarm_l": [-0.20, -1, -0.66], "lowerarm_r": [0.20, -1, -0.66],
    "hand_l": [-0.12, -1, -0.32], "hand_r": [0.12, -1, -0.32],
}
ROLL = json.loads(os.environ.get("ROLL", "{}"))
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
rig.location.z -= zmin
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
seat = min(v.z for o in meshes for v in verts(o) if abs(v.x) < 0.2 and -0.12 < v.y < 0.15 and v.z > 0.25)
info = {"seat_height": round(seat, 3)}
for j in ["hand_r", "lowerarm_r", "hand_l", "lowerarm_l", "upperarm_r", "head", "pelvis"]:
    h = rig.matrix_world @ pb[j].head; t = rig.matrix_world @ pb[j].tail
    info[j] = {"head": [round(c, 3) for c in h], "tail": [round(c, 3) for c in t]}
def avatar(v): return [round(v[0], 3), round(v[2], 3), round(-v[1], 3)]
wr, el = Vector(info["hand_r"]["head"]), Vector(info["lowerarm_r"]["head"])
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
print("SIDECAR", json.dumps(sidecar))
json.dump(sidecar, open(os.path.join(OUT, "Patient.json"), "w"), indent=2)


# ---- export USDZ (textures capped at 1024 px)
tex = os.path.join(OUT, "tex"); os.makedirs(tex, exist_ok=True)
for img in bpy.data.images:
    if img.size[0] == 0: continue
    if max(img.size) > 1024: img.scale(1024, 1024)
    img.filepath_raw = os.path.join(tex, os.path.splitext(os.path.basename(img.filepath or img.name))[0] + ".png")
    img.file_format = "PNG"; img.save()
for m in bpy.data.materials:
    if not m.node_tree or any(k in m.name for k in ("short", "eyebrow", "eyelash")): continue
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    for link in list(bsdf.inputs["Alpha"].links): m.node_tree.links.remove(link)
    bsdf.inputs["Alpha"].default_value = 1.0
print("MATERIALS", [(m.name, [n.type for n in m.node_tree.nodes]) for m in bpy.data.materials if m.node_tree])
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); rig.select_set(True)
bpy.ops.wm.usd_export(filepath=os.path.join(OUT, "Patient.usdz"), selected_objects_only=True,
                      export_animation=False, export_armatures=True, export_materials=True)
# preview render
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 900, 900
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
shot("front.png", (0.9, -2.6, 1.3))
shot("side.png", (-2.6, -0.6, 1.0))
shot("top.png", (-0.35, -1.0, 1.7), look=(-0.2, -0.35, 0.6))
