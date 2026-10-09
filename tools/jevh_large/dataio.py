"""Load JEV-H labels / decide logs, split by unique question, encode pairs."""
from __future__ import annotations

import json
import os
import random
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

NOUL_STEXT = {
    "yes": "yes: that is true given the state",
    "no": "no: that is not true given the state",
}

UPLOAD_DIRS = [
    Path(os.environ["JEVH_DATA_DIR"]) if os.environ.get("JEVH_DATA_DIR") else None,
    Path("/home/ubuntu/.cursor/projects/workspace/uploads"),
    Path("/workspace/uploads"),
    Path(__file__).resolve().parents[2] / "uploads",
    Path(__file__).resolve().parent / "data",
]
UPLOAD_DIRS = [p for p in UPLOAD_DIRS if p is not None]


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def find_data_file(stem: str) -> Path:
    """Resolve labels.jsonl / labels_*.jsonl from uploads, env, or bundled samples."""
    names = [stem, stem.replace(".jsonl", "") + ".jsonl"]
    prefixes = {
        "labels.jsonl": "labels",
        "decide_questions_dedup.jsonl": "decide_questions_dedup",
        "jevh_lane_bank.jsonl": "jevh_lane_bank",
    }
    prefix = prefixes.get(stem, Path(stem).stem)
    for folder in UPLOAD_DIRS:
        if not folder.is_dir():
            continue
        exact = folder / stem
        if exact.is_file():
            return exact
        matches = sorted(folder.glob(f"{prefix}*.jsonl"))
        # Prefer the full dump over the bundled sample.
        matches = [m for m in matches if "sample" not in m.name] + [m for m in matches if "sample" in m.name]
        if matches:
            return matches[0]
    raise FileNotFoundError(
        f"Could not find {stem} (prefix {prefix!r}). Set JEVH_DATA_DIR or place files in uploads/. "
        f"Looked in: {UPLOAD_DIRS}"
    )


def norm_label(x: Any) -> str:
    if x is None:
        return ""
    s = str(x).strip().lower()
    if ":" in s:
        s = s.split(":", 1)[0].strip()
    if s.startswith("yes") or s in ("true", "y"):
        return "yes"
    if s.startswith("no") or s in ("false", "n"):
        return "no"
    return s


def is_yesno(options: list[str]) -> bool:
    return len(options) == 2 and set(norm_label(o) for o in options) == {"yes", "no"}


def choice_index(choice: Any, options: list[str]) -> int | None:
    if choice is None:
        return None
    if choice in options:
        return options.index(choice)
    cl = str(choice).strip().lower()
    lowered = [str(o).strip().lower() for o in options]
    if cl in lowered:
        return lowered.index(cl)
    nl = norm_label(choice)
    norms = [norm_label(o) for o in options]
    if nl and norms.count(nl) == 1:
        return norms.index(nl)
    return None


def build_input(question: str, options: list[str], context: Any = None, qtype_req: Any = None) -> tuple[str, str, list[str], bool]:
    labs = [norm_label(o) for o in options]
    yesno = len(options) == 2 and set(labs) == {"yes", "no"}
    if qtype_req in ("choice", "noul", "score"):
        qtype = qtype_req
    else:
        qtype = "noul" if yesno else "choice"
    stexts = [NOUL_STEXT[l] for l in labs] if (qtype == "noul" and yesno) else [str(o) for o in options]
    ctx = context
    if ctx is not None and not isinstance(ctx, str):
        ctx = json.dumps(ctx, ensure_ascii=False)
    state = (ctx or "").strip() or question
    if state.strip() == question.strip():
        text_a = f"[{qtype}] {question}"
    else:
        text_a = f"[{qtype}] {question}\n{state}"
    return qtype, text_a, stexts, yesno


def option_bucket(n: int) -> str:
    if n <= 2:
        return "2"
    if n == 3:
        return "3"
    if n == 4:
        return "4"
    return "6+"


