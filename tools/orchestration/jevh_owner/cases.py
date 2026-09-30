"""Ownership family only.

Rule: the named worker owns the task, not a bystander.
Each case is one atomic choice between two real workers.
TOO_HARD and escalate are never options.
training_eligible is always false.
"""

from __future__ import annotations

FAMILY = "ownership"
KIND = "adversarial"
PREFIX = "Named worker owns the task, not a bystander."

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

# cid, contrast, named, bystander, lure, question override, why
# lure is the clause after "Bystander is NAME, ".
_SPECS: list[tuple] = [
    (
        "own-short",
        "short-rule",
        "Vesper",
        "Calder",
        None,
        "Who owns the task? The named worker owns it, not a bystander. Named worker is Vesper. Bystander is Calder.",
        "The sentence names Vesper as the worker. Calder is only the bystander.",
    ),
    (
        "own-short-shader",
        "short-shader",
        "Vesper",
        "Calder",
        None,
        "Who owns the shader task? The named worker owns it, not a bystander. Named worker is Vesper. Bystander is Calder.",
        "Shader work does not move ownership off the named worker Vesper.",
    ),
    (
        "own-domain-shader",
        "domain-shader",
        "Ada",
        "Ben",
        "who usually edits shaders",
        None,
        "Ada is the named worker. Ben's shader habit does not own the task.",
    ),
    (
        "own-audio",
        "domain-audio",
        "Moss",
        "Briar",
        "who usually edits audio",
        None,
        "Moss is named. Briar's audio habit is a bystander fact.",
    ),
    (
        "own-jelly",
        "domain-jelly",
        "Cleo",
        "Hugo",
        "who usually edits the jelly mesh",
        None,
        "Cleo is named. Hugo's mesh habit is a bystander fact.",
    ),
    (
        "own-shop",
        "domain-shop",
        "Pearl",
        "Otto",
        "who usually edits shop prices",
        None,
        "Pearl is named. Otto's shop habit is a bystander fact.",
    ),
    (
        "own-save",
        "domain-save",
        "Freya",
        "Idris",
        "who usually edits saves",
        None,
        "Freya is named. Idris's save habit is a bystander fact.",
    ),
    (
        "own-camera",
        "domain-camera",
        "Thea",
        "Jonas",
        "who usually edits the camera",
        None,
        "Thea is named. Jonas's camera habit is a bystander fact.",
    ),
    (
        "own-ui",
        "domain-ui",
        "Vera",
        "Emil",
        "who usually edits the journal",
        None,
        "Vera is named. Emil's journal habit is a bystander fact.",
    ),
    (
        "own-water",
        "domain-water",
        "Lila",
        "Sven",
        "who usually edits the pond",
        None,
        "Lila is named. Sven's pond habit is a bystander fact.",
    ),
    (
        "own-licence",
        "domain-licence",
        "Nora",
        "Felix",
        "who usually reviews the licence",
        None,
        "Nora is named. Felix's licence habit is a bystander fact.",
    ),
    (
        "own-title",
        "title-name",
        "Avery",
        "Parker",
        None,
        f"{PREFIX} The title names Parker. Named worker is Avery. Parker is a bystander. Who owns it?",
        "The title mentions Parker. Avery is the named worker.",
    ),
    (
        "own-skill",
        "skill-list",
        "Tatum",
        "Rowan",
        "who has the skill for this work",
        None,
        "Tatum is named. Rowan's skill does not assign the task.",
    ),
    (
        "own-previous",
        "previous-owner",
        "Ivy",
        "Cole",
        "who owned it yesterday",
        None,
        "Ivy is the named worker now. Cole's earlier ownership is a bystander fact.",
    ),
    (
        "own-author",
        "file-author",
        "Mina",
        "Rio",
        "who wrote the file",
        None,
        "Mina is named. Rio writing the file does not own this task.",
    ),
    (
        "own-lead",
        "team-lead",
        "Soren",
        "Blake",
        "who is the team lead",
        None,
        "Soren is named. Blake's lead role is a bystander fact.",
    ),
    (
        "own-lock",
        "edit-lock",
        "Casey",
        "Jules",
        "who holds the edit lock",
        None,
        "Casey is named. Jules holding the lock does not own the task.",
    ),
    (
        "own-reporter",
        "reporter",
        "Nia",
        "Sol",
        "who reported the bug",
        None,
        "Nia is named. Sol reporting the bug is a bystander fact.",
    ),
    (
        "own-comment",
        "last-comment",
        "Kit",
        "Wes",
        "who commented last",
        None,
        "Kit is named. Wes's comment does not assign the task.",
    ),
    (
        "own-mention",
        "mention",
        "Ora",
        "Pax",
        "who was mentioned",
        None,
        "Ora is named. A mention of Pax does not assign the task.",
    ),
    (
        "own-volunteer",
        "volunteer",
        "Jem",
        "Lux",
        "who volunteered",
        None,
        "Jem is named. Lux volunteering does not own the task.",
    ),
    (
        "own-requester",
        "requester",
        "Noa",
        "Tess",
        "who asked for the work",
        None,
        "Noa is named. Tess asking for the work is a bystander fact.",
    ),
    (
        "own-code-owner",
        "code-owner",
        "Gale",
        "Holt",
        "who is the code owner",
        None,
        "Gale is named. Holt's code-owner role is a bystander fact.",
    ),
    (
        "own-nearby",
        "nearby",
        "Wynn",
        "Beck",
        "who is standing nearby",
        None,
        "Wynn is named. Beck standing nearby does not own the task.",
    ),
    (
        "own-started",
        "already-started",
        "Reed",
        "Sage",
        "who already started a branch",
        None,
        "Reed is named. Sage starting a branch does not own the task.",
    ),
    (
        "own-reviewer",
        "reviewer",
        "Hart",
        "Quinn",
        "who will review the change",
        None,
        "Hart is named. Quinn reviewing later is a bystander fact.",
    ),
    (
        "own-backup",
        "backup",
        "Dale",
        "Finn",
        "who is the backup",
        None,
        "Dale is named. Finn as backup does not own the task.",
    ),
    (
        "own-affected",
        "affected-user",
        "Blair",
        "Rory",
        "who hit the bug",
        None,
        "Blair is named. Rory hitting the bug is a bystander fact.",
    ),
    (
        "own-queue",
        "usual-queue",
        "Drew",
        "Skye",
        "whose queue usually receives this",
        None,
        "Drew is named. Skye's usual queue does not own this task.",
    ),
    (
        "own-example",
        "quoted-example",
        "Shay",
        "Remy",
        "who appears only in an example",
        None,
        "Shay is named. Remy's name in an example is a bystander fact.",
    ),
    (
        "own-copied",
        "cc-watcher",
        "Arlo",
        "Nico",
        "who is copied on the thread",
        None,
        "Arlo is named. Nico being copied does not own the task.",
    ),
    (
        "own-other-ticket",
        "other-ticket",
        "Joss",
        "Emry",
        "who owns a different ticket",
        None,
        "Joss is named on this task. Emry's other ticket is a bystander fact.",
    ),
    (
        "own-busy",
        "free-bystander",
        "Ellis",
        "Maren",
        None,
        f"{PREFIX} Named worker is Ellis and is busy. Maren is free and is a bystander. Who owns it?",
        "Ellis is named. Maren being free does not own the task.",
    ),
    (
        "own-control",
        "named-is-specialist",
        "Indre",
        "Keir",
        None,
        f"{PREFIX} Named worker is Indre, who edits shaders. Keir is a bystander and does not. Who owns it?",
        "Indre is named and is the specialist. Keir is the bystander.",
    ),
]


