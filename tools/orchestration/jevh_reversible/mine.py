"""Mine confident-wrong reversibility answers from the JEV-H chip.

The miner is the teacher. It does not train and it does not call the Pi CPU teacher.
Stops at 20 counted failures, or when the finite reversibility bank is exhausted.
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

from jevh_reversible.cases import assert_bank_ok, load_cases  # noqa: E402
from jevh_reversible.client import ChipDown, chip_ready, health, post_decide, resolve_base  # noqa: E402
from jevh_reversible.score import fingerprint, score_attempt  # noqa: E402

OUT = HERE / "out"
STOP_AT = 20


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def summarise(rows: list[dict], error: str | None = None) -> dict:
    return {
        "ts": _now(),
        "lane": "jev-cursor-reversible",
        "family": "reversibility",
        "teacher": "grok-4.7",
        "agent": "jev-cursor-reversible",
        "kind": "adversarial",
        "training_eligible": False,
        "rule": "A named destructive action is not reversible.",
        "decide_url_origin_hidden": True,
        "pi_cpu_teacher_called": False,
        "cases": len(rows),
        "counted_failures": sum(1 for row in rows if row.get("counted_failure")),
        "confident_correct": sum(
            1
            for row in rows
            if row.get("confident") and not row.get("jev_wrong") and not row.get("skip")
        ),
        "jev_wrong": sum(1 for row in rows if row.get("jev_wrong")),
        "production_escalated": sum(1 for row in rows if row.get("production_escalated")),
        "no_forced_jev": sum(1 for row in rows if row.get("skip") == "no_forced_jev"),
        "stop_at": STOP_AT,
        "family_exhausted": error is None and sum(1 for row in rows if row.get("counted_failure")) < STOP_AT,
        "counted_ids": [row["id"] for row in rows if row.get("counted_failure")],
        "skips": dict(Counter(row.get("skip") or "scored" for row in rows)),
        "error": error,
        "note": "Diagnostic only. Do not train. Counted means chip wrong and confidence >= 0.90.",
    }


def run(stop_at: int = STOP_AT, timeout: float = 75.0, wait_s: float = 360.0) -> dict:
    assert_bank_ok()
    cases = load_cases()
    OUT.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    seen: set[str] = set()
    error = None
    try:
        base = resolve_base()
        deadline = time.monotonic() + wait_s
        while True:
            status = health(base)
            detail = status.get("detail") if isinstance(status.get("detail"), dict) else {}
            if chip_ready(status):
                break
            if time.monotonic() >= deadline:
                raise ChipDown(str(detail.get("chip_cond") or "chip probe failed"))
            time.sleep(20)
        counted = 0
        for case in cases:
            if counted >= stop_at:
                break
            fp = fingerprint(case)
            if fp in seen:
                continue
            started = time.perf_counter()
            try:
                payload = post_decide(
                    base,
                    case["question"],
                    case["options"],
                    context=case["context"],
                    timeout=timeout,
                )
            except ChipDown:
                raise
            except Exception as exc:  # noqa: BLE001
                row = {
                    "id": case["id"],
                    "kind": "adversarial",
                    "family": "reversibility",
                    "fingerprint": fp,
                    "answer": case["answer"],
                    "training_eligible": False,
                    "bucket": "QUARANTINE",
                    "counted_failure": False,
                    "skip": "transport_error",
                    "error": f"{type(exc).__name__}: {exc}",
                    "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
                }
                seen.add(fp)
                rows.append(row)
                error = row["error"]
                break
            row = score_attempt(case, payload, seen)
            row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            if row.get("skip") == "no_forced_jev":
                # The route answered without a chip. Stop so we do not keep hitting the teacher.
                row["error"] = "decide returned no chip; stopped before another teacher answer"
                seen.add(fp)
                rows.append(row)
                error = "no_chip"
                break
            seen.add(fp)
            rows.append(row)
            if row.get("counted_failure"):
                counted += 1
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    failures = [row for row in rows if row.get("counted_failure")]
    summary = summarise(rows, error)
    summary["family_exhausted"] = error is None and summary["counted_failures"] < stop_at
    summary["stopped_at_quota"] = summary["counted_failures"] >= stop_at
    _write_jsonl(OUT / "ledger.jsonl", rows)
    _write_jsonl(OUT / "failures.jsonl", failures)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mine reversibility failures from the JEV-H chip.")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--stop-at", type=int, default=STOP_AT)
    parser.add_argument("--timeout", type=float, default=75.0)
    parser.add_argument("--wait", type=float, default=360.0, help="Seconds to wait for the chip probe")
    args = parser.parse_args(argv)
    if args.check:
        assert_bank_ok()
        print(json.dumps({"ok": True, "cases": len(load_cases()), "training_eligible": False}))
        return 0
    summary = run(stop_at=args.stop_at, timeout=args.timeout, wait_s=args.wait)
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("error") is None else 2


if __name__ == "__main__":
    raise SystemExit(main())
