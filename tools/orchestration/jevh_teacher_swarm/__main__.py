"""python -m jevh_teacher_swarm {generate,run,status,check}"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ORCH = Path(__file__).resolve().parents[1]
if str(ORCH) not in sys.path:
    sys.path.insert(0, str(ORCH))

from jevh_teacher_swarm.config import load_config  # noqa: E402
from jevh_teacher_swarm.historical import collapse_historical  # noqa: E402
from jevh_teacher_swarm.io_util import read_jsonl, write_jsonl  # noqa: E402
from jevh_teacher_swarm.prepare import prepare_batch, tree  # noqa: E402
from jevh_teacher_swarm.report import write_reports  # noqa: E402
from jevh_teacher_swarm.runners.batch_runner import drain  # noqa: E402
from jevh_teacher_swarm.teachers.batch import authored_cases  # noqa: E402

CLEAN_LEDGER = ORCH / "jevh_clean_core" / "out" / "ledger.jsonl"
CLEAN_FAILURES = ORCH / "jevh_clean_core" / "out" / "failures.jsonl"


def _note(health: dict | None, sent: int) -> str:
    if health is None and sent == 0:
        return (
            "Queue is prepared. No decide call has been made in this run yet. "
            "Unique failures below are the clean-core chip ledger collapsed by mechanism, not new answers. "
            "Pending depth is the verified batch only. The high watermark blocks extra filler; "
            "the queue is not padded to the 2500 target with unverified rows."
        )
    cond = (health or {}).get("chip_cond")
    sha = (health or {}).get("hef_sha_prefix")
    return (
        "Live decide health model=%s device=%s hef_sha_prefix=%s chip_cond=%s. "
        "Sent %s decide calls. A row counts only when the ettin68m chip answer is wrong at confidence >= 0.90 "
        "and the mechanism is new. CPU teacher fallbacks are quarantine, not JEV."
        % ((health or {}).get("model"), (health or {}).get("device"), sha, cond, sent)
    )


def generate(cfg: dict, root: Path | None = None, failures: list[dict] | None = None, ledger: list[dict] | None = None) -> dict:
    paths = tree(root)
    if len(read_jsonl(paths["pending"])) >= int(cfg["high_watermark"]):
        return {"added": 0, "reason": "high_watermark"}
    ready, quarantined = prepare_batch(authored_cases())
    write_jsonl(paths["batch"], ready)
    attempted = {row.get("id") for row in read_jsonl(paths["attempts"])}
    pending = [row for row in ready if row["id"] not in attempted]
    write_jsonl(paths["pending"], pending)
    if not paths["inflight"].is_file():
        write_jsonl(paths["inflight"], [])
    source_failures = failures if failures is not None else read_jsonl(CLEAN_FAILURES)
    unique, dupes = collapse_historical(source_failures, cfg["confident_wrong_min"])
    swarm_unique = [
        row
        for row in read_jsonl(paths["attempts"])
        if row.get("counted_unique") and row.get("bucket") == "ACCEPTED_FAILURE"
    ]
    write_jsonl(paths["accepted_failures"], unique + swarm_unique)
    other_rejected = [row for row in read_jsonl(paths["rejected"]) if row.get("origin") != "jevh_clean_core"]
    write_jsonl(paths["rejected"], dupes + other_rejected)
    prior_q = [row for row in read_jsonl(paths["quarantine"]) if row.get("phase") != "prepare"]
    for row in quarantined:
        row["phase"] = "prepare"
        row["training_eligible"] = False
    write_jsonl(paths["quarantine"], prior_q + quarantined)
    if not paths["accepted_correct"].is_file():
        write_jsonl(paths["accepted_correct"], [])
    stats = write_reports(
        cfg,
        root=root,
        prior_ledger=ledger if ledger is not None else read_jsonl(CLEAN_LEDGER),
        note=_note(None, 0),
        prep_quarantine=len(quarantined),
    )
    return {
        "ready": len(ready),
        "pending": len(pending),
        "prepare_quarantine": len(quarantined),
        "historical_unique": len(unique),
        "historical_near_duplicates": len(dupes),
        "below_target_queue": len(pending) < int(cfg["target_queue"]),
        "teacher_agreement": stats["teacher_agreement"],
    }


def run(cfg: dict, limit: int | None) -> dict:
    from jevh_teacher_swarm.runners.jev_client import decide, fetch_health

    health = fetch_health()
    if health.get("hef_sha_prefix") and not str(health["hef_sha_prefix"]).startswith(str(cfg["expected_hef_sha_prefix"])[:8]):
        health["sha_mismatch"] = True
    summary = drain(cfg, decide, health=health, limit=limit)
    write_reports(
        cfg,
        prior_ledger=read_jsonl(CLEAN_LEDGER),
        note=_note(health, summary["sent"]),
        prep_quarantine=0,
    )
    summary["health"] = health
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="JEV-H frontier teacher swarm")
    parser.add_argument("command", choices=("generate", "run", "status", "check"))
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args(argv)
    cfg = load_config()
    if args.command == "check":
        ready, quarantined = prepare_batch(authored_cases())
        print(json.dumps({"ready": len(ready), "quarantine": len(quarantined), "training_eligible": False}))
        return 0 if not quarantined else 2
    if args.command == "generate":
        print(json.dumps(generate(cfg), indent=2))
        return 0
    if args.command == "status":
        stats = write_reports(cfg, prior_ledger=read_jsonl(CLEAN_LEDGER), note=_note(None, len(read_jsonl(tree()["attempts"]))))
        print(tree()["status"].read_text(encoding="utf-8"))
        return 0 if stats else 0
    summary = run(cfg, args.limit)
    print(json.dumps({key: value for key, value in summary.items() if key != "health"}, indent=2))
    print(json.dumps(summary.get("health"), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
