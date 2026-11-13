"""Test-run trace: every HTTP exchange and WebSocket frame as JSON lines, plus a per-session snapshot file.

Off with MEDSIM_TRACE=0. Files go to MEDSIM_LOG_DIR (default backend/logs):
  events.jsonl            one line per request/response or socket frame
  sessions/<id>.json      latest full session state (rewritten after each change, so it survives a restart)
"""
import json
import os
import re
import threading
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

MAX_BODY = 20_000  # characters kept per body; longer ones are cut
_SECRET = re.compile(r"token|secret|password|api[_-]?key|signed_url", re.I)
_lock = threading.Lock()


def enabled() -> bool:
    return os.environ.get("MEDSIM_TRACE") != "0"


def _dir() -> Path:
    return Path(os.environ.get("MEDSIM_LOG_DIR") or Path(__file__).resolve().parents[1] / "logs")


def _redact(v):
    if isinstance(v, dict):
        return {k: "***" if _SECRET.search(k) and isinstance(v[k], str) else _redact(v[k]) for k in v}
    if isinstance(v, list):
        return [_redact(x) for x in v]
    return v


def _default(o):
    return o.model_dump() if hasattr(o, "model_dump") else sorted(o) if isinstance(o, set) else str(o)


def body(raw: bytes, content_type: str | None):
    """Parsed JSON (secrets masked) when possible, else just its size and type."""
    if not raw:
        return None
    if content_type and "json" in content_type:
        try:
            return _redact(json.loads(raw))
        except ValueError:
            pass
    if content_type and content_type.startswith("text/"):
        return raw[:MAX_BODY].decode("utf-8", "replace")
    return {"bytes": len(raw), "content_type": content_type}


def event(kind: str, **fields) -> None:
    if not enabled():
        return
    line = json.dumps({"ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"), "kind": kind, **fields},
                      default=_default)
    if len(line) > MAX_BODY:
        line = json.dumps({"ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"), "kind": kind,
                           "truncated": line[:MAX_BODY]})
    path = _dir() / "events.jsonl"
    with _lock:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


def snapshot(session, live=None, **extra) -> None:
    """Write the session's full state (and scenario live state) to sessions/<id>.json."""
    if not enabled():
        return
    data = {"saved_at": datetime.now(timezone.utc).isoformat(timespec="milliseconds"), "session": asdict(session),
            "live": None if live is None else {"code": live.definition.code, "title": live.definition.title,
                                                "interventions": live.interventions, "hints": live.hints,
                                                "delivered": live.delivered, "available": live.available,
                                                "mood": live.mood, "noise": live.noise}, **extra}
    path = _dir() / "sessions" / f"{session.id}.json"
    with _lock:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(_redact(data), indent=1, default=_default), encoding="utf-8")
        tmp.replace(path)
