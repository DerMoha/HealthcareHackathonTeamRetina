"""Shared Blender helpers for the hero renders (hero_clinic.py, hero_roadside.py, hero_ultrasound.py).

Blender space: metres, Z up. The patient avatars face -Y (their left is +X), feet on z = 0.
Assets come from assets/pitch_hero/.cache (fetch_assets.py). Run the scene scripts through
render_heroes.sh, which also draws the glass UI panels and composites them.
"""
import bpy, bmesh, glob, json, math, os, sys
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, ".cache")
RES = os.path.join(ROOT, "visionos", "MedSimXR", "Resources")
OUT = os.environ.get("HERO_OUT", os.path.join(CACHE, "out"))
os.makedirs(OUT, exist_ok=True)
# HERO_QUICK=1: half resolution, few samples (for iterating)
QUICK = os.environ.get("HERO_QUICK", "0") == "1"
ENGINE = os.environ.get("HERO_ENGINE", "EEVEE")


def reset(samples=384):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    if ENGINE == "EEVEE":
        # shortcut: EEVEE because Cycles was too slow on the shared, overloaded machine; Cycles path kept
        sc.render.engine = "BLENDER_EEVEE"
        e = sc.eevee
        e.taa_render_samples = 24 if QUICK else int(os.environ.get("HERO_SAMPLES", "32"))
        e.use_raytracing = True
        e.ray_tracing_options.resolution_scale = "1"
        e.ray_tracing_options.trace_max_roughness = 0.6
        e.use_shadows = True; e.shadow_ray_count = 2; e.shadow_step_count = 8; e.shadow_pool_size = "1024"
        e.use_fast_gi = True; e.fast_gi_method = "GLOBAL_ILLUMINATION"
        e.volumetric_tile_size = "4"
        sc.render.resolution_x, sc.render.resolution_y = 3840, 2160
        # shortcut: final frames render at 70 % and composite.py upscales to 3840x2160 (UI drawn at full res)
        sc.render.resolution_percentage = 40 if QUICK else int(os.environ.get("HERO_PCT", "70"))
        sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_depth = "16"
        sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Medium High Contrast"
        sc.view_settings.exposure = float(os.environ.get("HERO_EXPOSURE", "0"))
        return sc
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
    sc.cycles.samples = 64 if QUICK else samples
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.max_bounces = 8
    sc.cycles.glossy_bounces = 4
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.blur_glossy = 0.6
    sc.cycles.sample_clamp_indirect = 8.0
    sc.render.resolution_x, sc.render.resolution_y = 3840, 2160
    sc.render.resolution_percentage = 40 if QUICK else 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "16"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    return sc


def world_hdri(name, strength=1.0, rot_deg=0.0, bg_strength=None, bg_tint=None):
    """HDRI world. bg_strength / bg_tint change only what the camera sees directly."""
    w = bpy.data.worlds.new("world"); bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree; N = nt.nodes; L = nt.links
    N.clear()
    out = N.new("ShaderNodeOutputWorld")
    tc = N.new("ShaderNodeTexCoord"); mp = N.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value[2] = math.radians(rot_deg)
    env = N.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(glob.glob(os.path.join(CACHE, "hdri", name + "_*.hdr"))[0])
    L.new(tc.outputs["Generated"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], env.inputs["Vector"])
    light = N.new("ShaderNodeBackground"); light.inputs["Strength"].default_value = strength
    L.new(env.outputs["Color"], light.inputs["Color"])
    if bg_strength is None and bg_tint is None:
        L.new(light.outputs[0], out.inputs[0]); return w
    cam = N.new("ShaderNodeBackground"); cam.inputs["Strength"].default_value = strength if bg_strength is None else bg_strength
    src = env.outputs["Color"]
    if bg_tint:
        mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        L.new(src, mix.inputs["A"]); mix.inputs["B"].default_value = (*bg_tint, 1)
        src = mix.outputs["Result"]
    L.new(src, cam.inputs["Color"])
    lp = N.new("ShaderNodeLightPath"); sh = N.new("ShaderNodeMixShader")
    L.new(lp.outputs["Is Camera Ray"], sh.inputs[0]); L.new(light.outputs[0], sh.inputs[1]); L.new(cam.outputs[0], sh.inputs[2])
    L.new(sh.outputs[0], out.inputs[0])
    return w


# ---------------------------------------------------------------- materials

