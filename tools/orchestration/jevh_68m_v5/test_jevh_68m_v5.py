#!/usr/bin/env python3
"""Fast unit tests: split, live encode format, attention-mask actually used."""
from __future__ import annotations

import unittest
from collections import Counter
from pathlib import Path

from data import n_options_bucket, read_jsonl, stratified_question_split, template_grouped_split, template_key
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
        ids, masks, mode, stats = tok.encode("[choice] hello", ["alpha", "beta"])
        self.assertEqual(mode, "only_first")
        self.assertFalse(stats[0]["overflow"])
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(ids[0]), SEQ_LEN)
        self.assertEqual(len(masks[0]), SEQ_LEN)
        self.assertEqual(sum(masks[0]), sum(1 for t in ids[0] if t != tok.pad_id))
        self.assertEqual(gold_index(["a", "b", "c"], "b"), 1)
        self.assertFalse(is_yesno(["Flag", "Accept"]))


class TemplateTests(unittest.TestCase):
    def test_modulo_and_worker_templates_collapse(self):
        a = "An event starts at tick 12, is delayed 3 ticks, and uses period 4. What is its modulo slot at execution?"
        b = "An event starts at tick 0, is delayed 1 ticks, and uses period 2. What is its modulo slot at execution?"
        self.assertEqual(template_key(a), template_key(b))
        w1 = "Worker Mina may transfer seeds up to 5 seeds without approval. The proposed action is 9 seeds. Does this action require approval?"
        w2 = "Worker Otto may queue notices up to 2 notices without approval. The proposed action is 4 notices. Does this action require approval?"
        self.assertEqual(template_key(w1), template_key(w2))

    def test_template_split_no_leakage(self):
        rows = read_jsonl(HERE / "data" / "labels.jsonl")
        questions = list(dict.fromkeys(r["question"] for r in rows))
        n_opts = {}
        tmpl = {}
        for r in rows:
            n_opts.setdefault(r["question"], len(r["options"]))
            tmpl.setdefault(r["question"], template_key(r["question"]))
        split = template_grouped_split(questions, n_opts, tmpl, seed=42)
        self.assertGreaterEqual(sum(1 for s in split.values() if s == "eval") / len(questions), 0.15)
        sets = {"train": set(), "dev": set(), "eval": set()}
        for q, s in split.items():
            sets[s].add(tmpl[q])
        self.assertFalse(sets["train"] & sets["eval"])
        self.assertFalse(sets["dev"] & sets["eval"])
        self.assertFalse(sets["train"] & sets["dev"])

        counts = Counter(tmpl[q] for q in questions)
        biggest, biggest_n = counts.most_common(1)[0]
        self.assertGreater(biggest_n, 100)
        for q, t in tmpl.items():
            if t == biggest:
                self.assertEqual(split[q], "train", "giant template families belong in train")
        eval_frac = sum(1 for s in split.values() if s == "eval") / len(questions)
        self.assertLess(eval_frac, 0.25, "smallest-first fill should not dump a giant family into eval")


class KeepOptionTests(unittest.TestCase):
    def test_overflow_keeps_option(self):
        tok = StudentTok(str(HERE / "data" / "tokenizer.json"), SEQ_LEN)
        question = "[choice] " + ("The parish page says the far lawn bell still stands. " * 20)
        option = "UNIQUE_OPTION_TOKEN_xyzzy keep me"
        ids, masks, mode, stats = tok.encode(question, [option, "other"])
        self.assertEqual(mode, "keep_option")
        self.assertTrue(stats[0]["overflow"])
        self.assertTrue(stats[0]["trimmed_question"])
        self.assertFalse(stats[0]["trimmed_option"])
        # option wordpiece ids should appear in the packed sequence
        opt_core = tok.t_raw.encode(option).ids
        # strip cls/sep
        if opt_core and opt_core[0] == 50281:
            opt_core = opt_core[1:]
        if opt_core and opt_core[-1] == 50282:
            opt_core = opt_core[:-1]
        packed = ids[0]
        # last non-pad tokens should include option tail
        self.assertTrue(any(packed[i : i + len(opt_core)] == opt_core for i in range(len(packed) - len(opt_core) + 1)))


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
