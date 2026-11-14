# Blender: a light-blue nitrile-gloved right hand gripping the ultrasound probe handle (metaballs -> mesh -> USDZ).
# Frame = probe local: +Y along the handle (footprint at y=0), handle box centred (0, 0.074, 0), X +-0.025, Z +-0.014.
# Palm on the +Z face, fingers wrap round the -X edge, thumb at the bottom (index nearest the footprint), wrist at +X.
import bpy, sys, math
from mathutils import Vector, Quaternion

out = sys.argv[sys.argv.index("--") + 1]
render = sys.argv[sys.argv.index("--") + 2] if len(sys.argv) > sys.argv.index("--") + 2 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

mb = bpy.data.metaballs.new("glove")
mb.resolution = 0.018
mb.render_resolution = 0.018
mb.threshold = 0.6
obj = bpy.data.objects.new("glove", mb)
scene.collection.objects.link(obj)

# calibration: a lone ball of radius 1 has its surface at k (stiffness 2, threshold 0.6)

U = 10.0  # built 10x larger (metaball resolution has a floor), scaled down after conversion
def ball(p, r, s=2.0):
    e = mb.elements.new(type="BALL"); e.co = Vector(p) * U; e.radius = r * U; e.stiffness = s; return e

def ell(p, size, r=1.0, s=2.0):
    e = mb.elements.new(type="ELLIPSOID"); e.co = Vector(p) * U; e.radius = S * U * 0.01; e.stiffness = s
    e.size_x, e.size_y, e.size_z = (v * 100 for v in size); return e

def cap(a, b, r, s=2.0):
    a, b = Vector(a) * U, Vector(b) * U
    e = mb.elements.new(type="CAPSULE"); e.co = (a + b) / 2; e.radius = r * U; e.stiffness = s
    e.size_x = (b - a).length / 2
    e.rotation = Vector((1, 0, 0)).rotation_difference((b - a).normalized())
    return e

S = 1.55  # metaball radius -> roughly surface radius / S (calibrated below by measuring)

# fingers: (y, knuckle x, radius scale, length scale)
fingers = [(0.050, 0.010, 1.0, 0.97), (0.0715, 0.006, 1.03, 1.0), (0.0925, 0.009, 0.98, 0.97), (0.1115, 0.016, 0.86, 0.86)]
for y, kx, rs, ls in fingers:
    r = 0.0104 * rs
    mcp = (kx, y, 0.027)
    pip = (-0.032, y + 0.001, 0.023)
    dip = (-0.039, y + 0.0015, -0.006)
    tip = (-0.030 + 0.012 * (1 - ls), y + 0.002, -0.022)
    cap(mcp, pip, r * S)
    cap(pip, dip, r * 0.95 * S)
    cap(dip, tip, r * 0.88 * S)
    ball(mcp, r * 1.02 * S)  # knuckle

# palm: a fan of metacarpal capsules from the wrist to each knuckle (blends into one thick, slightly domed hand)
for y, kx, rs, ls in fingers:
    cap((0.078, 0.080 + (y - 0.080) * 0.55, 0.029), (kx + 0.004, y, 0.028), 0.0125 * S)
    cap((0.070, 0.080 + (y - 0.080) * 0.6, 0.034), (kx + 0.012, y, 0.033), 0.0085 * S)
# thenar pad and thumb along the +Z face below the index finger
ball((0.062, 0.050, 0.028), 0.0145 * S)
cap((0.060, 0.042, 0.030), (0.030, 0.031, 0.029), 0.0115 * S)
cap((0.030, 0.031, 0.029), (0.004, 0.028, 0.026), 0.0105 * S)
cap((0.004, 0.028, 0.026), (-0.017, 0.029, 0.024), 0.0095 * S)
# wrist and a short glove cuff stub along the forearm direction
d = Vector((1.0, -0.35, 0.45)).normalized()
w = Vector((0.088, 0.080, 0.030))
cap((0.085, 0.068, 0.030), (0.085, 0.092, 0.030), 0.018 * S)
cap(tuple(w), tuple(w + d * 0.06), 0.025 * S)

bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.convert(target="MESH")
m = bpy.context.active_object
m.name = "glove"
m.scale = (1 / U,) * 3
bpy.ops.object.transform_apply(scale=True)
print("PITCH dims", tuple(round(v, 4) for v in m.dimensions), "verts", len(m.data.vertices))
bpy.ops.object.shade_smooth()
dec = m.modifiers.new("dec", "DECIMATE"); dec.ratio = 0.5
bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.shade_smooth()
print("PITCH verts after", len(m.data.vertices), "bbox x", min(v.co.x for v in m.data.vertices), max(v.co.x for v in m.data.vertices),
      "z", min(v.co.z for v in m.data.vertices), max(v.co.z for v in m.data.vertices))
mat = bpy.data.materials.new("glove"); mat.diffuse_color = (0.55, 0.75, 0.95, 1)
m.data.materials.append(mat)

# handle for the preview only
if render:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.074, 0)); h = bpy.context.active_object
    h.scale = (0.05, 0.11, 0.028)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam)
    cam.location = (0.15, 0.25, 0.35); cam.data.lens = 50
    cam.rotation_euler = (Vector((0.02, 0.075, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = scene.render.resolution_y = 700
    scene.render.filepath = render
    h.select_set(False)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(h)

# Blender is Z-up; the app frame is Y-up. Export with Y up so +Y stays along the handle.
for o in list(scene.objects):
    if o.type != "MESH": bpy.data.objects.remove(o)
bpy.ops.wm.usd_export(filepath=out, export_materials=False)
print("PITCH wrote", out)
