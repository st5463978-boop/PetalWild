"""Canonical-match cases. Two real options. No TOO_HARD. No modulo-slot.

Teacher rule: if canonical state matches its replica, a marked stale-client
or non-canonical cache is not a contradiction. A replica that differs from
canonical is a contradiction. training_eligible is always false.
"""

from __future__ import annotations

FAMILY = "canonical_match"
KIND = "canonical_contradicted"
EXCLUDED_FAMILIES = frozenset({"modulo-slot", "modulo_slot", "moduloslot"})
MARKS = frozenset({"stale-client", "non-canonical"})
FORBIDDEN_OPTIONS = frozenset(
    {
        "too_hard",
        "too-hard",
        "escalate",
        "escalated",
        "unknown",
        "idk",
        "n/a",
        "skip",
    }
)

# id, noun, canonical, replica, extra, mark, contradicted_first
# mark None: no extra record. extra is ignored then.
_ROWS = (
    ("cm-session-stale", "session", "4", "4", "1", "stale-client", True),
    ("cm-session-stale-flip", "session", "4", "4", "1", "stale-client", False),
    ("cm-schema-stale", "schema", "r12", "r12", "r2", "stale-client", True),
    ("cm-flag-stale", "flag", "on", "on", "off", "stale-client", True),
    ("cm-flag-stale-flip", "flag", "on", "on", "off", "stale-client", False),
    ("cm-etag-stale", "etag", "k7", "k7", "k2", "stale-client", True),
    ("cm-quota-stale", "quota", "100", "100", "0", "stale-client", True),
    ("cm-role-stale", "role", "admin", "admin", "guest", "stale-client", False),
    ("cm-build-stale", "build", "b18", "b18", "b3", "stale-client", True),
    ("cm-theme-stale", "theme", "dark", "dark", "light", "stale-client", False),
    ("cm-gate-stale", "gate", "open", "open", "closed", "stale-client", True),
    ("cm-consent-stale", "consent", "v2", "v2", "v1", "stale-client", True),
    ("cm-serial-stale", "serial", "41", "41", "7", "stale-client", False),
    ("cm-config-cache", "config", "30", "30", "2", "non-canonical", True),
    ("cm-config-cache-flip", "config", "30", "30", "2", "non-canonical", False),
    ("cm-lock-cache", "lock", "5", "5", "8", "non-canonical", True),
    ("cm-cert-cache", "cert", "aa", "aa", "bb", "non-canonical", False),
    ("cm-offset-cache", "offset", "50", "50", "0", "non-canonical", True),
    ("cm-bundle-cache", "bundle", "p4", "p4", "p1", "non-canonical", True),
    ("cm-shard-cache", "shard", "6", "6", "1", "non-canonical", False),
    ("cm-catalog-cache", "catalog", "15", "15", "10", "non-canonical", True),
    ("cm-window-cache", "window", "w3", "w3", "w1", "non-canonical", True),
    ("cm-keymap-cache", "keymap", "m8", "m8", "m1", "non-canonical", False),
    ("cm-epoch-cache", "epoch", "3", "3", "9", "non-canonical", True),
    ("cm-gen-cache", "generation", "g4", "g4", "g1", "non-canonical", False),
    ("cm-rev-cache", "revision", "20", "20", "11", "non-canonical", True),
    ("cm-ledger-match", "ledger", "8", "8", "", None, True),
    ("cm-hash-match", "hash", "ab", "ab", "", None, False),
    ("cm-session-stale-agrees", "session", "4", "4", "4", "stale-client", True),
    ("cm-cert-cache-agrees", "cert", "aa", "aa", "aa", "non-canonical", False),
    ("cm-session-split", "session", "4", "9", "", None, True),
    ("cm-schema-split", "schema", "r12", "r9", "", None, False),
    ("cm-flag-split", "flag", "on", "off", "", None, True),
    ("cm-session-split-stale", "session", "4", "9", "4", "stale-client", False),
    ("cm-config-split-cache", "config", "30", "2", "30", "non-canonical", True),
    ("cm-quota-split", "quota", "100", "80", "0", "stale-client", False),
)


