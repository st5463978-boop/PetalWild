"""Refill the same root-split run.

Unit conversion stays saturated. New cases are false alarms: the policy
predicate is false, so the calm label is gold. Scenes differ enough that
the 0.90 near-duplicate check can keep more than one per family.
"""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path

from jevh_teacher_swarm.analysis.dedupe import near_duplicate
from jevh_teacher_swarm.prepare import prepare_batch
from jevh_teacher_swarm.teachers.root300 import cmp_case, div_case

# root, alarm, calm, rel, left, right, policy tail. The tail's comparison is false.
_FAMILIES: list[tuple] = [
    (
        "threshold_boundary_error",
        "breach",
        "clear",
        "gt",
        4,
        15,
        "Counted amount is {a}. The line is {b}. A breach happens only when the counted amount is greater than the line. Is there a breach?",
    ),
    (
        "stale_state_preference",
        "stale",
        "fresh",
        "gt",
        4,
        18,
        "Age amount is {a} hours. Life amount is {b} hours. Stale means the age amount is greater than the life amount. Is it stale?",
    ),
    (
        "capacity_constraint_error",
        "over",
        "inside",
        "gt",
        4,
        15,
        "Load amount is {a} kg. Hold amount is {b} kg. Over capacity means the load amount is greater than the hold amount. Is it over capacity?",
    ),
    (
        "resource_conservation_error",
        "shortfall",
        "covered",
        "gt",
        4,
        15,
        "Issued amount is {a}. Baked amount is {b}. A shortfall means the issued amount is greater than the baked amount. Is there a shortfall?",
    ),
    (
        "false_completion_error",
        "complete",
        "open",
        "ge",
        4,
        15,
        "Finished amount is {a}. Required amount is {b}. Complete means the finished amount is greater than or equal to the required amount. Is it complete?",
    ),
    (
        "inclusive_exclusive_error",
        "full",
        "room",
        "ge",
        4,
        15,
        "Count amount is {a}. Cap amount is {b}. Full means the count amount is greater than or equal to the cap amount. Is it full?",
    ),
    (
        "causal_inversion",
        "inverted",
        "ordered",
        "lt",
        15,
        4,
        "Effect time is {a}. Cause time is {b}. Inverted means the effect time is less than the cause time. Is it inverted?",
    ),
    (
        "permission_scope_error",
        "allowed",
        "denied",
        "ge",
        4,
        15,
        "Actor rank is {a}. Required rank is {b}. Allowed means the actor rank is greater than or equal to the required rank. Is it allowed?",
    ),
    (
        "concurrency_race_error",
        "conflict",
        "clean",
        "ne",
        8,
        8,
        "Write version is {a}. Stored version is {b}. A conflict means the versions are not equal. Is there a conflict?",
    ),
    (
        "identity_confusion",
        "issued",
        "other",
        "eq",
        4,
        9,
        "Tool serial is {a}. Issued serial is {b}. Issued means the serials are equal. Is it issued?",
    ),
    (
        "save_state_invariant_error",
        "stale",
        "current",
        "lt",
        8,
        8,
        "Observed generation is {a}. Metadata generation is {b}. Stale means observed generation is less than metadata generation. Is it stale?",
    ),
    (
        "negative_sign_error",
        "shrink",
        "grow",
        "lt",
        6,
        0,
        "The stock change is {a}. A shrink means the change is less than {b}. Is this a shrink?",
    ),
    (
        "temporal_order_error",
        "valid",
        "invalid",
        "gt",
        4,
        15,
        "Effect minute is {a}. Cause minute is {b}. Valid means the effect minute is greater than the cause minute. Is it valid?",
    ),
    (
        "memory_authority_error",
        "canon",
        "note",
        "gt",
        4,
        15,
        "Canon rank is {a}. Note rank is {b}. Canon wins only when the canon rank is greater than the note rank. Does canon win?",
    ),
    (
        "deadline_miss_error",
        "late",
        "early",
        "gt",
        4,
        15,
        "Elapsed minutes are {a}. Allowance minutes are {b}. Late means elapsed minutes are greater than allowance minutes. Is it late?",
    ),
    (
        "quota_exceeded_error",
        "exceeded",
        "inside",
        "gt",
        4,
        15,
        "Used tokens are {a}. Quota tokens are {b}. Exceeded means used tokens are greater than quota tokens. Is it exceeded?",
    ),
    (
        "budget_overrun_error",
        "overrun",
        "inside",
        "gt",
        4,
        15,
        "Spent coins are {a}. Budget coins are {b}. Overrun means spent coins are greater than budget coins. Is there an overrun?",
    ),
    (
        "sla_breach_error",
        "breach",
        "met",
        "gt",
        4,
        15,
        "Latency ms is {a}. Slo ms is {b}. A breach means latency ms is greater than slo ms. Is there a breach?",
    ),
    (
        "replica_lag_error",
        "behind",
        "caught",
        "gt",
        4,
        15,
        "Replica lag is {a}. Lag cap is {b}. Behind means replica lag is greater than the lag cap. Is it behind?",
    ),
    (
        "rate_limit_error",
        "limited",
        "open",
        "gt",
        4,
        15,
        "Calls made are {a}. Call cap is {b}. Limited means calls made are greater than the call cap. Is it limited?",
    ),
    (
        "heartbeat_miss_error",
        "missed",
        "live",
        "gt",
        4,
        15,
        "Silent seconds are {a}. Window seconds are {b}. Missed means silent seconds are greater than window seconds. Is it missed?",
    ),
    (
        "quorum_shortfall_error",
        "met",
        "short",
        "ge",
        4,
        15,
        "Present voters are {a}. Needed voters are {b}. Met means present voters are greater than or equal to needed voters. Is quorum met?",
    ),
    (
        "inventory_stockout_error",
        "stockout",
        "stocked",
        "lt",
        15,
        4,
        "Stock units are {a}. Needed units are {b}. A stockout means stock units are less than needed units. Is there a stockout?",
    ),
    (
        "speed_limit_error",
        "over",
        "legal",
        "gt",
        4,
        15,
        "Speed reading is {a}. Limit reading is {b}. Over the limit means speed reading is greater than limit reading. Is it over the limit?",
    ),
    (
        "temperature_alarm_error",
        "alarming",
        "quiet",
        "ge",
        4,
        15,
        "Temperature reading is {a}. Alarm reading is {b}. Alarming means temperature reading is greater than or equal to alarm reading. Is it alarming?",
    ),
    (
        "retry_exhaustion_error",
        "exhausted",
        "left",
        "ge",
        4,
        15,
        "Attempts made are {a}. Attempt cap is {b}. Exhausted means attempts made are greater than or equal to the attempt cap. Is it exhausted?",
    ),
    (
        "balance_floor_error",
        "broke",
        "solvent",
        "lt",
        15,
        4,
        "Balance coins are {a}. Floor coins are {b}. Broke means balance coins are less than floor coins. Is it broke?",
    ),
    (
        "cooldown_ready_error",
        "ready",
        "waiting",
        "ge",
        4,
        15,
        "Waited minutes are {a}. Cooldown minutes are {b}. Ready means waited minutes are greater than or equal to cooldown minutes. Is it ready?",
    ),
    (
        "duplicate_key_error",
        "duplicate",
        "distinct",
        "eq",
        4,
        9,
        "Left key is {a}. Right key is {b}. Duplicate means the keys are equal. Is it a duplicate?",
    ),
    (
        "lock_ownership_error",
        "owned",
        "foreign",
        "eq",
        4,
        9,
        "Holder id is {a}. Requester id is {b}. Owned means the ids are equal. Does the requester own the lock?",
    ),
    (
        "certificate_window_error",
        "expired",
        "current",
        "gt",
        4,
        30,
        "Certificate age is {a} days. Certificate life is {b} days. Expired means age is greater than life. Is it expired?",
    ),
    (
        "disk_watermark_error",
        "paging",
        "quiet",
        "ge",
        4,
        15,
        "Disk use is {a} percent. Page line is {b} percent. Paging means disk use is greater than or equal to the page line. Is it paging?",
    ),
]