def stratified_question_split(
    questions: list[str],
    n_options: list[int],
    seed: int,
    eval_frac: float = 0.20,
) -> tuple[set[str], set[str]]:
    """Split unique questions with no leakage. Stratify by option-count bucket."""
    by_q: dict[str, int] = {}
    for q, n in zip(questions, n_options):
        by_q.setdefault(q, n)
    by_bucket: dict[str, list[str]] = defaultdict(list)
    for q, n in by_q.items():
        by_bucket[option_bucket(n)].append(q)
    rng = random.Random(seed)
    eval_q: set[str] = set()
    train_q: set[str] = set()
    for bucket in sorted(by_bucket):
        qs = sorted(by_bucket[bucket])
        rng.shuffle(qs)
        n_eval = int(round(len(qs) * eval_frac))
        n_eval = max(1, n_eval) if qs else 0
        n_eval = min(n_eval, max(0, len(qs) - 1)) if len(qs) > 1 else n_eval
        eval_q.update(qs[:n_eval])
        train_q.update(qs[n_eval:])
    if len(eval_q) / max(1, len(by_q)) < 0.15:
        leftovers = sorted(train_q)
        rng.shuffle(leftovers)
        need = int(math_ceil(0.15 * len(by_q))) - len(eval_q)
        for q in leftovers[: max(0, need)]:
            train_q.remove(q)
            eval_q.add(q)
    return train_q, eval_q


def math_ceil(x: float) -> int:
    return int(x) if int(x) == x else int(x) + 1


def load_gold(path: Path) -> list[dict[str, Any]]:
    rows = []
    for raw in _read_jsonl(path):
        options = [str(o) for o in (raw.get("options") or [])]
        question = str(raw.get("question") or "").strip()
        if not question or len(options) < 2:
            continue
        gold_i = choice_index(raw.get("jev_choice"), options)
        if gold_i is None:
            continue
        qtype, text_a, stexts, yesno = build_input(question, options, raw.get("context"), raw.get("qtype"))
        teacher_i = choice_index(raw.get("model_choice"), options)
        rows.append(
            {
                "source": "gold",
                "question": question,
                "context": raw.get("context"),
                "options": options,
                "text_a": text_a,
                "option_texts": stexts,
                "qtype": qtype,
                "yesno": yesno,
                "n_options": len(options),
                "gold_index": gold_i,
                "gold_choice": options[gold_i],
                "teacher_index": teacher_i,
                "teacher_choice": options[teacher_i] if teacher_i is not None else raw.get("model_choice"),
                "teacher_confidence": raw.get("model_confidence"),
                "teacher_scores": None,
                "jev_confidence": raw.get("jev_confidence"),
                "tier": raw.get("tier"),
            }
        )
    return rows


def load_decide(path: Path) -> list[dict[str, Any]]:
    rows = []
    for raw in _read_jsonl(path):
        options = [str(o) for o in (raw.get("options") or [])]
        question = str(raw.get("question") or "").strip()
        if not question or len(options) < 2:
            continue
        qtype, text_a, stexts, yesno = build_input(
            question, options, raw.get("context"), raw.get("student_qtype") or raw.get("qtype")
        )
        scores = raw.get("teacher_scores")
        if scores is not None:
            scores = [float(x) for x in scores]
            if len(scores) != len(options):
                scores = None
        teacher_i = choice_index(raw.get("teacher_choice"), options)
        rows.append(
            {
                "source": "decide",
                "question": question,
                "context": raw.get("context"),
                "options": options,
                "text_a": text_a,
                "option_texts": stexts,
                "qtype": qtype,
                "yesno": yesno,
                "n_options": len(options),
                "gold_index": None,
                "gold_choice": None,
                "teacher_index": teacher_i,
                "teacher_choice": raw.get("teacher_choice"),
                "teacher_confidence": raw.get("teacher_confidence"),
                "teacher_scores": scores,
                "student_choice": raw.get("student_choice"),
                "student_confidence": raw.get("student_confidence"),
            }
        )
    return rows


