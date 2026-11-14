"""AI help for the learner's notebook, on Amazon Bedrock (Claude Haiku 5.5).

tidy():   one dictation -> tidy bullet points. Keeps the learner's meaning; a draft that is
          rejected (new numbers, much longer than what was said) or any failure returns the
          raw dictation unchanged, so the notebook never depends on the model.
review(): after submission, the learner's notes against the conversation transcript:
          captured / missed / inaccurate, each with a verbatim transcript quote. Items whose
          quote is not in the transcript are dropped. Shown in the debrief, never scored.

Credentials: the standard AWS chain. MEDSIM_AWS_PROFILE (else AWS_PROFILE) and AWS_REGION
pick the account; MEDSIM_NOTES_MODEL overrides the inference profile; MEDSIM_NOTES_AI=off
turns both features off (tests, offline demos).
"""
import hashlib
import json
import os
import re

from pydantic import BaseModel

from .models import InaccuratePoint, NotesReview, NotesReviewRequest, ReviewPoint, TidyRequest, TidyResult

DEFAULT_MODEL = "us.anthropic.claude-haiku-5-5"
MAX_REVIEW_ITEMS = 8

_client = None


def _bedrock():
    """Lazily built Bedrock client, or None when the feature is off or the SDK is missing."""
    global _client
    if os.environ.get("MEDSIM_NOTES_AI", "on").lower() == "off":
        return None
    if _client is None:
        try:
            import anthropic
        except ImportError:
            return None
        _client = anthropic.AnthropicBedrock(
            aws_region=os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-west-2",
            aws_profile=os.environ.get("MEDSIM_AWS_PROFILE") or os.environ.get("AWS_PROFILE") or None,
            timeout=25, max_retries=1)
    return _client


def _model() -> str:
    return os.environ.get("MEDSIM_NOTES_MODEL") or DEFAULT_MODEL


def _ask(prompt: str, schema: type[BaseModel], effort: str, max_tokens: int):
    """Structured answer or None (unavailable, refused, failed). Never raises."""
    client = _bedrock()
    if client is None:
        return None
    try:
        r = client.messages.parse(model=_model(), max_tokens=max_tokens, output_config={"effort": effort},
                                  messages=[{"role": "user", "content": prompt}], output_format=schema)
    except Exception:  # network, auth, throttling, schema: the caller falls back
        return None
    return None if r.stop_reason in ("refusal", "max_tokens") else r.parsed_output


# --- tidy ---------------------------------------------------------------------------------------

class _Tidy(BaseModel):
    text: str


_TIDY_PROMPT = """You tidy a medical student's dictated note during a simulated patient consultation.

Rules:
- Keep every fact the student said and keep their meaning. Do not add, infer, interpret or \
diagnose anything, and do not drop facts.
- Remove fillers, false starts and repetitions ("uh", "so", "okay, um").
- Fix punctuation and the spelling of medical terms; standard abbreviations are fine (e.g. "y/o", "R").
- Write short bullet points, each starting with "- ". One short phrase stays one bullet.
- Write in the language the student used.
- If the text is already tidy, return it unchanged.

Note section: {field}

Dictation:
<dictation>
{text}
</dictation>"""

_NUMBER = re.compile(r"\d+(?:[.,]\d+)?")


def _adds_facts(raw: str, tidy: str) -> str | None:
    """Why the tidy draft must not replace the dictation, or None. Cheap checks only:
    numbers must come from the dictation, and tidying never makes a note much longer."""
    new = set(_NUMBER.findall(tidy)) - set(_NUMBER.findall(raw))
    if new:
        return f"it contained numbers that were not dictated ({', '.join(sorted(new))})"
    if len(tidy) > 1.4 * len(raw) + 40:
        return "it was much longer than what was dictated"
    return None


def tidy(req: TidyRequest) -> TidyResult:
    raw = req.text.strip()
    out = _ask(_TIDY_PROMPT.format(field=req.field or "general", text=raw), _Tidy, "low", 1500)
    if out is None:
        return TidyResult(text=raw, source="raw", note="AI tidy unavailable: kept your words as dictated.")
    text = out.text.strip()
    reason = _adds_facts(raw, text) if text else "it was empty"
    if reason:
        return TidyResult(text=raw, source="raw", note=f"AI tidy rejected because {reason}: kept your words.")
    return TidyResult(text=text, source="ai")


# --- review -------------------------------------------------------------------------------------

class _Review(BaseModel):
    captured: list[ReviewPoint]
    missed: list[ReviewPoint]
    inaccurate: list[InaccuratePoint]


_REVIEW_PROMPT = """A medical student interviewed a simulated patient, then wrote notes. Compare the \
notes with the conversation transcript.

Find the clinically relevant facts the PATIENT gave in the conversation (history, symptoms, \
mechanism, timing, medication, allergies, worries, social context). For each one decide:
- captured: the notes contain it (same meaning, any wording);
- missed: it is clinically relevant and the notes do not contain it;
- inaccurate: the notes state it differently from what was said (wrong side, time, number, ...).

Rules:
- Every "quote" must be copied character for character from one transcript line, short (under 25 words).
- Judge only facts from the conversation. Examination findings, imaging and the diagnosis are \
checked elsewhere: ignore them, and do not tell the student what the diagnosis is.
- Small talk and greetings are not facts. At most {limit} items per list, most important first.
- "point" is a short neutral phrase, e.g. "Fell onto outstretched right hand".

Transcript:
<transcript>
{transcript}
</transcript>

Student notes:
<notes>
{notes}
</notes>"""

_cache: dict[str, NotesReview] = {}


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def review(req: NotesReviewRequest) -> NotesReview:
    turns = [t for t in req.transcript if t.text.strip()]
    if not any(t.role == "learner" for t in turns):
        return NotesReview(source="unavailable", note="No conversation was recorded, so there is nothing to compare.")
    notes = req.notes.model_dump()
    written = "\n".join(f"{k}: {v.strip()}" for k, v in notes.items() if v.strip())
    if not written:
        return NotesReview(source="unavailable", note="The notebook is empty, so there is nothing to compare.")
    transcript = "\n".join(f"{'Student' if t.role == 'learner' else 'Patient'}: {t.text.strip()}" for t in turns)
    key = hashlib.sha256(json.dumps([transcript, written]).encode()).hexdigest()
    if key in _cache:  # the debrief may be reopened; one model call per notebook state
        return _cache[key]

    out = _ask(_REVIEW_PROMPT.format(limit=MAX_REVIEW_ITEMS, transcript=transcript, notes=written), _Review, "medium", 4000)
    if out is None:
        return NotesReview(source="unavailable", note="The AI comparison is unavailable right now.")
    said = _norm(transcript)
    grounded = lambda items: [i for i in items if _norm(i.quote) and _norm(i.quote) in said][:MAX_REVIEW_ITEMS]
    result = NotesReview(source="ai", captured=grounded(out.captured), missed=grounded(out.missed),
                         inaccurate=grounded(out.inaccurate),
                         note="AI comparison of your notes with the conversation. Not part of your score.")
    _cache[key] = result
    return result
