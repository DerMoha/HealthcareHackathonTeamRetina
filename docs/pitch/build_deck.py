"""Build the base pitch deck: docs/pitch/MedSimXR-pitch.pptx.

Run from the repo root:
    uv venv -p 3.12 /tmp/deckvenv && uv pip install -p /tmp/deckvenv/bin/python python-pptx pillow
    /tmp/deckvenv/bin/python docs/pitch/build_deck.py

Orange text in square brackets marks placeholders to fill in.
"""

from pathlib import Path
import tempfile

from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / "docs" / "screenshots"
OUT = ROOT / "docs" / "pitch" / "MedSimXR-pitch.pptx"
TMP = Path(tempfile.mkdtemp(prefix="deckimg-"))

NAVY = RGBColor(0x14, 0x23, 0x3C)
TEAL = RGBColor(0x0F, 0x9D, 0x9A)
GREY = RGBColor(0x5B, 0x67, 0x78)
LIGHT = RGBColor(0xF2, 0xF5, 0xF8)
ORANGE = RGBColor(0xE0, 0x6C, 0x00)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

W, H = Inches(13.333), Inches(7.5)
MARGIN = Inches(0.6)
FONT = "Helvetica Neue"

prs = Presentation()
prs.slide_width, prs.slide_height = W, H
BLANK = prs.slide_layouts[6]


def img(rel: str) -> Path:
    """Downscaled copy of a screenshot (originals are 4K)."""
    src = SHOTS / rel
    dst = TMP / (src.stem + ".jpg")
    if not dst.exists():
        im = Image.open(src).convert("RGB")
        im.thumbnail((1920, 1920))
        im.save(dst, "JPEG", quality=85)
    return dst