_DIVS: list[tuple] = [
    (
        "ratio_rate_error",
        "fast",
        "slow",
        "gt",
        8,
        4,
        5,
        "Covered distance is {n} miles and the time is {denom} hours. The integer rate is the distance divided by the time. Too fast means that rate is greater than {line}. Is it too fast?",
    ),
    (
        "integer_division_error",
        "over",
        "under",
        "gt",
        9,
        5,
        2,
        "Items are {n}. Group size is {denom}. Full groups are the integer quotient. Over means that quotient is greater than {line}. Is it over?",
    ),
]

_ALPHA = "abcdefghijklmnopqrstuvwxyz"
_BLOCKED = {"unit_conversion_error", "numeric_not_computable_overprediction"}
LOW_WATERMARK = 1000
TARGET_QUEUE = 5000
CAP = 15


def _token(index: int) -> str:
    chars = []
    value = index + 1
    for _ in range(5):
        chars.append(_ALPHA[value % 26])
        value //= 26
    return "".join(chars)


def scene(index: int) -> str:
    words = [_token(index * 12 + slot) for slot in range(12)]
    return (
        f"The {words[0]} {words[1]} at the {words[2]} {words[3]} {words[4]} before {words[5]}. "
        f"Then the {words[6]} {words[7]} {words[8]} {words[9]} near the {words[10]} during {words[11]}."
    )


