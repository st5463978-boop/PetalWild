"""Confidence bins for chip-scored rows only."""

from __future__ import annotations

BINS = ((0.0, 0.50), (0.50, 0.70), (0.70, 0.90), (0.90, 0.95), (0.95, 0.98), (0.98, 1.01))


def calibrate(rows: list[dict]) -> list[dict]:
    chip = [
        row
        for row in rows
        if row.get("jev_source") == "chip" and isinstance(row.get("jev_confidence"), (int, float)) and row.get("jev_wrong") is not None
    ]
    report = []
    for low, high in BINS:
        group = [row for row in chip if low <= float(row["jev_confidence"]) < high]
        correct = sum(1 for row in group if row.get("jev_wrong") is False)
        report.append(
            {
                "low": low,
                "high": high,
                "n": len(group),
                "accuracy": correct / len(group) if group else None,
            }
        )
    return report
