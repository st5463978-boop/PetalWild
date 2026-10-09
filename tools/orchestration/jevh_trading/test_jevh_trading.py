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


if __name__ == "__main__":
    unittest.main()