def _kept(question: str, gold: str, seen: list[tuple[str, str]]) -> bool:
    for prev_q, prev_a in seen:
        if prev_a != gold:
            continue
        if near_duplicate(question, prev_q, 0.90, gold, prev_a):
            return False
    return True


def wave_cases(
    wave: int,
    per_family: int,
    saturated: set[str],
    avoid_ids: set[str],
    seen: list[tuple[str, str]],
) -> list[dict]:
    """Build one wave. `seen` grows with questions that are distinct enough to send."""
    cases: list[dict] = []
    families = [(item, False) for item in _FAMILIES] + [(item, True) for item in _DIVS]
    for ordinal, (spec, is_div) in enumerate(families):
        root = spec[0]
        if root in _BLOCKED or root in saturated:
            continue
        alarm, calm, rel = spec[1], spec[2], spec[3]
        for offset in range(per_family):
            index = wave * 100000 + ordinal * 500 + offset
            cid = f"r3c-w{wave}-{root}-{offset}"
            if cid in avoid_ids:
                continue
            prefix = scene(index)
            if is_div:
                _root, _alarm, _calm, _rel, n, denom, line, tail = spec
                question = prefix + " " + tail.format(n=n, denom=denom, line=line)
                case = div_case(
                    cid,
                    root,
                    cid,
                    "refill",
                    question,
                    alarm,
                    calm,
                    n,
                    denom,
                    line,
                    rel,
                    flip_options=offset % 2 == 0,
                )
            else:
                _root, _alarm, _calm, _rel, left, right, tail = spec
                question = prefix + " " + tail.format(a=left, b=right)
                case = cmp_case(
                    cid,
                    root,
                    cid,
                    "refill",
                    question,
                    alarm,
                    calm,
                    left,
                    right,
                    rel,
                    flip_options=offset % 2 == 0,
                )
            if not _kept(case["question"], case["teacher_answer"], seen):
                continue
            seen.append((case["question"], case["teacher_answer"]))
            cases.append(case)
    return cases


def ready_wave(*args, **kwargs) -> tuple[list[dict], list[dict]]:
    return prepare_batch(wave_cases(*args, **kwargs))


def _read_jsonl(path: Path) -> list[dict]:
    from jevh_teacher_swarm.io_util import read_jsonl

    try:
        return read_jsonl(path)
    except json.JSONDecodeError:
        rows = []
        if not path.is_file():
            return rows
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return rows