def _maps(folder):
    """Finds albedo / normal / roughness / ARM maps in a Poly Haven or ambientCG folder."""
    fs = glob.glob(os.path.join(folder, "*.jpg"))
    def pick(*keys):
        for k in keys:
            for f in fs:
                if k in os.path.basename(f).lower(): return f
        return None
    return dict(color=pick("_diff_", "_color"), normal=pick("_nor_gl_", "_normalgl"), rough=pick("_rough_", "_roughness"),
                arm=pick("_arm_"), metal=pick("_metalness"), ao=pick("_ambientocclusion"))


def tex_folder(key):
    for d in (os.path.join(CACHE, "tex", key), os.path.join(CACHE, "acg", key)):
        if os.path.isdir(d): return d
    raise FileNotFoundError(key)


def pbr(name, key, scale=1.0, tint=None, tint_mix=1.0, rough_mul=1.0, rough_add=0.0, normal=1.0, metal=None,
        box=True, coat=0.0, rot=0.0, sat=None, value=None):
    """Principled material from texture maps. box=True: box projection on object coordinates
    (scale = texture repeats per metre), so procedural meshes need no UVs."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    bs = N["Principled BSDF"]
    mp = _maps(tex_folder(key))
    tc = N.new("ShaderNodeTexCoord"); mpn = N.new("ShaderNodeMapping")
    mpn.inputs["Scale"].default_value = (scale, scale, scale)
    mpn.inputs["Rotation"].default_value[2] = math.radians(rot)
    L.new(tc.outputs["Object" if box else "UV"], mpn.inputs["Vector"])
    def img(path, colour=False):
        t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path, check_existing=True)
        t.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        if box: t.projection = "BOX"; t.projection_blend = 0.25
        L.new(mpn.outputs["Vector"], t.inputs["Vector"]); return t
    col = img(mp["color"], True).outputs["Color"]
    if sat is not None or value is not None:
        h = N.new("ShaderNodeHueSaturation")
        h.inputs["Saturation"].default_value = 1.0 if sat is None else sat
        h.inputs["Value"].default_value = 1.0 if value is None else value
        L.new(col, h.inputs["Color"]); col = h.outputs["Color"]
    if tint:
        mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MULTIPLY"
        mx.inputs["Factor"].default_value = tint_mix
        L.new(col, mx.inputs["A"]); mx.inputs["B"].default_value = (*tint, 1); col = mx.outputs["Result"]
    L.new(col, bs.inputs["Base Color"])
    rough = None
    if mp["rough"]: rough = img(mp["rough"]).outputs["Color"]
    elif mp["arm"]:
        sp = N.new("ShaderNodeSeparateColor"); L.new(img(mp["arm"]).outputs["Color"], sp.inputs["Color"]); rough = sp.outputs[1]
    if rough is not None:
        ma = N.new("ShaderNodeMath"); ma.operation = "MULTIPLY_ADD"; ma.use_clamp = True
        ma.inputs[1].default_value = rough_mul; ma.inputs[2].default_value = rough_add
        L.new(rough, ma.inputs[0]); L.new(ma.outputs[0], bs.inputs["Roughness"])
    if mp["normal"] and normal > 0:
        nm = N.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = normal
        if box:  # box-projected normal maps are only approximately right; keep them gentle
            nm.inputs["Strength"].default_value = normal * 0.7
        L.new(img(mp["normal"]).outputs["Color"], nm.inputs["Color"]); L.new(nm.outputs[0], bs.inputs["Normal"])
    if metal is not None: bs.inputs["Metallic"].default_value = metal
    elif mp["metal"]: L.new(img(mp["metal"]).outputs["Color"], bs.inputs["Metallic"])
    if coat: bs.inputs["Coat Weight"].default_value = coat; bs.inputs["Coat Roughness"].default_value = 0.08
    return m


def plain(name, color, rough=0.5, metal=0.0, coat=0.0, emission=None, estrength=0.0, transmission=0.0, ior=1.45, alpha=1.0):
    """Untextured principled material: only for things that really are smooth (glass, screens,
    painted metal trims, light diffusers). Everything large gets pbr()."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal; b.inputs["Coat Weight"].default_value = coat
    b.inputs["Transmission Weight"].default_value = transmission; b.inputs["IOR"].default_value = ior
    b.inputs["Alpha"].default_value = alpha
    if emission:
        b.inputs["Emission Color"].default_value = (*emission, 1); b.inputs["Emission Strength"].default_value = estrength
    return m