def add_picture(slide, path: Path, left, top, width, height, cover=False):
    """Place an image inside a box: contain (default) or cover (crop to fill)."""
    iw, ih = Image.open(path).size
    box_ratio, img_ratio = width / height, iw / ih
    if cover:
        pic = slide.shapes.add_picture(str(path), left, top, width, height)
        if img_ratio > box_ratio:
            excess = 1 - box_ratio / img_ratio
            pic.crop_left = pic.crop_right = excess / 2
        else:
            excess = 1 - img_ratio / box_ratio
            pic.crop_top = pic.crop_bottom = excess / 2
        return pic
    if img_ratio > box_ratio:
        w, h = width, int(width / img_ratio)
    else:
        w, h = int(height * img_ratio), height
    pic = slide.shapes.add_picture(str(path), left + (width - w) // 2, top + (height - h) // 2, w, h)
    pic.line.color.rgb = RGBColor(0xD5, 0xDB, 0xE3)
    pic.line.width = Pt(0.75)
    return pic


def text(slide, s, left, top, width, height, size=18, color=NAVY, bold=False,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = 0
    for i, line in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        add_runs(p, line, size, color, bold)
    return tb


def add_runs(p, line, size, color, bold):
    """Text inside [square brackets] is a placeholder and shown in orange."""
    parts, buf, depth = [], "", 0
    for ch in line:
        if ch == "[" and depth == 0:
            if buf:
                parts.append((buf, False))
            buf, depth = ch, 1
        elif ch == "]" and depth == 1:
            parts.append((buf + ch, True))
            buf, depth = "", 0
        else:
            buf += ch
    if buf:
        parts.append((buf, depth == 1))
    for s, placeholder in parts:
        r = p.add_run()
        r.text = s
        r.font.name = FONT
        r.font.size = Pt(size)
        r.font.bold = bold or placeholder
        r.font.color.rgb = ORANGE if placeholder else color


def bullets(slide, items, left, top, width, height, size=20):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = 0
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_after = Pt(10)
        _bullet(p)
        add_runs(p, item, size, NAVY, False)
    return tb


def _bullet(p):
    """Real bullet with a hanging indent, so wrapped lines line up."""
    from pptx.oxml.ns import qn
    pPr = p._p.get_or_add_pPr()
    pPr.set("marL", str(Inches(0.3)))
    pPr.set("indent", str(-Inches(0.3)))
    clr = pPr.makeelement(qn("a:buClr"), {})
    clr.append(clr.makeelement(qn("a:srgbClr"), {"val": str(TEAL)}))
    pPr.append(clr)
    pPr.append(pPr.makeelement(qn("a:buChar"), {"char": "●"}))


def rect(slide, left, top, width, height, fill, line=None):
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shp.fill.solid()
    shp.fill.fore_color.rgb = fill
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line
    shp.shadow.inherit = False
    return shp


def notes(slide, s):
    slide.notes_slide.notes_text_frame.text = s


def content_slide(title, kicker=None):
    slide = prs.slides.add_slide(BLANK)
    rect(slide, 0, 0, Inches(0.18), H, TEAL)
    if kicker:
        text(slide, kicker.upper(), MARGIN, Inches(0.45), Inches(10), Inches(0.35), 12, TEAL, True)
    text(slide, title, MARGIN, Inches(0.75), W - 2 * MARGIN, Inches(0.8), 34, NAVY, True)
    n = len(prs.slides)
    text(slide, f"MedSim XR   {n}", W - MARGIN - Inches(2), H - Inches(0.5), Inches(2), Inches(0.3),
         10, GREY, align=PP_ALIGN.RIGHT)
    return slide


def bullets_and_images(title, kicker, items, images, note):
    """Bullets on the left and one image on the right; two images go side by side above the bullets."""
    if len(images) > 1:
        return bullets_below_images(title, kicker, images, items, note, height=Inches(3.4))
    slide = content_slide(title, kicker)
    top = Inches(1.8)
    bullets(slide, items, MARGIN, top, Inches(4.9), Inches(5))
    left, width = Inches(5.9), W - Inches(5.9) - MARGIN
    avail = H - top - Inches(0.7)
    gap = Inches(0.2)
    h = (avail - gap * (len(images) - 1)) // len(images)
    for i, rel in enumerate(images):
        add_picture(slide, img(rel), left, top + i * (h + gap), width, h)
    notes(slide, note)
    return slide


def bullets_below_images(title, kicker, images, items, note, captions=None, height=Inches(3.0)):
    """A row of images, bullets underneath."""
    slide = content_slide(title, kicker)
    top, gap = Inches(1.75), Inches(0.2)
    width = (W - 2 * MARGIN - gap * (len(images) - 1)) // len(images)
    h = height
    for i, rel in enumerate(images):
        x = MARGIN + i * (width + gap)
        add_picture(slide, img(rel), x, top, width, h, cover=True)
        if captions:
            text(slide, captions[i], x, top + h + Inches(0.08), width, Inches(0.35), 13, GREY, True,
                 PP_ALIGN.CENTER)
    y = top + h + Inches(0.6 if captions else 0.35)
    bullets(slide, items, MARGIN, y, W - 2 * MARGIN, H - y - Inches(0.6), 18)
    notes(slide, note)
    return slide


def full_bleed(path, title, subtitle, note):
    slide = prs.slides.add_slide(BLANK)
    add_picture(slide, path, 0, 0, W, H, cover=True)
    band = rect(slide, 0, H - Inches(2.4), W, Inches(2.4), NAVY)
    band.fill.fore_color.brightness = 0
    _set_alpha(band, 82)
    text(slide, title, MARGIN, H - Inches(2.15), W - 2 * MARGIN, Inches(0.9), 44, WHITE, True)
    text(slide, subtitle, MARGIN, H - Inches(1.25), W - 2 * MARGIN, Inches(0.9), 20, WHITE)
    notes(slide, note)
    return slide


def _set_alpha(shape, percent):
    """Semi-transparent fill (python-pptx has no API for alpha)."""
    from pptx.oxml.ns import qn
    srgb = shape.fill._xPr.find(qn("a:solidFill")).find(qn("a:srgbClr"))
    alpha = srgb.makeelement(qn("a:alpha"), {"val": str(percent * 1000)})
    srgb.append(alpha)


# 1. Title ------------------------------------------------------------------
full_bleed(
    img("pitch/hero-01-clinic.jpg"),
    "MedSim XR",
    "AI patients for clinical training on Apple Vision Pro\n[Team name · Event · Date]",
    "0:00–0:10\n"
    "- Who we are, one line.\n"
    "- Hook: clinical skills are learned on patients, and practice patients are scarce and expensive.",
)

# 2. Problem -----------------------------------------------------------------
s = content_slide("Clinical practice is scarce, costly and hard to repeat", "The problem")
bullets(s, [
    "Students get few chances to examine real or actor patients",
    "Actor patients and simulation centres are expensive and hard to schedule",
    "Every session is different, so grading is inconsistent",
    "Mistakes are rarely reviewed: no record of what actually happened",
    "Team scenarios (roadside, ambulance, handover) are almost never practised",
], MARGIN, Inches(1.9), Inches(7.6), Inches(5), 22)
rect(s, Inches(8.7), Inches(1.9), W - Inches(8.7) - MARGIN, Inches(4.6), LIGHT)
text(s, "[Quote or statistic from a student, instructor or study]\n\n[Source]",
     Inches(9.0), Inches(2.2), W - Inches(9.3) - MARGIN, Inches(4.0), 20, GREY,
     anchor=MSO_ANCHOR.MIDDLE)
notes(s,
      "0:10–0:25\n"
      "- Pick one or two pain points, not all five.\n"
      "- Use a real quote or number in the grey box if we have one.")

# 3. Cost of certification (placeholder) ------------------------------------
s = content_slide("What certification costs today", "The problem: cost")
tiles = [
    ("[$ ___]", "Exam fee per candidate\n[Which certification?]"),
    ("[$ ___ / h]", "Standardised (actor) patient"),
    ("[$ ___]", "Simulation centre session\nor mannequin"),
    ("[___ %]", "Fail / retake rate\n[$ ___ per retake]"),
]
gap = Inches(0.25)
tw = (W - 2 * MARGIN - gap * 3) // 4
for i, (big, label) in enumerate(tiles):
    x = MARGIN + i * (tw + gap)
    rect(s, x, Inches(1.9), tw, Inches(2.6), LIGHT)
    text(s, big, x, Inches(2.15), tw, Inches(1.0), 36, ORANGE, True, PP_ALIGN.CENTER)
    text(s, label, x + Inches(0.15), Inches(3.25), tw - Inches(0.3), Inches(1.1), 16, NAVY,
         align=PP_ALIGN.CENTER)
rect(s, MARGIN, Inches(4.8), W - 2 * MARGIN, Inches(1.1), NAVY)
text(s, "Total per certified student: [$ ___]      Instructor time per exam: [___ h]",
     MARGIN, Inches(4.8), W - 2 * MARGIN, Inches(1.1), 24, WHITE, True, PP_ALIGN.CENTER,
     MSO_ANCHOR.MIDDLE)
text(s, "Sources: [___]", MARGIN, Inches(6.2), W - 2 * MARGIN, Inches(0.4), 12, GREY)
notes(s,
      "0:25–0:45\n"
      "PLACEHOLDER: fill in with sourced numbers before the pitch.\n"
      "- Pick one certification the audience knows (e.g. medical licensing practical exam, OSCE, "
      "paramedic / EMT certification, trauma life-support course, sonography credential).\n"
      "- Per candidate: exam fee, prep course, travel, actor-patient hours, simulation-centre time.\n"
      "- Cost of failing: retake fee and delay to starting work.\n"
      "- Close with: MedSim XR moves practice hours out of the expensive room and into any room.")

# 4. Solution ----------------------------------------------------------------
bullets_and_images(
    "An AI patient in any room", "Our solution",
    [
        "Vision Pro app: the patient appears in your room or a virtual clinic",
        "Talk, examine, order imaging, treat",
        "Scored against the case's checklist",
        "Every session logged for review",
        "New scenarios built in the browser",
    ],
    ["pitch/wrist-01-in-your-room.jpg"],
    "0:45–0:55\n- One sentence: practise on a patient that talks back, as often as you like, and get scored.",
)

# 5. Patient -----------------------------------------------------------------
bullets_and_images(
    "A patient you can talk to", "Patient",
    [
        "Realistic 3D patient, female or male",
        "Own room or virtual clinic",
        "ElevenLabs voice agent",
        "Mood changes the answers: calm, nervous or angry",
    ],
    ["pitch/wrist-02-conversation.jpg", "review/03-wrist-female-avatar.jpg"],
    "0:55–1:05\n- Talk normally, no menus.\n- Same case, different mood: the student has to adapt.",
)

# 6. Examination -------------------------------------------------------------
bullets_and_images(
    "Examine and get a reaction", "Physical examination",
    [
        "Look and pinch to examine",
        "Patient flinches and pulls away",
        "Says what hurts or what feels better",
        "Per-case susceptibility notes",
    ],
    ["pitch/wrist-03-pain-reaction.jpg"],
    "1:05–1:15\n- Press the snuffbox: \"Ow, that's exactly where it hurts.\"",
)

# 7. Tools -------------------------------------------------------------------
bullets_and_images(
    "Measure and fit, like in the clinic", "Examination room tools",
    [
        "Drag the tape onto the wrist and forearm",
        "Pick a wrist support and drag it on",
        "Tighten and ask how it feels",
        "Wrong size or too tight: the patient tells you",
    ],
    ["pitch/wrist-05-orthotics-lab.jpg", "demo/05-lab-1-measure-wrist.jpg"],
    "1:15–1:25\n- Same workflow students use on real patients.",
)

# 8. Imaging -----------------------------------------------------------------
bullets_and_images(
    "X-ray and MRI on request", "Diagnostics",
    [
        "Order after your diagnosis, by voice or notebook",
        "Opens in a panel next to the patient",
        "Zoom and read the report",
        "MRI available alongside X-ray",
    ],
    ["pitch/wrist-04-xray.jpg", "demo/10-mri-report.jpg"],
    "1:25–1:35\n- Teaching point: a normal X-ray doesn't rule out a scaphoid fracture. What next?",
)

# 9. Ultrasound --------------------------------------------------------------
bullets_and_images(
    "Ultrasound on a pregnant patient", "Advanced: ultrasound",
    [
        "20-week anomaly scan",
        "Probe on the belly, gel needed",
        "Live sonogram views: head, heart, spine, placenta",
        "Scored against the scan checklist",
    ],
    ["pitch/us-03-heart.jpg", "pitch/us-02-head-bpd.jpg"],
    "1:35–1:45\n- Move the probe, the image changes. Where you place it is the skill.",
)

# 10. Journey ----------------------------------------------------------------
bullets_below_images(
    "One patient, three places", "Advanced: patient journey",
    ["pitch/rt-01-roadside.jpg", "pitch/rt-04-ambulance.jpg", "pitch/rt-05-resus.jpg"],
    [
        "Same patient and story from roadside to ambulance to rescue bay",
        "AI team members take observations, control bleeding and run other tasks",
        "Bystanders and crowd add realistic pressure",
    ],
    "1:45–2:00\n- Real care is a team effort with handovers.\n- You take one patient all the way through.",
    captions=["1  Roadside", "2  Ambulance", "3  Rescue bay"],
)

# 11. Notebook and scoring ---------------------------------------------------
bullets_below_images(
    "Dictate, review, get scored", "Notebook and scoring",
    ["pitch/wrist-06-notebook.jpg", "pitch/rt-07-team-log.jpg", "pitch/wrist-07-feedback.jpg"],
    [
        "Dictate notes; they are summarised into a draft",
        "Full session log and transcript, for students and examiners",
        "Notes scored against expected findings and the checklist; score card at the end",
    ],
    "2:00–2:15\n- Credit only for what you actually did.\n- Students replay what they missed.",
    captions=["Notebook", "Session log", "Score card"],
)

# 12. Studio -----------------------------------------------------------------
s = content_slide("MedSim Studio: build scenarios in the browser", "For instructors")
bullets(s, [
    "Generate new scenarios, or play random",
    "Difficulty: easy, medium, hard",
    "Crowd, bystanders (distracting, still, advising), equipment",
    "Mix and match places and assets",
    "Learning objectives with AI help; adjustable scoring",
    "Publish, then download to the headset",
], MARGIN, Inches(1.8), Inches(4.9), Inches(5), 18)
grid = ["pitch/studio-web-01-generator.jpg", "pitch/studio-web-02-ai-author.jpg",
        "pitch/studio-web-04-marketplace.jpg", "pitch/vp-02-download-crop.jpg"]
gx, gy, gap = Inches(5.9), Inches(1.8), Inches(0.2)
gw = (W - gx - MARGIN - gap) // 2
gh = (H - gy - Inches(0.7) - gap) // 2
for i, rel in enumerate(grid):
    add_picture(s, img(rel), gx + (i % 2) * (gw + gap), gy + (i // 2) * (gh + gap), gw, gh, cover=True)
notes(s, "2:15–2:35\n- An instructor builds and publishes a case in minutes.\n"
         "- Students download it to the headset and play.")

# 13. Roadmap ----------------------------------------------------------------
bullets_and_images(
    "Next", "Roadmap",
    [
        "Adaptive difficulty from the student's heart rate: more or fewer distractions, louder or quieter, patient more or less cooperative",
        "Multi-user: several students in one scenario",
        "Import certification guidelines from organisations",
    ],
    ["pitch/rt-02-crew.jpg"],
    "2:35–2:45\n- Calm students get pushed harder; overloaded students get room to work.\n"
    "- Today an instructor can already trigger events live from the Studio.\n"
    "- Image is a placeholder; replace with a mock-up.",
)

# 14. Close ------------------------------------------------------------------
full_bleed(
    img("pitch/hero-02-roadside.jpg"),
    "Practise. Get scored. Review. Repeat.",
    "[Our ask: pilot partners / funding / certification bodies]   [Contact]",
    "2:45–3:00\n- Come back to the cost slide: [$ ___] per student today.\n- State the ask.",
)

# 15. Credits ----------------------------------------------------------------
s = content_slide("Image credits", "Appendix")
text(s,
     "Ultrasound images: Verma AK et al., Cureus 2025;17(12):e98575, CC BY 4.0. "
     "Nevit Dilmen, Wolfgang Moroder, Guimi, Goleisureintl (Wikimedia Commons), CC BY-SA / CC BY.\n"
     "Forearm X-ray: Hellerhoff (Wikimedia Commons), CC BY-SA 4.0.\n"
     "Wrist X-ray: Mikael Häggström, M.D., CC0.\n"
     "Full list: assets/pitch/CREDITS-*.md, assets/ultrasound/README.md.\n\n"
     "Educational simulation only. All patient data is fictional.",
     MARGIN, Inches(1.8), W - 2 * MARGIN, Inches(4.5), 16, GREY)
notes(s, "Not presented. Keep for attribution.")

OUT.parent.mkdir(parents=True, exist_ok=True)
prs.save(OUT)
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {len(prs.slides)} slides)")
