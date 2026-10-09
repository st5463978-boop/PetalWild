#!/usr/bin/env python3
"""Fast checks: question split leakage, static ONNX, attention_mask effect."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from dataio import (  # noqa: E402
    encode_pair,
    normalize_template_text,
    stratified_question_split,
    stratified_template_split,
    template_key,
)
from model import EttinCfg, PairScorer  # noqa: E402
from onnx_export import assert_mask_affects_output, export_static_onnx, verify_parity  # noqa: E402


def test_split_no_leakage() -> None:
    questions, nopts = [], []
    for i in range(80):
        questions.append(f"q2-{i}")
        nopts.append(2)
    for i in range(120):
        questions.append(f"q4-{i}")
        nopts.append(4)
    # duplicate rows of the same question must not straddle the split
    questions += ["q4-0", "q4-0"]
    nopts += [4, 4]
    train_q, eval_q = stratified_question_split(questions, nopts, seed=42, eval_frac=0.2)
    assert not (train_q & eval_q)
    n_unique = len(set(questions))
    assert len(train_q | eval_q) == n_unique
    assert len(eval_q) / n_unique >= 0.15


def test_static_onnx_tiny(tmp_path: Path | None = None) -> None:
    import torch

    tmp_path = tmp_path or (HERE / "artifacts")
    tmp_path.mkdir(parents=True, exist_ok=True)
    seq = 32
    cfg = EttinCfg().tiny()
    model = PairScorer(cfg, seq, export_batch=1).eval()
    torch.manual_seed(0)
    recs = []
    for _ in range(4):
        ids = torch.randint(1, 50, (2, seq)).tolist()
        mask = torch.ones(2, seq, dtype=torch.long).tolist()
        for row in mask:
            for j in range(seq // 2, seq):
                row[j] = 0
        recs.append({"input_ids": ids, "attention_mask": mask, "n_options": 2})
    mask_info = assert_mask_affects_output(model, seq)
    assert mask_info["ok"], mask_info
    path = tmp_path / "tiny_seq32.onnx"
    info = export_static_onnx(model, path, seq, opset=17)
    assert info["ok"], info["issues"]
    assert info["attention_mask_used"]
    assert info["hard_forbidden_ops"] == []
    parity = verify_parity(model, path, recs, max_pairs=8)
    assert parity["ok"], parity


def test_keep_option_truncation() -> None:
    class FakeTok:
        cls_token_id = 1
        sep_token_id = 2
        pad_token_id = 0

        def encode(self, text, add_special_tokens=False):
            if str(text).startswith("QUESTION"):
                return list(range(10, 50))  # 40 tokens
            return list(range(100, 112))  # 12 option tokens

    tok = FakeTok()
    ids, mask, info = encode_pair(tok, "QUESTION long context", "OPTION text", 20, keep_option=True)
    assert info["kept_b"] == 12, info
    assert info["truncated_a"]
    assert not info["truncated_b"]
    assert ids[0] == 1
    assert 2 in ids  # SEP
    assert len(ids) == 20
    ids2, mask2, info2 = encode_pair(tok, "QUESTION long context", "OPTION text", 20, keep_option=False)
    assert info2["kept_a"] >= info2["kept_b"], info2
    assert info2["truncated_b"]
    assert len(ids) == len(ids2) == 20
    assert len(mask) == len(mask2) == 20


def test_template_split_no_leakage() -> None:
    recs = []
    for i in range(40):
        recs.append({"question": f"Tick modulo {i} on the north wall?", "n_options": 4})
    for i in range(25):
        recs.append({"question": f"Can Alice Smith open door {i}?", "n_options": 2})
    for i in range(15):
        recs.append({"question": f"Is the red chest locked in room {i}?", "n_options": 2})
    a = "Can Alice Smith open door 3?"
    b = "Can Bob Jones open door 9?"
    assert template_key(a, 2) == template_key(b, 2)
    assert "name" in normalize_template_text(a)
    assert "#" in normalize_template_text(a)
    train_q, eval_q, info = stratified_template_split(recs, seed=42, eval_frac=0.2)
    assert not (train_q & eval_q)
    assert info["leakage_templates"] == 0
    assert len(eval_q) / len(train_q | eval_q) >= 0.15
    train_t = {template_key(q, 4 if "Tick" in q else 2) for q in train_q}
    eval_t = {template_key(q, 4 if "Tick" in q else 2) for q in eval_q}
    assert not (train_t & eval_t), (train_t & eval_t)


if __name__ == "__main__":
    test_split_no_leakage()
    test_keep_option_truncation()
    test_template_split_no_leakage()
    test_static_onnx_tiny()
    print("ok")
