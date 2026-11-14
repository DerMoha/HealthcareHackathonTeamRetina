"""Baked poses for the people around the patient (PitchCrowd.swift): the bundled seated avatars
(Patient.usdz / Patient_female.usdz) posed in Blender and saved as static meshes,
visionos/MedSimXR/Resources/Pitch/crowd_<pose>_<m|f>.usdz.

  /opt/homebrew/bin/blender -b --python visionos/scripts/pitch_crowd_poses.py -- [pose ...] [--g m|f] [--preview DIR] [--no-write]

No pose names = all of POSES. --preview DIR also renders a front/side contact sheet per pose
(DIR/<pose>_<g>.png, Workbench, textured). Re-running overwrites the files.

How a file is made:
- import the avatar USDZ, pose its armature with the hero-render helpers (assets/pitch_hero/hero_common.py:
  pose_aim, pose_rot, solve_two_bone, curl), evaluate the skinned mesh (Armature modifier applied);
- write a new USD with the ORIGINAL mesh prim (same vertex order, faces, faceVarying UVs, the seven
  material GeomSubsets in the same order: body, suit, shoes, hair, eyebrows, eyelashes, eyes), only the
  points and normals replaced; skinning, skeleton and the MakeHuman vertex-group primvars removed;
- the materials keep their names but lose their textures (flat colours = the textures' mean), so a file
  is ~0.6 MB instead of 8 MB. The app copies the real materials from the cached original avatar
  (PitchCrowd.person), so outfits (PitchCrowd.dress), hair and skin tints work as before;
- avatar space like the originals' sidecars: metres, Y up, faces +Z, origin on the floor under the
  pelvis (the lowest vertex, a shoe sole or a knee, at y = 0);
- `anchor_head` (Xform at the head joint, rotated with the head) for hats/masks; `phone` (a separate
  mesh with its own material) in the right hand of the filming pose.
Blender space while posing: Z up, the avatar faces -Y, its left is +X.
"""
import bpy, bmesh, math, os, sys, tempfile, zipfile, shutil
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "assets", "pitch_hero"))
import hero_common as H  # noqa: E402
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, UsdUtils  # noqa: E402

RES = os.path.join(ROOT, "visionos", "MedSimXR", "Resources")
OUT = os.path.join(RES, "Pitch")
AVATAR = {"m": "Patient", "f": "Patient_female"}
V = Vector


# ---------------------------------------------------------------- pose helpers

class Rig:
    """The imported armature plus rest measurements (bone lengths, rest foot orientation)."""
    def __init__(self, rig):
        self.rig = rig
        pb = rig.pose.bones
        self.foot_rest = {s: pb["foot_" + s].matrix.to_3x3().copy() for s in "lr"}
        self.head_rest = pb["head"].matrix.to_3x3().copy()
        self.leg = {s: pb["thigh_" + s].length + pb["calf_" + s].length for s in "lr"}
        self.k = (pb["thigh_l"].length + pb["calf_l"].length + pb["spine_03"].length) / (0.43 + 0.437 + 0.139)  # 1 = male
        self.palm_sign = {}
        for s in "lr":  # palm normal at rest: the hands are held thumb up, palms facing each other (medially)
            n = self._palm_raw(s)
            self.palm_sign[s] = 1 if n.x * (-1 if s == "l" else 1) > 0 else -1

    def w(self, bone, tail=False):
        return H.bone_world(self.rig, bone, tail)

    def _palm_raw(self, s):
        a = self.w("index_01_" + s) - self.w("pinky_01_" + s)
        b = self.w("middle_01_" + s) - self.w("hand_" + s)
        return a.cross(b).normalized()

    def palm(self, s):
        return self._palm_raw(s) * self.palm_sign[s]

    def update(self):
        bpy.context.view_layer.update()


def sx(s):  # +1 for the avatar's left, -1 for its right (Blender X)
    return 1.0 if s == "l" else -1.0


def other(s):
    return "r" if s == "l" else "l"


def set_world_rot(r, bone, rot3):
    pb = r.rig.pose.bones[bone]
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ rot3.to_4x4()
    r.update()


