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
from jevh_teacher_swarm.teachers.root300 import root300_cases  # noqa: E402
from jevh_teacher_swarm.teachers.wall import wall_cases  # noqa: E402

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
    timeout = float(cfg["decide_timeout_s"])

    def post(case):
        return decide(case, timeout)

    already = len(read_jsonl(tree()["attempts"]))
    summary = drain(cfg, post, health=health, limit=limit)
    try:
        health = fetch_health()
    except Exception as exc:  # noqa: BLE001 — the drain result still stands
        health["after_error"] = f"{type(exc).__name__}: {exc}"
    sent = sum(1 for row in read_jsonl(tree()["attempts"]) if row.get("skip") != "transport_error")
    note = _note(health, sent)
    if already:
        note += " Resume: earlier calls in this batch either stayed on the CPU teacher or hit a dead tunnel."
    write_reports(
        cfg,
        prior_ledger=read_jsonl(CLEAN_LEDGER),
        note=note,
        prep_quarantine=0,
    )
    summary["health"] = health
    summary["sent_total"] = sent
    return summary


def _student_stopped(row: dict, payload: dict) -> bool:
    """The live student is decided_by chip with a chip object. Anything else ends the wall."""
    chip = payload.get("chip")
    return payload.get("decided_by") != "chip" or not isinstance(chip, dict)


def mine(cfg: dict, limit: int | None) -> dict:
    from jevh_teacher_swarm.analysis.dedupe import near_duplicate
    import threading

    from jevh_teacher_swarm.runners.batch_runner import drain_paced
    from jevh_teacher_swarm.runners.jev_client import DecideSession, fetch_health, resolve_decide_url

    health = fetch_health()
    if health.get("chip_cond") != "ok" or health.get("chip_held") is not True:
        print(json.dumps({"blocked": health.get("chip_cond"), "chip_held": health.get("chip_held"), "sent": 0}))
        return {"blocked": health.get("chip_cond"), "chip_held": health.get("chip_held"), "sent": 0, "health": health}
    ready, quarantined = prepare_batch(wall_cases())
    if quarantined:
        raise RuntimeError("wall failed verification: " + json.dumps(quarantined[:5]))
    paths = tree()
    attempted = {row.get("id") for row in read_jsonl(paths["attempts"])}
    known = read_jsonl(paths["accepted_failures"])
    mechanisms = {row.get("mechanism_id") for row in known if row.get("counted_unique")}
    known_q = [(row.get("question") or "", row.get("gold") or row.get("answer") or "") for row in known if row.get("counted_unique")]
    fresh = []
    for case in ready:
        if case["id"] in attempted or case["mechanism_id"] in mechanisms:
            continue
        if any(near_duplicate(case["question"], question, cfg["near_duplicate_ratio"], case["verifier_answer"], answer) for question, answer in known_q):
            continue
        fresh.append(case)
    if limit is not None:
        fresh = fresh[: max(0, limit)]
    write_jsonl(paths["pending"], fresh)
    write_jsonl(paths["batch"].with_name("wall.jsonl"), ready)
    url = resolve_decide_url()
    sessions = [DecideSession(url, 8.0) for _ in range(8)]
    free = list(sessions)
    slot = threading.Lock()

    def post(case):
        with slot:
            session = free.pop()
        try:
            return session.decide(case)
        finally:
            with slot:
                free.append(session)

    try:
        summary = drain_paced(cfg, post, fresh, health_check=fetch_health, pace_s=0.0415, max_in_flight=8)
    finally:
        for session in sessions:
            session.close()
    attempted_now = {row.get("id") for row in read_jsonl(paths["attempts"])}
    write_jsonl(paths["pending"], [row for row in fresh if row.get("id") not in attempted_now])
    write_jsonl(paths["inflight"], [])
    try:
        health = fetch_health()
    except Exception as exc:  # noqa: BLE001
        health["after_error"] = f"{type(exc).__name__}: {exc}"
    summary["health"] = health
    summary["wall"] = len(fresh)
    write_reports(
        cfg,
        prior_ledger=read_jsonl(CLEAN_LEDGER),
        note=_note(health, summary.get("sent") or 0) + " Wall mined against the live student.",
        prep_quarantine=0,
    )
    return summary