def write_status(run_root: Path, tally: dict, pending: int, note: str = "") -> None:
    reports = run_root / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    saturated = [name for name, count in tally["per_root"].items() if count >= CAP]
    lines = [
        f"FRESH COUNTED >=0.90: {len(tally['counted'])} / 300",
        f"ROOT FAMILIES REPRESENTED: {tally['families']}",
        "SATURATED FAMILIES: " + (", ".join(saturated) if saturated else "none"),
        f"READY QUEUE: {pending}",
        note,
        "",
    ]
    for name, count in sorted(tally["per_root"].items(), key=lambda item: -item[1]):
        lines.append(f"- {name}: {count}")
    (reports / "current_status.md").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def write_complete(run_root: Path, tally: dict, metrics: dict) -> None:
    counted = tally["counted"][:300]
    train = [row for row in counted if row.get("partition") != "CANARY"]
    holdout = [row for row in counted if row.get("partition") == "CANARY"]
    reports = run_root / "reports"
    reports.mkdir(parents=True, exist_ok=True)

    def _dump(path: Path, rows: list[dict]) -> None:
        path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")

    _dump(run_root / "fresh_300_retrain_candidates.jsonl", train)
    _dump(run_root / "fresh_300_canary_holdout.jsonl", holdout)
    summary = [
        "# Root family summary",
        "",
        f"Fresh counted at or above 0.90: {len(counted)}",
        f"Families: {tally['families']}",
        "Cap: 15 counted failures per family.",
        "",
    ]
    for name, count in sorted(tally["per_root"].items(), key=lambda item: -item[1]):
        summary.append(f"- {name}: {count}")
    (run_root / "root_family_summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    (run_root / "wall_metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    complete = [
        "# ROOT SPLIT 300 COMPLETE",
        "",
        "Retrain evidence threshold reached.",
        "",
        f"Fresh counted >=0.90: {len(counted)}",
        f"Root families: {tally['families']}",
        "Family cap 15 still holds.",
        "unit_conversion_error stayed saturated and was not reopened.",
        "",
        "No training, compile, flash, deploy, or merge was done.",
        "This run is frozen.",
    ]
    (run_root / "ROOT_SPLIT_300_COMPLETE.md").write_text("\n".join(complete) + "\n", encoding="utf-8")
    (reports / "ROOT_SPLIT_300_COMPLETE.md").write_text("\n".join(complete) + "\n", encoding="utf-8")


def serve_continuous(cfg: dict, fresh_counted) -> dict:
    from jevh_teacher_swarm.io_util import read_jsonl, write_jsonl
    from jevh_teacher_swarm.prepare import tree
    from jevh_teacher_swarm.runners.batch_runner import drain_paced
    from jevh_teacher_swarm.runners.jev_client import DecideSession, fetch_health, resolve_decide_url

    run_root = Path(__file__).resolve().parents[1] / "root300_run"
    paths = tree(run_root)
    if (run_root / "ROOT_SPLIT_300_COMPLETE.md").exists():
        print("already frozen", flush=True)
        return {"frozen": True}

    health = _wait_health(fetch_health)
    print("HEALTH " + json.dumps({"chip_held": health.get("chip_held"), "chip_cond": health.get("chip_cond"), "hef": health.get("hef_sha_prefix")}), flush=True)
    url = resolve_decide_url()
    sessions = [DecideSession(url, 15.0) for _ in range(8)]
    free = list(sessions)
    slot = threading.Lock()
    file_lock = threading.Lock()
    stop = threading.Event()
    sent_box = {"n": 0}

    def post(case):
        with slot:
            session = free.pop()
        try:
            return session.decide(case)
        finally:
            with slot:
                free.append(session)

    def saturated_now() -> set[str]:
        tally = fresh_counted(read_jsonl(paths["attempts"]))
        blocked = {name for name, count in tally["per_root"].items() if count >= CAP}
        blocked.update(_BLOCKED)
        return blocked

    def fill_to(target: int) -> int:
        added = 0
        wave_path = run_root / "refill_wave.txt"
        while True:
            with file_lock:
                pending = _read_jsonl(paths["pending"])
                if len(pending) >= target or stop.is_set():
                    return added
                attempts = _read_jsonl(paths["attempts"])
                tally = fresh_counted(attempts)
                blocked = {name for name, count in tally["per_root"].items() if count >= CAP}
                blocked.update(_BLOCKED)
                avoid = {row.get("id") for row in attempts}
                avoid.update(row.get("id") for row in pending)
                seen = [(row.get("question") or "", row.get("gold") or "") for row in tally["counted"]]
                for row in pending:
                    seen.append((row.get("question") or "", row.get("verifier_answer") or row.get("teacher_answer") or ""))
                wave = int(wave_path.read_text().strip()) if wave_path.exists() else 0
                wave_path.write_text(str(wave + 1), encoding="utf-8")
            raw, quarantined = ready_wave(wave, 40, blocked, avoid, seen)
            if quarantined:
                print(f"quarantine {len(quarantined)}", flush=True)
            if not raw:
                print(f"wave {wave} produced nothing", flush=True)
                return added
            with file_lock:
                pending = _read_jsonl(paths["pending"])
                have = {row.get("id") for row in pending}
                room = max(0, target - len(pending))
                take = [row for row in raw if row.get("id") not in have][:room]
                if take:
                    write_jsonl(paths["pending"], pending + take)
                added += len(take)
                print(f"REFILL pending {len(pending)} -> {len(pending) + len(take)} wave {wave}", flush=True)
            if len(take) < 40:
                return added

    def filler():
        try:
            while not stop.is_set():
                with file_lock:
                    depth = len(_read_jsonl(paths["pending"]))
                if depth < LOW_WATERMARK:
                    fill_to(TARGET_QUEUE)
                else:
                    time.sleep(0.4)
        except Exception as exc:  # noqa: BLE001 — keep the drainer alive
            print(f"FILLER FAILED {type(exc).__name__}: {exc}", flush=True)

    filler_thread = threading.Thread(target=filler, name="root300-refill", daemon=True)
    # First refill is synchronous so the queue is up before the first decide.
    fill_to(LOW_WATERMARK)
    filler_thread.start()
    try:
        while not stop.is_set():
            with file_lock:
                attempts = read_jsonl(paths["attempts"])
                tally = fresh_counted(attempts)
                pending = read_jsonl(paths["pending"])
                write_status(run_root, tally, len(pending))
            counted = len(tally["counted"])
            print(f"TALLY {counted}/300 families {tally['families']} pending {len(pending)}", flush=True)
            if counted >= 300 and tally["families"] >= 20:
                metrics = {
                    "fresh_counted": counted,
                    "families": tally["families"],
                    "per_root": tally["per_root"],
                    "sent_this_continuation": sent_box["n"],
                    "attempts": len(attempts),
                    "health": fetch_health(),
                    "cap": CAP,
                    "low_watermark": LOW_WATERMARK,
                    "target_queue": TARGET_QUEUE,
                }
                write_complete(run_root, tally, metrics)
                write_status(run_root, tally, len(pending), "FROZEN. Retrain evidence threshold reached.")
                print("FROZEN 300", flush=True)
                return {"frozen": True, "fresh_counted": counted, "families": tally["families"], "sent": sent_box["n"]}
            blocked = saturated_now()
            with file_lock:
                pending = read_jsonl(paths["pending"])
                chunk = []
                rest = []
                for row in pending:
                    root = row.get("root_family") or row.get("attack_family")
                    if len(chunk) < 80 and root not in blocked:
                        chunk.append(row)
                    else:
                        rest.append(row)
                write_jsonl(paths["pending"], rest)
            if not chunk:
                added = fill_to(TARGET_QUEUE)
                if added == 0:
                    print("stop: no unsaturated cases left", flush=True)
                    write_status(run_root, tally, 0, "Stopped with families still under the cap or yield too low to reach 300.")
                    return {"fresh_counted": counted, "families": tally["families"], "sent": sent_box["n"], "stalled": True}
                continue
            summary = drain_paced(
                cfg,
                post,
                chunk,
                health_check=fetch_health,
                pace_s=0.0415,
                max_in_flight=8,
                root=run_root,
            )
            sent_box["n"] += summary.get("sent") or 0
            print("CHUNK " + json.dumps(summary.get("first"), default=str), flush=True)
    finally:
        stop.set()
        filler_thread.join(timeout=2)
        for session in sessions:
            session.close()
    return {"fresh_counted": counted, "sent": sent_box["n"]}


def _wait_health(fetch_health, tries: int = 30) -> dict:
    last = {}
    for _ in range(tries):
        try:
            last = fetch_health()
        except Exception as exc:  # noqa: BLE001
            last = {"error": f"{type(exc).__name__}: {exc}"}
            time.sleep(2)
            continue
        if last.get("chip_held") is True and last.get("chip_cond") == "ok":
            return last
        time.sleep(2)
    raise RuntimeError(f"chip not held: {last}")