def plant_foot(r, s, yaw_out=8.0, pitch=0.0):
    """Foot flat as in the seated rest (sole on the floor), toes turned out by yaw_out degrees,
    pitch > 0 lifts the heel (toes stay down)."""
    R = Matrix.Rotation(math.radians(sx(s) * -yaw_out), 3, "Z") @ r.foot_rest[s]
    if pitch:
        R = Matrix.Rotation(math.radians(pitch), 3, R @ V((1, 0, 0))) @ R
    set_world_rot(r, "foot_" + s, R)


def leg_to(r, s, ankle, pole_fwd=1.0, pole_out=0.15):
    hip = r.w("thigh_" + s)
    H.solve_two_bone(r.rig, "thigh_" + s, "calf_" + s, ankle, hip + V((sx(s) * pole_out, -pole_fwd, -0.3)))


def stand_legs(r, weight="l", bend=0.995, free_fwd=0.09, free_out=0.07, hip_drop=4.0, toe_out=(8, 14)):
    """Contrapposto: weight on `weight` (knee nearly straight, foot under the hip), the free leg's hip
    lower, its knee bent and its foot a little forward and out. Then both feet flat."""
    f = other(weight)
    H.pose_rot(r.rig, "pelvis", (0, 1, 0), -sx(weight) * hip_drop)   # free hip drops
    H.pose_rot(r.rig, "spine_02", (0, 1, 0), sx(weight) * hip_drop * 0.7)  # shoulders counter-tilt
    H.pose_rot(r.rig, "pelvis", (0, 0, 1), sx(weight) * 4)        # hips turned a little
    hw, hf = r.w("thigh_" + weight), r.w("thigh_" + f)
    z = hw.z - bend * r.leg[weight]
    leg_to(r, weight, V((hw.x * 0.75, hw.y - 0.01, z)))
    leg_to(r, f, V((hf.x + sx(f) * free_out * r.k, hf.y - free_fwd * r.k, z)))
    plant_foot(r, weight, toe_out[0]); plant_foot(r, f, toe_out[1])


def arm_ik(r, s, wrist, pole):
    H.solve_two_bone(r.rig, "upperarm_" + s, "lowerarm_" + s, wrist, pole)


def hang_arm(r, s, out=0.11, back=0.05, bend=0.32, flex=0.12):
    """Arm hanging by the side, elbow a little bent, palm facing the thigh."""
    H.pose_aim(r.rig, "upperarm_" + s, (sx(s) * out, back, -1))
    H.pose_aim(r.rig, "lowerarm_" + s, (sx(s) * out * 0.3, -bend, -1))
    face_palm(r, s, V((-sx(s), 0.25, 0)))
    H.pose_aim(r.rig, "hand_" + s, (-sx(s) * flex * 0.5, -bend - flex, -1))
    H.curl(r.rig, s, 22, 8)


def face_palm(r, s, desired, bone=None):
    """Rolls the forearm about its own axis so the palm faces `desired` as far as it can."""
    bone = bone or "lowerarm_" + s
    axis = (r.w(bone, True) - r.w(bone)).normalized()
    n = r.palm(s)
    d = V(desired).normalized()
    n_p = (n - axis * n.dot(axis)); d_p = (d - axis * d.dot(axis))
    if n_p.length < 1e-4 or d_p.length < 1e-4: return
    n_p.normalize(); d_p.normalize()
    ang = math.atan2(axis.dot(n_p.cross(d_p)), n_p.dot(d_p))
    H.pose_rot(r.rig, bone, axis, math.degrees(ang))


def aim_hand(r, s, direction, palm=None):
    H.pose_aim(r.rig, "hand_" + s, direction)
    if palm is not None:  # roll the hand itself about its axis (small corrections only)
        axis = (r.w("hand_" + s, True) - r.w("hand_" + s)).normalized()
        n = r.palm(s); d = V(palm).normalized()
        n_p = (n - axis * n.dot(axis)); d_p = (d - axis * d.dot(axis))
        if n_p.length > 1e-4 and d_p.length > 1e-4:
            n_p.normalize(); d_p.normalize()
            H.pose_rot(r.rig, "hand_" + s, axis, math.degrees(math.atan2(axis.dot(n_p.cross(d_p)), n_p.dot(d_p))))


