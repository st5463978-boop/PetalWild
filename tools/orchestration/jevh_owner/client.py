"""POST ownership questions to the live JEV-H chip.

The host comes from the repo's ntfy discovery resolver. This module does
not invent a tunnel host and does not call the Pi CPU teacher ports.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

AGENT = "jev-cursor-owner"
KIND = "adversarial"
TIMEOUT = 75.0
TEACHER_MARKERS = (":8766", ":8769")

_TOOLS = Path(__file__).resolve().parents[2]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))


def origin(url: str) -> str:
    raw = url.strip().rstrip("/")
    for suffix in ("/v1/decide", "/decide"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)]
    return raw


def refuse_teacher(url: str) -> None:
    if any(marker in url for marker in TEACHER_MARKERS):
        raise RuntimeError("refusing Pi CPU teacher port")


def _get_json(url: str, timeout: float) -> dict:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("response was not an object")
    return payload


def get_health(url: str, timeout: float = 15.0) -> dict:
    refuse_teacher(url)
    root = origin(url)
    errors: list[str] = []
    for path in ("/health", "/v1/health"):
        try:
            return _get_json(root + path, timeout)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{type(exc).__name__} {path}")
    raise RuntimeError("health endpoint missing: " + ", ".join(errors))


def chip_probe_ok(health: dict) -> bool:
    """True only when the published health says the chip probe succeeded."""
    detail = health.get("detail")
    if not isinstance(detail, dict):
        return False
    probe = detail.get("last_probe")
    if isinstance(probe, dict) and probe.get("ok") is True:
        return True
    cond = str(detail.get("chip_cond") or "").lower()
    if not cond:
        return False
    if any(token in cond for token in ("fail", "error", "500")):
        return False
    return True


def resolve_decide_url() -> str:
    """Last https line on the repo's ntfy topic, health-checked. No invented host."""
    from hailo_decide_url import discover_base

    base = discover_base()
    if not base:
        raise RuntimeError("ntfy discovery returned no https host")
    url = base.rstrip("/") + "/v1/decide"
    refuse_teacher(url)
    health = get_health(url)
    if health.get("ok") is not True:
        raise RuntimeError("discovered decide host is not healthy")
    return url


def _post_json(url: str, body: dict, timeout: float) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("decide response was not an object")
    return payload


def post_decide(
    url: str,
    question: str,
    options: list[str],
    *,
    context: str = "",
    agent: str = AGENT,
    kind: str = KIND,
    timeout: float = TIMEOUT,
) -> dict:
    refuse_teacher(url)
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    body: dict = {
        "question": question,
        "options": list(options),
        "agent": agent,
        "kind": kind,
    }
    if context:
        body["context"] = context
    errors: list[str] = []
    for path in ("/decide", "/v1/decide"):
        try:
            payload = _post_json(origin(url) + path, body, timeout)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        payload = dict(payload)
        payload["_path"] = path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))
