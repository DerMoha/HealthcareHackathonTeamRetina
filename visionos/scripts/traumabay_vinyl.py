# Procedural seamless safety-vinyl sheet floor (speckled, slightly mottled) -> traumabay_vinyl_diff/_nor/_rough.jpg
import random, math
from PIL import Image, ImageFilter, ImageChops
N = 1024; random.seed(7)
import os
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../MedSimXR/Resources/Pitch/traumabay_vinyl")
def wrapblur(img, r):
    big = Image.new(img.mode, (3*N, 3*N))
    for i in range(3):
        for j in range(3): big.paste(img, (i*N, j*N))
    return big.filter(ImageFilter.GaussianBlur(r)).crop((N, N, 2*N, 2*N))
def noise(scale, r):
    s = N // scale
    small = Image.effect_noise((s, s), 64).convert("L")
    return wrapblur(small.resize((N, N), Image.BICUBIC), r)
mott = noise(16, 40)  # big soft mottling
base = Image.new("RGB", (N, N), (128, 138, 142))
# mottling +-8
m = mott.point(lambda v: v)
diff = Image.merge("RGB", [ImageChops.add(Image.new("L", (N, N), c), m.point(lambda v: max(0, v - 120) // 3)) for c in (118, 128, 133)])
px = diff.load(); rough = Image.new("L", (N, N), 175); rp = rough.load()
cols = [(205, 210, 212), (70, 76, 82), (160, 168, 172), (95, 120, 135), (230, 232, 230)]
for _ in range(26000):
    x, y = random.randrange(N), random.randrange(N); c = random.choice(cols); s = random.choice([1, 1, 1, 2, 2, 3])
    for dx in range(s):
        for dy in range(s):
            px[(x + dx) % N, (y + dy) % N] = c
            rp[(x + dx) % N, (y + dy) % N] = 140
diff = wrapblur(diff, 0.6)
diff.save(out + "_diff.jpg", quality=90)
# Roughness: mostly satin with scuffed patches
sc = noise(32, 12)
rough = ImageChops.add(wrapblur(rough, 0.8), sc.point(lambda v: max(0, v - 128) // 2))
rough.save(out + "_rough.jpg", quality=90)
# Normal: gentle orange-peel from fine noise
h = noise(2, 2.0); hp = h.load()
nor = Image.new("RGB", (N, N)); np_ = nor.load()
for y in range(N):
    for x in range(N):
        dx = (hp[(x + 1) % N, y] - hp[(x - 1) % N, y]) / 255 * 1.2
        dy = (hp[x, (y + 1) % N] - hp[x, (y - 1) % N]) / 255 * 1.2
        l = math.sqrt(dx*dx + dy*dy + 1)
        np_[x, y] = (int((-dx / l * 0.5 + 0.5) * 255), int((dy / l * 0.5 + 0.5) * 255), int((1 / l * 0.5 + 0.5) * 255))
nor.save(out + "_nor.jpg", quality=90)
print("ok")
