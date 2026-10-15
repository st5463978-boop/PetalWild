#!/usr/bin/env python3
"""Unit tests that do not download weights or train."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from data import Example, split_by_question
from encode import build_input, choice_index, is_yesno, norm_label


class EncodeTests(unittest.TestCase):
    def test_norm_and_yesno(self):
        self.assertEqual(norm_label("Yes: that is true given the state"), "yes")
        self.assertTrue(is_yesno(["yes", "no"]))
        self.assertTrue(is_yesno(["no: nope", "yes: yup"]))
        self.assertFalse(is_yesno(["bramble", "reed"]))
        self.assertFalse(is_yesno(["a tonne of lead", "a gram of feathers"]))

    def test_noul_rewrite(self):
        qtype, text_a, stexts, yesno = build_input("Is the stall open?", ["yes", "no"], None)
        self.assertEqual(qtype, "noul")
        self.assertTrue(yesno)
        self.assertEqual(text_a, "[noul] Is the stall open?")
        self.assertEqual(stexts[0], "yes: that is true given the state")
        self.assertEqual(stexts[1], "no: that is not true given the state")

    def test_choice_with_context(self):
        qtype, text_a, stexts, yesno = build_input(
            "What crop?",
            ["bramble", "reed"],
            "Bram Cobble is at the stall",
        )
        self.assertEqual(qtype, "choice")
        self.assertFalse(yesno)
        self.assertIn("Bram Cobble", text_a)
        self.assertEqual(stexts, ["bramble", "reed"])

    def test_gold_index(self):
        self.assertEqual(choice_index("reed", ["bramble", "reed"]), 1)
        self.assertEqual(choice_index("Yes", ["yes", "no"]), 0)


class SplitTests(unittest.TestCase):
    def test_no_question_leakage(self):
        rows = []
        for i in range(40):
            n = 2 if i < 10 else 4
            q = f"q-{i}"
            opts = ["a", "b"] if n == 2 else ["a", "b", "c", "d"]
            rows.append(
                Example(
                    question=q,
                    options=opts,
                    context=None,
                    gold_index=0,
                    teacher_index=0,
                    teacher_scores=None,
                    jev_confidence=0.7,
                    teacher_confidence=0.5,
                    source="labels",
                    n_options=n,
                    yesno=False,
                )
            )
            if i == 3:
                rows.append(
                    Example(
                        question=q,
                        options=opts,
                        context="again",
                        gold_index=1,
                        teacher_index=1,
                        teacher_scores=None,
                        jev_confidence=0.8,
                        teacher_confidence=0.4,
                        source="labels",
                        n_options=n,
                        yesno=False,
                    )
                )
        train, eval_, meta = split_by_question(rows, eval_frac=0.15, seed=42)
        train_q = {e.question for e in train}
        eval_q = {e.question for e in eval_}
        self.assertFalse(train_q & eval_q)
        self.assertGreaterEqual(meta["eval_frac"], 0.15)
        self.assertGreaterEqual(meta["eval_yesno_rows"] + meta["eval_multi_rows"], 1)
        # duplicate question stays on one side
        self.assertEqual(sum(1 for e in train + eval_ if e.question == "q-3"), 2)
        side = "train" if "q-3" in train_q else "eval"
        other = eval_q if side == "train" else train_q
        self.assertNotIn("q-3", other)


class TokenizerTests(unittest.TestCase):
    def test_seq128_and_mask(self):
        tok_path = Path(__file__).resolve().parent / "tokenizer" / "tokenizer.json"
        if not tok_path.is_file():
            self.skipTest("tokenizer.json not committed yet")
        from encode import StudentTok

        tok = StudentTok(str(tok_path), 128)
        ids, masks, qtype, mode = tok.encode_question("What crop?", ["bramble", "reed"], None)
        self.assertEqual(qtype, "choice")
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(ids[0]), 128)
        self.assertEqual(len(masks[0]), 128)
        self.assertEqual(tok.pad_id, ids[0][-1])
        self.assertEqual(masks[0][-1], 0)
        self.assertEqual(masks[0][0], 1)
        self.assertIn(mode, ("only_first", "longest_first"))


class ModelMaskTests(unittest.TestCase):
    def test_mask_changes_logit(self):
        try:
            import torch
        except ImportError:
            self.skipTest("torch not installed")
        from model import OptionScorer

        m = OptionScorer().eval()
        ids = torch.randint(10, 500, (1, 128))
        full = torch.ones(1, 128)
        half = torch.ones(1, 128)
        half[:, 40:] = 0
        with torch.no_grad():
            a = m(ids, full)
            b = m(ids, half)
        self.assertFalse(torch.allclose(a, b))

    def test_onnx_mask_input(self):
        try:
            import torch
            import onnx
        except ImportError:
            self.skipTest("torch/onnx not installed")
        from export import export_onnx
        from model import OptionScorer

        m = OptionScorer().eval()
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "t.onnx"
            info = export_onnx(m, path, opset=17)
            self.assertTrue(path.is_file())
            self.assertEqual(info["forbidden_ops"], [])
            names = [i["name"] for i in info["inputs"]]
            self.assertIn("input_ids", names)
            self.assertIn("attention_mask", names)
            self.assertTrue(info["attention_mask_used"])
            self.assertIn(info["opset"], set(range(13, 18)))
            for inp in info["inputs"]:
                self.assertEqual(inp["shape"], [1, 128])


if __name__ == "__main__":
    unittest.main()
