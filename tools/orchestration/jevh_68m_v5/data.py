"""Load JEV-H labels / decide logs and split by unique question or template."""
from __future__ import annotations

import gzip
import json
import math
import os
import random
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from encode import StudentTok, build_input, gold_index

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
DEFAULT_UPLOADS = Path("/home/ubuntu/.cursor/projects/workspace/uploads")
EVAL_FRAC = 0.15
DEV_FRAC = 0.15
SEED = 42
CONF_DISAGREE = 0.65

_NUM = re.compile(r"\b\d+(?:\.\d+)?\b")
_QUOT1 = re.compile(r"'[^']{0,160}'")
_QUOT2 = re.compile(r'"[^"]{0,160}"')
_SNAKE = re.compile(r"\b[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+\b")
_NAME = re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b")
_WORKER = re.compile(r"\bworker\s+\S+", re.I)
_SOURCE = re.compile(r"\bsource\s+\S+", re.I)
_PRESENT = re.compile(r"\b[A-Za-z][A-Za-z'-]+\s+is present and is not assigned")
_MAY_UPTO = re.compile(r"\bmay\s+[\w\s]+?\s+up to <NUM>\s+\w+", re.I)
_PROPOSED = re.compile(r"\bthe proposed action is <NUM>\s+\w+", re.I)
_REPORTS = re.compile(r"\breports\s+<ID>=<NUM>", re.I)