def finger(r, s, name, deg):
    for i in (1, 2, 3):
        pb = r.rig.pose.bones.get("%s_0%d_%s" % (name, i, s))
        if pb: pb.rotation_mode = "XYZ"; pb.rotation_euler.x += math.radians(deg * (0.6 if i == 1 else 1.0))
    r.update()


def lean(r, deg, spine=("spine_01", "spine_02", "spine_03")):
    for b in spine: H.pose_rot(r.rig, b, (1, 0, 0), deg / len(spine))


def look(r, yaw=0.0, pitch=0.0, tilt=0.0):
    """Head: yaw > 0 turns to the avatar's left, pitch > 0 nods down, tilt > 0 leans to its left."""
    if pitch: H.pose_rot(r.rig, "neck_01", (1, 0, 0), pitch * 0.4); H.pose_rot(r.rig, "head", (1, 0, 0), pitch * 0.6)
    if yaw: H.pose_rot(r.rig, "neck_01", (0, 0, 1), yaw * 0.35); H.pose_rot(r.rig, "head", (0, 0, 1), yaw * 0.65)
    if tilt: H.pose_rot(r.rig, "head", (0, 1, 0), -tilt)


def chest(r):   # on the front of the chest, at the lower end of the sternum
    return r.w("spine_03", True) + V((0, -0.15 * r.k, -0.03 * r.k))


def face(r):    # in front of the mouth
    return r.w("head") + V((0, -0.11 * r.k, 0.0))


# ---------------------------------------------------------------- poses
# Each gets (rig wrapper, g) and returns extras: {"phone": (centre, normal, up)} in Blender world space.

def stand_relaxed(r, g):
    stand_legs(r, "l")
    hang_arm(r, "l", out=0.10, back=0.04, bend=0.30)
    hang_arm(r, "r", out=0.11, back=0.07, bend=0.38)
    look(r, yaw=-12, pitch=4, tilt=3)


def stand_worried(r, g):
    """Right hand at the mouth, left forearm across the belly, leaning in a little."""
    stand_legs(r, "r", free_fwd=0.13, hip_drop=3)
    lean(r, 7)
    look(r, yaw=6, pitch=10, tilt=-4)
    k = r.k
    m = face(r)
    arm_ik(r, "r", m + V((0.03 * k, -0.02 * k, -0.21 * k)), r.w("upperarm_r") + V((-0.25, 0.05, -0.35)))
    aim_hand(r, "r", (0.2, -0.25, 1), palm=(0.3, 1, 0.2))
    H.curl(r.rig, "r", 34, 10)
    b = r.w("spine_01") + V((-0.03 * k, -0.19 * k, 0.02 * k))
    arm_ik(r, "l", b, r.w("upperarm_l") + V((0.35, 0.15, -0.3)))
    aim_hand(r, "l", (-1, -0.25, 0.1), palm=(0, 1, 0.3))
    H.curl(r.rig, "l", 30, 10)


def arms_crossed(r, g):
    stand_legs(r, "l", free_fwd=0.06, free_out=0.12, hip_drop=3)
    lean(r, -3)
    k = r.k
    c = chest(r)
    arm_ik(r, "r", c + V((0.15 * k, -0.08 * k, 0.0)), r.w("upperarm_r") + V((-0.4, 0.25, -0.35)))
    aim_hand(r, "r", (1, 0.35, 0.05), palm=(0, 1, 0))
    H.curl(r.rig, "r", 40, 15)
    arm_ik(r, "l", c + V((-0.135 * k, -0.18 * k, -0.08 * k)), r.w("upperarm_l") + V((0.4, 0.25, -0.35)))
    aim_hand(r, "l", (-1, 0.7, 0.1), palm=(0, 1, 0))
    H.curl(r.rig, "l", 45, 15)
    look(r, yaw=8, pitch=2, tilt=-3)


