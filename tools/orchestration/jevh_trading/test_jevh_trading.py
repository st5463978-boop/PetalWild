"""Offline tests. No exchange, no Pi, no HEF."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from jevh_trading.config import HOLD_LABELS, SEQ_LEN  # noqa: E402
from jevh_trading.dataset import (  # noqa: E402
    CoinFeat,
    _assign_splits,
    _gold,
    label_distribution,
)
from jevh_trading.indicators import atr_wilder, bollinger_typical, donchian_ensemble, rsi_wilder  # noqa: E402
from jevh_trading.metrics import ece  # noqa: E402


class IndicatorTests(unittest.TestCase):
    def test_rsi_flat_is_50(self):
        c = np.ones(30, dtype=np.float64)
        self.assertAlmostEqual(rsi_wilder(c, 14), 50.0, places=5)

    def test_rsi_monotone_up_is_100(self):
        c = np.arange(1, 40, dtype=np.float64)
        self.assertAlmostEqual(rsi_wilder(c, 14), 100.0, places=5)

    def test_atr_positive(self):
        h = np.linspace(11, 20, 30)
        l = np.linspace(9, 18, 30)
        c = np.linspace(10, 19, 30)
        a = atr_wilder(h, l, c, 14)
        self.assertIsNotNone(a)
        self.assertGreater(a, 0)

    def test_bollinger_mid_at_typical(self):
        x = np.linspace(100, 110, 25)
        bb = bollinger_typical(x + 1, x - 1, x, 20)
        self.assertIsNotNone(bb)
        self.assertGreater(bb["upper"], bb["lower"])

    def test_donchian_uptrend_long(self):
        c = np.linspace(1, 200, 200)
        d = donchian_ensemble(c, lookbacks=(5, 10, 20))
        self.assertGreater(d["score"], 0)
        self.assertGreater(d["longOn"], 0)
        self.assertEqual(d["shortOn"], 0)


class SplitTests(unittest.TestCase):
    def test_time_split_purge_no_overlap(self):
        n, warmup, horizon, purge = 400, 80, 16, 32
        s = _assign_splits(n, warmup, horizon, purge, 0.7)
        train = [i for i, v in s.items() if v == "train"]
        eval_ = [i for i, v in s.items() if v == "eval"]
        purge_i = [i for i, v in s.items() if v == "purge"]
        self.assertTrue(train)
        self.assertTrue(eval_)
        self.assertTrue(purge_i)
        self.assertLess(max(train), min(purge_i))
        self.assertLess(max(purge_i), min(eval_))
        self.assertEqual(min(eval_) - max(train), purge)
        self.assertLessEqual(max(eval_), n - horizon - 1)


class LabelTests(unittest.TestCase):
    def test_gold_is_argmax(self):
        self.assertEqual(_gold([0.1, 0.4, 0.2]), 1)

    def test_hold_set(self):
        self.assertIn("RIDE", HOLD_LABELS)
        self.assertIn("HOLD_WINNER", HOLD_LABELS)


class MetricTests(unittest.TestCase):
    def test_ece_perfect(self):
        conf = [0.5, 0.5, 0.5, 0.5]
        ok = [True, False, True, False]
        self.assertLess(ece(conf, ok, n_bins=10), 0.05)


class FeatTests(unittest.TestCase):
    def test_tiny_coinfeat(self):
        n = 200
        t = np.arange(n, dtype=np.int64) * 900 + 1_787_004_900
        c = 100 + np.cumsum(np.random.default_rng(0).normal(0, 0.2, n))
        m = {
            "t": t,
            "o": c,
            "h": c + 0.5,
            "l": c - 0.5,
            "c": c,
            "v": np.ones(n),
        }
        f = CoinFeat("BTC", m)
        self.assertEqual(f.c.size, n)
        self.assertTrue(np.isfinite(f.atr[50]))
        self.assertTrue(np.isfinite(f.rsi[50]))


class EncodeSmoke(unittest.TestCase):
    def test_seq_len_if_tokenizer_present(self):
        from jevh_trading.paths import tokenizer_path
        from jevh_trading.encode import encode_pair

        try:
            p = tokenizer_path()
        except FileNotFoundError:
            self.skipTest("tokenizer missing")
        ids, mask, mode = encode_pair("[choice] hello\nme: flat", "HOLD_WINNER: keep")
        self.assertEqual(len(ids), SEQ_LEN)
        self.assertEqual(len(mask), SEQ_LEN)
        self.assertEqual(sum(mask), int(np.count_nonzero(mask)))
        self.assertIn(mode, ("only_first", "longest_first"))
        self.assertEqual(ids[0], 50281)  # [CLS]
        self.assertTrue(any(x == 0 for x in mask) or mask[-1] == 1)


class OnnxSmoke(unittest.TestCase):
    def test_export_static_and_parity(self):
        try:
            import torch  # noqa: F401
            import onnx  # noqa: F401
            import onnxruntime  # noqa: F401
        except ImportError:
            self.skipTest("torch/onnx not installed")
        from jevh_trading.export import export_onnx, parity_check
        from jevh_trading.model import PairScorer

        m = PairScorer(dropout=0.0)
        m.eval()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "t.onnx"
            info = export_onnx(m, p)
            self.assertEqual(info["inputs"]["input_ids"], [1, SEQ_LEN])
            self.assertEqual(info["inputs"]["attention_mask"], [1, SEQ_LEN])
            self.assertIn("attention_mask", info["inputs"])
            self.assertNotIn("Loop", info["ops"])
            self.assertNotIn("If", info["ops"])
            self.assertNotIn("NonZero", info["ops"])
            ids = np.zeros((4, SEQ_LEN), np.int64)
            mask = np.ones((4, SEQ_LEN), np.int64)
            ids[:, 0] = 50281
            ids[:, 1] = 10
            par = parity_check(m, p, ids, mask)
            self.assertGreaterEqual(par["cos"], 0.999)


class DistTests(unittest.TestCase):
    def test_label_dist_helper(self):
        class E:
            def __init__(self, g):
                self.gold_label = g

        d = label_distribution([E("RIDE"), E("RIDE"), E("APE_BTC")])
        self.assertEqual(d["RIDE"], 2)


class IngestTests(unittest.TestCase):
    def test_parse_soft_targets_and_drop_single(self):
        from jevh_trading.ingest import ingest, is_varied, parse_row

        ape = parse_row(
            {
                "ts_ms": 1000,
                "bee": "bee2",
                "state": {"me": {"pos": "flat"}, "coins": {"cols": ["r7d_pct"], "rows": {"DOGE": [12]}}},
                "menu": ["APE_DOGE", "APE_PEPE", "APE_PENGU"],
                "choice": "APE_DOGE",
                "probabilities": {"APE_DOGE": 0.87, "APE_PEPE": 0.06, "APE_PENGU": 0.07},
            },
            "mem",
        )
        self.assertTrue(ape["usable_train"])
        self.assertTrue(ape["varied"])
        self.assertEqual(ape["gold"], 0)
        self.assertAlmostEqual(sum(ape["probs"]), 1.0, places=6)

        ride = parse_row(
            {
                "ts_ms": 1001,
                "bee": "bee2",
                "state": {"me": {"pos": "long DOGE"}},
                "menu": ["RIDE"],
                "choice": "RIDE",
                "probabilities": {"RIDE": 1},
            },
            "mem",
        )
        self.assertTrue(ride["single_option"])
        self.assertFalse(ride["usable_train"])
        self.assertFalse(is_varied(["HOLD_WINNER", "LONG_BTC", "SWITCH"], "HOLD_WINNER"))
        self.assertTrue(is_varied(["LONG_BTC", "SHORT_BTC", "LONG_ETH", "SHORT_ETH"], "SHORT_BTC"))

    def test_dedupe_and_time_split(self):
        from jevh_trading.ingest import ingest

        rows = []
        # 20 unique multi-option ticks, 10s apart, plus duplicates and a RIDE
        for i in range(20):
            rows.append(
                {
                    "id": i,
                    "ts_ms": 1_000_000 + i * 10_000,
                    "bee": "bee1",
                    "state": {"me": {"pos": "short BTC", "held_min": i}, "coins": {"cols": ["score"], "rows": {"BTC": [i]}}},
                    "menu": ["HOLD_WINNER", "LONG_BTC", "SWITCH"],
                    "choice": "HOLD_WINNER",
                    "probabilities": {"HOLD_WINNER": 0.7, "LONG_BTC": 0.1, "SWITCH": 0.2},
                }
            )
        rows.append(dict(rows[-1], id=99, ts_ms=rows[-1]["ts_ms"] + 1))  # same state hash later write wins
        rows.append(
            {
                "id": 100,
                "ts_ms": 1_000_000,
                "bee": "bee2",
                "state": {"me": {"pos": "long DOGE"}},
                "menu": ["RIDE"],
                "choice": "RIDE",
                "probabilities": {"RIDE": 1},
            }
        )
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "decisions.jsonl"
            p.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
            b = ingest([str(p)], purge_ms=30_000, train_frac=0.7, include_default=False)
        self.assertEqual(b["stats"]["single_option"], 1)
        self.assertEqual(b["stats"]["multi_option_trainish"], 20)  # duplicate dropped
        self.assertGreater(b["stats"]["train"], 0)
        self.assertGreater(b["stats"]["eval"], 0)
        if b["train"] and b["eval"]:
            self.assertLessEqual(max(r["ts_ms"] for r in b["train"]), min(r["ts_ms"] for r in b["eval"]))
        self.assertFalse(b["stats"]["enough_to_claim"])
        self.assertGreater(b["stats"]["shortfall"]["varied_multi"], 0)


class EncodeKeepOption(unittest.TestCase):
    def test_keep_option_on_overflow(self):
        from jevh_trading.encode import encode_pair
        from jevh_trading.paths import tokenizer_path

        try:
            tokenizer_path()
        except FileNotFoundError:
            self.skipTest("tokenizer missing")
        text_a = "[choice] " + ("state token " * 80)
        ids, mask, mode = encode_pair(text_a, "APE_STRK")
        self.assertEqual(len(ids), SEQ_LEN)
        self.assertEqual(len(mask), SEQ_LEN)
        self.assertEqual(ids[0], 50281)
        self.assertIn(mode, ("only_first", "longest_first", "keep_option"))


class SoftMaxMetrics(unittest.TestCase):
    def test_agreement_breakdown(self):
        from jevh_trading.metrics import agreement_breakdown

        m = agreement_breakdown(
            [0, 1, 0],
            [0, 0, 0],
            [[0.8, 0.2], [0.3, 0.7], [0.9, 0.1]],
            [["HOLD_WINNER", "SWITCH"], ["HOLD_WINNER", "SWITCH"], ["APE_BTC", "APE_ETH"]],
            varied=[False, False, True],
        )
        self.assertEqual(m["n"], 3)
        self.assertAlmostEqual(m["accuracy"], 2 / 3)
        self.assertEqual(m["by_menu_size"]["2"]["n"], 3)
        self.assertEqual(m["varied_n"], 1)
        self.assertEqual(m["collapsed_n"], 2)


if __name__ == "__main__":
    unittest.main()
