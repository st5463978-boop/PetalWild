"""POST forced-choice questions to JEV-H /decide.

Default on-box URL is Scott's Pi listen address. This VM resolves the
already-published discovery topic when localhost is closed. It does not
invent hosts or compile a HEF.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_DECIDE_URL = "http://127.0.0.1:8771/decide"
AGENT = "jevh-clean-core"
TIMEOUT = 75.0

_TOOLS = Path(__file__).resolve().parents[2]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))


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


def healthy(base: str, timeout: float = 12.0) -> bool:
    root = origin(base)
    for path in ("/health", "/v1/health"):
        try:
            payload = _get_json(root + path, timeout)
        except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
            continue
        if payload.get("ok") is True:
            return True
    return False


def resolve_decide_url(explicit: str | None = None) -> str:
    env = (explicit or os.environ.get("HAILO_DECIDE_URL") or "").strip()
    if env and healthy(env):
        return env
    if healthy(DEFAULT_DECIDE_URL):
        return DEFAULT_DECIDE_URL
    from hailo_decide_url import resolve_decide_url as discover

    found = discover(force=True).rstrip("/")
    if found:
        return found
    if env:
        return env
    return DEFAULT_DECIDE_URL


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
    kind: str = "",
    timeout: float = TIMEOUT,
) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    body: dict = {"question": question, "options": options, "agent": agent}
    if context:
        body["context"] = context
    if kind:
        body["kind"] = kind
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
        payload["_url"] = origin(url) + path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))