def phone_filming(r, g):
    """Phone held up in the right hand at upper-chest height, screen towards the face."""
    stand_legs(r, "l", free_fwd=0.1)
    k = r.k
    look(r, yaw=-4, pitch=18)
    wrist = r.w("head") + V((-0.05 * k, -0.31 * k, -0.27 * k))
    arm_ik(r, "r", wrist, r.w("upperarm_r") + V((-0.3, 0.1, -0.4)))
    aim_hand(r, "r", (0.15, -0.25, 1), palm=(0.15, 1, 0.1))
    H.curl(r.rig, "r", 42, 18)
    hang_arm(r, "l", out=0.10, back=0.03, bend=0.42)
    # phone: in the palm, screen to the face, long edge along the hand
    h0, h1 = r.w("hand_r"), r.w("middle_01_r")
    up = (h1 - h0).normalized()
    n = r.palm("r")
    centre = h0 + up * 0.075 * k + n * 0.022
    return {"phone": (centre, n, up)}


def pointing(r, g):
    """Driver explaining: right arm pointing ahead to his right, left hand loosely at the waist."""
    stand_legs(r, "r", free_fwd=0.12, hip_drop=3)
    k = r.k
    d = V((-0.55, -0.82, 0.12)).normalized()
    sh = r.w("upperarm_r")
    arm_ik(r, "r", sh + d * 0.49 * k, sh + V((-0.2, 0.0, -0.5)))
    aim_hand(r, "r", d, palm=(0.2, 0, -1))
    for f, deg in (("index", 2), ("middle", 75), ("ring", 85), ("pinky", 90), ("thumb", 30)):
        finger(r, "r", f, deg)
    arm_ik(r, "l", r.w("spine_01") + V((0.15 * k, -0.15 * k, 0.04 * k)), r.w("upperarm_l") + V((0.45, 0.2, -0.3)))
    aim_hand(r, "l", (-0.6, -0.6, -0.2), palm=(-0.4, 0.4, 0))
    H.curl(r.rig, "l", 35, 10)
    look(r, yaw=-24, pitch=-2)
    H.pose_rot(r.rig, "spine_03", (0, 0, 1), -6)


def kneel_work(r, g):
    """Kneeling on the right knee, left foot planted forward, trunk leaning in, both hands forward at
    the height of a seated casualty's forearm (holding the arm / a dressing)."""
    rig = r.rig; k = r.k
    H.pose_rot(rig, "pelvis", (1, 0, 0), -12)   # out of the seated pelvic tilt
    # kneeling (right) leg: thigh down, shin back along the floor, toes tucked
    H.pose_aim(rig, "thigh_r", (-0.08, 0.12, -1))
    H.pose_aim(rig, "calf_r", (0.0, 1, -0.12))
    plant_foot(r, "r", 4, pitch=0)
    H.pose_aim(rig, "foot_r", (0.0, 0.25, -1))   # toes on the floor
    H.pose_aim(rig, "ball_r", (0.0, -0.9, -0.3))
    knee = r.w("calf_r")
    floor = knee.z - 0.055 * k
    # front (left) leg: foot flat ahead, knee up
    hl = r.w("thigh_l")
    ankle_h = 0.086 * k
    leg_to(r, "l", V((hl.x + 0.06 * k, hl.y - 0.42 * k, floor + ankle_h)), pole_fwd=1.0, pole_out=0.25)
    plant_foot(r, "l", 10)
    lean(r, 14)
    look(r, yaw=4, pitch=14)
    # hands forward and down, a little apart, as if holding the casualty's forearm
    c = chest(r)
    arm_ik(r, "r", c + V((-0.07 * k, -0.36 * k, -0.12 * k)), r.w("upperarm_r") + V((-0.35, 0.1, -0.4)))
    aim_hand(r, "r", (0.3, -1, -0.35), palm=(0.4, 0, -1))
    arm_ik(r, "l", c + V((0.10 * k, -0.38 * k, -0.06 * k)), r.w("upperarm_l") + V((0.35, 0.1, -0.4)))
    aim_hand(r, "l", (-0.35, -1, -0.3), palm=(-0.4, 0, -1))
    H.curl(rig, "r", 30, 10); H.curl(rig, "l", 26, 10)


