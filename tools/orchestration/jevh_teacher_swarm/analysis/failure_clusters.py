"""One cluster per counted mechanism."""

from __future__ import annotations

from collections import defaultdict


def clusters(rows: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        if not (row.get("counted_unique") or row.get("counted_failure")):
            continue
        if row.get("jev_source") not in (None, "chip") and row.get("counted_unique") is not True:
            continue
        if row.get("counted_unique") is False:
            continue
        key = row.get("mechanism_id") or row.get("family") or row.get("id")
        grouped[str(key)].append(row)
    out = []
    for key, items in grouped.items():
        confs = [item.get("jev_confidence") for item in items if isinstance(item.get("jev_confidence"), (int, float))]
        out.append(
            {
                "mechanism_id": key,
                "n": len(items),
                "ids": [item.get("id") for item in items],
                "max_confidence": max(confs) if confs else None,
                "attack_family": items[0].get("attack_family") or items[0].get("family"),
            }
        )
    out.sort(key=lambda item: (-item["n"], item["mechanism_id"]))
    return out
