"""Load JEV-H labels / decide logs and split by unique question (no leakage)."""
from __future__ import annotations

import json
import math
import os
import random
from collections import defaultdict
from pathlib import Path
from typing import Any

from encode import StudentTok, build_input, gold_index, is_yesno

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
DEFAULT_UPLOADS = Path("/home/ubuntu/.cursor/projects/workspace/uploads")
EVAL_FRAC = 0.15
DEV_FRAC = 0.15
SEED = 42
CONF_DISAGREE = 0.65


def _uploads_dir() -> Path:
    return Path(os.environ.get("JEVH_UPLOADS_DIR", str(DEFAULT_UPLOADS)))


def resolve_file(env_name: str, bundled: str, patterns: list[str], required: bool = True) -> Path | None:
    env = os.environ.get(env_name)
    if env:
        p = Path(env)
        if p.is_file():
            return p
    uploads = _uploads_dir()
    if uploads.is_dir():
        hits: list[Path] = []
        for pat in patterns:
            hits.extend(uploads.glob(pat))
        hits = [h for h in hits if h.is_file()]
        if hits:
            hits.sort(key=lambda x: x.stat().st_size, reverse=True)
            return hits[0]
    bundled_path = DATA_DIR / bundled
    if bundled_path.is_file():
        return bundled_path
    if required:
        raise FileNotFoundError(f"{env_name}: no file (looked at ${env_name}, {uploads}, {bundled_path})")
    return None


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def load_paths() -> dict[str, Path | None]:
    return {
        "labels": resolve_file("JEVH_LABELS_PATH", "labels.jsonl", ["labels_*.jsonl", "labels.jsonl"]),
        "decide": resolve_file(
            "JEVH_DECIDE_PATH",
            "decide_questions.sample.jsonl",
            ["decide_questions_dedup*.jsonl", "decide_questions*.jsonl"],
            required=False,
        ),
        "lane": resolve_file("JEVH_LANE_PATH", "lane_bank.jsonl", ["jevh_lane_bank*.jsonl", "lane_bank.jsonl"]),
        "tokenizer": resolve_file(
            "JEVH_TOKENIZER_PATH",
            "tokenizer.json",
            ["jevh_student_tokenizer*.json", "tokenizer.json"],
        ),
    }


def n_options_bucket(n: int) -> str:
    if n <= 2:
        return "2"
    if n == 3:
        return "3"
    if n == 4:
        return "4"
    return "6plus"


def stratified_question_split(
    questions: list[str],
    n_opts: dict[str, int],
    seed: int = SEED,
    eval_frac: float = EVAL_FRAC,
    dev_frac: float = DEV_FRAC,
) -> dict[str, str]:
    """Map unique question -> train|dev|eval. Stratify by option count. Eval >= 15%."""
    rng = random.Random(seed)
    by_b: dict[str, list[str]] = defaultdict(list)
    for q in questions:
        by_b[n_opts[q]].append(q)
    assign: dict[str, str] = {}
    for bucket, qs in sorted(by_b.items()):
        rng.shuffle(qs)
        n = len(qs)
        n_eval = int(math.ceil(n * eval_frac))
        n_dev = int(math.ceil(n * dev_frac))
        if n >= 2:
            n_eval = min(max(n_eval, 1), n - 1)
        if n - n_eval >= 2:
            n_dev = min(max(n_dev, 1), n - n_eval - 1)
        else:
            n_dev = 0
        for q in qs[:n_eval]:
            assign[q] = "eval"
        for q in qs[n_eval : n_eval + n_dev]:
            assign[q] = "dev"
        for q in qs[n_eval + n_dev :]:
            assign[q] = "train"
    n_q = len(questions)
    n_eval_q = sum(1 for s in assign.values() if s == "eval")
    need = int(math.ceil(n_q * eval_frac))
    if n_eval_q < need:
        extra = [q for q, s in assign.items() if s == "train"]
        rng.shuffle(extra)
        for q in extra[: need - n_eval_q]:
            assign[q] = "eval"
    return assign


def _choice_index(options: list[str], choice: Any) -> int | None:
    if choice is None:
        return None
    try:
        return gold_index(options, choice)
    except ValueError:
        return None


