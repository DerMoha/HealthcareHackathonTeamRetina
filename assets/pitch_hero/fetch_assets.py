"""Downloads the CC0 assets the hero renders use into assets/pitch_hero/.cache/ (git-ignored).

    python3 assets/pitch_hero/fetch_assets.py

Poly Haven (api.polyhaven.com) and ambientCG (ambientcg.com), all CC0. Idempotent: files that are
already there are skipped. The list below is the single source of truth; CREDITS-hero.md mirrors it.
"""
import json, os, sys, urllib.request, zipfile, io

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
UA = {"User-Agent": "MedSimXR-pitch-hero/1.0"}

# Poly Haven HDRIs: id -> resolution
HDRIS = {"hospital_room_2": "2k", "modern_evening_street": "4k", "stuttgart_suburbs": "2k",
         "small_empty_room_3": "2k", "cedar_bridge_sunset_2": "4k"}
# Poly Haven textures: id -> resolution (diffuse, normal (GL), roughness, arm)
TEXTURES = {"asphalt_02": "2k", "concrete_pavement_02": "2k", "beige_wall_001": "2k",
            "fabric_leather_02": "1k", "denim_fabric_05": "1k", "concrete": "1k",
            "painted_plaster_wall": "2k", "wood_table_001": "1k", "brushed_concrete": "1k",
            "bi_stretch": "1k", "plastered_wall_04": "2k"}
# Poly Haven models (glTF): id -> resolution
MODELS = {"metal_stool_02": "1k", "wall_clock": "1k", "potted_plant_02": "1k", "potted_plant_04": "1k",
          "medical_box": "1k", "clipboard": "1k", "vintage_crutches_01": "1k", "drawer_cabinet": "1k",
          "metal_office_desk": "1k", "korean_fire_extinguisher_01": "1k", "SchoolChair_01": "1k",
          "metal_trash_can": "1k", "street_lamp_02": "1k", "concrete_road_barrier": "1k",
          "utility_box_01": "1k", "water_manhole_cover": "1k", "office_notepads": "1k",
          "classic_laptop": "1k", "side_table_01": "1k", "steel_frame_shelves_01": "1k",
          "plastic_crate_01": "1k", "trashbag": "1k", "fire_hydrant": "1k", "medical_tape": "1k"}
# ambientCG materials (1K or 2K JPG zips)
AMBIENT = {"OfficeCeiling005": "2K", "Terrazzo018": "2K", "Fabric030": "1K", "Plastic010": "1K",
           "Metal032": "1K", "Rubber004": "1K", "Tiles074": "2K"}


def get(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    print("GET", url)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r:
        data = r.read()
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)


def files(asset_id):
    with urllib.request.urlopen(urllib.request.Request("https://api.polyhaven.com/files/" + asset_id, headers=UA)) as r:
        return json.load(r)


def main(only=None):
    for k, res in HDRIS.items():
        if only and k not in only: continue
        get(files(k)["hdri"][res]["hdr"]["url"], os.path.join(CACHE, "hdri", "%s_%s.hdr" % (k, res)))
    for k, res in TEXTURES.items():
        if only and k not in only: continue
        f = files(k)
        for m in ("Diffuse", "nor_gl", "Rough", "arm"):
            if m in f and res in f[m]:
                url = f[m][res]["jpg"]["url"]
                get(url, os.path.join(CACHE, "tex", k, os.path.basename(url)))
    for k, res in MODELS.items():
        if only and k not in only: continue
        g = files(k)["gltf"][res]["gltf"]
        d = os.path.join(CACHE, "models", k)
        get(g["url"], os.path.join(d, os.path.basename(g["url"])))
        for rel, inc in g.get("include", {}).items():
            get(inc["url"], os.path.join(d, rel))
    for k, res in AMBIENT.items():
        if only and k not in only: continue
        d = os.path.join(CACHE, "acg", k)
        if os.path.isdir(d) and os.listdir(d): continue
        url = "https://ambientcg.com/get?file=%s_%s-JPG.zip" % (k, res)
        print("GET", url)
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r:
            z = zipfile.ZipFile(io.BytesIO(r.read()))
        os.makedirs(d, exist_ok=True)
        for n in z.namelist():
            if n.lower().endswith(".jpg") and "/" not in n and ".." not in n:
                with open(os.path.join(d, n), "wb") as f:
                    f.write(z.read(n))


if __name__ == "__main__":
    main(set(sys.argv[1:]) or None)