def stand_lean_work(r, g):
    """Second crew member bending in to a seated casualty: feet apart, knees soft, leaning from the hips,
    left hand braced on the left thigh above the knee, right hand reaching forward (to the casualty's shoulder)."""
    rig = r.rig; k = r.k
    stand_legs(r, "l", bend=0.955, free_fwd=0.2, free_out=0.12, hip_drop=2, toe_out=(10, 18))
    lean(r, 30, spine=("pelvis", "spine_01", "spine_02", "spine_03"))
    look(r, yaw=-6, pitch=-16)
    kn, hip = r.w("calf_l"), r.w("thigh_l")
    on_thigh = kn.lerp(hip, 0.35) + V((0.01 * k, -0.08 * k, 0.04 * k))
    arm_ik(r, "l", on_thigh, r.w("upperarm_l") + V((0.45, 0.0, -0.2)))
    aim_hand(r, "l", (-0.2, -0.5, -1), palm=(0, 0.6, -1))
    H.curl(rig, "l", 22, 8)
    c = chest(r)
    arm_ik(r, "r", c + V((0.03 * k, -0.30 * k, -0.10 * k)), r.w("upperarm_r") + V((-0.35, 0.1, -0.4)))
    aim_hand(r, "r", (0.3, -1, -0.05), palm=(1, 0, -0.4))
    H.curl(rig, "r", 28, 8)


def stand_hands_front(r, g):
    """Waiting/attending: hands loosely together in front of the lower belly."""
    stand_legs(r, "r", free_fwd=0.07, free_out=0.08, hip_drop=3)
    k = r.k
    p = r.w("spine_01") + V((0, -0.17 * k, -0.06 * k))
    arm_ik(r, "r", p + V((-0.05 * k, 0.0, 0.0)), r.w("upperarm_r") + V((-0.3, 0.3, -0.35)))
    aim_hand(r, "r", (1, -0.2, -0.45), palm=(0.2, 1, 0.3))
    arm_ik(r, "l", p + V((0.045 * k, -0.025 * k, 0.015 * k)), r.w("upperarm_l") + V((0.3, 0.3, -0.35)))
    aim_hand(r, "l", (-1, -0.2, -0.5), palm=(-0.2, 1, 0.3))
    H.curl(r.rig, "r", 30, 10); H.curl(r.rig, "l", 36, 10)
    look(r, yaw=5, pitch=6, tilt=2)


POSES = {f.__name__: f for f in (stand_relaxed, stand_worried, arms_crossed, phone_filming, pointing,
                                 kneel_work, stand_lean_work, stand_hands_front)}


# ---------------------------------------------------------------- export

C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))   # Blender (x, y, z) -> avatar (x, z, -y)


def to_avatar(p, origin):
    q = C @ (V(p) - origin)
    return Gf.Vec3f(q.x, q.y, q.z)


