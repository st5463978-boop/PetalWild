"""POST canonical-match questions to the chip behind the repo's ntfy discovery.

Does not hardcode a tunnel host. Does not call the Pi CPU teacher. If the
discovery health probe says the chip backend is down, the caller waits
instead of posting, because that gateway would answer from the CPU teacher.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from jevh_canonical import AGENT, POST_KIND

_TOOLS = Path(__file__).resolve().parents[2]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from hailo_decide_url import discover_base  # noqa: E402

TIMEOUT = 75.0


class ChipDown(RuntimeError):
    """Chip probe is failing. Posting would hit the CPU teacher."""


def origin(url: str) -> str:
    raw = url.strip().rstrip("/")
    for suffix in ("/v1/decide", "/decide"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)]
    return raw


def _get_json(url: str, timeout: float) -> dict:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("response was not an object")
    return payload


def resolve_base() -> str:
    """Live tunnel base from the ntfy topic already in this repo."""
    base = discover_base()
    if not base:
        raise ChipDown("ntfy discovery returned no https base")
    return base.rstrip("/")


def health(base: str, timeout: float = 15.0) -> dict:
    root = origin(base)
    errors: list[str] = []
    for path in ("/health", "/v1/health"):
        try:
            return _get_json(root + path, timeout)
        except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{path}: {exc}")
    raise ChipDown("health unread: " + "; ".join(errors))


def chip_block_reason(payload: dict) -> str | None:
    """None when the last chip probe succeeded."""
    detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
    probe = detail.get("last_probe") if isinstance(detail.get("last_probe"), dict) else {}
    if probe.get("ok") is True:
        return None
    cond = str(detail.get("chip_cond") or "")
    if probe.get("ok") is False or "probe_failed" in cond or "HTTP 500" in cond:
        return cond or "probe_failed"
    if detail.get("chip_held") is False and probe:
        return cond or "chip_probe_not_ok"
    return None


def chip_retry_at(payload: dict) -> datetime | None:
    detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
    raw = str(detail.get("chip_expires_at") or "")
    if not raw:
        return None
    text = raw.replace("Z", "+00:00")
    if "." in text:
        head, frac = text.split(".", 1)
        digits = []
        rest = ""
        for index, char in enumerate(frac):
            if char.isdigit() and len(digits) < 6:
                digits.append(char)
            else:
                rest = frac[index:]
                break
        text = head + "." + "".join(digits) + (rest or "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def post_decide(
    base: str,
    question: str,
    options: list[str],
    *,
    context: str = "",
    agent: str = AGENT,
    kind: str = POST_KIND,
    timeout: float = TIMEOUT,
) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    if kind != POST_KIND:
        raise ValueError("canonical lane posts kind adversarial")
    if agent != AGENT:
        raise ValueError("canonical lane agent is jev-cursor-canonical")
    body = {
        "question": question,
        "options": list(options),
        "context": context,
        "agent": agent,
        "kind": kind,
    }
    errors: list[str] = []
    for path in ("/decide", "/v1/decide"):
        request = urllib.request.Request(
            origin(base) + path,
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode())
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        if not isinstance(payload, dict):
            raise ValueError("decide response was not an object")
        payload = dict(payload)
        payload["_path"] = path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))
