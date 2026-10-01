"""Per-family attempt stats from scored chip rows."""

from __future__ import annotations

from collections import defaultdict


def family_stats(rows: list[dict]) -> dict[str, dict]:
    buckets: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        if row.get("jev_source") != "chip":
            continue
        family = row.get("attack_family") or row.get("family") or "unknown"
        buckets[family].append(row)
    out = {}
    for family, items in buckets.items():
        scored = [item for item in items if item.get("skip") in (None, "scored")]
        wrong = [item for item in scored if item.get("jev_wrong") is True]
        confident_wrong = [item for item in wrong if item.get("counted_failure") or item.get("confident")]
        confs = [item["jev_confidence"] for item in scored if isinstance(item.get("jev_confidence"), (int, float))]
        disagreements = [item for item in items if item.get("teacher_verifier_agree") is False]
        out[family] = {
            "attempts": len(items),
            "valid_labels": len(scored),
            "accuracy": (len(scored) - len(wrong)) / len(scored) if scored else None,
            "confident_wrong_count": sum(1 for item in scored if item.get("jev_wrong") and item.get("confident")),
            "confident_wrong_rate": (
                sum(1 for item in scored if item.get("jev_wrong") and item.get("confident")) / len(scored)
                if scored
                else None
            ),
            "average_confidence": sum(confs) / len(confs) if confs else None,
            "teacher_disagreement_rate": len(disagreements) / len(items) if items else None,
            "suppressed_near_duplicates": sum(1 for item in confident_wrong if item.get("counted_unique") is False),
        }
    return out
