"""Source-freshness failures for the JEV-H chip.

The teacher is this script: an in-TTL source is not stale. The answer is
fixed from the question before the chip is asked. A row is counted only when
the chip is wrong and its confidence is >= 0.90.

Posts go to the ntfy-discovered decide address already in this repo. Localhost
is not used. The Pi CPU teacher is not a client here: if health says the chip
is down, we wait; a teacher-only payload is not scored.
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from hailo_decide_url import discover_base  # noqa: E402

OUT = HERE / "out"
AGENT = "jev-cursor-fresh"
KIND = "adversarial"
CONFIDENT = 0.90
STOP_AT = 20
MAX_CHIP_WAITS = 16

# Each sentence is a different freshness situation. Digit-normalized duplicates
# are rejected. stale_option is the choice that means "stale".
CASES = [
    {
        "id": "remaining-positive",
        "inside_ttl": True,
        "question": "TTL remaining on the committed manifest is 18 minutes. Is that manifest stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_remaining_min=18 inside_ttl=true",
        "why": "Remaining TTL is positive, so the manifest is inside TTL and not stale.",
    },
    {
        "id": "expires-later-today",
        "inside_ttl": True,
        "question": "The source expires at 16:00. The clock reads 15:22. Is the source stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "expires_at=16:00 now=15:22 inside_ttl=true",
        "why": "Expiry is still ahead of the clock, so the source is inside TTL.",
    },
    {
        "id": "age-under-ttl-named",
        "inside_ttl": True,
        "question": "Age is under the TTL. Inside TTL means not stale. Is the source stale?",
        "options": ["yes", "no"],
        "answer": "no",
        "stale_option": "yes",
        "context": "age_lt_ttl=true rule=in_ttl_is_not_stale",
        "why": "The question states the source is under its TTL, which means not stale.",
    },
    {
        "id": "quote-ttl-open",
        "inside_ttl": True,
        "question": "The quote feed's TTL has not elapsed. Is the quote feed stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_elapsed=false inside_ttl=true",
        "why": "A TTL that has not elapsed means the feed is still inside TTL.",
    },
    {
        "id": "asked-as-fresh",
        "inside_ttl": True,
        "question": "The source is inside its TTL. Is the source fresh?",
        "options": ["yes", "no"],
        "answer": "yes",
        "stale_option": "no",
        "context": "inside_ttl=true rule=in_ttl_is_not_stale",
        "why": "Inside TTL means not stale, so the source is fresh.",
    },
    {
        "id": "window-already-past",
        "inside_ttl": False,
        "question": "The source expiry time is already past. Is the source stale?",
        "options": ["stale", "fresh"],
        "answer": "stale",
        "stale_option": "stale",
        "context": "expiry_in_past=true inside_ttl=false",
        "why": "An expiry already past is outside TTL, so the source is stale.",
    },
    {
        "id": "half-ttl-unused",
        "inside_ttl": True,
        "question": "Half the TTL is still unused. Is the source stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_unused_fraction=0.5 inside_ttl=true",
        "why": "Unused TTL remains, so the source is still inside TTL.",
    },
    {
        "id": "committed-while-fetch-inflight",
        "inside_ttl": True,
        "question": "The committed copy is inside TTL. A newer fetch is in flight and uncommitted. Is the committed source stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "committed_inside_ttl=true in_flight_committed=false",
        "why": "The committed source is inside TTL. An uncommitted fetch does not age it out.",
    },
    {
        "id": "tile-clock-span",
        "inside_ttl": True,
        "question": "The tile was stored at 09:15. The clock is 09:28. TTL is 45 minutes. Is the tile stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "stored=09:15 now=09:28 ttl_min=45 inside_ttl=true",
        "why": "Thirteen minutes of a 45-minute TTL have passed, so the tile is inside TTL.",
    },
    {
        "id": "zero-remaining-counts",
        "inside_ttl": False,
        "question": "TTL remaining is zero. Age at the TTL limit counts as stale. Is the source stale?",
        "options": ["fresh", "stale"],
        "answer": "stale",
        "stale_option": "stale",
        "context": "ttl_remaining=0 policy=age_at_limit_is_stale",
        "why": "The question states that zero remaining TTL counts as stale.",
    },
    {
        "id": "policy-after-elapse",
        "inside_ttl": True,
        "question": "Policy marks a source stale only after the TTL elapses. This record's TTL has not elapsed. Is the record stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "stale_only_after_elapse=true ttl_elapsed=false",
        "why": "The stated policy is not met, and the record is still inside TTL.",
    },
    {
        "id": "fresh-until-tomorrow",
        "inside_ttl": True,
        "question": "The mirror stays fresh until tomorrow. Today is still inside that window. Is the mirror stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "fresh_until=tomorrow today_inside_window=true",
        "why": "Today is inside the freshness window, so the mirror is not stale.",
    },
    {
        "id": "younger-than-max-age",
        "inside_ttl": True,
        "question": "The signed map is younger than its max-age. Inside max-age means not stale. Is the map stale?",
        "options": ["yes", "no"],
        "answer": "no",
        "stale_option": "yes",
        "context": "age_lt_max_age=true rule=inside_max_age_is_not_stale",
        "why": "Younger than max-age means inside TTL, so the map is not stale.",
    },
    {
        "id": "age-exceeds-max-age",
        "inside_ttl": False,
        "question": "Age exceeds max-age. Is the response stale?",
        "options": ["stale", "fresh"],
        "answer": "stale",
        "stale_option": "stale",
        "context": "age_gt_max_age=true inside_ttl=false",
        "why": "Age past max-age is outside TTL, so the response is stale.",
    },
    {
        "id": "next-update-ahead",
        "inside_ttl": True,
        "question": "nextUpdate is still in the future. A future nextUpdate means the cached response is inside TTL. Is the cached response stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "next_update_in_future=true inside_ttl=true",
        "why": "The question states that a future nextUpdate is inside TTL.",
    },
    {
        "id": "revalidation-still-open",
        "inside_ttl": True,
        "question": "The ETag was revalidated and the revalidation interval is still open. An open interval means not stale. Is the validated copy stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "revalidation_interval_open=true",
        "why": "The question states that an open revalidation interval is not stale.",
    },
    {
        "id": "fetched-at-inside",
        "inside_ttl": True,
        "question": "fetched_at sits inside the TTL window. Is the source stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "fetched_at_inside_ttl_window=true",
        "why": "fetched_at inside the TTL window means the source is not stale.",
    },
    {
        "id": "keep-inside-catalog",
        "inside_ttl": True,
        "question": "The catalog was taken inside its TTL. Which action matches the rule that inside TTL means not stale?",
        "options": ["treat the catalog as stale", "keep the catalog"],
        "answer": "keep the catalog",
        "stale_option": "treat the catalog as stale",
        "context": "taken_inside_ttl=true rule=in_ttl_is_not_stale",
        "why": "Inside TTL means not stale, so the catalog is kept.",
    },
    {
        "id": "ttl-elapsed-earlier",
        "inside_ttl": False,
        "question": "The feed's TTL elapsed earlier. Is the feed stale?",
        "options": ["yes", "no"],
        "answer": "yes",
        "stale_option": "yes",
        "context": "ttl_elapsed=true inside_ttl=false",
        "why": "A TTL that already elapsed means the feed is stale.",
    },
    {
        "id": "resolver-ttl-left",
        "inside_ttl": True,
        "question": "The resolver still has TTL left on the record. Is the record stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_left=true inside_ttl=true",
        "why": "TTL left on the record means it is inside TTL and not stale.",
    },
    {
        "id": "minute-inside-hour",
        "inside_ttl": True,
        "question": "The source was read one minute ago and the TTL is one hour, so it is inside TTL. Is it stale?",
        "options": ["yes", "no"],
        "answer": "no",
        "stale_option": "yes",
        "context": "age=1m ttl=1h inside_ttl=true",
        "why": "One minute is inside a one-hour TTL, so the source is not stale.",
    },
    {
        "id": "webhook-window-open",
        "inside_ttl": True,
        "question": "The webhook payload's TTL window is still open. Is the payload stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_window_open=true",
        "why": "An open TTL window means the payload is not stale.",
    },
    {
        "id": "clock-before-expiry",
        "inside_ttl": True,
        "question": "The clock is earlier than expires_at. Is the file stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "now_lt_expires_at=true inside_ttl=true",
        "why": "A clock before expires_at means the file is still inside TTL.",
    },
    {
        "id": "clock-after-expiry",
        "inside_ttl": False,
        "question": "expires_at was 10:00 and the clock reads 10:05. Is the source stale?",
        "options": ["stale", "fresh"],
        "answer": "stale",
        "stale_option": "stale",
        "context": "expires_at=10:00 now=10:05 inside_ttl=false",
        "why": "The clock is after expires_at, so the source is outside TTL.",
    },
    {
        "id": "seal-younger",
        "inside_ttl": True,
        "question": "The ledger seal is younger than its seal TTL. Is the sealed page stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "seal_age_lt_seal_ttl=true",
        "why": "A seal younger than its TTL is inside TTL and not stale.",
    },
    {
        "id": "backup-not-lapsed",
        "inside_ttl": True,
        "question": "The backup's freshness TTL has not lapsed. Is the backup stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "freshness_ttl_lapsed=false",
        "why": "A freshness TTL that has not lapsed means the backup is not stale.",
    },
    {
        "id": "deadline-later-than-now",
        "inside_ttl": True,
        "question": "The subset's TTL deadline is later than now. Is the subset stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_deadline_gt_now=true",
        "why": "A deadline still in the future means the subset is inside TTL.",
    },
    {
        "id": "age-fraction-of-ttl",
        "inside_ttl": True,
        "question": "The reading's age is a fraction of its TTL. Is the reading stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "age_is_fraction_of_ttl=true inside_ttl=true",
        "why": "An age that is only a fraction of the TTL is still inside TTL.",
    },
    {
        "id": "mirrored-inside-week",
        "inside_ttl": True,
        "question": "The index TTL is one week and the copy was mirrored yesterday, which is inside that week. Is the index stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl=1w mirrored=yesterday inside_ttl=true",
        "why": "Yesterday is inside a one-week TTL, so the index is not stale.",
    },
    {
        "id": "closed-window",
        "inside_ttl": False,
        "question": "The window closed before now. A closed TTL window means stale. Is the source stale?",
        "options": ["fresh", "stale"],
        "answer": "stale",
        "stale_option": "stale",
        "context": "ttl_window_closed=true",
        "why": "The question states that a closed TTL window means stale.",
    },
    {
        "id": "age-header-under",
        "inside_ttl": True,
        "question": "The Age header is lower than max-age. Lower than max-age means inside TTL. Is the response stale?",
        "options": ["yes", "no"],
        "answer": "no",
        "stale_option": "yes",
        "context": "age_header_lt_max_age=true",
        "why": "The question states that Age below max-age is inside TTL and not stale.",
    },
    {
        "id": "timer-not-zero",
        "inside_ttl": True,
        "question": "The zone copy's TTL timer has not hit zero. Is the zone copy stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_timer_gt_zero=true",
        "why": "A TTL timer above zero means the zone copy is inside TTL.",
    },
    {
        "id": "remaining-ttl-positive",
        "inside_ttl": True,
        "question": "Remaining TTL is positive. Is the source stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_remaining_positive=true",
        "why": "Positive remaining TTL means the source is inside TTL and not stale.",
    },
    {
        "id": "not-yet-expired",
        "inside_ttl": True,
        "question": "The object has not yet expired. An unexpired source is inside TTL. Is the object stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "expired=false rule=unexpired_is_inside_ttl",
        "why": "The question states that an unexpired source is inside TTL.",
    },
    {
        "id": "fresh-until-ahead",
        "inside_ttl": True,
        "question": "The caption says fresh-until a time that is still ahead. Is the caption's source stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "fresh_until_in_future=true",
        "why": "fresh-until still ahead means the source is inside TTL.",
    },
    {
        "id": "budget-mostly-unused",
        "inside_ttl": True,
        "question": "A replica was refreshed and its TTL budget is mostly unused. Is the replica stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "ttl_budget_mostly_unused=true inside_ttl=true",
        "why": "A mostly unused TTL budget means the replica is still inside TTL.",
    },
    {
        "id": "pinned-inside",
        "inside_ttl": True,
        "question": "The manifest digest was pinned inside the TTL. Is the pinned digest stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "pinned_inside_ttl=true",
        "why": "Pinned inside the TTL means the digest is not stale.",
    },
    {
        "id": "second-fetch-uncommitted",
        "inside_ttl": True,
        "question": "The first committed snapshot is inside TTL. A second fetch has not committed. Is the first snapshot stale?",
        "options": ["fresh", "stale"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "first_committed_inside_ttl=true second_committed=false",
        "why": "The committed snapshot is inside TTL. The uncommitted fetch is not the source.",
    },
    {
        "id": "watermark-inside",
        "inside_ttl": True,
        "question": "The watermark is still inside the freshness window. Is the watermarked source stale?",
        "options": ["stale", "fresh"],
        "answer": "fresh",
        "stale_option": "stale",
        "context": "watermark_inside_freshness_window=true",
        "why": "A watermark inside the freshness window means the source is not stale.",
    },
    {
        "id": "soft-expire-not-reached",
        "inside_ttl": True,
        "question": "Soft-expire has not been reached. The source is inside TTL until soft-expire. Is the source stale?",
        "options": ["yes", "no"],
        "answer": "no",
        "stale_option": "yes",
        "context": "soft_expire_reached=false inside_until_soft_expire=true",
        "why": "The question states the source stays inside TTL until soft-expire, which has not been reached.",
    },
]


def _norm(text: str) -> str:
    return re.sub(r"\d+", "#", " ".join(text.lower().split()))


def assert_bank_ok() -> None:
    banned = {"too_hard", "too hard", "escalate", "escalated", "unsure"}
    seen = {}
    for case in CASES:
        options = case["options"]
        if len(options) < 2:
            raise SystemExit(f"{case['id']}: needs two options")
        folded = {_norm(opt) for opt in options}
        if folded & banned:
            raise SystemExit(f"{case['id']}: banned option")
        if case["answer"] not in options:
            raise SystemExit(f"{case['id']}: answer not in options")
        if case["stale_option"] not in options:
            raise SystemExit(f"{case['id']}: stale_option not in options")
        inside = case["inside_ttl"]
        if inside and case["answer"] == case["stale_option"]:
            raise SystemExit(f"{case['id']}: in-TTL answer marked stale")
        if not inside and case["answer"] != case["stale_option"]:
            raise SystemExit(f"{case['id']}: past-TTL answer is not stale")
        key = _norm(case["question"])
        if key in seen:
            raise SystemExit(f"{case['id']}: number-swap of {seen[key]}")
        seen[key] = case["id"]
    if len({case["id"] for case in CASES}) != len(CASES):
        raise SystemExit("duplicate case id")


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _get_json(url: str, timeout: float = 20.0) -> dict:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("response was not an object")
    return payload


def _post_json(url: str, body: dict, timeout: float = 75.0) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode())
    if not isinstance(payload, dict):
        raise ValueError("decide response was not an object")
    return payload


def chip_ready(health: dict) -> bool:
    detail = health.get("detail") if isinstance(health.get("detail"), dict) else {}
    probe = detail.get("last_probe") if isinstance(detail.get("last_probe"), dict) else {}
    if probe.get("ok") is True:
        return True
    cond = str(detail.get("chip_cond") or "").lower()
    if any(token in cond for token in ("fail", "not_resident", "unavailable", "error")):
        return False
    return cond in {"ok", "ready", "resident", "loaded", "held"}


def _parse_expiry(health: dict) -> float | None:
    detail = health.get("detail") if isinstance(health.get("detail"), dict) else {}
    raw = str(detail.get("chip_expires_at") or "")
    if not raw:
        return None
    raw = raw.replace("Z", "+00:00")
    # Trim extra fractional digits so fromisoformat accepts the stamp.
    if "." in raw:
        head, tail = raw.split(".", 1)
        frac = "".join(ch for ch in tail if ch.isdigit())[:6]
        tz = ""
        for mark in ("+", "-"):
            at = tail.find(mark)
            if at >= 0:
                tz = tail[at:]
                break
        raw = f"{head}.{frac}{tz}" if frac else f"{head}{tz}"
    try:
        stamp = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp.timestamp()


def wait_for_chip() -> tuple[str, dict]:
    last = {}
    for attempt in range(MAX_CHIP_WAITS):
        base = discover_base()
        if not base:
            raise RuntimeError("ntfy discovery returned no https base")
        health = _get_json(base.rstrip("/") + "/health")
        last = health
        if health.get("ok") is True and chip_ready(health):
            return base.rstrip("/"), health
        expiry = _parse_expiry(health)
        delay = 20.0
        if expiry is not None:
            delay = max(5.0, min(240.0, expiry - time.time() + 3.0))
        detail = health.get("detail") if isinstance(health.get("detail"), dict) else {}
        print(
            json.dumps(
                {
                    "wait": attempt + 1,
                    "chip_cond": detail.get("chip_cond"),
                    "sleep_s": round(delay, 1),
                }
            ),
            flush=True,
        )
        time.sleep(delay)
    detail = last.get("detail") if isinstance(last.get("detail"), dict) else {}
    raise RuntimeError(f"chip not ready: {detail.get('chip_cond')}")


def post_chip(base: str, case: dict) -> dict:
    body = {
        "question": case["question"],
        "options": case["options"],
        "context": case["context"],
        "agent": AGENT,
        "kind": KIND,
    }
    errors = []
    for path in ("/v1/decide", "/decide"):
        try:
            payload = _post_json(base + path, body)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                errors.append(f"404 {path}")
                continue
            raise
        payload = dict(payload)
        payload["_path"] = path
        return payload
    raise RuntimeError("decide endpoint missing: " + ", ".join(errors))


def _clean(raw: object) -> str:
    text = str(raw or "")
    for token in ("<|im_end|>", "<|im_start|>"):
        text = text.replace(token, "")
    return text.strip()


def chip_blob(payload: dict) -> dict | None:
    chip = payload.get("chip")
    if isinstance(chip, dict) and ("choice" in chip or "index" in chip or "scores" in chip):
        blob = dict(chip)
        if "shuffle_order" not in blob and payload.get("shuffle_order") is not None:
            blob["shuffle_order"] = payload.get("shuffle_order")
        return blob
    decided = str(payload.get("decided_by") or "").lower()
    device = str(payload.get("device") or "").lower()
    model = str(payload.get("model") or "").lower()
    if "teacher" in decided or "gguf" in model or device.startswith("cpu"):
        return None
    if any(token in decided or token in model or token in device for token in ("chip", "student", "hef", "hailo", "npu")):
        return payload
    return None


def confidence_of(blob: dict) -> float | None:
    value = blob.get("confidence")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    scores = blob.get("scores")
    if (
        isinstance(scores, list)
        and scores
        and all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in scores)
    ):
        return float(max(scores))
    return None


def map_choice(blob: dict, options: list[str]) -> dict:
    index = blob.get("index")
    choice = _clean(blob.get("choice"))
    if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(options):
        by_index = options[index]
        if choice and choice in options and choice != by_index:
            return {"ok": False, "bug": "index_choice_mismatch", "choice": choice, "index": index}
        return {"ok": True, "option": by_index, "index": index}
    if choice in options:
        return {"ok": True, "option": choice, "index": options.index(choice)}
    return {"ok": False, "bug": "unmapped_choice", "choice": choice, "index": index}


def score_case(case: dict, payload: dict) -> dict:
    blob = chip_blob(payload)
    row = {
        "id": case["id"],
        "kind": "source_freshness",
        "family": "in_ttl_not_stale" if case["inside_ttl"] else "past_ttl_is_stale",
        "inside_ttl": case["inside_ttl"],
        "question": case["question"],
        "options": case["options"],
        "answer": case["answer"],
        "why": case["why"],
        "training_eligible": False,
        "agent": AGENT,
        "request_kind": KIND,
        "production_escalated": bool(payload.get("escalated")),
        "decided_by": payload.get("decided_by"),
        "model": payload.get("model"),
        "decision_id": payload.get("decision_id"),
        "latency_ms": payload.get("latency_ms"),
        "counted_failure": False,
    }
    if blob is None:
        row["skip"] = "teacher_only"
        return row
    mapped = map_choice(blob, case["options"])
    confidence = confidence_of(blob)
    row["jev_choice"] = mapped.get("option")
    row["jev_index"] = mapped.get("index")
    row["jev_confidence"] = confidence
    row["jev_scores"] = blob.get("scores")
    row["chip_model"] = blob.get("model") or payload.get("model")
    if not mapped.get("ok"):
        row["skip"] = mapped.get("bug")
        return row
    wrong = mapped["option"] != case["answer"]
    confident = confidence is not None and confidence >= CONFIDENT
    row["jev_wrong"] = wrong
    row["confident"] = confident
    row["counted_failure"] = bool(wrong and confident)
    row["skip"] = None
    return row


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def summarise(rows: list[dict], error: str | None, asked: int) -> dict:
    counted = [row for row in rows if row.get("counted_failure")]
    return {
        "ts": _now(),
        "lane": "jev-cursor-fresh",
        "family": "source_freshness",
        "teacher": "in_ttl_means_not_stale",
        "training_eligible": False,
        "decide_url_origin_hidden": True,
        "agent": AGENT,
        "request_kind": KIND,
        "asked": asked,
        "bank": len(CASES),
        "counted_failures": len(counted),
        "stop_at": STOP_AT,
        "stopped_because": (
            "counted_20"
            if len(counted) >= STOP_AT
            else "family_exhausted"
            if asked >= len(CASES) and error is None
            else error or "partial"
        ),
        "confident_correct": sum(
            1 for row in rows if row.get("confident") and row.get("jev_wrong") is False and not row.get("skip")
        ),
        "chip_wrong_any_confidence": sum(1 for row in rows if row.get("jev_wrong")),
        "teacher_only": sum(1 for row in rows if row.get("skip") == "teacher_only"),
        "counted_ids": [row["id"] for row in counted],
        "error": error,
        "note": "Counted only when the chip is wrong and confidence >= 0.90. Do not train.",
    }


def run() -> dict:
    assert_bank_ok()
    rows: list[dict] = []
    error = None
    asked = 0
    try:
        base, _health = wait_for_chip()
        for case in CASES:
            if sum(1 for row in rows if row.get("counted_failure")) >= STOP_AT:
                break
            base, health = wait_for_chip() if not chip_ready(_health) else (base, _health)
            if not chip_ready(health):
                base, health = wait_for_chip()
            _health = health
            started = time.perf_counter()
            payload = post_chip(base, case)
            row = score_case(case, payload)
            row["client_ms"] = round(1000.0 * (time.perf_counter() - started), 1)
            row["ts"] = _now()
            rows.append(row)
            asked += 1
            if row.get("skip") == "teacher_only":
                # The service skipped the chip. Do not keep calling the teacher.
                error = "teacher_only_response"
                break
            print(
                json.dumps(
                    {
                        "id": row["id"],
                        "choice": row.get("jev_choice"),
                        "answer": row["answer"],
                        "confidence": row.get("jev_confidence"),
                        "counted": row["counted_failure"],
                        "skip": row.get("skip"),
                    }
                ),
                flush=True,
            )
            counted = [item for item in rows if item.get("counted_failure")]
            _write_jsonl(OUT / "failures.jsonl", counted)
            _write_jsonl(OUT / "ledger.jsonl", rows)
    except Exception as exc:  # noqa: BLE001 — recorded, not trained
        error = f"{type(exc).__name__}: {exc}"
    counted = [row for row in rows if row.get("counted_failure")]
    summary = summarise(rows, error, asked)
    OUT.mkdir(parents=True, exist_ok=True)
    _write_jsonl(OUT / "failures.jsonl", counted)
    _write_jsonl(OUT / "ledger.jsonl", rows)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if "--check" in argv:
        assert_bank_ok()
        print(json.dumps({"ok": True, "cases": len(CASES), "training_eligible": False}))
        return 0
    summary = run()
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("error") is None else 2


if __name__ == "__main__":
    raise SystemExit(main())
