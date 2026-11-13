#!/usr/bin/env python3
"""Fetch CC0 assets for the pitch scenes into visionos/MedSimXR/Resources/Pitch/, bundle-ready
for PitchKit (visionos/MedSimXR/Reality/Pitch/README.md), and credit each in
assets/pitch/CREDITS-<key>.md (key: --key, else the prefix up to its first "_").

  pitch_assets.py texture  <polyhaven id> <prefix> [--res 1k|2k] [--size PX]
  pitch_assets.py ambientcg <ambientCG id> <prefix> [--res 1K|2K] [--size PX]
      -> <prefix>_diff.jpg _nor.jpg _rough.jpg (+ _ao.jpg _metal.jpg when the set has them)
  pitch_assets.py hdri     <polyhaven id> <name>   [--res 1k|2k]
      -> <name>.hdr   (Radiance HDR equirect, PitchKit.light(_:hdri:) loads it)
  pitch_assets.py model    <polyhaven id> <name>   [--res 1k|2k] [--decimate 0.5] [--tex 1024]
      -> <name>.usdz  (glTF -> USDZ via headless Blender, textures embedded and downscaled)

Every name gets your agent prefix (bundle files are flattened, so names must be unique).
Run with the system python3; needs Pillow, and Blender for models (BLENDER env, default
/opt/homebrew/bin/blender).
"""
import argparse, datetime, io, json, os, shutil, subprocess, sys, tempfile, urllib.request, zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "visionos", "MedSimXR", "Resources", "Pitch")
CREDITS = os.path.join(ROOT, "assets", "pitch")
BLENDER = os.environ.get("BLENDER", "/opt/homebrew/bin/blender")
UA = {"User-Agent": "MedSimXR-pitch-assets/1.0"}  # both APIs reject the default urllib agent


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def save_jpeg(data, path, size=None, quality=88):
    from PIL import Image
    img = Image.open(io.BytesIO(data))
    img = img.convert("L" if img.mode in ("L", "I", "I;16", "F") else "RGB")
    if size and max(img.size) > size:
        img.thumbnail((size, size), Image.LANCZOS)
    img.save(path, "JPEG", quality=quality, optimize=True)
    print(f"  {os.path.relpath(path, ROOT)}  {img.size[0]}x{img.size[1]}  {os.path.getsize(path) // 1024} KB")


def credit(key, name, title, url, author, licence="CC0 1.0"):
    os.makedirs(CREDITS, exist_ok=True)
    path = os.path.join(CREDITS, f"CREDITS-{key}.md")
    new = not os.path.exists(path)
    with open(path, "a") as f:
        if new:
            f.write(f"# Pitch assets ({key})\n\nFiles in visionos/MedSimXR/Resources/Pitch/. Added by visionos/scripts/pitch_assets.py.\n\n")
        f.write(f"- `{name}`: {title} by {author}, {url}, {licence}, fetched {datetime.date.today()}\n")
    print(f"  credited in {os.path.relpath(path, ROOT)}")


def ph_info(asset):
    info = json.loads(get(f"https://api.polyhaven.com/info/{asset}"))
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
    return info, files, ", ".join(info.get("authors", {}).keys()) or "Poly Haven"


def ph_pick(maps, res):
    """The requested resolution, else the nearest smaller one, else the smallest."""
    order = ["1k", "2k", "4k", "8k"]
    have = [r for r in order if r in maps]
    smaller = [r for r in have if order.index(r) <= order.index(res)]
    return maps[(smaller or have)[-1 if smaller else 0]]


def cmd_texture(a):
    info, files, author = ph_info(a.id)
    maps = {"diff": "Diffuse", "nor": "nor_gl", "rough": "Rough", "ao": "AO", "metal": "Metal"}
    for suffix, key in maps.items():
        if key not in files:
            if suffix in ("diff", "nor", "rough"): sys.exit(f"{a.id} has no {key} map")
            continue
        f = ph_pick(files[key], a.res)
        f = f.get("jpg") or f.get("png")
        save_jpeg(get(f["url"]), os.path.join(OUT, f"{a.prefix}_{suffix}.jpg"), a.size)
    credit(a.key, f"{a.prefix}_*.jpg", info["name"], f"https://polyhaven.com/a/{a.id}", author)


def cmd_ambientcg(a):
    data = get(f"https://ambientcg.com/get?file={a.id}_{a.res}-JPG.zip")
    maps = {"Color": "diff", "NormalGL": "nor", "Roughness": "rough", "AmbientOcclusion": "ao", "Metalness": "metal"}
    found = set()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for n in z.namelist():
            stem = os.path.splitext(os.path.basename(n))[0]
            for key, suffix in maps.items():
                if stem.endswith("_" + key):
                    save_jpeg(z.read(n), os.path.join(OUT, f"{a.prefix}_{suffix}.jpg"), a.size)
                    found.add(suffix)
    missing = {"diff", "nor", "rough"} - found
    if missing: sys.exit(f"{a.id}: zip lacks {sorted(missing)}")
    credit(a.key, f"{a.prefix}_*.jpg", a.id, f"https://ambientcg.com/view?id={a.id}", "ambientCG (Lennart Demes)")


def cmd_hdri(a):
    info, files, author = ph_info(a.id)
    f = ph_pick(files["hdri"], a.res)["hdr"]
    path = os.path.join(OUT, f"{a.name}.hdr")
    with open(path, "wb") as out: out.write(get(f["url"]))
    print(f"  {os.path.relpath(path, ROOT)}  {os.path.getsize(path) // 1024} KB")
    credit(a.key, f"{a.name}.hdr", info["name"], f"https://polyhaven.com/a/{a.id}", author)


