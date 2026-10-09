"""Load JEV-H labels / decide logs, split by unique question, no leakage."""
from __future__ import annotations

import json
import os
import random
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

from encode import choice_index, is_yesno

UPLOADS = Path("/home/ubuntu/.cursor/projects/workspace/uploads")
HERE = Path(__file__).resolve().parent
SAMPLE_DIR = HERE / "data"
EVAL_FRAC = 0.15
SEED = 42


@dataclass
class Example:
    question: str
    options: list[str]
    context: str | None
    gold_index: int | None
    teacher_index: int | None
    teacher_scores: list[float] | None
    jev_confidence: float | None
    teacher_confidence: float | None
    source: str
    n_options: int
    yesno: bool

    def is_binary(self) -> bool:
        return self.n_options == 2


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _first_existing(candidates: Iterable[Path]) -> Path | None:
    for p in candidates:
        if p and p.is_file():
            return p
    return None


def _glob_first(directory: Path, pattern: str) -> Path | None:
    if not directory.is_dir():
        return None
    hits = sorted(directory.glob(pattern))
    return hits[0] if hits else None


def resolve_paths(args: Any | None = None) -> dict[str, Path]:
    """Find full datasets. Prefer env / CLI, then agent uploads, then samples."""
    data_dir = None
    if args is not None and getattr(args, "data_dir", None):
        data_dir = Path(args.data_dir)
    elif os.environ.get("JEVH_DATA_DIR"):
        data_dir = Path(os.environ["JEVH_DATA_DIR"])

    def pick(cli_attr: str, env_name: str, names: list[str], patterns: list[str]) -> Path:
        if args is not None and getattr(args, cli_attr, None):
            p = Path(getattr(args, cli_attr))
            if not p.is_file():
                raise FileNotFoundError(p)
            return p
        env = os.environ.get(env_name)
        if env:
            p = Path(env)
            if not p.is_file():
                raise FileNotFoundError(p)
            return p
        cands: list[Path] = []
        search_dirs = [p for p in (data_dir, UPLOADS, SAMPLE_DIR, Path.cwd()) if p]
        for d in search_dirs:
            for n in names:
                cands.append(d / n)
            for pat in patterns:
                hit = _glob_first(d, pat)
                if hit:
                    cands.append(hit)
        found = _first_existing(cands)
        if found is None:
            raise FileNotFoundError(f"could not find {names[0]} in {search_dirs}")
        return found

    tok_default = HERE / "tokenizer" / "tokenizer.json"
    paths = {
        "labels": pick("labels", "JEVH_LABELS_PATH", ["labels.jsonl"], ["labels*.jsonl"]),
        "decide": pick(
            "decide",
            "JEVH_DECIDE_PATH",
            ["decide_questions_dedup.jsonl"],
            ["decide_questions_dedup*.jsonl"],
        ),
        "lane": pick(
            "lane",
            "JEVH_LANE_PATH",
            ["jevh_lane_bank.jsonl", "lane_bank.jsonl"],
            ["jevh_lane_bank*.jsonl", "*lane_bank*.jsonl"],
        ),
        "tokenizer": pick(
            "tokenizer",
            "JEVH_TOKENIZER_PATH",
            ["tokenizer.json", "jevh_student_tokenizer.json"],
            ["jevh_student_tokenizer*.json", "tokenizer.json"],
        ),
    }
    if not paths["tokenizer"].is_file() and tok_default.is_file():
        paths["tokenizer"] = tok_default
    return paths


def _ctx(row: dict[str, Any]) -> str | None:
    c = row.get("context")
    if c is None:
        return None
    if isinstance(c, str):
        s = c.strip()
        return s or None
    return json.dumps(c, ensure_ascii=False)


def _scores(row: dict[str, Any], key: str, n: int) -> list[float] | None:
    s = row.get(key)
    if not isinstance(s, list) or len(s) != n:
        return None
    try:
        out = [float(x) for x in s]
    except (TypeError, ValueError):
        return None
    tot = sum(max(v, 0.0) for v in out)
    if tot <= 0:
        return None
    return [max(v, 0.0) / tot for v in out]


def load_decide_index(path: Path) -> dict[tuple[str, tuple[str, ...]], dict[str, Any]]:
    idx: dict[tuple[str, tuple[str, ...]], dict[str, Any]] = {}
    for row in read_jsonl(path):
        q = (row.get("question") or "").strip()
        opts = [str(o) for o in (row.get("options") or [])]
        if not q or len(opts) < 2:
            continue
        idx[(q, tuple(opts))] = row
    return idx


def load_labels(path: Path, decide_idx: dict | None = None) -> list[Example]:
    out: list[Example] = []
    for row in read_jsonl(path):
        q = (row.get("question") or "").strip()
        opts = [str(o) for o in (row.get("options") or [])]
        if not q or len(opts) < 2:
            continue
        gold = choice_index(row.get("jev_choice"), opts)
        if gold is None:
            continue
        dec = (decide_idx or {}).get((q, tuple(opts)))
        context = _ctx(row) or (dec and _ctx(dec))
        teacher_scores = _scores(row, "teacher_scores", len(opts))
        if teacher_scores is None and dec is not None:
            teacher_scores = _scores(dec, "teacher_scores", len(opts))
        teacher_choice = row.get("model_choice")
        teacher_conf = row.get("model_confidence")
        if dec is not None:
            if teacher_choice is None:
                teacher_choice = dec.get("teacher_choice")
            if teacher_conf is None:
                teacher_conf = dec.get("teacher_confidence")
        teacher_index = choice_index(teacher_choice, opts)
        out.append(
            Example(
                question=q,
                options=opts,
                context=context,
                gold_index=gold,
                teacher_index=teacher_index,
                teacher_scores=teacher_scores,
                jev_confidence=_float(row.get("jev_confidence")),
                teacher_confidence=_float(teacher_conf),
                source="labels",
                n_options=len(opts),
                yesno=is_yesno(opts),
            )
        )
    return out


