#!/usr/bin/env python3
"""Fast unit tests: split, live encode format, attention-mask actually used."""
from __future__ import annotations

import unittest
from pathlib import Path

from data import n_options_bucket, read_jsonl, stratified_question_split
from encode import NOUL_STEXT, SEQ_LEN, StudentTok, build_input, gold_index, is_yesno

HERE = Path(__file__).resolve().parent


class SplitTests(unittest.TestCase):
    def test_no_leakage_and_eval_frac(self):
        rows = read_jsonl(HERE / "data" / "labels.jsonl")
        questions = []
        seen = set()
        n_opts = {}
        for r in rows:
            q = r["question"]
            n_opts.setdefault(q, len(r["options"]))
            if q not in seen:
                seen.add(q)
                questions.append(q)
        split = stratified_question_split(questions, n_opts, seed=42)
        self.assertEqual(len(split), len(questions))
        eval_q = {q for q, s in split.items() if s == "eval"}
        self.assertGreaterEqual(len(eval_q) / len(questions), 0.15)
        # a question is in exactly one split
        self.assertEqual(set(split), set(questions))
        # option-count strata all appear in eval when the bucket is large
        eval_buckets = {n_options_bucket(n_opts[q]) for q in eval_q}
        self.assertIn("2", eval_buckets)
        self.assertIn("4", eval_buckets)

    def test_rows_follow_question_split(self):
        rows = read_jsonl(HERE / "data" / "labels.jsonl")
        questions = list(dict.fromkeys(r["question"] for r in rows))
        n_opts = {}
        for r in rows:
            n_opts.setdefault(r["question"], len(r["options"]))
        split = stratified_question_split(questions, n_opts, seed=42)
        by_q = {}
        for r in rows:
            s = split[r["question"]]
            by_q.setdefault(r["question"], s)
            self.assertEqual(by_q[r["question"]], s)


class EncodeTests(unittest.TestCase):
    def test_noul_yesno(self):
        qtype, text_a, stexts, yesno = build_input("Is the gate open?", ["yes", "no"])
        self.assertTrue(yesno)
        self.assertEqual(qtype, "noul")
        self.assertEqual(text_a, "[noul] Is the gate open?")
        self.assertEqual(stexts, [NOUL_STEXT["yes"], NOUL_STEXT["no"]])

    def test_choice_with_context(self):
        qtype, text_a, stexts, yesno = build_input(
            "What crop?",
            ["bramble", "reed"],
            context="Bram Cobble is at the stall.",
        )
        self.assertFalse(yesno)
        self.assertEqual(qtype, "choice")
        self.assertEqual(text_a, "[choice] What crop?\nBram Cobble is at the stall.")
        self.assertEqual(stexts, ["bramble", "reed"])

    def test_two_way_non_noul_stays_choice(self):
        qtype, text_a, stexts, yesno = build_input(
            "Conflict?",
            ["Flag the conflict and do not treat it as settled", "Accept it and continue"],
        )
        self.assertFalse(yesno)
        self.assertEqual(qtype, "choice")
        self.assertTrue(text_a.startswith("[choice] "))

    def test_tokenizer_pair_len(self):
        tok = StudentTok(str(HERE / "data" / "tokenizer.json"), SEQ_LEN)
        ids, masks, mode = tok.encode("[choice] hello", ["alpha", "beta"])
        self.assertEqual(mode, "only_first")
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(ids[0]), SEQ_LEN)
        self.assertEqual(len(masks[0]), SEQ_LEN)
        self.assertEqual(sum(masks[0]), sum(1 for t in ids[0] if t != tok.pad_id))
        self.assertEqual(gold_index(["a", "b", "c"], "b"), 1)
        self.assertFalse(is_yesno(["Flag", "Accept"]))


class MaskTests(unittest.TestCase):
    def test_attention_mask_changes_logits(self):
        import torch

        from model import Ettin68mScorer

        torch.manual_seed(0)
        m = Ettin68mScorer()
        m.eval()
        ids = torch.randint(10, 500, (1, SEQ_LEN), dtype=torch.long)
        ids[0, 0] = 50281
        full = torch.ones(1, SEQ_LEN, dtype=torch.long)
        half = full.clone()
        half[:, 64:] = 0
        with torch.no_grad():
            a = m(ids, full)
            b = m(ids, half)
        self.assertEqual(tuple(a.shape), (1, 1))
        self.assertFalse(torch.allclose(a, b, atol=1e-5))


if __name__ == "__main__":
    unittest.main()