def mean_colour(path):
    img = bpy.data.images.load(path, check_existing=True)
    px = img.pixels[:]
    n = len(px) // 4; step = max(1, n // 4096)
    acc = [0.0, 0.0, 0.0]; cnt = 0
    for i in range(0, n, step):
        if px[i * 4 + 3] < 0.5: continue
        for c in range(3): acc[c] += px[i * 4 + c]
        cnt += 1
    srgb = [a / max(cnt, 1) for a in acc]  # byte images: the stored (sRGB) values
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def write(name, g, P, N, origin, head_rot, head_pos, extras):
    """New USD from the original avatar's layer: mesh prim copied, points/normals replaced, skinning and
    textures removed. Packaged as <OUT>/<name>.usdz."""
    work = tempfile.mkdtemp(prefix="crowd_")
    with zipfile.ZipFile(os.path.join(RES, AVATAR[g] + ".usdz")) as z: z.extractall(work)
    src = Sdf.Layer.FindOrOpen(os.path.join(work, AVATAR[g] + ".usdc"))
    usdc = os.path.join(work, name + ".usdc")
    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y); UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/root"); stage.SetDefaultPrim(root.GetPrim())
    layer = stage.GetRootLayer()
    Sdf.CopySpec(src, "/root/_materials", layer, "/root/_materials")
    Sdf.CopySpec(src, "/root/Human_rig/Human/base", layer, "/root/body")
    body = stage.GetPrimAtPath("/root/body")
    keep = {"faceVertexCounts", "faceVertexIndices", "normals", "points", "extent", "primvars:st", "primvars:st:indices",
            "doubleSided", "subdivisionScheme", "material:binding", "subsetFamily:materialBind:familyType", "orientation"}
    for prop in list(body.GetProperties()):
        if prop.GetName() not in keep: body.RemoveProperty(prop.GetName())
    body.RemoveAppliedSchema("SkelBindingAPI")
    mesh = UsdGeom.Mesh(body)
    pts = [to_avatar(p, origin) for p in P]
    mesh.GetPointsAttr().Set(pts)
    mesh.GetNormalsAttr().Set([Gf.Vec3f(*(C @ V(n))) for n in N])
    mesh.GetExtentAttr().Set(UsdGeom.PointBased.ComputeExtent(pts))
    # materials: drop the textures, keep a flat colour (the app swaps in the original materials)
    for mat in [p for p in stage.Traverse() if p.IsA(UsdShade.Material)]:
        for sh in list(mat.GetChildren()):
            s = UsdShade.Shader(sh)
            if s.GetIdAttr().Get() != "UsdUVTexture": continue
            f = s.GetInput("file").Get()
            surf = UsdShade.Shader(mat.GetChild("Principled_BSDF"))
            for inp in surf.GetInputs():
                srcs = [c.GetPrimPath() for c in inp.GetAttr().GetConnections()]
                if sh.GetPath() not in srcs: continue
                inp.GetAttr().ClearConnections()
                if inp.GetBaseName() == "diffuseColor" and f:
                    tex = os.path.join(work, f.path)
                    inp.Set(Gf.Vec3f(*mean_colour(tex)) if os.path.exists(tex) else Gf.Vec3f(0.5, 0.5, 0.5))
                elif inp.GetBaseName() == "opacity":
                    inp.Set(1.0)
                else:
                    surf.GetPrim().RemoveProperty(inp.GetAttr().GetName())
            stage.RemovePrim(sh.GetPath())
        uv = mat.GetChild("uvmap")
        if uv: stage.RemovePrim(uv.GetPath())
    # head anchor
    a = UsdGeom.Xform.Define(stage, "/root/anchor_head")
    a.AddTranslateOp().Set(Gf.Vec3d(*to_avatar(head_pos, origin)))
    q = (C @ head_rot @ C.transposed()).to_quaternion()
    a.AddOrientOp().Set(Gf.Quatf(q.w, q.x, q.y, q.z))
    if "phone" in extras:
        phone_mesh(stage, extras["phone"], origin)
    layer.Save()
    dst = os.path.join(OUT, name + ".usdz")
    if os.path.exists(dst): os.remove(dst)
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), dst)
    shutil.rmtree(work, ignore_errors=True)
    return dst


