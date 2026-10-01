"""Drain the pending queue through the live decide path. One request at a time."""

from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor
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


def _held(health: dict | None) -> bool:
    return bool(health) and health.get("chip_held") is True and health.get("chip_cond") == "ok"


def _wait_held(health_check, samples: list[dict]) -> dict:
    """GET health only. No decide calls while the chip is not held."""
    while True:
        health = health_check()
        samples.append({"ts": _now(), "chip_held": health.get("chip_held"), "chip_cond": health.get("chip_cond")})
        if _held(health):
            return health
        time.sleep(2.0)


def drain_paced(
    cfg: dict,
    post,
    cases: list[dict],
    *,
    health_check,
    pace_s: float = 0.0415,
    max_in_flight: int = 2,
    root=None,
) -> dict:
    """Send about every 41.5 ms. Pause when the chip is not held or a call falls through to the teacher."""
    paths = default_tree(root)
    state = empty_state(read_jsonl(paths["accepted_failures"]))
    samples: list[dict] = []
    health = _wait_held(health_check, samples)
    sent = 0
    kept = 0
    first = None
    paused = False
    futures: dict = {}
    index = 0
    next_at = time.perf_counter()
    pool = ThreadPoolExecutor(max_workers=max_in_flight)

    def _store(case: dict, payload: dict | None, started: float, error: str | None = None) -> bool:
        nonlocal sent, kept, first, paused
        if error is not None:
            row = {
                "id": case.get("id"),
                "bucket": "QUARANTINE",
                "skip": "transport_error",
                "failure_class": "harness",
                "error": error,
                "counted_unique": False,
                "counted_failure": False,
                "training_eligible": False,
                "chip_backed": False,
                "origin": "jevh-teacher-swarm",
                "ts": _now(),
                "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
            }
            teacher = True
        else:
            row = judge(case, payload or {}, state, cfg)
            row["origin"] = "jevh-teacher-swarm"
            row["ts"] = _now()
            row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            row["health_chip_cond"] = health.get("chip_cond")
            sent += 1
            if row.get("counted_unique"):
                kept += 1
            if first is None:
                first = {
                    "id": row.get("id"),
                    "decided_by": row.get("decided_by"),
                    "confidence": row.get("jev_confidence"),
                    "latency_ms": row.get("latency_ms"),
                    "client_ms": row.get("client_ms"),
                    "model": row.get("model"),
                    "choice": row.get("jev_choice"),
                    "chip_backed": row.get("chip_backed"),
                }
                print("FIRST " + json_dumps(first), flush=True)
            teacher = (payload or {}).get("decided_by") == "teacher" or (payload or {}).get("chip") is None
        append_jsonl(paths["attempts"], row)
        append_jsonl(paths[_BUCKET.get(row.get("bucket"), "quarantine")], row)
        print(
            "%s skip=%s decided_by=%s conf=%s latency_ms=%s"
            % (row.get("id"), row.get("skip"), row.get("decided_by"), row.get("jev_confidence"), row.get("latency_ms")),
            flush=True,
        )
        return teacher

    try:
        while index < len(cases) or futures:
            done = [item for item in list(futures) if item.done()]
            for future in done:
                case, started = futures.pop(future)
                try:
                    payload = future.result()
                except Exception as exc:  # noqa: BLE001
                    if _store(case, None, started, f"{type(exc).__name__}: {exc}"):
                        paused = True
                else:
                    if _store(case, payload, started):
                        paused = True
            if paused and not futures:
                health = _wait_held(health_check, samples)
                paused = False
                next_at = time.perf_counter()
            if index < len(cases) and len(futures) < max_in_flight and not paused:
                now = time.perf_counter()
                if now < next_at:
                    time.sleep(min(0.01, next_at - now))
                    continue
                if index % 24 == 0:
                    health = health_check()
                    samples.append({"ts": _now(), "chip_held": health.get("chip_held"), "chip_cond": health.get("chip_cond")})
                    if not _held(health):
                        paused = True
                        continue
                case = cases[index]
                index += 1
                started = time.perf_counter()
                next_at = started + pace_s
                futures[pool.submit(post, case)] = (case, started)
            elif futures:
                time.sleep(0.004)
    finally:
        pool.shutdown(wait=True, cancel_futures=False)
    return {
        "sent": sent,
        "kept": kept,
        "first": first,
        "chip_held_samples": samples,
        "queue_depth": len(cases) - index,
    }


def json_dumps(payload: dict) -> str:
    import json
    return json.dumps(payload, sort_keys=True)
