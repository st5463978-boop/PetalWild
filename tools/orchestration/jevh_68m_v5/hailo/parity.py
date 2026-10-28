"""Compare decision indexes. A missing HEF run is not treated as agreement."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from hailo.contract import AGREEMENT_FLOOR, accept_agreement, confident_wrong, decision_agreement, expected_calibration_error
from hailo.runtime import probe


def evaluate(cpu_index: list[int] | None, hef_index: list[int] | None, confidence: list[float] | None = None) -> dict:
    state = probe()
    measured = None
    counts = None
    if cpu_index is not None and hef_index is not None:
        measured = decision_agreement(cpu_index, hef_index)
        wrong = None
        if confidence is not None:
            wrong = confident_wrong(confidence, hef_index, cpu_index)
        counts = {
            "n": len(cpu_index),
            "confident_wrong_vs_cpu": wrong,
        }
    gate = accept_agreement(measured)
    return {
        "hardware_tested": bool(measured is not None and state["device"] and not state["import_error"]),
        "device": state,
        "agreement_floor": AGREEMENT_FLOOR,
        "cpu_hef_agreement": measured,
        "gate": gate,
        "counts": counts,
        "note": "Agreement is CPU index versus HEF index on the same rows. It is omitted when either side was not run.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="CPU versus HEF decision agreement")
    parser.add_argument("--cpu-indexes", type=Path)
    parser.add_argument("--hef-indexes", type=Path)
    parser.add_argument("--confidence", type=Path)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args(argv)
    cpu = hef = conf = None
    if args.cpu_indexes and args.hef_indexes and args.cpu_indexes.is_file() and args.hef_indexes.is_file():
        cpu = json.loads(args.cpu_indexes.read_text())
        hef = json.loads(args.hef_indexes.read_text())
        if args.confidence and args.confidence.is_file():
            conf = json.loads(args.confidence.read_text())
    report = evaluate(cpu, hef, conf)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(text)
    sys.stdout.write(text)
    if report["cpu_hef_agreement"] is None:
        return 3
    return 0 if report["gate"]["accepted"] else 5


if __name__ == "__main__":
    raise SystemExit(main())


# Re-export so callers can compute ECE without importing contract directly.
__all__ = ["evaluate", "expected_calibration_error"]