def examples_from_labels(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for i, r in enumerate(rows):
        options = [str(o) for o in (r.get("options") or [])]
        if len(options) < 2:
            continue
        q = str(r.get("question") or "").strip()
        if not q:
            continue
        try:
            g = gold_index(options, r.get("jev_choice"))
        except ValueError:
            continue
        teacher_i = _choice_index(options, r.get("model_choice"))
        jev_conf = float(r.get("jev_confidence") or 0.0)
        teacher_conf = float(r.get("model_confidence") or 0.0) if r.get("model_confidence") is not None else None
        disagree = teacher_i is not None and teacher_i != g
        weight = 1.0
        if disagree and jev_conf >= CONF_DISAGREE:
            weight = 3.0
        elif disagree:
            weight = 1.5
        qtype, text_a, stexts, yesno = build_input(q, options, r.get("context"), r.get("qtype"))
        out.append(
            {
                "id": f"label-{i}",
                "source": "labels",
                "question": q,
                "options": options,
                "option_texts": stexts,
                "text_a": text_a,
                "qtype": qtype,
                "yesno": yesno,
                "gold": g,
                "n_options": len(options),
                "teacher_index": teacher_i,
                "teacher_choice": r.get("model_choice"),
                "teacher_confidence": teacher_conf,
                "jev_choice": r.get("jev_choice"),
                "jev_confidence": jev_conf,
                "disagree": disagree,
                "conf_disagree": bool(disagree and jev_conf >= CONF_DISAGREE),
                "weight": weight,
                "kind": "gold",
            }
        )
    return out


def examples_from_decide(rows: list[dict[str, Any]], eval_dev_questions: set[str]) -> list[dict[str, Any]]:
    """Soft-label / unlabeled rows. Never gold. Skip eval/dev questions."""
    out = []
    for i, r in enumerate(rows):
        q = str(r.get("question") or "").strip()
        if not q or q in eval_dev_questions:
            continue
        options = [str(o) for o in (r.get("options") or [])]
        if len(options) < 2:
            continue
        scores = r.get("teacher_scores")
        tchoice = r.get("teacher_choice")
        if not scores or tchoice is None or len(scores) != len(options):
            continue
        teacher_i = _choice_index(options, tchoice)
        if teacher_i is None:
            continue
        qtype, text_a, stexts, yesno = build_input(q, options, r.get("context"), r.get("student_qtype"))
        out.append(
            {
                "id": f"decide-{i}",
                "source": "decide",
                "question": q,
                "options": options,
                "option_texts": stexts,
                "text_a": text_a,
                "qtype": qtype,
                "yesno": yesno,
                "gold": None,
                "n_options": len(options),
                "teacher_index": teacher_i,
                "teacher_scores": [float(x) for x in scores],
                "teacher_choice": tchoice,
                "teacher_confidence": float(r.get("teacher_confidence") or 0.0),
                "student_choice": r.get("student_choice"),
                "student_confidence": r.get("student_confidence"),
                "student_scores": r.get("student_scores"),
                "weight": 0.4,
                "kind": "kd",
            }
        )
    return out


def tokenize_example(tok: StudentTok, ex: dict[str, Any]) -> dict[str, Any]:
    ids, masks, mode = tok.encode(ex["text_a"], ex["option_texts"])
    ex = dict(ex)
    ex["input_ids"] = ids
    ex["attention_mask"] = masks
    ex["truncation"] = mode
    return ex


def attach_student_preds(label_ex: list[dict[str, Any]], decide_rows: list[dict[str, Any]]) -> None:
    by_q: dict[str, dict[str, Any]] = {}
    for r in decide_rows:
        if not r.get("student_choice"):
            continue
        by_q[str(r.get("question") or "")] = r
    for ex in label_ex:
        r = by_q.get(ex["question"])
        if not r:
            continue
        if [str(o) for o in (r.get("options") or [])] != ex["options"]:
            # still record choice if it matches an option
            pass
        ex["student_choice"] = r.get("student_choice")
        ex["student_confidence"] = r.get("student_confidence")
        ex["student_scores"] = r.get("student_scores")
        ex["student_index"] = _choice_index(ex["options"], r.get("student_choice"))
