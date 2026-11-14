"""Draws visionOS-style glass panels and composites them onto the Blender renders.

    python3 assets/pitch_hero/composite.py hero-01-clinic [hero-01-clinic-b ...]

Reads .cache/out/<name>.png + <name>.json (panel quads projected by the scene script) and writes
docs/screenshots/pitch/<name>.jpg (3840x2160). Colours follow the app: teal = learner,
orange = patient, violet = bystander/crew.
"""
import json, os, sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.environ.get("HERO_OUT", os.path.join(HERE, ".cache", "out"))
DOCS = os.path.join(ROOT, "docs", "screenshots", "pitch")

TEAL, ORANGE, VIOLET, GREEN, AMBER, RED = (64, 206, 196), (255, 159, 67), (176, 140, 255), (88, 214, 141), (255, 196, 70), (255, 99, 88)
WHITE, DIM, FAINT = (255, 255, 255), (235, 235, 245, 165), (235, 235, 245, 90)


def font(size, weight="Regular", mono=False, rounded=False):
    f = ImageFont.truetype("/System/Library/Fonts/" + ("SFNSMono.ttf" if mono else "SFNSRounded.ttf" if rounded else "SFNS.ttf"), size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f


def wrap(d, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) <= width: cur = t
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    return lines


class Panel:
    """A panel canvas in design pixels; content is drawn in RGBA on a transparent layer, the
    glass itself is added when compositing."""
    def __init__(self, w, h, radius=46):
        self.w, self.h, self.r = w, h, radius
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); self.d = ImageDraw.Draw(self.im)
        self.mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(self.mask).rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=255)
        # rim light: thin bright top edge, faint elsewhere
        self.d.rounded_rectangle((1, 1, w - 2, h - 2), radius, outline=(255, 255, 255, 70), width=3)

    def text(self, xy, s, size, weight="Regular", fill=WHITE, **kw):
        self.d.text(xy, s, font=font(size, weight, **kw), fill=fill)

    def para(self, x, y, s, size, width, weight="Regular", fill=WHITE, lh=1.3):
        f = font(size, weight)
        for ln in wrap(self.d, s, f, width):
            self.d.text((x, y), ln, font=f, fill=fill); y += size * lh
        return y

    def chip(self, x, y, s, size, fg, bg_alpha=60, pad=(18, 8), weight="Semibold"):
        f = font(size, weight); tw = self.d.textlength(s, font=f)
        self.d.rounded_rectangle((x, y, x + tw + 2 * pad[0], y + size + 2 * pad[1]), (size + 2 * pad[1]) / 2, fill=(*fg, 235))
        self.d.text((x + pad[0], y + pad[1] - size * 0.08), s, font=f, fill=(16, 20, 24))
        return x + tw + 2 * pad[0]

    def sep(self, y, x0=40, x1=None):
        self.d.line((x0, y, x1 or self.w - 40, y), fill=(255, 255, 255, 40), width=2)


def waveform(p, x, y, w, h, colour, n=46, seed=3):
    import random
    rnd = random.Random(seed); bw = w / n
    for i in range(n):
        env = math.sin(math.pi * (i + 0.5) / n) ** 0.6
        a = h * (0.12 + 0.88 * env * (0.35 + 0.65 * abs(math.sin(i * 0.73 + seed)) * rnd.uniform(0.6, 1.0)))
        cx = x + i * bw + bw / 2
        p.d.rounded_rectangle((cx - bw * 0.28, y + h / 2 - a / 2, cx + bw * 0.28, y + h / 2 + a / 2), bw * 0.28, fill=(*colour, 235))


def score_ring(p, cx, cy, r, frac, colour, width=22, label=None, sub=None):
    p.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 255, 255, 45), width=width)
    p.d.arc((cx - r, cy - r, cx + r, cy + r), -90, -90 + 360 * frac, fill=(*colour, 255), width=width)
    for a in (-90, -90 + 360 * frac):  # round caps
        ex, ey = cx + (r - width / 2) * math.cos(math.radians(a)), cy + (r - width / 2) * math.sin(math.radians(a))
        p.d.ellipse((ex - width / 2, ey - width / 2, ex + width / 2, ey + width / 2), fill=(*colour, 255))
    if label:
        f = font(int(r * 0.62), "Bold", rounded=True); tw = p.d.textlength(label, font=f)
        p.d.text((cx - tw / 2, cy - r * 0.46), label, font=f, fill=WHITE)
    if sub:
        f = font(max(int(r * 0.2), 22), "Semibold"); tw = p.d.textlength(sub, font=f)
        p.d.text((cx - tw / 2, cy + r * 0.24), sub, font=f, fill=DIM)


