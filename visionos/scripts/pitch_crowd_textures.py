#!/usr/bin/env python3
"""Recoloured clothing textures for the pitch crowd (PitchCrowd.swift): the bundled MakeHuman
casual-suit textures (CC0) of Patient.usdz / Patient_female.usdz, re-dyed per outfit, so clones of
the two avatars read as different people.
Output: visionos/MedSimXR/Resources/Pitch/roadside_crowd_<outfit>.jpg

  python3 -I visionos/scripts/pitch_crowd_textures.py
"""
import io, os, sys, zipfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "visionos", "MedSimXR", "Resources")
OUT = os.path.join(RES, "Pitch")


def suit(model):
    with zipfile.ZipFile(os.path.join(RES, model + ".usdz")) as z:
        name = next(n for n in z.namelist() if "casualsuit01_diffuse" in n)
        return Image.open(io.BytesIO(z.read(name))).convert("RGB")


# UV islands (x, y in 0..1, y down): top or bottom garment, None = leave as is.
def male_part(x, y):
    if 0.36 < x < 0.71:
        return "bottom"
    if (x < 0.32 and y < 0.3) or (x > 0.71 and y < 0.2):
        return None
    return "top"


def female_part(x, y):
    return "top" if y < 0.43 or (x > 0.72 and y > 0.55) else "bottom"


# Reflective shin bands on the trouser islands (y ranges).
STRIPES = {"male": [(0.345, 0.37), (0.865, 0.89)], "female": [(0.875, 0.9)]}

OUTFITS = {  # name: (model, top rgb, bottom rgb, reflective stripes)
    "paramedic_m": ("male", (0.16, 0.30, 0.20), (0.13, 0.24, 0.16), True),
    "paramedic_f": ("female", (0.16, 0.30, 0.20), (0.13, 0.24, 0.16), True),
    "police": ("male", (0.80, 0.86, 0.12), (0.07, 0.07, 0.09), True),
    "driver": ("male", (0.62, 0.62, 0.60), (0.52, 0.44, 0.32), False),
    "bystander_m": ("male", (0.45, 0.10, 0.12), (0.16, 0.16, 0.18), False),
    "bystander_f": ("female", (0.78, 0.58, 0.14), (0.08, 0.08, 0.10), False),
    "bystander_f2": ("female", (0.86, 0.84, 0.80), (0.20, 0.30, 0.50), False),
    "hiker_m": ("male", (0.70, 0.18, 0.10), (0.25, 0.26, 0.24), False),
    "hiker_f": ("female", (0.10, 0.45, 0.50), (0.22, 0.22, 0.22), False),
}


def dye(src, kind, top, bottom, stripes):
    w, h = src.size
    part = male_part if kind == "male" else female_part
    px = src.load()
    lum = lambda c: (0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]) / 255
    sums = {"top": [0.0, 0], "bottom": [0.0, 0]}
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            p = part(x / w, y / h)
            if p:
                sums[p][0] += lum(px[x, y]); sums[p][1] += 1
    mean = {k: v[0] / max(v[1], 1) for k, v in sums.items()}
    out = src.copy(); o = out.load()
    for y in range(h):
        for x in range(w):
            p = part(x / w, y / h)
            if not p:
                continue
            k = (lum(px[x, y]) / max(mean[p], 1e-3)) ** 0.85  # keep the fabric's folds and seams
            c = top if p == "top" else bottom
            if kind == "female" and 0.71 < x / w < 0.88 and 0.14 < y / h < 0.32:
                k = 1.0  # paint out the print on the T-shirt
            if stripes and p == "bottom" and any(a <= y / h <= b for a, b in STRIPES[kind]):
                c, k = (0.78, 0.80, 0.80), min(k, 1.1)
            o[x, y] = tuple(max(0, min(255, int(255 * ch * k))) for ch in c)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    src = {k: v.resize((512, 512), Image.LANCZOS) for k, v in {"male": suit("Patient"), "female": suit("Patient_female")}.items()}
    for name, (kind, top, bottom, stripes) in OUTFITS.items():
        img = dye(src[kind], kind, top, bottom, stripes)
        path = os.path.join(OUT, f"roadside_crowd_{name}.jpg")
        img.save(path, "JPEG", quality=85, optimize=True)
        print(os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    sys.exit(main())
