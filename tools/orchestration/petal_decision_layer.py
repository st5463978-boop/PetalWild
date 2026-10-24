"""PETAL_DECISION_LAYER — cheap bounded choices for recovery agents.

Uses the existing Pi Hailo decide service (Qwen3-1.7B.hef). Does not run the
router benchmark, does not call chat completions, and does not pick options[0]
when the service fails. One file lock so concurrent recovery agents do not
stampede the Pi.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

_TOOLS = Path(__file__).resolve().parents[1]
_ORCH = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))
if str(_ORCH) not in sys.path:
    sys.path.insert(0, str(_ORCH))

from petal_dispatch.hailo_backend import choice_from_payload, decide_url, post_decide  # noqa: E402

RECEIPTS = _ORCH / "runtime" / "decide-receipts.jsonl"
LOCK = Path("/tmp/petal_decision_layer.lock")
DOWN = Path("/tmp/petal_decision_layer.down")
TIMEOUT = 30.0
DOWN_TTL = 600.0

DECISIONS = ("ADOPT", "PORT", "STUDY", "REJECT")
LICENCES = ("GREEN", "YELLOW", "REVIEW", "RED")
PRIORITIES = ("HIGH", "MEDIUM", "LOW")
LANES = (
    "PETAL-01",
    "PETAL-02",
    "PETAL-03",
    "PETAL-04",
    "PETAL-05",
    "PETAL-06",
    "PETAL-07",
    "PETAL-08",
)


def PETAL_DECISION_LAYER(question: str, options: list[str], timeout: float = TIMEOUT) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    with LOCK.open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        cached = _down_reason()
        if cached:
            result = _escalate(question, options, started, "backend_unavailable", cached)
        else:
            try:
                url = decide_url()
                payload = post_decide(url, question[:500], options, timeout)
                choice = choice_from_payload(payload, options)
                result = {
                    "status": "ok",
                    "choice": choice,
                    "index": payload.get("index"),
                    "model": payload.get("model"),
                    "latency_ms": payload.get("latency_ms"),
                    "raw": payload.get("raw"),
                    "presented_index": payload.get("presented_index"),
                    "shuffle_order": payload.get("shuffle_order"),
                    "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
                    "question": question[:500],
                    "options": options,
                }
                if DOWN.exists():
                    DOWN.unlink()
            except Exception as exc:  # noqa: BLE001 — recovery continues; Grok owns the call
                DOWN.write_text(f"{time.time()}\n{type(exc).__name__}: {exc}\n", encoding="utf-8")
                result = _escalate(question, options, started, "backend_unavailable", f"{type(exc).__name__}: {exc}")
    _append_receipt(result)
    return result


def _down_reason() -> str:
    if not DOWN.is_file():
        return ""
    try:
        stamp_s, _, detail = DOWN.read_text(encoding="utf-8").partition("\n")
        if time.time() - float(stamp_s) > DOWN_TTL:
            return ""
    except (OSError, ValueError):
        return ""
    return "cached: " + detail.strip()


def _escalate(question: str, options: list[str], started: float, reason: str, error: str) -> dict:
    return {
        "status": "escalate",
        "reason": reason,
        "error": error,
        "choice": None,
        "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
        "question": question[:500],
        "options": options,
    }


def _append_receipt(result: dict) -> None:
    try:
        RECEIPTS.parent.mkdir(parents=True, exist_ok=True)
        row = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "source": "PETAL_DECISION_LAYER",
            "question": result.get("question"),
            "options": result.get("options"),
            "choice": result.get("choice"),
            "status": result.get("status"),
            "index": result.get("index"),
            "model": result.get("model"),
            "latency_ms": result.get("latency_ms"),
            "raw": result.get("raw"),
            "presented_index": result.get("presented_index"),
            "shuffle_order": result.get("shuffle_order"),
            "reason": result.get("reason"),
        }
        with RECEIPTS.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    except OSError:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="PETAL_DECISION_LAYER")
    parser.add_argument("--question", required=True)
    parser.add_argument("--option", action="append", required=True)
    parser.add_argument("--timeout", type=float, default=TIMEOUT)
    args = parser.parse_args()
    result = PETAL_DECISION_LAYER(args.question, args.option, args.timeout)
    print(json.dumps(result))
    if result["status"] != "ok":
        sys.exit(2)


if __name__ == "__main__":
    main()