def bubble(p, x, y, w, who, colour, text, size=34, live=False):
    """One conversation turn: coloured name, text block on a faint tinted card."""
    f = font(size); lines = wrap(p.d, text, f, w - 60)
    h = 74 + len(lines) * size * 1.3
    p.d.rounded_rectangle((x, y, x + w, y + h), 28, fill=(*colour, 34))
    p.d.rounded_rectangle((x, y + 16, x + 7, y + h - 16), 3, fill=(*colour, 255))
    p.text((x + 30, y + 16), who, int(size * 0.78), "Bold", fill=colour)
    if live:
        f2 = font(int(size * 0.6), "Semibold"); p.chip(x + w - 66 - p.d.textlength("speaking", font=f2), y + 14, "speaking", int(size * 0.6), colour, 55)
    yy = y + 60
    for ln in lines:
        p.d.text((x + 30, yy), ln, font=f, fill=WHITE); yy += size * 1.3
    return y + h


def header(p, title, icon_colour, right=None):
    p.d.ellipse((44, 40, 80, 76), fill=(*icon_colour, 255))
    p.text((98, 34), title, 40, "Bold")
    if right: p.chip(p.w - 60 - p.d.textlength(right, font=font(26, "Semibold")) - 36, 38, right, 26, icon_colour, 55)
    p.sep(104)


def check_row(p, x, y, w, label, value, state, size=30):
    col = {"ok": GREEN, "part": AMBER, "miss": RED, "todo": (150, 150, 160)}[state]
    p.d.ellipse((x, y + 4, x + size, y + 4 + size), fill=(*col, 255) if state != "todo" else None,
                outline=None if state != "todo" else (*col, 255), width=3)
    mark = {"ok": "✓", "part": "–", "miss": "×", "todo": ""}[state]
    if mark:
        f = font(int(size * 0.8), "Bold"); tw = p.d.textlength(mark, font=f)
        p.d.text((x + size / 2 - tw / 2, y + 2), mark, font=f, fill=(20, 24, 28))
    p.text((x + size + 20, y), label, size, "Medium")
    if value:
        f = font(size, "Semibold"); tw = p.d.textlength(value, font=f)
        leader(p, x + size + 34 + p.d.textlength(label, font=font(size, "Medium")), x + w - tw - 14, y + size * 0.72)
        p.d.text((x + w - tw, y), value, font=f, fill=DIM)


def leader(p, x0, x1, y, step=12):
    """Dotted leader so a right-aligned value stays tied to its label once the panel is in perspective."""
    x = x0
    while x < x1:
        p.d.ellipse((x, y - 2, x + 4, y + 2), fill=(255, 255, 255, 70)); x += step


# ------------------------------------------------------------------ panel content

def p_conversation_clinic():
    p = Panel(1000, 560); header(p, "Conversation", TEAL, "Voice · live")
    y = bubble(p, 40, 130, 920, "You", TEAL, "What happened exactly? How did you fall?", 32)
    y = bubble(p, 40, y + 18, 920, "Alex", ORANGE, "I braked hard on wet leaves and went over the handlebars. I landed on my right hand — ow, it hurts right at the base of my thumb.", 32, live=True)
    waveform(p, 60, y + 22, 880, 56, ORANGE)
    return p