def load_soft_decide(path: Path, exclude_questions: set[str]) -> list[Example]:
    """Teacher soft targets only. Never treated as gold."""
    out: list[Example] = []
    for row in read_jsonl(path):
        q = (row.get("question") or "").strip()
        if not q or q in exclude_questions:
            continue
        opts = [str(o) for o in (row.get("options") or [])]
        if len(opts) < 2:
            continue
        scores = _scores(row, "teacher_scores", len(opts))
        if scores is None:
            continue
        t_idx = choice_index(row.get("teacher_choice"), opts)
        out.append(
            Example(
                question=q,
                options=opts,
                context=_ctx(row),
                gold_index=None,
                teacher_index=t_idx,
                teacher_scores=scores,
                jev_confidence=None,
                teacher_confidence=_float(row.get("teacher_confidence")),
                source="decide_soft",
                n_options=len(opts),
                yesno=is_yesno(opts),
            )
        )
    return out


def load_lane_bank(path: Path) -> list[Example]:
    out: list[Example] = []
    for row in read_jsonl(path):
        q = (row.get("question") or "").strip()
        opts = [str(o) for o in (row.get("options") or [])]
        if not q or len(opts) < 2:
            continue
        out.append(
            Example(
                question=q,
                options=opts,
                context=_ctx(row),
                gold_index=None,
                teacher_index=None,
                teacher_scores=None,
                jev_confidence=None,
                teacher_confidence=None,
                source="lane_bank",
                n_options=len(opts),
                yesno=is_yesno(opts),
            )
        )
    return out


def _float(x: Any) -> float | None:
    if x is None:
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def option_bucket(n: int) -> str:
    if n <= 2:
        return "2"
    if n == 3:
        return "3"
    if n == 4:
        return "4"
    return "6plus"


def split_by_question(
    examples: list[Example],
    eval_frac: float = EVAL_FRAC,
    seed: int = SEED,
) -> tuple[list[Example], list[Example], dict[str, Any]]:
    """Hold out >= eval_frac of unique questions, stratified by option count."""
    by_q: dict[str, list[Example]] = defaultdict(list)
    for ex in examples:
        by_q[ex.question].append(ex)
    buckets: dict[str, list[str]] = defaultdict(list)
    for q, rows in by_q.items():
        n = rows[0].n_options
        buckets[option_bucket(n)].append(q)
    rng = random.Random(seed)
    eval_qs: set[str] = set()
    split_counts: dict[str, dict[str, int]] = {}
    for bucket, qs in sorted(buckets.items()):
        qs = list(qs)
        rng.shuffle(qs)
        n_eval = max(1, int(round(len(qs) * eval_frac))) if qs else 0
        if len(qs) >= 2 and n_eval >= len(qs):
            n_eval = len(qs) - 1
        eval_qs.update(qs[:n_eval])
        split_counts[bucket] = {"n_questions": len(qs), "n_eval": n_eval, "n_train": len(qs) - n_eval}
    frac = (len(eval_qs) / len(by_q)) if by_q else 0.0
    if frac < eval_frac and by_q:
        remain = [q for q in by_q if q not in eval_qs]
        rng.shuffle(remain)
        need = int((eval_frac - frac) * len(by_q) + 0.9999)
        eval_qs.update(remain[:need])
        frac = len(eval_qs) / len(by_q)
    train, eval_ = [], []
    for q, rows in by_q.items():
        (eval_ if q in eval_qs else train).extend(rows)
    meta = {
        "n_unique_questions": len(by_q),
        "n_eval_questions": len(eval_qs),
        "n_train_questions": len(by_q) - len(eval_qs),
        "eval_frac": frac,
        "n_train_rows": len(train),
        "n_eval_rows": len(eval_),
        "by_option_count": split_counts,
        "seed": seed,
        "eval_yesno_rows": sum(1 for e in eval_ if e.is_binary()),
        "eval_multi_rows": sum(1 for e in eval_ if not e.is_binary()),
        "train_yesno_rows": sum(1 for e in train if e.is_binary()),
        "train_multi_rows": sum(1 for e in train if not e.is_binary()),
        "eval_strict_noul_rows": sum(1 for e in eval_ if e.yesno),
        "train_strict_noul_rows": sum(1 for e in train if e.yesno),
    }
    return train, eval_, meta


def subsample(examples: list[Example], k: int, seed: int) -> list[Example]:
    if k < 0 or k >= len(examples):
        return list(examples)
    rng = random.Random(seed)
    return rng.sample(examples, k)


def dump_split(path: Path, train: list[Example], eval_: list[Example], meta: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "meta": meta,
        "train_questions": sorted({e.question for e in train}),
        "eval_questions": sorted({e.question for e in eval_}),
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def example_to_dict(ex: Example) -> dict[str, Any]:
    return asdict(ex)