def _question(named: str, bystander: str, lure: str | None, override: str | None) -> str:
    if override:
        return override
    if not lure:
        raise ValueError("lure or question override required")
    return (
        f"{PREFIX} Named worker is {named}. "
        f"Bystander is {bystander}, {lure}. Who owns it?"
    )


def _case(
    cid: str,
    contrast: str,
    named: str,
    bystander: str,
    question: str,
    why: str,
    *,
    flip: bool,
) -> dict:
    options = [named, bystander] if flip else [bystander, named]
    if named == bystander:
        raise ValueError(f"{cid} options must differ")
    if len(options) != 2:
        raise ValueError(f"{cid} must be atomic")
    lowered = [part.strip().lower() for part in options]
    if any(part in FORBIDDEN_OPTIONS for part in lowered):
        raise ValueError(f"{cid} has a forbidden option")
    if named not in question or bystander not in question:
        raise ValueError(f"{cid} question must name both workers")
    text = (question + " " + why).lower()
    if "too_hard" in text or "escalate" in text:
        raise ValueError(f"{cid} mentions a forbidden choice")
    return {
        "id": cid + ("-flip" if flip else ""),
        "kind": KIND,
        "family": FAMILY,
        "contrast": contrast,
        "named": named,
        "bystander": bystander,
        "question": question,
        "options": options,
        "answer": named,
        "context": (
            f"rule=named_worker_owns_task named={named} "
            f"bystander={bystander} contrast={contrast}"
        ),
        "why": why,
        "training_eligible": False,
        "bucket": "CANARY-EVAL",
    }


def load_cases() -> list[dict]:
    rows: list[dict] = []
    for cid, contrast, named, bystander, lure, override, why in _SPECS:
        question = _question(named, bystander, lure, override)
        rows.append(_case(cid, contrast, named, bystander, question, why, flip=False))
        rows.append(_case(cid, contrast, named, bystander, question, why, flip=True))
    return rows


def assert_bank_ok(cases: list[dict] | None = None) -> None:
    rows = cases if cases is not None else load_cases()
    if len(rows) < 2:
        raise ValueError("ownership bank is empty")
    ids = [row["id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate case ids")
    flips = {row["id"][: -len("-flip")] for row in rows if row["id"].endswith("-flip")}
    bases = {row["id"] for row in rows if not row["id"].endswith("-flip")}
    if flips != bases:
        raise ValueError("every ownership case needs an option-order flip")
    first = 0
    for row in rows:
        if row["family"] != FAMILY or row["kind"] != KIND:
            raise ValueError(f"{row['id']} left the ownership family")
        if row["training_eligible"] is not False:
            raise ValueError(f"{row['id']} must stay training_eligible false")
        options = row["options"]
        if len(options) != 2 or len(set(options)) != 2:
            raise ValueError(f"{row['id']} must have two real options")
        if row["answer"] != row["named"] or row["answer"] not in options:
            raise ValueError(f"{row['id']} answer must be the named worker")
        if row["bystander"] not in options:
            raise ValueError(f"{row['id']} must offer the bystander")
        for option in options:
            if option.strip().lower() in FORBIDDEN_OPTIONS:
                raise ValueError(f"{row['id']} has a forbidden option")
        if row["answer"] == options[0]:
            first += 1
    if first == 0 or first == len(rows):
        raise ValueError("answers must not all sit on one option slot")
