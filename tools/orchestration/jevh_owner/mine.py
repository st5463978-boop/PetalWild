"""Mine confident-wrong ownership decisions from the JEV-H chip.

The grader is this process. It does not call the Pi CPU teacher.
It does not train. Stop at 20 counted failures or when the bank is done.
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

from jevh_owner.cases import assert_bank_ok, load_cases  # noqa: E402
from jevh_owner.client import (  # noqa: E402
    chip_probe_ok,
    get_health,
    post_decide,
    resolve_decide_url,
)
from jevh_owner.score import clear_position_bias, fingerprint, score_attempt  # noqa: E402

OUT = HERE / "out"
STOP_COUNTED = 20


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def summarise(rows: list[dict], *, asked: int, bank: int, error: str | None, chip_wait: dict | None) -> dict:
    counted_rows = [row for row in rows if row.get("counted_failure")]
    contrasts = Counter(row.get("contrast") or "" for row in counted_rows)
    skips = Counter(row.get("skip") or "scored" for row in rows)
    return {
        "ts": _now(),
        "lane": "jev-cursor-owner",
        "family": "ownership",
        "kind": "adversarial",
        "rule": "The named worker owns the task, not a bystander.",
        "training_eligible": False,
        "teacher": "cursor-grok",
        "pi_cpu_teacher_called": False,
        "decide_url_origin_hidden": True,
        "bank": bank,
        "asked": asked,
        "cases_scored": len(rows),
        "counted_failures": len(counted_rows),
        "stop_at": STOP_COUNTED,
        "stopped_early": len(counted_rows) >= STOP_COUNTED,
        "family_exhausted": len(counted_rows) < STOP_COUNTED and asked >= bank and error is None,
        "confident_correct": sum(
            1
            for row in rows
            if row.get("confident") and not row.get("jev_wrong") and not row.get("skip")
        ),
        "jev_wrong": sum(1 for row in rows if row.get("jev_wrong")),
        "production_escalated": sum(1 for row in rows if row.get("production_escalated")),
        "index_bugs": sum(
            1
            for row in rows
            if row.get("skip")
            in {"index_choice_mismatch", "unmapped_choice", "position_index_bias"}
        ),
        "no_forced_jev": sum(1 for row in rows if row.get("skip") == "no_forced_jev"),
        "failures_by_contrast": dict(contrasts),
        "counted_ids": [row["id"] for row in counted_rows],
        "skips": dict(skips),
        "chip_wait": chip_wait,
        "error": error,
        "note": "Diagnostic gold only. Do not train on this ledger. Count only a wrong chip at confidence >= 0.90.",
    }


def _ask(url: str, case: dict, timeout: float, seen: set[str]) -> dict:
    started = time.perf_counter()
    try:
        payload = post_decide(
            url,
            case["question"],
            case["options"],
            context=case["context"],
            timeout=timeout,
        )
        row = score_attempt(case, payload, seen)
        row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
        return row
    except Exception as exc:  # noqa: BLE001 — recorded, not scored as a chip failure
        return {
            "id": case["id"],
            "kind": case["kind"],
            "family": case["family"],
            "contrast": case.get("contrast"),
            "fingerprint": fingerprint(case),
            "answer": case["answer"],
            "training_eligible": False,
            "bucket": "QUARANTINE",
            "counted_failure": False,
            "skip": "transport_error",
            "error": f"{type(exc).__name__}: {exc}",
            "client_ms": round(1000.0 * (time.perf_counter() - started), 1),
        }


def wait_for_chip(url: str, attempts: int, pause: float) -> tuple[dict | None, dict]:
    """Poll published health. Do not POST while the chip probe is failing."""
    last = None
    info = {"attempts": 0, "chip_probe_ok": False, "chip_cond": None}
    for attempt in range(1, attempts + 1):
        info["attempts"] = attempt
        try:
            last = get_health(url)
        except Exception as exc:  # noqa: BLE001
            info["health_error"] = f"{type(exc).__name__}: {exc}"
            time.sleep(pause)
            continue
        detail = last.get("detail") if isinstance(last.get("detail"), dict) else {}
        info["chip_cond"] = detail.get("chip_cond")
        info["chip_held"] = detail.get("chip_held")
        probe = detail.get("last_probe") if isinstance(detail.get("last_probe"), dict) else {}
        info["last_probe_ok"] = probe.get("ok")
        info["last_probe_error"] = probe.get("error")
        if chip_probe_ok(last):
            info["chip_probe_ok"] = True
            return last, info
        if attempt < attempts:
            time.sleep(pause)
    return last, info


def run(
    *,
    timeout: float = 75.0,
    stop_counted: int = STOP_COUNTED,
    wait_attempts: int = 16,
    wait_pause: float = 20.0,
) -> dict:
    assert_bank_ok()
    cases = load_cases()
    url = resolve_decide_url()
    _health, chip_wait = wait_for_chip(url, wait_attempts, wait_pause)
    OUT.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    seen: set[str] = set()
    error = None
    asked = 0
    if not chip_wait.get("chip_probe_ok"):
        error = "chip_probe_failed"
    else:
        try:
            for case in cases:
                row = _ask(url, case, timeout, seen)
                seen.add(row["fingerprint"])
                rows.append(row)
                asked += 1
                clear_position_bias(rows)
                if row.get("skip") == "no_forced_jev":
                    error = "decide_returned_no_chip"
                    break
                counted = sum(1 for item in rows if item.get("counted_failure"))
                if counted >= stop_counted and str(case["id"]).endswith("-flip"):
                    break
        except Exception as exc:  # noqa: BLE001
            error = f"{type(exc).__name__}: {exc}"
    clear_position_bias(rows)
    failures = [row for row in rows if row.get("counted_failure")]
    summary = summarise(
        rows,
        asked=asked,
        bank=len(cases),
        error=error,
        chip_wait=chip_wait,
    )
    _write_jsonl(OUT / "ledger.jsonl", rows)
    _write_jsonl(OUT / "failures.jsonl", failures)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mine confident-wrong JEV-H ownership decisions.")
    parser.add_argument("--timeout", type=float, default=75.0)
    parser.add_argument("--stop-counted", type=int, default=STOP_COUNTED)
    parser.add_argument("--wait-attempts", type=int, default=16)
    parser.add_argument("--wait-pause", type=float, default=20.0)
    parser.add_argument("--check", action="store_true", help="Validate the ownership bank and exit")
    args = parser.parse_args(argv)
    if args.check:
        assert_bank_ok()
        print(
            json.dumps(
                {
                    "ok": True,
                    "family": "ownership",
                    "cases": len(load_cases()),
                    "training_eligible": False,
                }
            )
        )
        return 0
    summary = run(
        timeout=args.timeout,
        stop_counted=args.stop_counted,
        wait_attempts=args.wait_attempts,
        wait_pause=args.wait_pause,
    )
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("error") in {None, "chip_probe_failed", "decide_returned_no_chip"} else 2


if __name__ == "__main__":
    raise SystemExit(main())
