"""Score Hailo routers. If the NPU is absent, record that and do not invent accuracy."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from petal_dispatch.discover import discover  # noqa: E402
from petal_dispatch.hailo_backend import backends_for_probe  # noqa: E402
from petal_dispatch.router import extract_json  # noqa: E402
from petal_dispatch.schema import parse_decision, prompt_for  # noqa: E402

HERE = Path(__file__).resolve().parent
TASKS = HERE / "tasks.jsonl"
RESULTS = HERE / "latest_results.json"


def load_tasks() -> list[dict]:
    rows = []
    for line in TASKS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def score_model(backend, rows: list[dict]) -> dict:
    owner_hits = 0
    action_hits = 0
    valid = 0
    escalations = 0
    latencies = []
    failures = []
    for row in rows:
        started = time.perf_counter()
        try:
            raw = backend.complete(prompt_for(row["task"]), 8.0)
            parsed = parse_decision(extract_json(raw or "") or {})
        except Exception as exc:  # noqa: BLE001
            parsed = None
            raw = f"{type(exc).__name__}"
        elapsed = time.perf_counter() - started
        latencies.append(elapsed)
        if parsed is None:
            failures.append({"id": row["id"], "reason": "malformed"})
            continue
        valid += 1
        if parsed["owner"] == row["gold_owner"]:
            owner_hits += 1
        else:
            failures.append({"id": row["id"], "got": parsed["owner"], "gold": row["gold_owner"]})
        if parsed["action"] == row["gold_action"]:
            action_hits += 1
        if parsed["escalate"] or parsed["owner"] == "ESCALATE_GROK":
            escalations += 1
    count = len(rows) or 1
    return {
        "model": backend.name,
        "tasks": len(rows),
        "structured_output_validity": valid / count,
        "owner_accuracy": owner_hits / count,
        "action_accuracy": action_hits / count,
        "escalation_rate": escalations / count,
        "failure_rate": (count - valid) / count,
        "latency_ms_mean": round(1000.0 * (sum(latencies) / count), 2),
        "sample_failures": failures[:12],
    }


def choose(scores: list[dict]) -> str | None:
    if not scores:
        return None
    ranked = sorted(
        scores,
        key=lambda row: (
            row["owner_accuracy"],
            row["structured_output_validity"],
            -row["latency_ms_mean"],
        ),
        reverse=True,
    )
    best = ranked[0]
    if best["structured_output_validity"] < 0.9 or best["owner_accuracy"] <= 0:
        return None
    return best["model"]


def run() -> dict:
    if not TASKS.is_file():
        from gold_tasks import main as write_tasks

        write_tasks()
    rows = load_tasks()
    probe = discover()
    if not probe.get("available"):
        payload = {
            "status": "not_run",
            "reason": probe.get("reason") or "no_hailo_device",
            "selected_model": None,
            "note": "No accuracy is reported. Confidence labels were not calibrated. This is not a Jev model and not an RLCD policy.",
            "task_count": len(rows),
            "probe": probe,
            "models": [],
        }
    else:
        scores = [score_model(backend, rows) for backend in backends_for_probe(probe)]
        payload = {
            "status": "scored",
            "reason": "",
            "selected_model": choose(scores),
            "note": "Selection uses owner accuracy, then JSON validity, then latency. Labels are not calibrated probabilities.",
            "task_count": len(rows),
            "probe": probe,
            "models": scores,
        }
    RESULTS.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


if __name__ == "__main__":
    result = run()
    print(json.dumps({"status": result["status"], "reason": result["reason"], "selected_model": result["selected_model"], "tasks": result["task_count"]}))
