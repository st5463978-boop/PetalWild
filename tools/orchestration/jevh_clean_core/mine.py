"""Run the clean-core JEV-H failure-mining lane.

Scores the chip's forced answer. Escalation is recorded separately.
Does not train. Does not compile a HEF. Writes diagnostic rows only.
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

from jevh_clean_core.cases import assert_bank_ok, load_cases  # noqa: E402
from jevh_clean_core.client import post_decide, resolve_decide_url  # noqa: E402
from jevh_clean_core.score import fingerprint, score_attempt  # noqa: E402

OUT = HERE / "out"


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def summarise(rows: list[dict], error: str | None = None) -> dict:
    kinds = Counter(row["kind"] for row in rows if row.get("counted_failure"))
    skips = Counter(row.get("skip") or "scored" for row in rows)
    return {
        "ts": _now(),
        "lane": "jevh-clean-core",
        "training_eligible": False,
        "decide_url_origin_hidden": True,
        "cases": len(rows),
        "counted_failures": sum(1 for row in rows if row.get("counted_failure")),
        "confident_correct": sum(
            1 for row in rows if row.get("confident") and not row.get("jev_wrong") and not row.get("skip")
        ),
        "jev_wrong": sum(1 for row in rows if row.get("jev_wrong")),
        "production_escalated": sum(1 for row in rows if row.get("production_escalated")),
        "index_bugs": sum(1 for row in rows if row.get("skip") in {"index_choice_mismatch", "letter_without_index", "unmapped_choice"}),
        "no_forced_jev": sum(1 for row in rows if row.get("skip") == "no_forced_jev"),
        "failures_by_kind": dict(kinds),
        "skips": dict(skips),
        "error": error,
        "note": "Diagnostic gold only. Do not train on this ledger. JEV is the chip forced answer.",
    }


def run(limit: int | None = None, url: str | None = None, timeout: float = 75.0) -> dict:
    assert_bank_ok()
    cases = load_cases()
    if limit is not None:
        cases = cases[: max(0, limit)]
    target = resolve_decide_url(url)
    OUT.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    seen: set[str] = set()
    error = None
    try:
        for case in cases:
            started = time.perf_counter()
            try:
                payload = post_decide(
                    target,
                    case["question"],
                    case["options"],
                    context=case["context"],
                    kind=case["kind"],
                    timeout=timeout,
                )
                row = score_attempt(case, payload, seen)
                row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            except Exception as exc:  # noqa: BLE001 — recorded, not retried in a loop
                row = {
                    "id": case["id"],
                    "kind": case["kind"],
                    "family": case["family"],
                    "fingerprint": fingerprint(case),
                    "answer": case["answer"],
                    "training_eligible": False,
                    "bucket": "QUARANTINE",
                    "counted_failure": False,
                    "skip": "transport_error",
                    "error": f"{type(exc).__name__}: {exc}",
                    "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
                }
            seen.add(row["fingerprint"])
            rows.append(row)
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
    failures = [row for row in rows if row.get("counted_failure")]
    summary = summarise(rows, error)
    _write_jsonl(OUT / "ledger.jsonl", rows)
    _write_jsonl(OUT / "failures.jsonl", failures)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mine confident-wrong JEV-H clean-core decisions.")
    parser.add_argument("--limit", type=int, default=None, help="Max cases to send")
    parser.add_argument("--url", default=None, help="Override decide URL")
    parser.add_argument("--timeout", type=float, default=75.0)
    parser.add_argument("--check", action="store_true", help="Validate the case bank and exit")
    args = parser.parse_args(argv)
    if args.check:
        assert_bank_ok()
        print(json.dumps({"ok": True, "cases": len(load_cases()), "training_eligible": False}))
        return 0
    summary = run(limit=args.limit, url=args.url, timeout=args.timeout)
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("error") is None else 2


if __name__ == "__main__":
    raise SystemExit(main())