def fresh_counted(rows: list[dict], cap: int = 15) -> dict:
    from jevh_teacher_swarm.analysis.dedupe import near_duplicate

    counted = []
    per_root: dict[str, int] = {}
    seen_mech: set[str] = set()
    questions: list[tuple[str, str]] = []
    for row in rows:
        if row.get("jev_source") != "chip" or row.get("jev_wrong") is not True:
            continue
        confidence = row.get("jev_confidence")
        if not isinstance(confidence, (int, float)) or confidence < 0.90:
            continue
        if row.get("skip") not in (None, "near_duplicate"):
            continue
        root = str(row.get("root_family") or row.get("attack_family") or "unclassified")
        if root == "numeric_not_computable_overprediction":
            continue
        if per_root.get(root, 0) >= cap:
            continue
        mech = str(row.get("mechanism_id") or "")
        if mech in seen_mech:
            continue
        gold = str(row.get("gold") or "")
        question = str(row.get("question") or "")
        if any(near_duplicate(question, prev_q, 0.90, gold, prev_a) for prev_q, prev_a in questions):
            continue
        per_root[root] = per_root.get(root, 0) + 1
        seen_mech.add(mech)
        questions.append((question, gold))
        counted.append(row)
    return {"counted": counted, "per_root": per_root, "families": len(per_root)}


def serve_root300(cfg: dict) -> dict:
    import threading
    from pathlib import Path

    from jevh_teacher_swarm.runners.batch_runner import drain_paced
    from jevh_teacher_swarm.runners.jev_client import DecideSession, fetch_health, resolve_decide_url

    health = fetch_health()
    if health.get("chip_cond") != "ok" or health.get("chip_held") is not True:
        print(json.dumps({"blocked": health.get("chip_cond"), "chip_held": health.get("chip_held"), "sent": 0}))
        return {"blocked": health.get("chip_cond"), "sent": 0, "health": health}
    ready, quarantined = prepare_batch(root300_cases())
    run_root = Path(__file__).resolve().parent / "root300_run"
    paths = tree(run_root)
    attempted = {row.get("id") for row in read_jsonl(paths["attempts"])}
    fresh = [case for case in ready if case["id"] not in attempted]
    write_jsonl(paths["pending"], fresh)
    url = resolve_decide_url()
    sessions = [DecideSession(url, 8.0) for _ in range(8)]
    free = list(sessions)
    slot = threading.Lock()

    def post(case):
        with slot:
            session = free.pop()
        try:
            return session.decide(case)
        finally:
            with slot:
                free.append(session)

    try:
        summary = drain_paced(cfg, post, fresh, health_check=fetch_health, pace_s=0.0415, max_in_flight=8, root=run_root)
    finally:
        for session in sessions:
            session.close()
    rows = read_jsonl(paths["attempts"])
    tally = fresh_counted(rows)
    summary["fresh_counted_300"] = len(tally["counted"])
    summary["root_families"] = tally["families"]
    summary["per_root"] = tally["per_root"]
    summary["health"] = fetch_health()
    (run_root / "reports").mkdir(parents=True, exist_ok=True)
    lines = [
        f"FRESH COUNTED >=0.90: {len(tally['counted'])} / 300",
        f"ROOT FAMILIES REPRESENTED: {tally['families']}",
        "SATURATED FAMILIES: " + ", ".join(name for name, n in tally["per_root"].items() if n >= 15) or "none",
        f"READY QUEUE: {summary.get('queue_depth')}",
        "",
    ]
    for name, n in sorted(tally["per_root"].items(), key=lambda item: -item[1]):
        lines.append(f"- {name}: {n}")
    (run_root / "reports" / "current_status.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="JEV-H frontier teacher swarm")
    parser.add_argument("command", choices=("generate", "run", "status", "check", "mine", "root300"))
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
    if args.command == "root300":
        summary = serve_root300(cfg)
        printable = {key: value for key, value in summary.items() if key != "health"}
        print(json.dumps(printable, indent=2, default=str))
        print(json.dumps(summary.get("health"), indent=2))
        return 0
    if args.command == "mine":
        summary = mine(cfg, args.limit)
        print(json.dumps({key: value for key, value in summary.items() if key != "health"}, indent=2))
        print(json.dumps(summary.get("health"), indent=2))
        return 0
    summary = run(cfg, args.limit)
    print(json.dumps({key: value for key, value in summary.items() if key != "health"}, indent=2))
    print(json.dumps(summary.get("health"), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
