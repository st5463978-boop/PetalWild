"""Compact status from the corpus. Teacher latency is not HEF latency."""

from __future__ import annotations

from jevh_teacher_swarm.analysis.calibration import calibrate
from jevh_teacher_swarm.analysis.failure_clusters import clusters
from jevh_teacher_swarm.analysis.family_stats import family_stats
from jevh_teacher_swarm.io_util import read_jsonl
from jevh_teacher_swarm.prepare import tree as default_tree


def _pct(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * p
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    frac = rank - low
    return ordered[low] * (1 - frac) + ordered[high] * frac


def _fmt(value, digits=3) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def build_status(cfg: dict, root=None, prior_ledger: list[dict] | None = None) -> dict:
    paths = default_tree(root)
    generated = read_jsonl(paths["batch"])
    seen_ids = {row.get("id") for row in generated}
    for row in read_jsonl(paths["batch"].with_name("wall.jsonl")):
        if row.get("id") not in seen_ids:
            generated.append(row)
            seen_ids.add(row.get("id"))
    pending = read_jsonl(paths["pending"])
    attempts = [row for row in read_jsonl(paths["attempts"]) if row.get("origin") != "jevh_clean_core"]
    accepted = [row for row in read_jsonl(paths["accepted_failures"]) if row.get("counted_unique")]
    rejected = read_jsonl(paths["rejected"])
    quarantine = read_jsonl(paths["quarantine"])
    correct = read_jsonl(paths["accepted_correct"])
    chip_rows = [row for row in attempts if row.get("chip_backed") and row.get("jev_wrong") is not None]
    chip_correct = [row for row in chip_rows if row.get("jev_wrong") is False]
    wrong_90 = [row for row in chip_rows if row.get("jev_wrong") and row.get("confident")]
    wrong_95 = [row for row in chip_rows if row.get("jev_wrong") and row.get("confident_095")]
    wrong_98 = [row for row in chip_rows if row.get("jev_wrong") and row.get("confident_098")]
    prior = prior_ledger or []
    prior_chip = [row for row in prior if row.get("jev_source") == "chip" and isinstance(row.get("latency_ms"), (int, float))]
    this_npu = [float(row["chip_npu_ms"]) for row in chip_rows if isinstance(row.get("chip_npu_ms"), (int, float))]
    this_latency = [float(row["latency_ms"]) for row in chip_rows if isinstance(row.get("latency_ms"), (int, float))]
    prior_latency = [float(row["latency_ms"]) for row in prior_chip]
    prior_npu = [float(row["chip_npu_ms"]) for row in prior_chip if isinstance(row.get("chip_npu_ms"), (int, float))]
    prior_fast = [value for value in prior_latency if value < 200]
    prior_slow = [value for value in prior_latency if value >= 200]
    agree = [row for row in generated if row.get("teacher_verifier_agree")]
    dup_rejects = [
        row
        for row in rejected
        if row.get("origin") != "jevh_clean_core" and row.get("skip") in {"near_duplicate", "duplicate"}
    ]
    target = int(cfg["target_unique_failures"])
    unique = len(accepted)
    sent = sum(1 for row in attempts if row.get("skip") != "transport_error")
    accuracy = len(chip_correct) / len(chip_rows) if chip_rows else None
    chip_seconds = sum(this_latency) / 1000.0
    rate = len(chip_rows) / chip_seconds if chip_seconds else None
    forced = [row for row in attempts if row.get("skip") == "no_forced_jev"]
    chip_answers = len(chip_rows)
    no_chip = len(forced)
    return {
        "generated": len(generated),
        "sent": sent,
        "queue_depth": len(pending),
        "accuracy": accuracy,
        "chip_scored": len(chip_rows),
        "wrong_90": len(wrong_90),
        "wrong_95": len(wrong_95),
        "wrong_98": len(wrong_98),
        "unique": unique,
        "target": target,
        "remaining": max(0, target - unique),
        "teacher_agreement": len(agree) / len(generated) if generated else None,
        "quarantine": len(quarantine),
        "duplicate_rejection_rate": len(dup_rejects) / len(generated) if generated else None,
        "p50": _pct(this_npu or this_latency, 0.50),
        "p95": _pct(this_npu or this_latency, 0.95),
        "decisions_per_second": rate,
        "latency_source": "this_run_chip" if this_npu or this_latency else "no_chip_latency_this_run",
        "prior_p50": _pct(prior_npu, 0.50),
        "prior_p95": _pct(prior_npu, 0.95),
        "prior_n": len(prior_chip),
        "prior_fast_n": len(prior_fast),
        "prior_fast_p50": _pct(prior_fast, 0.50),
        "prior_slow_n": len(prior_slow),
        "prior_slow_p50": _pct(prior_slow, 0.50),
        "clusters": clusters(accepted),
        "families": family_stats(chip_rows + [row for row in accepted if row.get("origin") == "jevh_clean_core"]),
        "calibration": calibrate(chip_rows),
        "correct": len(correct),
        "chip_answers": chip_answers,
        "no_chip": no_chip,
        "wire_models": sorted({str(row.get("model")) for row in attempts if row.get("model")}),
        "wire_devices": sorted({str(row.get("device")) for row in attempts if row.get("device")}),
        "wire_decided_by": sorted({str(row.get("decided_by")) for row in attempts if row.get("decided_by")}),
        "cpu_teacher_matched_verifier": sum(1 for row in forced if row.get("teacher_choice_on_wire") == row.get("gold")),
        "cpu_teacher_differed": sum(1 for row in forced if row.get("teacher_choice_on_wire") != row.get("gold")),
    }


def render_status(stats: dict, note: str) -> str:
    lines = [
        "TOTAL GENERATED: %s" % stats["generated"],
        "TOTAL SENT TO JEV: %s" % stats["sent"],
        "QUEUE DEPTH: %s" % stats["queue_depth"],
        "",
        "JEV ACCURACY: %s" % (_fmt(stats["accuracy"]) if stats["chip_scored"] else "n/a"),
        "JEV >= .90 CONFIDENT WRONG: %s" % stats["wrong_90"],
        "JEV >= .95 CONFIDENT WRONG: %s" % stats["wrong_95"],
        "JEV >= .98 CONFIDENT WRONG: %s" % stats["wrong_98"],
        "",
        "ACCEPTED UNIQUE FAILURES: %s" % stats["unique"],
        "TARGET = %s" % stats["target"],
        "TARGET REMAINING: %s" % stats["remaining"],
        "",
        "TEACHER AGREEMENT RATE: %s" % _fmt(stats["teacher_agreement"]),
        "QUARANTINE COUNT: %s" % stats["quarantine"],
        "DUPLICATE REJECTION RATE: %s" % _fmt(stats["duplicate_rejection_rate"]),
        "",
        "P50 LATENCY: %s" % _fmt(stats["p50"], 1),
        "P95 LATENCY: %s" % _fmt(stats["p95"], 1),
        "DECISIONS / SECOND: %s" % _fmt(stats["decisions_per_second"], 2),
        "",
        "CHIP ANSWERS THIS RUN: %s" % stats["chip_answers"],
        "NO FORCED JEV THIS RUN: %s" % stats["no_chip"],
        "WIRE DECIDED_BY: %s" % (", ".join(stats["wire_decided_by"]) or "n/a"),
        "WIRE MODEL: %s" % (", ".join(stats["wire_models"]) or "n/a"),
        "WIRE DEVICE: %s" % (", ".join(stats["wire_devices"]) or "n/a"),
        "CPU TEACHER MATCHED VERIFIER (not counted): %s" % stats["cpu_teacher_matched_verifier"],
        "CPU TEACHER DIFFERED (not counted): %s" % stats["cpu_teacher_differed"],
        "LATENCY SOURCE: %s" % stats["latency_source"],
        "PRIOR CHIP ROWS: %s" % stats["prior_n"],
        "PRIOR NPU P50 MS: %s" % _fmt(stats["prior_p50"], 1),
        "PRIOR NPU P95 MS: %s" % _fmt(stats["prior_p95"], 1),
        "PRIOR SERVER LATENCY <200ms: %s p50=%s" % (stats["prior_fast_n"], _fmt(stats["prior_fast_p50"], 1)),
        "PRIOR SERVER LATENCY >=200ms: %s p50=%s" % (stats["prior_slow_n"], _fmt(stats["prior_slow_p50"], 1)),
        "",
        "TOP FAILURE MECHANISMS:",
    ]
    clusters = stats["clusters"][:10] or []
    if not clusters:
        lines.append("- none")
    for item in clusters:
        lines.append(
            "- %s n=%s max_conf=%s ids=%s"
            % (item["mechanism_id"], item["n"], _fmt(item["max_confidence"], 3), ",".join(item["ids"][:6]))
        )
    lines.extend(["", note.strip(), ""])
    return "\n".join(lines)


def render_agreement(generated: list[dict], quarantined_prep: int) -> str:
    agreed = sum(1 for row in generated if row.get("teacher_verifier_agree"))
    return "\n".join(
        [
            "# Teacher agreement",
            "",
            "Teacher claim versus deterministic interpreter. JEV is not a voter.",
            "Agreed: %s / %s" % (agreed, len(generated)),
            "Held out of the queue at prepare time: %s" % quarantined_prep,
            "A single teacher label is not gold. Disagreement is quarantine, not a vote.",
            "",
        ]
    )


def render_families(stats: dict) -> str:
    lines = ["# Failure families", "", "Chip-scored rows only. CPU-teacher answers are omitted.", ""]
    families = stats["families"]
    if not families:
        lines.append("No chip-scored family rows in this run.")
    for name, row in sorted(families.items(), key=lambda item: -(item[1]["confident_wrong_count"] or 0)):
        lines.append(
            "- %s attempts=%s accuracy=%s confident_wrong=%s avg_conf=%s"
            % (
                name,
                row["attempts"],
                _fmt(row["accuracy"]),
                row["confident_wrong_count"],
                _fmt(row["average_confidence"]),
            )
        )
    lines.append("")
    lines.append("Calibration bins (chip confidence):")
    for band in stats["calibration"]:
        lines.append("- [%s, %s) n=%s accuracy=%s" % (band["low"], band["high"], band["n"], _fmt(band["accuracy"])))
    lines.append("")
    return "\n".join(lines)


def write_reports(cfg: dict, root=None, prior_ledger: list[dict] | None = None, note: str = "", prep_quarantine: int = 0) -> dict:
    paths = default_tree(root)
    stats = build_status(cfg, root, prior_ledger)
    paths["status"].parent.mkdir(parents=True, exist_ok=True)
    paths["status"].write_text(render_status(stats, note), encoding="utf-8")
    generated = read_jsonl(paths["batch"])
    paths["agreement"].write_text(render_agreement(generated, prep_quarantine), encoding="utf-8")
    paths["families"].write_text(render_families(stats), encoding="utf-8")
    return stats