def gold(canonical: str, replica: str, mark: str | None) -> str:
    """Independently establishable answer for this family."""
    if canonical != replica:
        return "contradicted"
    if mark is None or mark in MARKS:
        return "consistent"
    raise ValueError(f"mark {mark!r} is outside canonical-match")


def _question(noun: str, canonical: str, replica: str, extra: str, mark: str | None) -> str:
    text = f"Canonical {noun} is {canonical}. Replica {noun} is {replica}."
    if mark == "stale-client":
        text += f" A client shows {extra} and is marked stale-client."
    elif mark == "non-canonical":
        text += f" A cache shows {extra} and is marked non-canonical."
    elif mark is None:
        text += " No other record is present."
    else:
        raise ValueError(mark)
    return text + " Is canonical state contradicted?"


def _context(canonical: str, replica: str, extra: str, mark: str | None) -> str:
    parts = [f"canonical={canonical}", f"replica={replica}"]
    if mark is None:
        parts.append("extra=none")
    else:
        parts.append(f"extra={extra}")
        parts.append(f"extra_marked={mark}")
    return " ".join(parts)


def _why(canonical: str, replica: str, mark: str | None) -> str:
    if canonical != replica:
        return "Replica differs from canonical, so canonical state is contradicted."
    if mark in MARKS:
        return (
            "Canonical matches its replica. A marked stale-client or "
            "non-canonical cache is not a contradiction."
        )
    return "Canonical matches its replica and no disagreeing replica is present."


def _case(row: tuple) -> dict:
    cid, noun, canonical, replica, extra, mark, contradicted_first = row
    if mark is not None and not extra:
        raise ValueError(f"{cid} mark needs an extra value")
    answer = gold(canonical, replica, mark)
    options = (
        ["contradicted", "consistent"]
        if contradicted_first
        else ["consistent", "contradicted"]
    )
    return {
        "id": cid,
        "kind": KIND,
        "family": FAMILY,
        "question": _question(noun, canonical, replica, extra, mark),
        "options": options,
        "answer": answer,
        "context": _context(canonical, replica, extra, mark),
        "why": _why(canonical, replica, mark),
        "training_eligible": False,
        "bucket": "CANARY-EVAL",
    }


def load_cases() -> list[dict]:
    return [_case(row) for row in _ROWS]


def assert_bank_ok(cases: list[dict] | None = None) -> None:
    cases = load_cases() if cases is None else cases
    if len(cases) < 2:
        raise ValueError("canonical-match bank needs at least two cases")
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate case id")
    families = {case["family"] for case in cases}
    if families != {FAMILY}:
        raise ValueError(f"family must be only {FAMILY}")
    if families & EXCLUDED_FAMILIES:
        raise ValueError("modulo-slot family is excluded")
    answers = set()
    first = 0
    for case in cases:
        if case["kind"] != KIND:
            raise ValueError(case["id"])
        if case["training_eligible"] is not False:
            raise ValueError(case["id"])
        options = case["options"]
        if len(options) != 2 or len(set(options)) != 2:
            raise ValueError(f"{case['id']} needs two distinct options")
        if case["answer"] not in options:
            raise ValueError(case["id"])
        lowered = [option.strip().lower() for option in options]
        if any(option in FORBIDDEN_OPTIONS for option in lowered):
            raise ValueError(f"{case['id']} has a forbidden option")
        blob = (case["question"] + " " + case["context"] + " " + case["family"]).lower()
        if "too_hard" in blob or "escalate" in blob:
            raise ValueError(f"{case['id']} offers an escape")
        if "modulo" in blob or "slot" in blob:
            raise ValueError(f"{case['id']} repeats modulo-slot")
        answers.add(case["answer"])
        if case["answer"] == options[0]:
            first += 1
    if answers != {"consistent", "contradicted"}:
        raise ValueError("bank must include both real answers")
    if first == 0 or first == len(cases):
        raise ValueError("answer must not always be the same option index")