# Runs inside Blender: import glTF, optional decimate, export USDZ (Y up, textures downscaled), then
# give every texture channel its own UsdUVTexture: RealityKit renders a material BLACK when one
# texture node feeds two inputs (Poly Haven's packed AO/rough/metal "arm" map -> roughness + metallic).
BLENDER_SCRIPT = r"""
import bpy, sys, os, zipfile, tempfile
from pxr import Usd, UsdShade, Sdf, UsdUtils
src, dst, ratio, tex = sys.argv[sys.argv.index("--") + 1:]

def split_shared_textures(usdz):
    work = tempfile.mkdtemp()
    with zipfile.ZipFile(usdz) as z: z.extractall(work)
    root = [n for n in os.listdir(work) if n.endswith((".usdc", ".usda"))][0]
    stage = Usd.Stage.Open(os.path.join(work, root))
    layer, split = stage.GetRootLayer(), 0
    for prim in list(stage.Traverse()):
        surf = UsdShade.Shader(prim)
        if not surf or surf.GetIdAttr().Get() != "UsdPreviewSurface": continue
        seen = set()
        for inp in surf.GetInputs():
            for src_path in inp.GetAttr().GetConnections():
                tex_path = src_path.GetPrimPath()
                if tex_path not in seen: seen.add(tex_path); continue
                new = tex_path.ReplaceName(tex_path.name + "_" + inp.GetBaseName())
                Sdf.CopySpec(layer, tex_path, layer, new)
                inp.GetAttr().SetConnections([new.AppendProperty(src_path.name)])
                split += 1
    layer.Save()
    os.remove(usdz)
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(os.path.join(work, root)), usdz)
    print(f"PITCH split {split} shared texture node(s)")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ratio = float(ratio)
tris = 0
for o in bpy.context.scene.objects:
    if o.type != "MESH": continue
    if ratio < 1:
        m = o.modifiers.new("decimate", "DECIMATE"); m.ratio = ratio
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
print(f"PITCH source triangles {tris}, decimate {ratio}")
bpy.ops.wm.usd_export(filepath=dst, export_animation=False, export_lights=False, export_cameras=False,
    convert_world_material=False, evaluation_mode="RENDER", generate_preview_surface=True,
    convert_orientation=True, export_global_up_selection="Y", export_global_forward_selection="NEGATIVE_Z",
    usdz_downscale_size=tex, triangulate_meshes=True, export_textures_mode="NEW")
split_shared_textures(dst)
"""


def cmd_model(a):
    info, files, author = ph_info(a.id)
    f = ph_pick(files["gltf"], a.res)["gltf"]
    work = tempfile.mkdtemp(prefix="pitch_model_")  # downloads only: untrusted data
    scripts = tempfile.mkdtemp(prefix="pitch_blender_")
    try:
        gltf = os.path.join(work, os.path.basename(f["url"]))
        with open(gltf, "wb") as out: out.write(get(f["url"]))
        for rel, inc in f.get("include", {}).items():
            p = os.path.normpath(os.path.join(work, rel))
            if not p.startswith(work + os.sep): sys.exit(f"refusing include path {rel}")
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as out: out.write(get(inc["url"]))
        script = os.path.join(scripts, "to_usdz.py")
        with open(script, "w") as s: s.write(BLENDER_SCRIPT)
        dst = os.path.join(OUT, f"{a.name}.usdz")
        r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", script, "--",
                            gltf, dst, str(a.decimate), str(a.tex)], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if line.startswith("PITCH") or "Error" in line: print("  " + line)
        if r.returncode or not os.path.exists(dst): sys.exit(f"blender failed:\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
        print(f"  {os.path.relpath(dst, ROOT)}  {os.path.getsize(dst) // 1024} KB")
        credit(a.key, f"{a.name}.usdz", info["name"], f"https://polyhaven.com/a/{a.id}", author)
    finally:
        shutil.rmtree(work, ignore_errors=True); shutil.rmtree(scripts, ignore_errors=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn, res in [("texture", cmd_texture, "1k"), ("ambientcg", cmd_ambientcg, "1K")]:
        s = sub.add_parser(name); s.set_defaults(fn=fn)
        s.add_argument("id"); s.add_argument("prefix")
        s.add_argument("--res", default=res); s.add_argument("--size", type=int, help="max edge in px after download")
    s = sub.add_parser("hdri"); s.set_defaults(fn=cmd_hdri)
    s.add_argument("id"); s.add_argument("name"); s.add_argument("--res", default="1k")
    s = sub.add_parser("model"); s.set_defaults(fn=cmd_model)
    s.add_argument("id"); s.add_argument("name"); s.add_argument("--res", default="1k")
    s.add_argument("--decimate", type=float, default=1.0, help="keep this fraction of triangles (0-1)")
    s.add_argument("--tex", default="1024", choices=["KEEP", "256", "512", "1024", "2048"], help="max embedded texture size")
    for s in sub.choices.values():
        s.add_argument("--key", help="credits file key (default: prefix up to the first _)")
    a = p.parse_args()
    a.key = a.key or (getattr(a, "prefix", None) or a.name).split("_")[0]
    os.makedirs(OUT, exist_ok=True)
    a.fn(a)


if __name__ == "__main__":
    main()
