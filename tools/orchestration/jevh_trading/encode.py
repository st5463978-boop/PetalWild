"""JEV-H pair encoding: text_a = '[choice] question\\nstate', text_b = option text.

Matches the live student wrapper (seq 128). Default is only_first; if the pair
would overflow, keep the option (text_b) and trim question/context (68m-v5
keep_option). Copied in spirit from tools/orchestration/jevh_68m_v5/encode.py
on cursor/jevh-variant-68m-v5-f666 (not merged).
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import numpy as np

from .config import CLS_ID, PAD_ID, SEQ_LEN, SEP_ID
from .paths import tokenizer_path

MIN_QUESTION_TOKS = 8


def _core_ids(tok, text: str) -> list[int]:
    ids = tok.encode(text).ids
    if ids and ids[0] == CLS_ID:
        ids = ids[1:]
    if ids and ids[-1] == SEP_ID:
        ids = ids[:-1]
    return ids


class StudentTok:
    """tokenizers-only pair encoder used by the live :8771 service (seq 128)."""

    def __init__(self, path: str, max_len: int = SEQ_LEN):
        from tokenizers import Tokenizer

        self.max_len = max_len
        self.t_first = Tokenizer.from_file(path)
        self.t_longest = Tokenizer.from_file(path)
        self.t_raw = Tokenizer.from_file(path)
        self.t_raw.no_truncation()
        self.t_raw.no_padding()
        pad_id = self.t_first.token_to_id("[PAD]")
        if pad_id is None:
            pad_id = PAD_ID
        self.pad_id = int(pad_id)
        for tok, strat in ((self.t_first, "only_first"), (self.t_longest, "longest_first")):
            tok.enable_truncation(max_length=max_len, strategy=strat)
            tok.enable_padding(length=max_len, pad_id=self.pad_id, pad_token="[PAD]")

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
                ids.append(list(enc.ids))
                masks.append(list(enc.attention_mask))
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


@lru_cache(maxsize=4)
def load_student_tok(path: str | None = None, max_len: int = SEQ_LEN) -> StudentTok:
    p = Path(path) if path else tokenizer_path()
    return StudentTok(str(p), max_len)


@lru_cache(maxsize=1)
def load_tokenizer(path: str | None = None):
    """Back-compat: (t_first, t_long, pad_id) like round 1."""
    tok = load_student_tok(path)
    return tok.t_first, tok.t_longest, tok.pad_id


def encode_pair(text_a: str, option: str, tok_path: str | None = None) -> tuple[list[int], list[int], str]:
    tok = load_student_tok(tok_path)
    ids, mask, mode, _stats = tok.encode(text_a, [option])
    if len(ids[0]) != SEQ_LEN:
        raise RuntimeError(f"expected seq {SEQ_LEN}, got {len(ids[0])}")
    return ids[0], mask[0], mode


def encode_menu(text_a: str, options: list[str], tok_path: str | None = None, max_len: int = SEQ_LEN) -> dict[str, Any]:
    tok = load_student_tok(tok_path, max_len)
    ids, masks, mode, stats = tok.encode(text_a, options)
    return {
        "input_ids": np.asarray(ids, dtype=np.int64),
        "attention_mask": np.asarray(masks, dtype=np.int64),
        "n_options": np.int64(len(options)),
        "mode": mode,
        "truncation": stats,
    }


def encode_example(ex, tok_path: str | None = None) -> dict[str, np.ndarray]:
    opts = [o.text if hasattr(o, "text") else str(o) for o in ex.options]
    packed = encode_menu(ex.text_a, opts, tok_path)
    packed["gold_index"] = np.int64(ex.gold_index)
    return packed
