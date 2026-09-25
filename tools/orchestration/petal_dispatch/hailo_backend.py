"""Pi Hailo decide client for system-1 routing.

High-frequency choices go to the Pi `hailo-decision` service.
`HAILO_DECIDE_URL` is resolved at startup from the ntfy discovery topic
(health-checked tunnel), then the existing env value, then the Pi on
Tailscale. A decide failure resolves again. This module does not call
MinoJEV, an RLCD policy, a local Ollama tag, or `/v1/chat/completions`.
It does not download or recompile HEFs.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

_TOOLS = Path(__file__).resolve().parents[2]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from hailo_decide_url import resolve_decide_url  # noqa: E402
from petal_dispatch.discover import discover
from petal_dispatch.router import Backend
from petal_dispatch.schema import OWNER_ACTION, OWNERS

# Pi Tailscale. MagicDNS http://piai-1:8766/v1/decide is the same service.
DEFAULT_DECIDE_URL = "http://100.126.22.71:8766/v1/decide"
MAGICDNS_DECIDE_URL = "http://piai-1:8766/v1/decide"
DECIDE_MODEL = "Qwen3-1.7B.hef"
DECIDE_TIMEOUT = 75.0


class HailoGenAIBackend(Backend):
    def __init__(self, base_url: str, model: str, probe: dict | None = None):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.probe = probe if probe is not None else discover()
        self.name = f"hailo:{model}"

    def available(self) -> bool:
        return bool(self.probe.get("available")) and bool(self.model)

    def complete(self, prompt: str, timeout: float) -> str:
        body = {
            "model": self.model,
            "temperature": 0,
            "max_tokens": 80,
            "messages": [{"role": "user", "content": prompt}],
        }
        request = urllib.request.Request(
            self.base_url + "/v1/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode())
        return payload["choices"][0]["message"]["content"]


def list_models(base_url: str, timeout: float = 2.0) -> list[str]:
    request = urllib.request.Request(base_url.rstrip("/") + "/v1/models", method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError):
        return []
    names = []
    for item in payload.get("data", []):
        name = item.get("id") or item.get("name") or ""
        if name:
            names.append(name)
    return names


def decide_url() -> str:
    """Startup resolve: discovery, then existing HAILO_DECIDE_URL, then Tailscale."""
    return resolve_decide_url().rstrip("/")


def refresh_decide_url() -> str:
    """After a decide failure, fetch the discovery topic again."""
    return resolve_decide_url(force=True).rstrip("/")


def decide_origin(url: str) -> str:
    """Host root for /health and /decide. A URL may already end in /v1/decide."""
    raw = url.strip().rstrip("/")
    for suffix in ("/v1/decide", "/decide"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)]
    return raw


def question_for(prompt: str) -> str:
    task = prompt
    marker = "TASK:"
    at = prompt.rfind(marker)
    if at >= 0:
        task = prompt[at + len(marker) :]
    event = ""
    for line in prompt.splitlines():
        if line.startswith("EVENT:"):
            event = line.replace("EVENT:", "", 1).strip()
            break
    text = " ".join(task.split())
    if event:
        text = f"{event}. {text}"
    return text[:500]


def choice_from_payload(payload: dict, options: list[str]) -> str:
    """Map a decide response onto one of the options. Never defaults to options[0]."""
    if not isinstance(payload, dict):
        raise ValueError("decide response was not an object")
    index = payload.get("index")
    if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(options):
        return options[index]
    choice = str(payload.get("choice", ""))
    for token in ("<|im_end|>", "<|im_start|>"):
        choice = choice.replace(token, "")
    choice = choice.strip()
    if choice in options:
        return choice
    letter = choice[:1].upper()
    if letter.isalpha() and len(choice) <= 3:
        idx = ord(letter) - ord("A")
        if 0 <= idx < len(options):
            return options[idx]
    raise ValueError("decide choice did not match an option")


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


def _post_decide_once(base_url: str, question: str, options: list[str], timeout: float) -> dict:
    body = {"question": question, "options": options}
    errors: list[str] = []
    for path in ("/decide", "/v1/decide"):
        try:
            payload = _post_json(decide_origin(base_url) + path, body, timeout)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        payload = dict(payload)
        payload["_path"] = path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))


def post_decide(base_url: str, question: str, options: list[str], timeout: float) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    try:
        return _post_decide_once(base_url, question, options, timeout)
    except Exception:
        fresh = refresh_decide_url()
        if decide_origin(fresh) == decide_origin(base_url):
            raise
        return _post_decide_once(fresh, question, options, timeout)


def get_health(base_url: str, timeout: float = 5.0) -> dict:
    request = urllib.request.Request(decide_origin(base_url) + "/health", method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("health response was not an object")
    return payload


class HailoDecideBackend(Backend):
    """System-1 owner choice via the Pi HEF. Chat completions are not used."""

    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or decide_url()).rstrip("/")
        self.name = f"hailo-decision:{DECIDE_MODEL}"
        self.last: dict = {}

    def available(self) -> bool:
        return bool(self.base_url)

    def complete(self, prompt: str, timeout: float) -> str:
        options = list(OWNERS)
        payload = post_decide(self.base_url, question_for(prompt), options, timeout)
        self.last = payload
        owner = choice_from_payload(payload, options)
        action = OWNER_ACTION.get(owner, "ROUTE_AGENT")
        return json.dumps(
            {
                "owner": owner,
                "secondary": "NONE",
                "priority": "MEDIUM",
                "parallel": False,
                "action": action,
                "escalate": owner == "ESCALATE_GROK",
                "confidence": "HIGH",
            }
        )


def smoke(timeout: float = DECIDE_TIMEOUT) -> dict:
    url = decide_url()
    report: dict = {"decide_url": url, "model": DECIDE_MODEL}
    started = time.perf_counter()
    try:
        report["health"] = get_health(url, 15.0)
        report["health_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
        report["health_ok"] = True
    except Exception as exc:  # noqa: BLE001 — recorded for the status note
        report["health_ok"] = False
        report["health_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
        report["health_error"] = f"{type(exc).__name__}: {exc}"
    started = time.perf_counter()
    try:
        payload = post_decide(
            url,
            "Which lane owns a jelly squash bug?",
            ["PETAL_03_JELLY", "PETAL_12_QA"],
            timeout,
        )
        report["decide_ok"] = True
        report["decide_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
        report["decide"] = payload
        report["choice"] = choice_from_payload(payload, ["PETAL_03_JELLY", "PETAL_12_QA"])
    except Exception as exc:  # noqa: BLE001
        report["decide_ok"] = False
        report["decide_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
        report["decide_error"] = f"{type(exc).__name__}: {exc}"
    return report


def backends_for_probe(probe: dict) -> list[HailoGenAIBackend]:
    if not probe.get("available"):
        return []
    found = []
    for url in probe.get("endpoints", []):
        names = list_models(url)
        for name in names:
            found.append(HailoGenAIBackend(url, name, probe))
    return found


if __name__ == "__main__":
    print(json.dumps(smoke(), indent=2))
