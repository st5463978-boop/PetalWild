"""Drain the pending queue through the live decide path. One request at a time."""

from __future__ import annotations

import time
from datetime import datetime, timezone

from jevh_teacher_swarm.io_util import append_jsonl, read_jsonl, write_jsonl
from jevh_teacher_swarm.judge import empty_state, judge
from jevh_teacher_swarm.prepare import tree as default_tree

_BUCKET = {
    "ACCEPTED_FAILURE": "accepted_failures",
    "ACCEPTED_CORRECT": "accepted_correct",
    "REJECTED": "rejected",
    "QUARANTINE": "quarantine",
}


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def drain(cfg: dict, post, health: dict | None = None, root=None, limit: int | None = None, stop_when=None) -> dict:
    paths = default_tree(root)
    pending = read_jsonl(paths["pending"])
    inflight = read_jsonl(paths["inflight"])
    attempted = {row.get("id") for row in read_jsonl(paths["attempts"])}
    queued = []
    seen = set()
    for row in inflight + pending:
        if row.get("id") in attempted or row.get("id") in seen:
            continue
        seen.add(row["id"])
        queued.append(row)
    if limit is not None:
        queued = queued[: max(0, limit)]
    state = empty_state(read_jsonl(paths["accepted_failures"]))
    sent = 0
    chip_answers = 0
    transport_errors = 0
    stopped_not_student = False
    for case in queued:
        write_jsonl(paths["inflight"], [case])
        started = time.perf_counter()
        try:
            payload = post(case)
            transport_errors = 0
        except Exception as exc:  # noqa: BLE001 — recorded, drain continues
            payload = None
            transport_errors += 1
            row = {
                "id": case.get("id"),
                "bucket": "QUARANTINE",
                "skip": "transport_error",
                "failure_class": "harness",
                "error": f"{type(exc).__name__}: {exc}",
                "counted_unique": False,
                "counted_failure": False,
                "training_eligible": False,
                "chip_backed": False,
                "ts": _now(),
                "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
            }
        else:
            row = judge(case, payload, state, cfg)
            row["origin"] = "jevh-teacher-swarm"
            row["ts"] = _now()
            row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            row["health_chip_cond"] = (health or {}).get("chip_cond")
            sent += 1
            if row.get("chip_backed"):
                chip_answers += 1
        append_jsonl(paths["attempts"], row)
        bucket = _BUCKET.get(row.get("bucket"), "quarantine")
        append_jsonl(paths[bucket], row)
        print(
            "%s skip=%s chip=%s client_ms=%s model=%s"
            % (row.get("id"), row.get("skip"), row.get("chip_backed"), row.get("client_ms"), row.get("model")),
            flush=True,
        )
        attempted.add(case.get("id"))
        if transport_errors >= 3:
            break
        if stop_when is not None and payload is not None and stop_when(row, payload):
            stopped_not_student = True
            break
    remaining = [row for row in read_jsonl(paths["pending"]) if row.get("id") not in attempted]
    write_jsonl(paths["pending"], remaining)
    write_jsonl(paths["inflight"], [])
    return {
        "sent": sent,
        "chip_answers": chip_answers,
        "stopped_on_transport": transport_errors >= 3,
        "stopped_not_student": stopped_not_student,
        "queue_depth": len(remaining),
        "health": health,
    }
