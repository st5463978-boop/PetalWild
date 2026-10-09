"""Live JEV-H student input format: [qtype] question (+ context) paired with each option."""
from __future__ import annotations

from typing import Any

from tokenizers import Tokenizer

SEQ_LEN = 128
CLS_ID = 50281
SEP_ID = 50282
NOUL_STEXT = {
    "yes": "yes: that is true given the state",
    "no": "no: that is not true given the state",
}
MIN_QUESTION_TOKS = 8


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
    labs = [norm_label(o) for o in options]
    return len(options) == 2 and set(labs) == {"yes", "no"}


def build_input(
    question: str,
    options: list[str],
    context: str | None = None,
    qtype_req: Any = None,
) -> tuple[str, str, list[str], bool]:
    """Match jevh_service.build_input. Returns qtype, text_a, option_texts, yesno."""
    labs = [norm_label(o) for o in options]
    yesno = len(options) == 2 and set(labs) == {"yes", "no"}
    if qtype_req in ("choice", "noul", "score"):
        qtype = qtype_req
    else:
        qtype = "noul" if yesno else "choice"
    if qtype == "noul" and yesno:
        stexts = [NOUL_STEXT[l] for l in labs]
    else:
        stexts = [str(o) for o in options]
    state = (context or "").strip() or question
    if state.strip() == question.strip():
        text_a = f"[{qtype}] {question}"
    else:
        text_a = f"[{qtype}] {question}\n{state}"
    return qtype, text_a, stexts, yesno


def gold_index(options: list[str], choice: Any) -> int:
    if choice in options:
        return options.index(choice)
    want = norm_label(choice)
    labs = [norm_label(o) for o in options]
    if want in labs:
        return labs.index(want)
    raise ValueError(f"choice {choice!r} not in options {options!r}")


def _core_ids(tok: Tokenizer, text: str) -> list[int]:
    """Strip [CLS] … [SEP] from a single-sequence encode."""
    ids = tok.encode(text).ids
    if ids and ids[0] == CLS_ID:
        ids = ids[1:]
    if ids and ids[-1] == SEP_ID:
        ids = ids[:-1]
    return ids


class StudentTok:
    """tokenizers-only pair encoder used by the live :8771 service (seq 128).

    Default path matches live `only_first` pair encoding. If the pair would
    exceed seq128, keep the option (text_b) and trim question/context (text_a).
    """

    def __init__(self, path: str, max_len: int = SEQ_LEN):
        self.max_len = max_len
        self.t_first = Tokenizer.from_file(path)
        self.t_longest = Tokenizer.from_file(path)
        self.t_raw = Tokenizer.from_file(path)
        self.t_raw.no_truncation()
        self.t_raw.no_padding()
        pad_id = self.t_first.token_to_id("[PAD]")
        if pad_id is None:
            raise RuntimeError("tokenizer has no [PAD] token")
        self.pad_id = pad_id
        for tok, strat in ((self.t_first, "only_first"), (self.t_longest, "longest_first")):
            tok.enable_truncation(max_length=max_len, strategy=strat)
            tok.enable_padding(length=max_len, pad_id=pad_id, pad_token="[PAD]")

    def true_pair_len(self, text_a: str, option: str) -> int:
        return len(self.t_raw.encode(text_a, option).ids)

    def encode(self, text_a: str, options: list[str]) -> tuple[list[list[int]], list[list[int]], str, list[dict]]:
        ids: list[list[int]] = []
        masks: list[list[int]] = []
        stats: list[dict] = []
        any_keep = False
        for opt in options:
            true_n = self.true_pair_len(text_a, opt)
            if true_n <= self.max_len:
                try:
                    enc = self.t_first.encode(text_a, opt)
                    mode = "only_first"
                except Exception:
                    enc = self.t_longest.encode(text_a, opt)
                    mode = "longest_first"
                ids.append(enc.ids)
                masks.append(enc.attention_mask)
                stats.append(
                    {
                        "true_len": true_n,
                        "overflow": False,
                        "trimmed_question": False,
                        "trimmed_option": False,
                        "mode": mode,
                    }
                )
            else:
                any_keep = True
                row_ids, row_mask, st = self._keep_option(text_a, opt, true_n)
                ids.append(row_ids)
                masks.append(row_mask)
                stats.append(st)
        mode = "keep_option" if any_keep else "only_first"
        return ids, masks, mode, stats

    def _keep_option(self, text_a: str, option: str, true_n: int) -> tuple[list[int], list[int], dict]:
        a = _core_ids(self.t_raw, text_a)
        b = _core_ids(self.t_raw, option)
        room = self.max_len - 3  # [CLS] A [SEP] B [SEP]
        min_a = min(MIN_QUESTION_TOKS, max(len(a), 1), room - 1)
        trimmed_o = False
        if len(b) > room - min_a:
            b = b[: room - min_a]
            trimmed_o = True
        a_budget = room - len(b)
        trimmed_q = len(a) > a_budget
        if trimmed_q:
            a = a[:a_budget]
        packed = [CLS_ID] + a + [SEP_ID] + b + [SEP_ID]
        if len(packed) > self.max_len:
            packed = packed[: self.max_len]
        mask = [1] * len(packed) + [0] * (self.max_len - len(packed))
        packed = packed + [self.pad_id] * (self.max_len - len(packed))
        return packed, mask, {
            "true_len": true_n,
            "overflow": True,
            "trimmed_question": trimmed_q,
            "trimmed_option": trimmed_o,
            "mode": "keep_option",
        }
