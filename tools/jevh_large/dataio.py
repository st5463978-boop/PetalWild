"""Load JEV-H labels / decide logs, split by unique question, encode pairs."""
from __future__ import annotations

import json
import os
import random
import re
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


def _plain_ids(tokenizer: Any, text: str) -> list[int]:
    if hasattr(tokenizer, "encode"):
        try:
            return list(tokenizer.encode(text, add_special_tokens=False))
        except TypeError:
            ids = tokenizer.encode(text)
            return list(ids) if isinstance(ids, (list, tuple)) else list(ids["input_ids"])
    return list(tokenizer(text)["input_ids"])


def _special_ids(tokenizer: Any) -> tuple[int, int, int]:
    cls_id = getattr(tokenizer, "cls_token_id", None)
    sep_id = getattr(tokenizer, "sep_token_id", None)
    pad_id = getattr(tokenizer, "pad_token_id", None)
    if cls_id is None:
        cls_id = 50281
    if sep_id is None:
        sep_id = 50282
    if pad_id is None:
        pad_id = getattr(tokenizer, "pad_id", 50283) or 0
    return int(cls_id), int(sep_id), int(pad_id)


def encode_pair(
    tokenizer: Any,
    text_a: str,
    text_b: str,
    seq_len: int,
    keep_option: bool = True,
) -> tuple[list[int], list[int], dict[str, Any]]:
    """Pack [CLS] text_a [SEP] text_b [SEP]. Prefer keeping the option (text_b).

    Question/context (text_a) is trimmed from the tail first, so a leading
    `[qtype] question` survives longer than trailing context. The option is
    only trimmed (from its tail) if it cannot fit with a small question stub.
    """
    cls_id, sep_id, pad_id = _special_ids(tokenizer)
    a_ids = _plain_ids(tokenizer, text_a)
    b_ids = _plain_ids(tokenizer, text_b)
    raw_a, raw_b = len(a_ids), len(b_ids)
    budget = max(1, seq_len - 3)
    min_a = min(8, len(a_ids), budget // 4) if keep_option else budget // 2
    if keep_option:
        max_b = min(len(b_ids), max(1, budget - min_a))
        b_ids = b_ids[:max_b]
        a_ids = a_ids[: max(0, budget - len(b_ids))]
    else:
        a_ids = a_ids[: budget]
        b_ids = b_ids[: max(0, budget - len(a_ids))]
    ids = [cls_id] + a_ids + [sep_id] + b_ids + [sep_id]
    if len(ids) > seq_len:
        ids = ids[: seq_len - 1] + [sep_id]
    mask = [1] * len(ids) + [0] * (seq_len - len(ids))
    ids = ids + [pad_id] * (seq_len - len(ids))
    info = {
        "raw_a": raw_a,
        "raw_b": raw_b,
        "kept_a": len(a_ids),
        "kept_b": len(b_ids),
        "pair_raw": raw_a + raw_b + 3,
        "truncated": (raw_a + raw_b + 3) > seq_len,
        "truncated_a": raw_a > len(a_ids),
        "truncated_b": raw_b > len(b_ids),
    }
    return ids, mask, info


def encode_record(tokenizer: Any, rec: dict[str, Any], seq_len: int, keep_option: bool = True) -> dict[str, Any]:
    ids, masks, flags = [], [], []
    for opt in rec["option_texts"]:
        i, m, info = encode_pair(tokenizer, rec["text_a"], opt, seq_len, keep_option=keep_option)
        ids.append(i)
        masks.append(m)
        flags.append(info)
    rec = dict(rec)
    rec["input_ids"] = ids
    rec["attention_mask"] = masks
    rec["truncation"] = flags
    rec["truncated"] = any(f["truncated"] for f in flags)
    rec["truncated_option"] = any(f["truncated_b"] for f in flags)
    return rec


def truncation_report(tokenizer: Any, rows: list[dict[str, Any]], seq_lens: list[int]) -> dict[str, Any]:
    """Untruncated pair lengths vs each seq_len, 2-way vs multi."""
    def bag():
        return {"n": 0, "trunc": 0, "trunc_option": 0, "max_pair": 0, "p90_pair": 0}

    out: dict[str, Any] = {"n": len(rows), "by_seq": {}}
    raw_lens: dict[str, list[int]] = {"all": [], "binary_2way": [], "multi_choice": []}
    for r in rows:
        pair = 0
        opt_max = 0
        for opt in r["option_texts"]:
            a = len(_plain_ids(tokenizer, r["text_a"]))
            b = len(_plain_ids(tokenizer, opt))
            pair = max(pair, a + b + 3)
            opt_max = max(opt_max, b)
        tag = "binary_2way" if r["n_options"] == 2 else "multi_choice"
        raw_lens["all"].append(pair)
        raw_lens[tag].append(pair)
        r["_pair_raw"] = pair
        r["_opt_raw"] = opt_max
    for seq in seq_lens:
        block = {"all": bag(), "binary_2way": bag(), "multi_choice": bag()}
        for r in rows:
            tag = "binary_2way" if r["n_options"] == 2 else "multi_choice"
            for key in ("all", tag):
                block[key]["n"] += 1
                block[key]["max_pair"] = max(block[key]["max_pair"], r["_pair_raw"])
                if r["_pair_raw"] > seq:
                    block[key]["trunc"] += 1
                if r["_opt_raw"] > seq - 3:
                    block[key]["trunc_option"] += 1
        for key, lens in raw_lens.items():
            if not lens:
                continue
            sl = sorted(lens)
            block[key]["p90_pair"] = sl[min(len(sl) - 1, int(len(sl) * 0.9))]
            block[key]["trunc_rate"] = block[key]["trunc"] / max(1, block[key]["n"])
        out["by_seq"][str(seq)] = block
    for r in rows:
        r.pop("_pair_raw", None)
        r.pop("_opt_raw", None)
    return out


_NAME_RE = re.compile(r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b")
_NUM_RE = re.compile(r"\d+(?:\.\d+)?")
_QUOTE_RE = re.compile(r"['\"“”][^'\"“”]{1,}['\"“”]")
_SPACE_RE = re.compile(r"\s+")


def normalize_template_text(question: str) -> str:
    """Slot numbers, multi-word names, and quoted strings so near-dupes share a skeleton."""
    s = question.strip()
    s = _NAME_RE.sub("NAME", s)
    s = _NUM_RE.sub("#", s)
    s = _QUOTE_RE.sub("'#'", s)
    s = s.lower()
    return _SPACE_RE.sub(" ", s).strip()


def template_key(question: str, n_options: int, head_words: int = 10) -> tuple[int, str]:
    words = normalize_template_text(question).split()
    head = " ".join(words[:head_words])
    return (int(n_options), head)


def stratified_template_split(
    records: list[dict[str, Any]],
    seed: int,
    eval_frac: float = 0.20,
) -> tuple[set[str], set[str], dict[str, Any]]:
    """Assign whole question templates to train or eval. No template spans both."""
    groups: dict[tuple[int, str], list[str]] = defaultdict(list)
    nopt_of: dict[str, int] = {}
    for r in records:
        q = r["question"]
        nopt_of[q] = r["n_options"]
        groups[template_key(q, r["n_options"])].append(q)
    # unique questions per group
    group_qs = {k: sorted(set(v)) for k, v in groups.items()}
    rng = random.Random(seed)
    # stratify groups by option-count of the key and size bucket
    buckets: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for key, qs in group_qs.items():
        nopt, _ = key
        size = len(qs)
        if size >= 100:
            sb = "xl"
        elif size >= 10:
            sb = "l"
        elif size >= 2:
            sb = "m"
        else:
            sb = "s"
        buckets[f"{option_bucket(nopt)}-{sb}"].append(key)

    eval_q: set[str] = set()
    train_q: set[str] = set()
    n_all = len(nopt_of)
    target = max(int(round(n_all * eval_frac)), int(math_ceil(0.15 * n_all)))

    # Fill eval with smaller groups first so one giant family cannot consume the whole eval.
    ordered: list[tuple[int, str]] = []
    for b in sorted(buckets):
        keys = list(buckets[b])
        rng.shuffle(keys)
        keys.sort(key=lambda k: len(group_qs[k]))  # small first, still shuffled within size via rng then stable-ish
        ordered.extend(keys)
    rng2 = random.Random(seed + 1)
    # re-shuffle small/medium only; keep xl for train if they would blow past target
    small = [k for k in ordered if len(group_qs[k]) < 100]
    xl = [k for k in ordered if len(group_qs[k]) >= 100]
    rng2.shuffle(small)
    for key in small:
        qs = group_qs[key]
        if len(eval_q) < target:
            eval_q.update(qs)
        else:
            train_q.update(qs)
    for key in xl:
        train_q.update(group_qs[key])
    # if eval too small, move some train groups over
    if len(eval_q) / max(1, n_all) < 0.15:
        leftovers = sorted(train_q)
        # move whole templates
        by_t: dict[tuple[int, str], list[str]] = defaultdict(list)
        for q in leftovers:
            by_t[template_key(q, nopt_of[q])].append(q)
        for key, qs in sorted(by_t.items(), key=lambda kv: len(kv[1])):
            if len(eval_q) / max(1, n_all) >= 0.15:
                break
            if len(qs) >= 100:
                continue
            for q in qs:
                train_q.discard(q)
                eval_q.add(q)
    overlap = {template_key(q, nopt_of[q]) for q in train_q} & {template_key(q, nopt_of[q]) for q in eval_q}
    assert not overlap, f"template leakage {len(overlap)}"
    info = {
        "n_templates": len(group_qs),
        "n_questions": n_all,
        "eval_questions": len(eval_q),
        "train_questions": len(train_q),
        "eval_frac": len(eval_q) / max(1, n_all),
        "leakage_templates": 0,
        "xl_templates_in_train": len(xl),
        "group_size_hist": dict(Counter(len(v) for v in group_qs.values())),
    }
    return train_q, eval_q, info


def classify_eval_by_template(
    train_rows: list[dict[str, Any]],
    eval_rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    """Split eval rows into template-seen-in-train vs unseen (no near-dup leakage)."""
    train_keys = {template_key(r["question"], r["n_options"]) for r in train_rows}
    seen, unseen = [], []
    for r in eval_rows:
        k = template_key(r["question"], r["n_options"])
        rec = dict(r)
        rec["template_key"] = list(k)
        if k in train_keys:
            seen.append(rec)
        else:
            unseen.append(rec)
    info = {
        "eval_n": len(eval_rows),
        "template_seen_n": len(seen),
        "template_unseen_n": len(unseen),
        "template_seen_frac": len(seen) / max(1, len(eval_rows)),
        "train_templates": len(train_keys),
        "seen_binary": sum(1 for r in seen if r["n_options"] == 2),
        "seen_multi": sum(1 for r in seen if r["n_options"] > 2),
        "unseen_binary": sum(1 for r in unseen if r["n_options"] == 2),
        "unseen_multi": sum(1 for r in unseen if r["n_options"] > 2),
    }
    return seen, unseen, info


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