def p_notebook_clinic():
    p = Panel(820, 900); header(p, "Clinical notebook", TEAL, "Your notes")
    y = 128
    for title, items in (("History", ["Fell off bicycle yesterday onto outstretched R hand (FOOSH)", "Pain at base of R thumb, worse on gripping"]),
                         ("Examination", ["Tender anatomical snuffbox", "Pain on axial thumb compression", "No deformity, radial pulse present, CRT < 2 s"]),
                         ("Impression", ["Suspected R scaphoid fracture"])):
        p.text((44, y), title.upper(), 24, "Bold", fill=(*TEAL, 255)); y += 40
        for it in items:
            p.d.ellipse((50, y + 13, 60, y + 23), fill=(255, 255, 255, 160))
            y = p.para(78, y, it, 29, 700) + 8
        y += 14
    # AI tidy suggestion the learner approves
    p.d.rounded_rectangle((36, y, 784, y + 240), 26, fill=(255, 255, 255, 22), outline=(*TEAL, 120), width=2)
    p.chip(58, y + 20, "●  Dictated  0:14", 22, ORANGE, 50)
    p.chip(282, y + 20, "AI tidy", 22, TEAL, 50)
    p.para(60, y + 70, "Plan: scaphoid series X-ray, thumb-spica splint, fracture clinic review in 7–10 days.", 28, 700, fill=(235, 235, 245, 230))
    bx = 60
    for s, col, a in (("Approve", TEAL, 255), ("Edit", WHITE, 40)):
        f = font(26, "Semibold"); tw = p.d.textlength(s, font=f)
        p.d.rounded_rectangle((bx, y + 168, bx + tw + 56, y + 218), 25, fill=(*col, a) if s == "Approve" else (255, 255, 255, 40))
        p.d.text((bx + 28, y + 177), s, font=f, fill=(12, 30, 32) if s == "Approve" else WHITE); bx += tw + 76
    return p


def p_score_clinic():
    p = Panel(560, 300, 40)
    score_ring(p, 150, 150, 100, 0.78, GREEN, 18, "78", "of 100")
    p.text((280, 52), "OSCE debrief", 30, "Bold")
    p.chip(280, 98, "Pass", 24, GREEN, 60)
    y = 150
    for k, v in (("History", "13/20"), ("Examination", "17/25"), ("Communication", "13/15")):
        p.text((280, y), k, 24, fill=DIM); f = font(24, "Semibold"); tw = p.d.textlength(v, font=f)
        leader(p, 290 + p.d.textlength(k, font=font(24)), 510 - tw, y + 17, 10); p.d.text((520 - tw, y), v, font=f, fill=WHITE); y += 36
    return p


def p_title_roadside():
    p = Panel(1500, 300, 60)
    p.text((70, 46), "STAGE 1 OF 3", 30, "Bold", fill=(*AMBER, 255))
    p.text((70, 92), "At the roadside", 92, "Bold")
    x = 70
    for i, s in enumerate(("Roadside", "Ambulance", "Resus bay")):
        col = AMBER if i == 0 else (255, 255, 255)
        p.d.rounded_rectangle((x, 228, x + 300, 238), 5, fill=(*col, 255 if i == 0 else 60))
        p.text((x, 248), s, 26, "Semibold", fill=(*col, 255) if i == 0 else FAINT); x += 330
    p.text((1100, 70), "Cyclist vs car, 40 km/h", 30, "Semibold", fill=DIM)
    p.text((1100, 114), "Dusk · wet road · bystanders", 28, fill=DIM)
    return p


def p_bystander():
    p = Panel(820, 300, 40)
    bubble(p, 30, 30, 760, "Bystander", VIOLET, "He just came out of nowhere! Is he going to be okay? Shouldn't you move him off the road?", 31, live=True)
    waveform(p, 52, 236, 300, 40, VIOLET, n=26, seed=7)
    p.text((380, 238), "keeps interrupting", 26, fill=DIM)
    return p


def p_patient_roadside():
    p = Panel(760, 250, 40)
    bubble(p, 30, 30, 700, "Jordan", ORANGE, "My arm… it's bent the wrong way. Please don't touch it!", 31, live=True)
    waveform(p, 52, 186, 640, 40, ORANGE, n=40, seed=11)
    return p


def p_abcde():
    p = Panel(660, 580, 40); header(p, "Primary survey", TEAL, "<C>ABCDE")
    y = 132
    for label, val, st in (("Catastrophic haemorrhage", "none", "ok"), ("Airway", "patent, talking", "ok"),
                           ("C-spine", "not cleared", "part"),
                           ("Breathing", "RR 24, SpO₂ 95 %", "ok"), ("Circulation", "HR 118, CRT 3 s", "part"),
                           ("Disability", "", "todo"), ("Exposure", "", "todo")):
        check_row(p, 44, y, 580, label, val, st, 27); y += 60
    return p