def image_emit(name, path, strength=1.0, rough=0.25, gloss_coat=0.6):
    """A screen: image as emission under a glossy glass coat."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    b = N["Principled BSDF"]
    t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path); t.extension = "EXTEND"
    L.new(t.outputs["Color"], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = strength
    b.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = gloss_coat; b.inputs["Coat Roughness"].default_value = 0.03
    b.inputs["Specular IOR Level"].default_value = 0.15 if gloss_coat < 0.2 else 0.5  # matte screens: no hot-spot glare
    return m


# ---------------------------------------------------------------- geometry

def link(o, coll=None):
    (coll or bpy.context.scene.collection).objects.link(o); return o


def box(name, size, loc, mat=None, bevel=0.004, rot=(0, 0, 0), segments=3):
    """Box with real dimensions in the mesh (no object scale), bevelled edges, smooth shading."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); o.location = loc; o.rotation_euler = rot
    if mat: me.materials.append(mat)
    if bevel:
        bv = o.modifiers.new("bevel", "BEVEL"); bv.width = bevel; bv.segments = segments; bv.limit_method = "ANGLE"
        bv.harden_normals = False
    for p in me.polygons: p.use_smooth = True
    o.modifiers.new("wn", "WEIGHTED_NORMAL").keep_sharp = True
    return o


def plane(name, size, loc, mat=None, rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    for v in bm.verts: v.co = Vector((v.co.x * size[0], v.co.y * size[1], 0))
    uv = bm.loops.layers.uv.new()
    for f in bm.faces:
        for l in f.loops: l[uv].uv = (l.vert.co.x / size[0] + 0.5, l.vert.co.y / size[1] + 0.5)
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); o.location = loc; o.rotation_euler = rot
    if mat: me.materials.append(mat)
    return o


def cylinder(name, r, h, loc, mat=None, rot=(0, 0, 0), verts=48, bevel=0.002):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r, depth=h)
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); o.location = loc; o.rotation_euler = rot
    if mat: me.materials.append(mat)
    for p in me.polygons: p.use_smooth = True
    if bevel:
        bv = o.modifiers.new("bevel", "BEVEL"); bv.width = bevel; bv.segments = 2; bv.limit_method = "ANGLE"
    o.modifiers.new("wn", "WEIGHTED_NORMAL").keep_sharp = True
    return o