def template_key(question: str) -> str:
    """Normalize numbers, names, and entities so near-duplicate questions share a template."""
    s = (question or "").strip()
    s = _QUOT1.sub("<Q>", s)
    s = _QUOT2.sub("<Q>", s)
    s = _NUM.sub("<NUM>", s)
    s = _WORKER.sub("worker <NAME>", s)
    s = _SOURCE.sub("source <ID>", s)
    s = _PRESENT.sub("<NAME> is present and is not assigned", s)
    s = _NAME.sub("<NAME>", s)
    s = _SNAKE.sub("<ID>", s)
    s = _MAY_UPTO.sub("may <ACT> up to <NUM> <UNIT>", s)
    s = _PROPOSED.sub("the proposed action is <NUM> <UNIT>", s)
    s = _REPORTS.sub("reports <ID>=<NUM>", s)
    s = s.lower()
    s = re.sub(r"\s+", " ", s).strip()
    return s


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
    extra = DATA_DIR / "external" / bundled
    if extra.is_file():
        return extra
    if required:
        raise FileNotFoundError(f"{env_name}: no file (looked at ${env_name}, {uploads}, {bundled_path})")
    return None


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if str(path).endswith(".gz"):
        fh = gzip.open(path, "rt", encoding="utf-8")
    else:
        fh = path.open(encoding="utf-8")
    with fh as f:
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
        "large_soft": resolve_file(
            "JEVH_LARGE_SOFT_PATH",
            "jevh_large_soft_on_decide_questions_dedup.jsonl.gz",
            ["jevh_large_soft_on_decide*.jsonl.gz", "jevh_large_soft*.jsonl.gz"],
            required=False,
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


def template_grouped_split(
    questions: list[str],
    n_opts: dict[str, int],
    templates: dict[str, str] | None = None,
    seed: int = SEED,
    eval_frac: float = EVAL_FRAC,
    dev_frac: float = DEV_FRAC,
) -> dict[str, str]:
    """Split by template group so a template never appears in two splits. Eval >= 15% of questions."""
    rng = random.Random(seed)
    tmpl = templates or {q: template_key(q) for q in questions}
    groups: dict[str, list[str]] = defaultdict(list)
    for q in questions:
        groups[tmpl[q]].append(q)
    by_b: dict[str, list[str]] = defaultdict(list)
    for t, qs in groups.items():
        bucket = n_options_bucket(n_opts[qs[0]])
        by_b[bucket].append(t)
    assign_t: dict[str, str] = {}
    for bucket, ts in sorted(by_b.items()):
        rng.shuffle(ts)
        # smallest groups first so a giant family (e.g. modulo-slot) stays in train
        ts.sort(key=lambda t: len(groups[t]))
        n_q_b = sum(len(groups[t]) for t in ts)
        need_e = int(math.ceil(n_q_b * eval_frac)) if n_q_b else 0
        need_d = int(math.ceil(n_q_b * dev_frac)) if n_q_b else 0
        got_e = got_d = 0
        for t in ts:
            n = len(groups[t])
            if got_e < need_e:
                assign_t[t] = "eval"
                got_e += n
            elif got_d < need_d:
                assign_t[t] = "dev"
                got_d += n
            else:
                assign_t[t] = "train"
        # keep at least one train group when possible (prefer keeping the largest)
        if all(assign_t.get(t) != "train" for t in ts) and len(ts) >= 2:
            for t in reversed(ts):
                if assign_t[t] != "train" and len(groups[t]) < n_q_b:
                    assign_t[t] = "train"
                    break
    assign = {q: assign_t[tmpl[q]] for q in questions}
    n_q = len(questions)
    n_eval_q = sum(1 for s in assign.values() if s == "eval")
    need = int(math.ceil(n_q * eval_frac))
    if n_eval_q < need:
        # move whole train templates into eval until we hit the floor (smallest first)
        train_t = [t for t, s in assign_t.items() if s == "train"]
        rng.shuffle(train_t)
        train_t.sort(key=lambda t: len(groups[t]))
        for t in train_t:
            if n_eval_q >= need:
                break
            assign_t[t] = "eval"
            n_eval_q += len(groups[t])
        assign = {q: assign_t[tmpl[q]] for q in questions}
    return assign


def _choice_index(options: list[str], choice: Any) -> int | None:
    if choice is None:
        return None
    try:
        return gold_index(options, choice)
    except ValueError:
        return None


def blend_soft(qwen: list[float] | None, large: list[float] | None) -> tuple[list[float] | None, str]:
    """Blend Qwen3 and JEV-H-large distributions. Large gets more weight on disagreement."""
    if large is None and qwen is None:
        return None, "none"
    if large is None:
        s = sum(qwen) or 1.0
        return [float(x) / s for x in qwen], "qwen"
    if qwen is None:
        s = sum(large) or 1.0
        return [float(x) / s for x in large], "large"
    if len(qwen) != len(large):
        s = sum(large) or 1.0
        return [float(x) / s for x in large], "large"
    qi = max(range(len(qwen)), key=lambda i: qwen[i])
    li = max(range(len(large)), key=lambda i: large[i])
    if qi == li:
        w_l, w_q, tag = 0.65, 0.35, "agree"
    else:
        w_l, w_q, tag = 0.80, 0.20, "disagree"
    mix = [w_l * float(a) + w_q * float(b) for a, b in zip(large, qwen)]
    z = sum(mix) or 1.0
    return [x / z for x in mix], tag


def load_large_index(rows: list[dict[str, Any]]) -> dict[tuple[str, tuple[str, ...]], dict[str, Any]]:
    out: dict[tuple[str, tuple[str, ...]], dict[str, Any]] = {}
    for r in rows:
        q = str(r.get("question") or "").strip()
        opts = tuple(str(o) for o in (r.get("options") or []))
        if q and len(opts) >= 2 and r.get("large_scores"):
            out[(q, opts)] = r
    return out


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
                "template": template_key(q),
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


def examples_from_decide(
    rows: list[dict[str, Any]],
    eval_dev_questions: set[str],
    large_index: dict[tuple[str, tuple[str, ...]], dict[str, Any]] | None = None,
    eval_dev_templates: set[str] | None = None,
) -> list[dict[str, Any]]:
    """Soft-label / unlabeled rows. Never gold. Skip eval/dev questions and templates."""
    out = []
    large_index = large_index or {}
    skip_tmpl = eval_dev_templates or set()
    for i, r in enumerate(rows):
        q = str(r.get("question") or "").strip()
        if not q or q in eval_dev_questions:
            continue
        tmpl = template_key(q)
        if tmpl in skip_tmpl:
            continue
        options = [str(o) for o in (r.get("options") or [])]
        if len(options) < 2:
            continue
        qwen_scores = r.get("teacher_scores")
        if qwen_scores is not None:
            qwen_scores = [float(x) for x in qwen_scores]
            if len(qwen_scores) != len(options):
                qwen_scores = None
        lr = large_index.get((q, tuple(options)))
        large_scores = None
        if lr and lr.get("large_scores") and len(lr["large_scores"]) == len(options):
            large_scores = [float(x) for x in lr["large_scores"]]
        blended, tag = blend_soft(qwen_scores, large_scores)
        if blended is None:
            continue
        tchoice = r.get("teacher_choice")
        teacher_i = _choice_index(options, tchoice) if tchoice is not None else None
        qtype, text_a, stexts, yesno = build_input(q, options, r.get("context"), r.get("student_qtype") or r.get("qtype"))
        out.append(
            {
                "id": f"decide-{i}",
                "source": "decide",
                "question": q,
                "template": tmpl,
                "options": options,
                "option_texts": stexts,
                "text_a": text_a,
                "qtype": qtype,
                "yesno": yesno,
                "gold": None,
                "n_options": len(options),
                "teacher_index": teacher_i,
                "teacher_scores": blended,
                "teacher_choice": tchoice,
                "blend": tag,
                "qwen_scores": qwen_scores,
                "large_scores": large_scores,
                "teacher_confidence": float(r.get("teacher_confidence") or 0.0),
                "student_choice": r.get("student_choice"),
                "student_confidence": r.get("student_confidence"),
                "student_scores": r.get("student_scores"),
                "weight": 0.5 if tag in ("large", "agree") else 0.35,
                "kind": "kd",
            }
        )
    return out


def attach_large_to_gold(gold: list[dict[str, Any]], large_index: dict) -> None:
    for ex in gold:
        lr = large_index.get((ex["question"], tuple(ex["options"])))
        if not lr:
            continue
        ls = lr.get("large_scores")
        if not ls or len(ls) != ex["n_options"]:
            continue
        qwen = None
        # teacher_confidence lives on the label; we don't always have qwen scores there
        ex["large_scores"] = [float(x) for x in ls]
        ex["large_choice"] = lr.get("large_choice")
        ex["large_index"] = _choice_index(ex["options"], lr.get("large_choice"))
        blended, tag = blend_soft(qwen, ex["large_scores"])
        ex["blend_scores"] = blended
        ex["blend"] = tag


def tokenize_example(tok: StudentTok, ex: dict[str, Any]) -> dict[str, Any]:
    ids, masks, mode, stats = tok.encode(ex["text_a"], ex["option_texts"])
    ex = dict(ex)
    ex["input_ids"] = ids
    ex["attention_mask"] = masks
    ex["truncation"] = mode
    ex["tok_stats"] = stats
    return ex


def truncation_report(examples: list[dict[str, Any]]) -> dict[str, Any]:
    n_pair = n_over = n_trim_q = n_trim_o = 0
    two_over = two_n = 0
    for ex in examples:
        stats = ex.get("tok_stats") or []
        is2 = ex["n_options"] == 2
        if is2:
            two_n += 1
        row_over = False
        for st in stats:
            n_pair += 1
            if st.get("overflow") or (st.get("true_len") or 0) > 128:
                n_over += 1
                row_over = True
            if st.get("trimmed_question"):
                n_trim_q += 1
            if st.get("trimmed_option"):
                n_trim_o += 1
        if is2 and row_over:
            two_over += 1
    return {
        "pairs": n_pair,
        "pairs_true_len_gt_128": n_over,
        "pair_overflow_rate": n_over / n_pair if n_pair else 0.0,
        "trimmed_question_pairs": n_trim_q,
        "trimmed_option_pairs": n_trim_o,
        "two_way_rows": two_n,
        "two_way_rows_overflow": two_over,
        "two_way_overflow_rate": two_over / two_n if two_n else 0.0,
    }


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
        ex["student_choice"] = r.get("student_choice")
        ex["student_confidence"] = r.get("student_confidence")
        ex["student_scores"] = r.get("student_scores")
        ex["student_index"] = _choice_index(ex["options"], r.get("student_choice"))