def p_checklist_us():
    p = Panel(760, 1000); header(p, "Anomaly scan checklist", TEAL, "20+0 wks")
    y = 132
    for label, val, st in (("Head shape + BPD", "46.1 mm", "ok"), ("Cavum septi pellucidi", "seen", "ok"), ("Cerebellum + cisterna magna", "seen", "ok"),
                           ("Face + lips", "seen", "ok"), ("Four-chamber heart", "seen", "ok"), ("Outflow tracts", "", "part"),
                           ("Spine (sagittal + coronal)", "", "todo"), ("Abdominal wall + cord insertion", "", "todo"),
                           ("Kidneys + bladder", "", "todo"), ("Femur length", "", "todo"), ("Placenta + amniotic fluid", "", "todo")):
        check_row(p, 44, y, 672, label, val, st, 28); y += 62
    p.sep(y + 6)
    score_ring(p, 120, y + 110, 64, 5 / 11, TEAL, 14, "5", "of 11")
    p.text((220, y + 62), "Views documented", 30, "Bold")
    p.para(220, y + 104, "Your notes are scored against the mid-trimester mark scheme.", 24, 500, fill=DIM)
    return p


def p_conversation_us():
    p = Panel(820, 250, 40)
    y = bubble(p, 30, 30, 760, "Sarah", ORANGE, "Is that the head? Is everything all right with the baby?", 31, live=True)
    waveform(p, 52, y + 18, 700, 44, ORANGE, n=44, seed=5)
    return p


PANELS = {"conversation": p_conversation_clinic, "notebook": p_notebook_clinic, "score": p_score_clinic,
          "title": p_title_roadside, "bystander": p_bystander, "patient_rt": p_patient_roadside, "abcde": p_abcde,
          "checklist": p_checklist_us, "patient_us": p_conversation_us}


# ------------------------------------------------------------------ warping + glass

def solve(A, b):
    n = len(b); M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(M[r][c])); M[c], M[piv] = M[piv], M[c]
        for r in range(n):
            if r != c:
                f = M[r][c] / M[c][c]; M[r] = [a - f * bb for a, bb in zip(M[r], M[c])]
    return [M[i][n] / M[i][i] for i in range(n)]


def persp_coeffs(dst, src):
    """Coefficients for Image.transform(PERSPECTIVE): maps output (dst) points to input (src)."""
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return solve(A, b)


def warp(img, quad, size):
    w, h = img.size
    c = persp_coeffs(quad, [(0, 0), (w, 0), (w, h), (0, h)])
    return img.transform(size, Image.PERSPECTIVE, c, Image.BICUBIC)


def composite(name):
    frame = Image.open(os.path.join(OUT, name + ".png")).convert("RGB")
    meta = json.load(open(os.path.join(OUT, name + ".json")))
    if os.environ.get("HERO_QUICK") != "1":
        frame = frame.resize((meta["width"], meta["height"]), Image.LANCZOS)
    sx, sy = frame.width / meta["width"], frame.height / meta["height"]
    vg = Image.radial_gradient("L").resize(frame.size).point(lambda v: 255 - int(min(255, v * 1.15) * 0.22))  # soft vignette
    frame = ImageChops.multiply(frame, Image.merge("RGB", (vg, vg, vg)))
    blurred = frame.filter(ImageFilter.GaussianBlur(frame.width / 90))
    glass = Image.blend(blurred, Image.new("RGB", frame.size, (30, 33, 40)), 0.6)
    out = frame.copy()
    for pm in sorted(meta["panels"], key=lambda p: -p["depth"]):
        p = PANELS[pm["name"]]()
        quad = [(x * sx, y * sy) for x, y in pm["quad"]]
        m = warp(p.mask, quad, frame.size)
        sh = m.filter(ImageFilter.GaussianBlur(frame.width / 160)); sh = ImageChops.offset(sh, 0, int(frame.width / 300))
        out = Image.composite(Image.new("RGB", frame.size, (0, 0, 0)), out, sh.point(lambda v: v * 0.28))
        out = Image.composite(glass, out, m)
        c = warp(p.im, quad, frame.size)
        out.paste(c, (0, 0), c)
        if pm.get("anchor"):
            speaker_line(out, quad, [pm["anchor"][0] * sx, pm["anchor"][1] * sy], SPEAKER[pm["name"]], frame.width / 3840)
    os.makedirs(DOCS, exist_ok=True)
    dst = os.path.join(DOCS, name + ".jpg")
    out.save(dst, quality=92, subsampling=0)
    print("WROTE", dst, out.size)


