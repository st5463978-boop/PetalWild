"""Mine canonical-match chip failures. Stop at 20 counted, or when the bank ends.

Does not train. Does not merge. Does not call the Pi CPU teacher. Rows stay
training_eligible false.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORCH = HERE.parent
if str(ORCH) not in sys.path:
    sys.path.insert(0, str(ORCH))

from jevh_canonical.cases import assert_bank_ok, load_cases  # noqa: E402
from jevh_canonical.client import (  # noqa: E402
    ChipDown,
    chip_block_reason,
    chip_retry_at,
    health,
    post_decide,
    resolve_base,
)
from jevh_canonical.score import fingerprint, score_attempt  # noqa: E402

OUT = HERE / "out"
STOP_AT = 20


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def drop_position_bias(rows: list[dict]) -> None:
    """Same slot on both option orders is a harness bug, not a counted failure.

    A pair that picks the same choice text on both orders is a real answer.
    """
    groups: dict[tuple, list[dict]] = {}
    for row in rows:
        if row.get("skip") not in (None,):
            continue
        key = (
            row.get("question"),
            tuple(sorted(row.get("options") or [])),
            row.get("answer"),
        )
        groups.setdefault(key, []).append(row)
    for group in groups.values():
        if len(group) < 2:
            continue
        indexes = {row.get("jev_index") for row in group}
        choices = {row.get("jev_choice") for row in group}
        if len(indexes) == 1 and len(choices) > 1:
            for row in group:
                if row.get("counted_failure"):
                    row["counted_failure"] = False
                    row["skip"] = "position_bias"
                    row["bucket"] = "QUARANTINE"


def summarise(rows: list[dict], *, sent: int, stop_reason: str, error: str | None = None) -> dict:
    kinds = Counter(row["kind"] for row in rows if row.get("counted_failure"))
    return {
        "ts": _now(),
        "lane": "jevh-canonical-match",
        "family": "canonical_match",
        "agent": "jev-cursor-canonical",
        "kind": "adversarial",
        "teacher": "cursor",
        "training_eligible": False,
        "decide_url_origin_hidden": True,
        "cases_in_bank": len(load_cases()),
        "cases_sent": sent,
        "cases_scored": len(rows),
        "counted_failures": sum(1 for row in rows if row.get("counted_failure")),
        "stop_at": STOP_AT,
        "stop_reason": stop_reason,
        "confident_correct": sum(
            1
            for row in rows
            if row.get("confident") and not row.get("jev_wrong") and not row.get("skip")
        ),
        "jev_wrong": sum(1 for row in rows if row.get("jev_wrong")),
        "production_escalated": sum(1 for row in rows if row.get("production_escalated")),
        "no_forced_jev": sum(1 for row in rows if row.get("skip") == "no_forced_jev"),
        "index_bugs": sum(
            1
            for row in rows
            if row.get("skip") in {"index_choice_mismatch", "unmapped_choice", "position_bias"}
        ),
        "failures_by_kind": dict(kinds),
        "counted_ids": [row["id"] for row in rows if row.get("counted_failure")],
        "error": error,
        "note": (
            "Diagnostic gold only. Canonical matches its replica: a marked "
            "stale-client or non-canonical cache is not a contradiction. "
            "Do not train on this ledger. The chip answer is the only score."
        ),
    }


def wait_until_chip(budget_s: float) -> str:
    """Return a discovery base once the chip probe is ok. Never posts."""
    deadline = time.monotonic() + budget_s
    last = "chip probe not ok"
    while True:
        base = resolve_base()
        payload = health(base)
        reason = chip_block_reason(payload)
        if reason is None:
            return base
        last = reason
        print(f"chip_down {reason}", flush=True)
        if time.monotonic() >= deadline:
            raise ChipDown(last)
        retry = chip_retry_at(payload)
        sleep_s = 20.0
        if retry is not None:
            delay = (retry - datetime.now(timezone.utc)).total_seconds() + 2.0
            if delay > 0:
                sleep_s = min(delay, max(1.0, deadline - time.monotonic()))
        time.sleep(min(sleep_s, max(1.0, deadline - time.monotonic())))


def run(budget_s: float = 900.0, timeout: float = 75.0) -> dict:
    assert_bank_ok()
    cases = load_cases()
    OUT.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    seen: set[str] = set()
    error = None
    sent = 0
    stop_reason = "family_exhausted"
    try:
        base = wait_until_chip(budget_s)
        for case in cases:
            fp = fingerprint(case)
            if fp in seen:
                continue
            # Re-check the probe so a mid-run chip outage does not fall through to the teacher.
            payload_health = health(base)
            if chip_block_reason(payload_health):
                base = wait_until_chip(max(30.0, budget_s - 1.0))
            started = time.perf_counter()
            payload = post_decide(
                base,
                case["question"],
                case["options"],
                context=case["context"],
                timeout=timeout,
            )
            sent += 1
            row = score_attempt(case, payload, seen)
            row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            if row.get("skip") == "no_forced_jev":
                rows.append(row)
                stop_reason = "chip_missing_stopped"
                error = "decide returned no chip answer; stopped before another teacher fallback"
                break
            seen.add(row["fingerprint"])
            rows.append(row)
            drop_position_bias(rows)
            print(
                f"{case['id']} choice={row.get('jev_choice')} "
                f"conf={row.get('jev_confidence')} counted={row.get('counted_failure')} "
                f"skip={row.get('skip')}",
                flush=True,
            )
            if sum(1 for item in rows if item.get("counted_failure")) >= STOP_AT:
                stop_reason = "counted_20"
                break
        else:
            if sum(1 for row in rows if row.get("counted_failure")) >= STOP_AT:
                stop_reason = "counted_20"
            elif error is None:
                stop_reason = "family_exhausted"
    except Exception as exc:  # noqa: BLE001 — recorded, run stops
        error = f"{type(exc).__name__}: {exc}"
        if not rows:
            stop_reason = "chip_unavailable"
        elif stop_reason == "family_exhausted":
            stop_reason = "stopped_on_error"
    drop_position_bias(rows)
    counted = sum(1 for row in rows if row.get("counted_failure"))
    if counted >= STOP_AT and stop_reason == "family_exhausted":
        stop_reason = "counted_20"
    failures = [row for row in rows if row.get("counted_failure")]
    summary = summarise(rows, sent=sent, stop_reason=stop_reason, error=error)
    _write_jsonl(OUT / "ledger.jsonl", rows)
    _write_jsonl(OUT / "failures.jsonl", failures)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mine canonical-match JEV-H chip failures.")
    parser.add_argument("--check", action="store_true", help="Validate the case bank and exit")
    parser.add_argument("--budget", type=float, default=900.0, help="Seconds to wait for the chip")
    parser.add_argument("--timeout", type=float, default=75.0)
    args = parser.parse_args(argv)
    if args.check:
        assert_bank_ok()
        print(json.dumps({"ok": True, "cases": len(load_cases()), "training_eligible": False}))
        return 0
    summary = run(budget_s=args.budget, timeout=args.timeout)
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("error") is None else 2


if __name__ == "__main__":
    raise SystemExit(main())
