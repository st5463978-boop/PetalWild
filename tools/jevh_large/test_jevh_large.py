#!/usr/bin/env python3
"""Fast checks: question split leakage, static ONNX, attention_mask effect."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from dataio import stratified_question_split  # noqa: E402
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


if __name__ == "__main__":
    test_split_no_leakage()
    test_static_onnx_tiny()
    print("ok")
