"""System-1 decide client.

High-frequency choices go to the trained Qwen3-1.7B DPO CPU service:
hef-dfc primary, Pi CPU fallback, then the existing hailo-decision hop.
URLs come from ntfy discovery (health-checked), then env. A 503 while the
model is loading, a timeout, or a 502 moves to the next tier. This module
does not call MinoJEV, an RLCD policy, a local Ollama tag, or
`/v1/chat/completions`. It does not download or recompile HEFs.
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

from hailo_decide_url import (  # noqa: E402
    FALLBACK_TIMEOUT,
    LAST_RESORT_TIMEOUT,
    PRIMARY_TIMEOUT,
    resolve_decide_tiers,
    resolve_decide_url,
)
from petal_dispatch.discover import discover
from petal_dispatch.router import Backend
from petal_dispatch.schema import OWNER_ACTION, OWNERS

# Last-resort Pi Tailscale. MagicDNS http://piai-1:8766/v1/decide is the same hop.
DEFAULT_DECIDE_URL = "http://100.126.22.71:8766/v1/decide"
MAGICDNS_DECIDE_URL = "http://piai-1:8766/v1/decide"
DECIDE_MODEL = "HailoJEV-Qwen3-1.7B-DPO"
DECIDE_TIMEOUT = PRIMARY_TIMEOUT + FALLBACK_TIMEOUT + LAST_RESORT_TIMEOUT


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
    """Startup resolve: first healthy DPO/Hailo tier."""
    return resolve_decide_url().rstrip("/")


def refresh_decide_url() -> str:
    """After a decide failure, fetch discovery topics again."""
    return resolve_decide_url(force=True).rstrip("/")


def decide_tiers(force: bool = False) -> list[tuple[str, str, float]]:
    return [(name, url.rstrip("/"), timeout) for name, url, timeout in resolve_decide_tiers(force)]


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


def _log_decide(tier: str, payload: dict) -> None:
    print(
        "decide "
        f"tier={tier} "
        f"confidence={payload.get('confidence')} "
        f"margin={payload.get('margin')} "
        f"latency_ms={payload.get('latency_ms')} "
        f"mode={payload.get('mode')} "
        f"model={payload.get('model')}",
        file=sys.stderr,
        flush=True,
    )


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


def _tier_for_url(url: str, tiers: list[tuple[str, str, float]]) -> tuple[str, float]:
    origin = decide_origin(url)
    for name, tier_url, timeout in tiers:
        if decide_origin(tier_url) == origin:
            return name, timeout
    return "given", PRIMARY_TIMEOUT


def post_decide(base_url: str, question: str, options: list[str], timeout: float) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    last_error: BaseException | None = None
    seen: set[str] = set()
    chain: list[tuple[str, str, float]] = []
    try:
        tiers = decide_tiers()
    except Exception:
        tiers = []
    if base_url:
        name, tier_timeout = _tier_for_url(base_url, tiers)
        chain.append((name, base_url.rstrip("/"), timeout if name == "given" else tier_timeout))
    for name, url, tier_timeout in tiers:
        chain.append((name, url, tier_timeout))
    for name, url, tier_timeout in chain:
        origin = decide_origin(url)
        if origin in seen:
            continue
        seen.add(origin)
        try:
            payload = _post_decide_once(url, question, options, tier_timeout)
        except Exception as exc:  # noqa: BLE001 — walk the next DPO/Hailo tier
            last_error = exc
            continue
        payload = dict(payload)
        payload["_tier"] = name
        payload["_decide_url"] = url
        _log_decide(name, payload)
        return payload
    if last_error is not None:
        fresh = decide_tiers(force=True)
        for name, url, tier_timeout in fresh:
            origin = decide_origin(url)
            if origin in seen:
                continue
            payload = _post_decide_once(url, question, options, tier_timeout)
            payload = dict(payload)
            payload["_tier"] = name
            payload["_decide_url"] = url
            _log_decide(name, payload)
            return payload
        raise last_error
    raise RuntimeError("no decide tier resolved")


def get_health(base_url: str, timeout: float = 5.0) -> dict:
    request = urllib.request.Request(decide_origin(base_url) + "/health", method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("health response was not an object")
    return payload


class HailoDecideBackend(Backend):
    """System-1 owner choice via DPO CPU, Hailo last resort. Chat completions are not used."""

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
