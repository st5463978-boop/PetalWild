"""Live JEV-H student input format and tokenisation (seq=128).

Mirrors the Pi service in the attached jevh_current_student_reference:
  qtype = noul when the two options normalise to yes/no, else choice
  noul options become the training strings
    "yes: that is true given the state" / "no: that is not true given the state"
  text_a = "[qtype] question" or "[qtype] question\\ncontext"
  each option is text_b; one encoder pass per option; softmax over option logits
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

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


def choice_index(choice: Any, options: list[str]) -> int | None:
    if choice is None:
        return None
    raw = str(choice).strip().lower()
    for i, opt in enumerate(options):
        if str(opt).strip().lower() == raw:
            return i
    gold = norm_label(choice)
    labs = [norm_label(o) for o in options]
    hits = [i for i, lab in enumerate(labs) if lab == gold]
    if len(hits) == 1:
        return hits[0]
    if gold in labs:
        return labs.index(gold)
    return None


def build_input(
    question: str,
    options: list[str],
    context: str | None = None,
    qtype_req: str | None = None,
) -> tuple[str, str, list[str], bool]:
    yesno = is_yesno(options)
    if qtype_req in ("choice", "noul", "score"):
        qtype = qtype_req
    else:
        qtype = "noul" if yesno else "choice"
    labs = [norm_label(o) for o in options]
    if qtype == "noul" and yesno:
        stexts = [NOUL_STEXT[lab] for lab in labs]
    else:
        stexts = [str(o) for o in options]
    state = (context or "").strip() or question
    if state.strip() == question.strip():
        text_a = f"[{qtype}] {question}"
    else:
        text_a = f"[{qtype}] {question}\n{state}"
    return qtype, text_a, stexts, yesno


@dataclass
class EncodedPair:
    input_ids: list[int]
    attention_mask: list[int]
    truncation: str
    n_tokens: int


class StudentTok:
    """tokenizers-only pair encoder. Same contract as app/jevh_tok.py."""

    def __init__(self, path: str, max_len: int = SEQ_LEN):
        from tokenizers import Tokenizer

        self.max_len = max_len
        self.t_first = Tokenizer.from_file(path)
        self.t_longest = Tokenizer.from_file(path)
        pad_id = self.t_first.token_to_id("[PAD]")
        if pad_id is None:
            pad_id = 50283
        self.pad_id = pad_id
        for tok, strat in ((self.t_first, "only_first"), (self.t_longest, "longest_first")):
            tok.enable_truncation(max_length=max_len, strategy=strat)
            tok.enable_padding(length=max_len, pad_id=pad_id, pad_token="[PAD]")

    def encode_pair(self, text_a: str, option: str) -> EncodedPair:
        ids_list, mode = self.encode(text_a, [option])
        ids = ids_list[0]
        mask = [0 if t == self.pad_id else 1 for t in ids]
        return EncodedPair(
            input_ids=ids,
            attention_mask=mask,
            truncation=mode,
            n_tokens=int(sum(mask)),
        )

    def encode(self, text_a: str, options: list[str]) -> tuple[list[list[int]], str]:
        pairs = [(text_a, o) for o in options]
        try:
            enc = self.t_first.encode_batch(pairs)
            mode = "only_first"
        except Exception:
            enc = self.t_longest.encode_batch(pairs)
            mode = "longest_first"
        ids = [list(e.ids) for e in enc]
        for row in ids:
            if len(row) != self.max_len:
                raise RuntimeError(f"expected seq {self.max_len}, got {len(row)}")
        return ids, mode

    def encode_question(
        self,
        question: str,
        options: list[str],
        context: str | None = None,
        qtype_req: str | None = None,
    ) -> tuple[list[list[int]], list[list[int]], str, str]:
        qtype, text_a, stexts, _yesno = build_input(question, options, context, qtype_req)
        ids, mode = self.encode(text_a, stexts)
        masks = [[0 if t == self.pad_id else 1 for t in row] for row in ids]
        return ids, masks, qtype, mode
