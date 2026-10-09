"""JEV-H pair encoding: text_a = '[choice] question\\nstate', text_b = option text.

Matches the live student wrapper (seq 128, only_first then longest_first, max_length pad).
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import numpy as np

from .config import PAD_ID, SEQ_LEN
from .dataset import Example
from .paths import tokenizer_path


@lru_cache(maxsize=1)
def load_tokenizer(path: str | None = None):
    from tokenizers import Tokenizer

    p = Path(path) if path else tokenizer_path()
    t_first = Tokenizer.from_file(str(p))
    t_long = Tokenizer.from_file(str(p))
    pad_id = t_first.token_to_id("[PAD]")
    if pad_id is None:
        pad_id = PAD_ID
    for t, strat in ((t_first, "only_first"), (t_long, "longest_first")):
        t.enable_truncation(max_length=SEQ_LEN, strategy=strat)
        t.enable_padding(length=SEQ_LEN, pad_id=pad_id, pad_token="[PAD]")
    return t_first, t_long, int(pad_id)


def encode_pair(text_a: str, option: str, tok_path: str | None = None) -> tuple[list[int], list[int], str]:
    t_first, t_long, _pad = load_tokenizer(tok_path)
    try:
        enc = t_first.encode(text_a, option)
        mode = "only_first"
    except Exception:
        enc = t_long.encode(text_a, option)
        mode = "longest_first"
    ids = list(enc.ids)
    mask = list(enc.attention_mask)
    if len(ids) != SEQ_LEN:
        raise RuntimeError(f"expected seq {SEQ_LEN}, got {len(ids)}")
    return ids, mask, mode


def encode_example(ex: Example, tok_path: str | None = None) -> dict[str, np.ndarray]:
    ids, masks = [], []
    for opt in ex.options:
        i, m, _ = encode_pair(ex.text_a, opt.text, tok_path)
        ids.append(i)
        masks.append(m)
    return {
        "input_ids": np.asarray(ids, dtype=np.int64),
        "attention_mask": np.asarray(masks, dtype=np.int64),
        "gold_index": np.int64(ex.gold_index),
        "n_options": np.int64(len(ex.options)),
    }
