"""Live JEV-H student input format: [qtype] question (+ context) paired with each option."""
from __future__ import annotations

from typing import Any

from tokenizers import Tokenizer

SEQ_LEN = 128
NOUL_STEXT = {
    "yes": "yes: that is true given the state",
    "no": "no: that is not true given the state",
}


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


class StudentTok:
    """tokenizers-only pair encoder used by the live :8771 service (seq 128)."""

    def __init__(self, path: str, max_len: int = SEQ_LEN):
        self.max_len = max_len
        self.t_first = Tokenizer.from_file(path)
        self.t_longest = Tokenizer.from_file(path)
        pad_id = self.t_first.token_to_id("[PAD]")
        if pad_id is None:
            raise RuntimeError("tokenizer has no [PAD] token")
        self.pad_id = pad_id
        for tok, strat in ((self.t_first, "only_first"), (self.t_longest, "longest_first")):
            tok.enable_truncation(max_length=max_len, strategy=strat)
            tok.enable_padding(length=max_len, pad_id=pad_id, pad_token="[PAD]")

    def encode(self, text_a: str, options: list[str]) -> tuple[list[list[int]], list[list[int]], str]:
        pairs = [(text_a, o) for o in options]
        try:
            enc = self.t_first.encode_batch(pairs)
            mode = "only_first"
        except Exception:
            enc = self.t_longest.encode_batch(pairs)
            mode = "longest_first"
        ids = [e.ids for e in enc]
        masks = [e.attention_mask for e in enc]
        return ids, masks, mode