SPEAKER = {"bystander": VIOLET, "patient_rt": ORANGE, "patient_us": ORANGE, "conversation": ORANGE}


def speaker_line(out, quad, a, col, k):
    """Leader from the panel edge (nearest edge midpoint) to the speaker, drawn 3x supersampled."""
    mids = [((quad[i][0] + quad[(i + 1) % 4][0]) / 2, (quad[i][1] + quad[(i + 1) % 4][1]) / 2) for i in range(4)]
    m = min(mids, key=lambda q: (q[0] - a[0]) ** 2 + (q[1] - a[1]) ** 2)
    x0, y0 = min(m[0], a[0]) - 40, min(m[1], a[1]) - 40; x1, y1 = max(m[0], a[0]) + 40, max(m[1], a[1]) + 40
    S = 3; lay = Image.new("RGBA", (int((x1 - x0) * S), int((y1 - y0) * S)), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    P = lambda q: ((q[0] - x0) * S, (q[1] - y0) * S)
    d.line((P(m), P(a)), fill=(*col, 210), width=int(5 * k * S))
    for (q, r) in ((m, 9), (a, 14)):
        cx, cy = P(q); r *= k * S
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*col, 255), outline=(255, 255, 255, 230), width=int(3 * k * S))
    lay = lay.resize((int(x1 - x0), int(y1 - y0)), Image.LANCZOS)
    out.paste(lay, (int(x0), int(y0)), lay)


def us_screen():
    """The ultrasound monitor image (a real 20-week transthalamic BPD view with machine chrome)."""
    W, H = 1600, 1000
    im = Image.new("RGB", (W, H), (6, 8, 10)); d = ImageDraw.Draw(im)
    scan = Image.open(os.path.join(ROOT, "visionos", "MedSimXR", "Resources", "Ultrasound", "us_head_bpd.jpg")).convert("RGB")
    scan = scan.resize((int(scan.width * 820 / scan.height), 820), Image.LANCZOS)
    im.paste(scan, (110, 110))
    d.rectangle((385, 122, 480, 168), fill=(0, 0, 0))  # vendor mark in the source frame
    d.rectangle((0, 0, W, 74), fill=(24, 30, 38))
    d.text((30, 18), "OB  ·  2nd trimester", font=font(34, "Semibold"), fill=(230, 235, 240))
    d.text((520, 22), "C5-1  ·  Abdomen  ·  GA 20w0d", font=font(28), fill=(150, 165, 180))
    d.text((W - 260, 22), "MI 0.9  TIs 0.3", font=font(26, "Medium", mono=True), fill=(150, 165, 180))
    x = 110 + scan.width + 50
    y = 140
    for k, v in (("Depth", "14 cm"), ("Gain", "52 %"), ("Freq", "3.5 MHz"), ("Dyn R", "66 dB"), ("Frame", "24 Hz")):
        d.rectangle((x - 10, y - 10, W - 30, y + 80), fill=(6, 8, 10))
        d.text((x, y), k, font=font(26), fill=(120, 135, 150)); d.text((x, y + 32), v, font=font(34, "Semibold", mono=True), fill=(120, 230, 255)); y += 100
    d.rectangle((x - 10, 690, W - 30, 930), outline=(255, 196, 70), width=3)
    d.text((x + 10, 705), "BPD", font=font(30, "Bold"), fill=(255, 196, 70))
    d.text((x + 10, 745), "46.1 mm", font=font(46, "Bold", mono=True), fill=(255, 255, 255))
    d.text((x + 10, 810), "20w0d  ±7d", font=font(28, mono=True), fill=(200, 210, 220))
    d.text((x + 10, 855), "Hadlock", font=font(24), fill=(120, 135, 150))
    d.text((110, 945), "Transthalamic view  ·  midline echo, CSP, thalami", font=font(28), fill=(150, 165, 180))
    path = os.path.join(OUT, "us_screen.png"); im.save(path); print("WROTE", path)


if __name__ == "__main__":
    if sys.argv[1:] == ["--us-screen"]:
        us_screen(); sys.exit()
    assert abs(sum(persp_coeffs([(0, 0), (2, 0), (2, 2), (0, 2)], [(0, 0), (1, 0), (1, 1), (0, 1)])[:1]) - 0.5) < 1e-9  # self-check: 2x scale
    for n in sys.argv[1:]:
        composite(n)
