"""Gel and probe scans: predefined views per belly region, from the scenario's `ultrasound` block.

Educational simulation. Images are real example sonograms (bundled in the app) from different
pregnancies; nothing here measures anything. Mirrored by the Swift offline engine.

RULES
- Gel: every application is recorded (`Session.gels`). The first answers `gel.patient_response`
  ("cold"), later ones `gel.repeat_response`.
- Scan: the gel counts when at least one gel event exists AND the request does not say
  `gel_applied: false`. Without gel the result is poor: no view, no image, the `no_gel` text,
  and the scan is recorded as a poor attempt (it never counts as an obtained view).
- With gel the N-th good scan of a region (N from 0) returns `views[N % len(views)]` of that region,
  so scanning the same region again (or rotating the probe) cycles through its views.
- `repeat_count`: scans of the same region and view so far (poor attempts: of that region), this one included.
- A view is OBTAINED once a good scan returned it; the rubric credits obtained views only.
"""
from .models import GelResult, ScanResult
from .sessions import Session


def apply_gel(scenario: dict, s: Session) -> GelResult | None:
    """Record a gel application; None when the case has no ultrasound."""
    us = scenario.get("ultrasound")
    if us is None:
        return None
    s.gels.append({"seq": s.next_seq()})
    first = len(s.gels) == 1
    g = us["gel"]
    return GelResult(applied=True, repeat_count=len(s.gels),
                     patient_response=g["patient_response"] if first else g["repeat_response"],
                     voice_context=g["voice_context"] if first else g["repeat_voice_context"])


def gel_on_skin(s: Session, hint: bool | None) -> bool:
    return bool(s.gels) and hint is not False


def scan(scenario: dict, s: Session, region_id: str, gel_hint: bool | None) -> ScanResult | None:
    """Record one scan of a belly region. None for an unknown region (or a case without ultrasound)."""
    us = scenario.get("ultrasound")
    region = next((r for r in us["regions"] if r["id"] == region_id), None) if us else None
    if region is None:
        return None
    if not gel_on_skin(s, gel_hint):
        s.scans.append({"seq": s.next_seq(), "region_id": region_id, "view_id": None, "gel": False, "quality": "poor"})
        n = sum(1 for e in s.scans if e["region_id"] == region_id and e["quality"] == "poor")
        bad = us["no_gel"]
        return ScanResult(region_id=region_id, view_id=None, image=None, title=bad["title"], caption=bad["caption"],
                          measurements=[], image_credit="", depth_cm=bad["depth_cm"], gain=bad["gain"], quality="poor",
                          gel_applied=False, patient_response=bad["patient_response"], voice_context=bad["voice_context"],
                          repeat_count=n)
    done = sum(1 for e in s.scans if e["region_id"] == region_id and e["quality"] == "good")
    view_id = region["views"][done % len(region["views"])]
    view = next(v for v in us["views"] if v["id"] == view_id)
    s.scans.append({"seq": s.next_seq(), "region_id": region_id, "view_id": view_id, "gel": True, "quality": "good"})
    n = sum(1 for e in s.scans if e["region_id"] == region_id and e["view_id"] == view_id)
    return ScanResult(region_id=region_id, view_id=view_id, image=view["image"], title=view["title"],
                      caption=view["caption"], measurements=view["measurements"], image_credit=view["image_credit"],
                      depth_cm=view["depth_cm"], gain=view["gain"], quality="good", gel_applied=True,
                      patient_response=view["patient_response"], voice_context=view["voice_context"], repeat_count=n)


def obtained_views(s: Session) -> list[str]:
    """Distinct views obtained by good scans, in order of first appearance."""
    return list(dict.fromkeys(e["view_id"] for e in sorted(s.scans, key=lambda e: e["seq"]) if e["quality"] == "good"))