def lathe(name, profile, loc, mat=None, segments=64):
    """Surface of revolution about Z from [(r, z), ...] (bottom to top)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / segments), r * math.sin(2 * math.pi * i / segments), z)) for i in range(segments)]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); o.location = loc
    if mat: me.materials.append(mat)
    for p in me.polygons: p.use_smooth = True
    return o


def area_light(name, loc, size, energy, color=(1, 1, 1), target=None, shape="RECTANGLE", size_y=None, spread=180):
    l = bpy.data.lights.new(name, "AREA"); l.energy = energy; l.color = color; l.shape = shape
    l.size = size; l.size_y = size_y or size; l.spread = math.radians(spread)
    o = link(bpy.data.objects.new(name, l)); o.location = loc
    if target is not None: aim(o, target)
    return o


def point_light(name, loc, energy, color=(1, 1, 1), radius=0.05):
    l = bpy.data.lights.new(name, "POINT"); l.energy = energy; l.color = color; l.shadow_soft_size = radius
    o = link(bpy.data.objects.new(name, l)); o.location = loc; return o


def spot_light(name, loc, energy, target, color=(1, 1, 1), angle=60, blend=0.6, radius=0.05):
    l = bpy.data.lights.new(name, "SPOT"); l.energy = energy; l.color = color; l.spot_size = math.radians(angle)
    l.spot_blend = blend; l.shadow_soft_size = radius
    o = link(bpy.data.objects.new(name, l)); o.location = loc; aim(o, target); return o


def aim(o, target):
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


# ---------------------------------------------------------------- imported assets

def gltf(key, loc=(0, 0, 0), rot_z=0.0, scale=1.0, name=None):
    """Imports a Poly Haven glTF model under one empty placed at loc (base on the floor)."""
    path = glob.glob(os.path.join(CACHE, "models", key, "*.gltf"))[0]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new(name or key, None); link(root)
    for o in new:
        if o.parent is None: o.parent = root
        for c in o.users_collection:
            if c is not bpy.context.scene.collection:
                c.objects.unlink(o); bpy.context.scene.collection.objects.link(o)
    root.location = loc; root.rotation_euler = (0, 0, math.radians(rot_z)); root.scale = (scale,) * 3
    bpy.context.view_layer.update()
    return root


def bounds(root):
    pts = []
    for o in [root] + list(root.children_recursive):
        if o.type == "MESH":
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def patient(name="Patient", loc=(0, 0, 0), rot_z=0.0):
    """Imports a patient avatar USDZ. Returns (root empty, armature, body mesh). Skin gets
    subsurface scattering and a softer sheen; eyes get a wet coat."""
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=os.path.join(RES, name + ".usdz"))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE"); body = next(o for o in new if o.type == "MESH")
    top = [o for o in new if o.parent is None]
    root = link(bpy.data.objects.new(name + "_root", None))
    for o in top: o.parent = root
    root.location = loc; root.rotation_euler = (0, 0, math.radians(rot_z))
    for slot in body.material_slots:
        m = slot.material
        if not m or not m.node_tree: continue
        m.surface_render_method = "DITHERED"  # EEVEE: blended hair cards sort badly at the crown
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not b: continue
        n = m.name.lower()
        if "body" in n:
            b.inputs["Subsurface Weight"].default_value = 0.22
            b.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
            b.inputs["Subsurface Scale"].default_value = 0.012
            b.inputs["Roughness"].default_value = 0.48
            b.inputs["Specular IOR Level"].default_value = 0.45
        elif "low_poly" in n or "eye" == n[-3:]:
            b.inputs["Coat Weight"].default_value = 1.0; b.inputs["Coat Roughness"].default_value = 0.02
            b.inputs["Roughness"].default_value = 0.3
        elif any(k in n for k in ("suit", "shirt", "jeans", "sportsuit", "casual")):
            b.inputs["Roughness"].default_value = 0.85
            b.inputs["Sheen Weight"].default_value = 0.4; b.inputs["Sheen Roughness"].default_value = 0.5
        elif any(k in n for k in ("short02", "ponytail", "eyebrow", "eyelash")):
            b.inputs["Roughness"].default_value = 0.55
            b.inputs["Coat Weight"].default_value = 0.0
    for o in new:
        if o.type == "MESH": o.visible_shadow = True
    bpy.context.view_layer.update()
    return root, rig, body


def pose_aim(rig, bone, direction, roll=0.0):
    """Rotates `bone` (armature space, which is rig-local) so it points along `direction`, with an
    extra roll in degrees about that direction. Children follow."""
    pb = rig.pose.bones[bone]
    cur = (pb.tail - pb.head).normalized()
    d = Vector(direction).normalized()
    q = cur.rotation_difference(d)
    R = q.to_matrix().to_4x4()
    if roll: R = Matrix.Rotation(math.radians(roll), 4, d) @ R
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


def pose_rot(rig, bone, axis, deg):
    """Rotates `bone` about an armature-space axis through its head."""
    pb = rig.pose.bones[bone]; h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized()) @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


def curl(rig, side, amount=30.0, thumb=15.0, fingers=("index", "middle", "ring", "pinky")):
    """Curls the fingers of one hand (local X rotation of each phalanx)."""
    for f in fingers:
        for i in (1, 2, 3):
            pb = rig.pose.bones.get("%s_0%d_%s" % (f, i, side))
            if pb:
                pb.rotation_mode = "XYZ"; pb.rotation_euler.x += math.radians(amount * (0.6 if i == 1 else 1.0))
    for i in (2, 3):
        pb = rig.pose.bones.get("thumb_0%d_%s" % (i, side))
        if pb: pb.rotation_mode = "XYZ"; pb.rotation_euler.x += math.radians(thumb)
    bpy.context.view_layer.update()


def bone_world(rig, bone, tail=False):
    pb = rig.pose.bones[bone]
    return rig.matrix_world @ (pb.tail if tail else pb.head)


def solve_two_bone(rig, upper, lower, target_world, pole_world):
    """Analytic two-bone IK: points `upper` and `lower` so the end of `lower` reaches target_world,
    with the elbow bent towards pole_world. Keeps bone lengths."""
    inv = rig.matrix_world.inverted()
    t = inv @ Vector(target_world); pole = inv @ Vector(pole_world)
    a = rig.pose.bones[upper]; b = rig.pose.bones[lower]
    s = a.head.copy(); l1 = (a.tail - a.head).length; l2 = (b.tail - b.head).length
    d = t - s; dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    ang = math.acos(max(-1, min(1, cos_a)))
    pv = (pole - s); pv = (pv - dn * pv.dot(dn)).normalized()
    elbow = s + dn * (math.cos(ang) * l1) + pv * (math.sin(ang) * l1)
    pose_aim(rig, upper, elbow - s)
    pose_aim(rig, lower, (s + dn * dist) - elbow)
    return rig.matrix_world @ elbow


# ---------------------------------------------------------------- camera + panels

def camera(loc, target, lens=35.0, fstop=None, focus=None, sensor=36.0, shift_y=0.0):
    c = bpy.data.cameras.new("cam"); c.lens = lens; c.sensor_width = sensor; c.shift_y = shift_y
    o = link(bpy.data.objects.new("cam", c)); o.location = loc; aim(o, target)
    if fstop:
        c.dof.use_dof = True; c.dof.aperture_fstop = fstop
        c.dof.focus_distance = focus if focus else (Vector(target) - Vector(loc)).length
    bpy.context.scene.camera = o
    return o


def panel_quad(center, width, height, facing, tilt_deg=0.0):
    """3D corners (tl, tr, br, bl) of an upright panel at `center` whose front faces towards
    `facing` (a point), optionally tilted back by tilt_deg."""
    c = Vector(center); f = Vector(facing) - c; f.z = 0; f.normalize()
    right = Vector((0, 0, 1)).cross(f).normalized()   # viewer's right when looking at the front
    up = Vector((0, 0, 1))
    if tilt_deg:
        R = Matrix.Rotation(math.radians(-tilt_deg), 3, right); up = R @ up
    hw, hh = right * (width / 2), up * (height / 2)
    return [c - hw + hh, c + hw + hh, c + hw - hh, c - hw - hh]


def write_panels(panels, path):
    """Projects panel corners to pixel coordinates of the final 3840x2160 frame and writes JSON
    for composite.py: [{name, quad: [[x, y] x4], depth}]."""
    sc = bpy.context.scene; cam = sc.camera
    bpy.context.view_layer.update()  # camera matrix_world is stale right after aim()
    W, H = sc.render.resolution_x, sc.render.resolution_y
    out = []
    for p in panels:
        quad = []
        for v in p["corners"]:
            co = world_to_camera_view(sc, cam, Vector(v))
            quad.append([round(co.x * W, 2), round((1 - co.y) * H, 2)])
        depth = (Vector(p["corners"][0]) - cam.location).length
        extra = {}
        if p.get("anchor"):  # speaker point for the bubble's leader line
            co = world_to_camera_view(sc, cam, Vector(p["anchor"])); extra["anchor"] = [round(co.x * W, 2), round((1 - co.y) * H, 2)]
        out.append(dict({k: v for k, v in p.items() if k not in ("corners", "anchor")}, quad=quad, depth=round(depth, 3), **extra))
    json.dump({"width": W, "height": H, "panels": out}, open(path, "w"), indent=1)


def render(name):
    sc = bpy.context.scene
    if os.environ.get("HERO_NORENDER"):  # layout check: print panel quads only
        print("LAYOUT", name, [[p["name"], [[int(x), int(y)] for x, y in p["quad"]]] for p in json.load(open(os.path.join(OUT, name + ".json")))["panels"]]); return
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)


def save_blend(name):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))


def screen_panels(specs):
    """Panels placed by screen position: specs = [(name, sx, sy, dist, width, height)], sx/sy in
    -1..1 (frame centre 0, right/up positive), dist in metres from the camera along its axis.
    Returns write_panels() input; the panels face the camera."""
    sc = bpy.context.scene; cam = sc.camera; bpy.context.view_layer.update()
    fr = cam.data.view_frame(scene=sc)  # local corners at some depth
    fx = max(abs(v.x) for v in fr); fy = max(abs(v.y) for v in fr); fz = abs(fr[0].z)
    out = []
    for name, sx, sy, dist, w, h, *anchor in specs:
        p = cam.matrix_world @ (Vector((sx * fx, sy * fy, -fz)) * (dist / fz))
        out.append(dict(name=name, corners=panel_quad(p, w, h, cam.matrix_world.translation), anchor=anchor[0] if anchor else None))
    return out
