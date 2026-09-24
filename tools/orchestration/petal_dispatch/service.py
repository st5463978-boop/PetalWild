"""Local foreman. It records approved routes. It does not spawn shells."""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from petal_dispatch.discover import discover  # noqa: E402
from petal_dispatch.hailo_backend import DECIDE_TIMEOUT, HailoDecideBackend, decide_url, get_health  # noqa: E402
from petal_dispatch.router import decide  # noqa: E402

RUNTIME = ROOT / "runtime"
QUEUE = RUNTIME / "queue.jsonl"
HOST = "127.0.0.1"
PORT = 8731

EVENTS = {
    "agent_finished",
    "agent_failed",
    "build_failed",
    "test_failed",
    "merge_conflict",
    "issue_created",
    "performance_regression",
    "asset_request",
    "visual_qa_failed",
    "",
}


def enqueue(record: dict) -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with QUEUE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def route_task(task: str, event: str = "") -> dict:
    if event not in EVENTS:
        event = ""
    # ponytail: one Pi HEF call; no local Ollama fallback if the tunnel is down.
    backend = HailoDecideBackend(decide_url())
    decision = decide(task, backend, event=event, timeout=DECIDE_TIMEOUT)
    record = {
        "task": task,
        "event": event,
        "decision": decision,
        "decide_url": backend.base_url,
        "remote": backend.last,
    }
    enqueue(record)
    return record


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        return

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/health"):
            url = decide_url()
            remote: dict = {"ok": False}
            try:
                remote = get_health(url, 5.0)
                remote["ok"] = True
            except Exception as exc:  # noqa: BLE001 — the foreman stays up when the tailnet is down
                remote = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
            self._send(200, {"ok": True, "decide_url": url, "remote": remote, "hailo": discover()})
            return
        if self.path.startswith("/queue"):
            lines = []
            if QUEUE.is_file():
                lines = [json.loads(line) for line in QUEUE.read_text().splitlines() if line.strip()]
            self._send(200, {"count": len(lines), "items": lines[-20:]})
            return
        self._send(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.startswith("/route"):
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length).decode() if length else "{}"
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                self._send(400, {"error": "malformed_json"})
                return
            task = str(payload.get("task", "")).strip()
            if not task:
                self._send(400, {"error": "task_required"})
                return
            event = str(payload.get("event", ""))
            self._send(200, route_task(task, event))
            return
        self._send(404, {"error": "not_found"})


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"petal dispatch http://{HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
