"""POST reversibility questions to the chip behind the repo's ntfy decide address.

Does not invent a host. Does not call the Pi CPU teacher. If the Hailo probe
is down, the public decide route would answer as the teacher, so this client
waits and does not POST.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

AGENT = "jev-cursor-reversible"
KIND = "adversarial"
TIMEOUT = 75.0

_TOOLS = Path(__file__).resolve().parents[2]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from hailo_decide_url import discover_base  # noqa: E402


class ChipDown(RuntimeError):
    """Hailo probe is failing. Posting /decide would hit the CPU teacher."""


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
    base = discover_base()
    if not base:
        raise RuntimeError("ntfy discovery returned no https base")
    return origin(base)


def health(base: str, timeout: float = 15.0) -> dict:
    root = origin(base)
    errors: list[str] = []
    for path in ("/health", "/v1/health"):
        try:
            payload = _get_json(root + path, timeout)
        except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{path}: {exc}")
            continue
        if payload.get("ok") is True:
            return payload
        errors.append(f"{path}: not ok")
    raise RuntimeError("health failed: " + "; ".join(errors))


def chip_ready(payload: dict) -> bool:
    """True only when the last Hailo probe succeeded. Otherwise /decide uses the CPU teacher."""
    detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
    probe = detail.get("last_probe") if isinstance(detail.get("last_probe"), dict) else {}
    if probe and probe.get("ok") is not True:
        return False
    cond = str(detail.get("chip_cond") or "").lower()
    if any(token in cond for token in ("fail", "error", "timeout")):
        return False
    return True


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
    base: str,
    question: str,
    options: list[str],
    *,
    context: str = "",
    timeout: float = TIMEOUT,
) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    status = health(base)
    if not chip_ready(status):
        detail = status.get("detail") if isinstance(status.get("detail"), dict) else {}
        raise ChipDown(str(detail.get("chip_cond") or "chip probe failed"))
    body = {
        "question": question,
        "options": options,
        "context": context,
        "agent": AGENT,
        "kind": KIND,
    }
    errors: list[str] = []
    for path in ("/decide", "/v1/decide"):
        try:
            payload = _post_json(origin(base) + path, body, timeout)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        payload = dict(payload)
        payload["_path"] = path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))
