"""OpenAI-compatible client for a Hailo genai server on this machine.

The request carries no tools. The server is expected to be hailo-ollama or
the Hailo genai runtime bound to localhost. This module does not download models.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from petal_dispatch.discover import discover
from petal_dispatch.router import Backend


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


def backends_for_probe(probe: dict) -> list[HailoGenAIBackend]:
    if not probe.get("available"):
        return []
    found = []
    for url in probe.get("endpoints", []):
        names = list_models(url)
        for name in names:
            found.append(HailoGenAIBackend(url, name, probe))
    return found