def load_lane_bank(path: Path) -> list[dict[str, Any]]:
    rows = []
    for raw in _read_jsonl(path):
        options = [str(o) for o in (raw.get("options") or [])]
        question = str(raw.get("question") or "").strip()
        if not question or len(options) < 2:
            continue
        qtype, text_a, stexts, yesno = build_input(question, options, raw.get("context"))
        rows.append(
            {
                "source": "lane_bank",
                "question": question,
                "context": raw.get("context"),
                "options": options,
                "text_a": text_a,
                "option_texts": stexts,
                "qtype": qtype,
                "yesno": yesno,
                "n_options": len(options),
                "gold_index": None,
                "gold_choice": None,
                "teacher_index": None,
                "teacher_choice": None,
                "teacher_confidence": None,
                "teacher_scores": None,
            }
        )
    return rows


def attach_soft_scores(gold_rows: list[dict[str, Any]], decide_rows: list[dict[str, Any]]) -> None:
    by_key: dict[tuple[str, tuple[str, ...]], dict[str, Any]] = {}
    for r in decide_rows:
        if r.get("teacher_scores"):
            by_key[(r["question"], tuple(r["options"]))] = r
    for r in gold_rows:
        hit = by_key.get((r["question"], tuple(r["options"])))
        if hit and hit.get("teacher_scores"):
            r["teacher_scores"] = list(hit["teacher_scores"])


def dedup_records(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: dict[tuple[str, tuple[str, ...]], dict[str, Any]] = {}
    order: list[tuple[str, tuple[str, ...]]] = []
    for r in rows:
        key = (r["question"], tuple(r["options"]))
        if key not in seen:
            order.append(key)
        seen[key] = r
    return [seen[k] for k in order]


def encode_pair(tokenizer: Any, text_a: str, text_b: str, seq_len: int) -> tuple[list[int], list[int]]:
    kwargs = dict(
        truncation="only_first",
        max_length=seq_len,
        padding="max_length",
        return_attention_mask=True,
    )
    try:
        enc = tokenizer(text_a, text_b, **kwargs)
    except Exception:
        kwargs["truncation"] = "longest_first"
        enc = tokenizer(text_a, text_b, **kwargs)
    return list(enc["input_ids"]), list(enc["attention_mask"])


def encode_record(tokenizer: Any, rec: dict[str, Any], seq_len: int) -> dict[str, Any]:
    ids, masks = [], []
    for opt in rec["option_texts"]:
        i, m = encode_pair(tokenizer, rec["text_a"], opt, seq_len)
        ids.append(i)
        masks.append(m)
    rec = dict(rec)
    rec["input_ids"] = ids
    rec["attention_mask"] = masks
    return rec


def iter_minibatches(records: list[dict[str, Any]], rng: random.Random, target_pairs: int = 8) -> Iterable[list[dict[str, Any]]]:
    by_k: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for r in records:
        by_k[r["n_options"]].append(r)
    keys = list(by_k)
    rng.shuffle(keys)
    for k in keys:
        rs = list(by_k[k])
        rng.shuffle(rs)
        bs = max(1, target_pairs // max(1, k))
        for i in range(0, len(rs), bs):
            yield rs[i : i + bs]


def split_report(train_rows: list[dict[str, Any]], eval_rows: list[dict[str, Any]]) -> dict[str, Any]:
    def bag(rows: list[dict[str, Any]]) -> dict[str, int]:
        return {
            "rows": len(rows),
            "unique_questions": len({r["question"] for r in rows}),
            "nopt": dict(Counter(r["n_options"] for r in rows)),
            "yesno": sum(1 for r in rows if r["yesno"]),
            "binary": sum(1 for r in rows if r["n_options"] == 2),
            "multi": sum(1 for r in rows if r["n_options"] > 2),
        }

    train_q = {r["question"] for r in train_rows}
    eval_q = {r["question"] for r in eval_rows}
    return {
        "train": bag(train_rows),
        "eval": bag(eval_rows),
        "eval_frac_questions": len(eval_q) / max(1, len(train_q | eval_q)),
        "leakage_questions": len(train_q & eval_q),
    }
