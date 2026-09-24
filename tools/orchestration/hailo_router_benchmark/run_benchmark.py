"""Score Hailo routers. If the NPU is absent, record that and do not invent accuracy."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from petal_dispatch.hailo_backend import DECIDE_MODEL, decide_url  # noqa: E402

HERE = Path(__file__).resolve().parent
TASKS = HERE / "tasks.jsonl"
RESULTS = HERE / "latest_results.json"


def load_tasks() -> list[dict]:
    rows = []
    for line in TASKS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def run() -> dict:
    if not TASKS.is_file():
        from gold_tasks import main as write_tasks

        write_tasks()
    rows = load_tasks()
    # ponytail: the Pi HEF is the system-1 model; this script does not rank local Ollama tags.
    payload = {
        "status": "fixed_endpoint",
        "reason": "pi_hef_decide",
        "selected_model": DECIDE_MODEL,
        "decide_url": decide_url(),
        "note": "System-1 calls POST /decide on the Pi Hailo-10H. This bake-off does not score MinoJEV, RLCD, or a local CPU Qwen. Confidence labels are not calibrated.",
        "task_count": len(rows),
        "models": [],
    }
    RESULTS.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


if __name__ == "__main__":
    result = run()
    print(json.dumps({"status": result["status"], "reason": result["reason"], "selected_model": result["selected_model"], "tasks": result["task_count"]}))
