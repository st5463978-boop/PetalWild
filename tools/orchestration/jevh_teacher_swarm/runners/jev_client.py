"""Live JEV-H client.

POST goes through the clean-core miner. Discovery order is that client's:
explicit URL, localhost, then the ntfy topic. No tunnel host is hardcoded.
A DecideSession keeps one connection for a wall of questions.
"""

from __future__ import annotations

import http.client
import json
import socket
import ssl
import urllib.parse

from jevh_clean_core.client import _get_json, origin, post_decide, resolve_decide_url

AGENT = "jevh-teacher-swarm"


def context_for(case: dict) -> str:
    parts = []
    for key, value in (case.get("facts") or {}).items():
        parts.append(f"{key}={value}")
    return " ".join(parts)[:240]


def fetch_health(timeout: float = 20.0) -> dict:
    url = resolve_decide_url()
    root = origin(url)
    errors: list[str] = []
    for path in ("/health", "/v1/health"):
        try:
            payload = _get_json(root + path, timeout)
        except Exception as exc:  # noqa: BLE001 — health is best-effort evidence
            errors.append(f"{path}:{type(exc).__name__}")
            continue
        if payload.get("ok") is True:
            detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
            sha = str(detail.get("hef_sha256") or "")
            return {
                "ok": True,
                "model": payload.get("model"),
                "device": payload.get("device"),
                "hef_sha_prefix": sha[:8],
                "chip_cond": detail.get("chip_cond"),
                "chip_held": detail.get("chip_held"),
                "last_probe": detail.get("last_probe"),
                "threshold": detail.get("threshold"),
                "decisions": detail.get("decisions"),
                "escalated": detail.get("escalated"),
                "npu_fail_streak": detail.get("npu_fail_streak"),
            }
    raise RuntimeError("health failed: " + ",".join(errors))


def decide(case: dict, timeout: float) -> dict:
    url = resolve_decide_url()
    return post_decide(
        url,
        case["question"],
        list(case["presented_options"]),
        context=context_for(case),
        agent=AGENT,
        kind=case.get("kind") or "",
        timeout=timeout,
    )


class DecideSession:
    """One keep-alive connection. Question and options only, so the student stays near its own latency."""

    def __init__(self, url: str, timeout: float):
        root = origin(url)
        parsed = urllib.parse.urlparse(root)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ValueError("decide URL has no host")
        self._https = parsed.scheme == "https"
        self._host = parsed.hostname
        self._port = parsed.port or (443 if self._https else 80)
        self._timeout = timeout
        self._conn: http.client.HTTPConnection | None = None

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def _open(self) -> http.client.HTTPConnection:
        if self._conn is not None:
            return self._conn
        infos = socket.getaddrinfo(self._host, self._port, socket.AF_INET, socket.SOCK_STREAM)
        ip = infos[0][4][0]
        raw = socket.create_connection((ip, self._port), timeout=self._timeout)
        if self._https:
            raw = ssl.create_default_context().wrap_socket(raw, server_hostname=self._host)
            conn: http.client.HTTPConnection = http.client.HTTPSConnection(self._host, self._port, timeout=self._timeout)
        else:
            conn = http.client.HTTPConnection(self._host, self._port, timeout=self._timeout)
        raw.settimeout(self._timeout)
        conn.sock = raw
        self._conn = conn
        return conn

    def decide(self, case: dict) -> dict:
        body = json.dumps(
            {
                "question": case["question"],
                "options": list(case["presented_options"]),
                "agent": AGENT,
                "kind": case.get("kind") or "",
            }
        ).encode()
        headers = {"Content-Type": "application/json", "Connection": "keep-alive"}
        conn = self._open()
        try:
            conn.request("POST", "/v1/decide", body=body, headers=headers)
            response = conn.getresponse()
            raw = response.read()
        except Exception:
            self.close()
            raise
        if response.status == 404:
            self.close()
            conn = self._open()
            conn.request("POST", "/decide", body=body, headers=headers)
            response = conn.getresponse()
            raw = response.read()
        if response.status >= 400:
            raise RuntimeError(f"HTTP {response.status}: {raw[:200]!r}")
        payload = json.loads(raw.decode())
        if not isinstance(payload, dict):
            raise ValueError("decide response was not an object")
        payload["_path"] = "/v1/decide"
        return payload