def phone_mesh(stage, spec, origin):
    centre, n, up = spec
    side = up.cross(n).normalized(); up = n.cross(side).normalized()
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = V((v.co.x * 0.072, v.co.y * 0.148, v.co.z * 0.009))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.004, segments=2, affect="EDGES")
    bmesh.ops.triangulate(bm, faces=bm.faces)
    M = Matrix((side, up, n)).transposed()  # local x -> side, y -> along the hand, z -> screen normal
    pts, counts, idx = [], [], []
    for v in bm.verts: pts.append(to_avatar(centre + M @ v.co, origin))
    bm.verts.index_update()
    for f in bm.faces:
        counts.append(len(f.verts)); idx.extend(v.index for v in f.verts)
    bm.free()
    m = UsdGeom.Mesh.Define(stage, "/root/phone")
    m.GetPointsAttr().Set(pts); m.GetFaceVertexCountsAttr().Set(counts); m.GetFaceVertexIndicesAttr().Set(idx)
    m.GetExtentAttr().Set(UsdGeom.PointBased.ComputeExtent(pts)); m.GetSubdivisionSchemeAttr().Set("none")
    mat = UsdShade.Material.Define(stage, "/root/_materials/phone")
    sh = UsdShade.Shader.Define(stage, "/root/_materials/phone/surface")
    sh.CreateIdAttr("UsdPreviewSurface")
    sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.02, 0.02, 0.025))
    sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.25)
    sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.6)
    mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
    UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(mat)


# ---------------------------------------------------------------- preview

def preview(path, body, phone_spec, origin):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = False
    sc.render.resolution_x, sc.render.resolution_y = 520, 760
    sc.view_settings.view_transform = "Standard"
    extra = []
    if phone_spec:
        c, n, up = phone_spec
        bpy.ops.mesh.primitive_cube_add(size=1, location=c)
        ph = bpy.context.active_object; extra.append(ph)
        side = up.cross(n).normalized(); up2 = n.cross(side).normalized()
        ph.matrix_world = Matrix.Translation(c) @ Matrix((side, up2, n)).transposed().to_4x4() @ Matrix.Diagonal((0.072, 0.148, 0.009, 1))
    floor = bpy.data.objects.new("floorgrid", bpy.data.meshes.new("fg"))
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=12, y_segments=12, size=1.2); bm.to_mesh(floor.data); bm.free()
    floor.location = (origin.x, origin.y, origin.z - 0.001); bpy.context.scene.collection.objects.link(floor); extra.append(floor)
    cam = bpy.data.objects.new("pcam", bpy.data.cameras.new("pcam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 50
    files = []
    tgt = origin + V((0, 0, 0.85))
    for view, off in (("front", V((0.6, -3.4, 0.55))), ("side", V((3.4, -0.4, 0.55))), ("q", V((-2.2, -2.4, 1.2)))):
        cam.location = tgt + off; H.aim(cam, tgt)
        f = path + "_" + view + ".png"; sc.render.filepath = f
        bpy.ops.render.render(write_still=True); files.append(f)
    for o in extra: bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)
    return files


# ---------------------------------------------------------------- main

def build(pose, g, write_file=True, preview_dir=None):
    H.reset()
    root, rig, body = H.patient(AVATAR[g])
    r = Rig(rig)
    extras = POSES[pose](r, g) or {}
    r.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    mw = body.matrix_world
    P = [mw @ v.co for v in me.vertices]
    N = [(mw.to_3x3() @ v.normal).normalized() for v in me.vertices]
    ev.to_mesh_clear()
    pel = r.w("pelvis")
    origin = V((pel.x, pel.y, min(p.z for p in P)))
    hb = rig.pose.bones["head"]
    head_rot = (rig.matrix_world.to_3x3() @ hb.matrix.to_3x3()) @ (rig.matrix_world.to_3x3() @ r.head_rest).inverted()
    head_pos = r.w("head")
    name = "crowd_%s_%s" % (pose, g)
    height = max(p.z for p in P) - origin.z
    if write_file:
        dst = write(name, g, P, N, origin, head_rot, head_pos, extras)
        print("CROWD wrote %s %.0f KB height %.3f" % (os.path.relpath(dst, ROOT), os.path.getsize(dst) / 1024, height))
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        files = preview(os.path.join(preview_dir, name), body, extras.get("phone"), origin)
        print("CROWD preview", " ".join(files))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pv = None; genders = ["m", "f"]; write_file = True; poses = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--preview": pv = argv[i + 1]; i += 2; continue
        if a == "--g": genders = [argv[i + 1]]; i += 2; continue
        if a == "--no-write": write_file = False; i += 1; continue
        poses.append(a); i += 1
    for p in poses or list(POSES):
        for g in genders:
            build(p, g, write_file, pv)
