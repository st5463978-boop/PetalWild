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
        try:
            ids, mask, mode = encode_pair("[choice] hello\nme: flat", "HOLD_WINNER: keep")
        except ModuleNotFoundError:
            self.skipTest("tokenizers missing")
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

    def test_option_text_uses_menu_detail(self):
        from jevh_trading.ingest import option_text, option_texts_for, parse_row

        self.assertEqual(
            option_text("SWITCH", {"label": "SWITCH", "kind": "switch", "coin": "ETH", "side": "short", "desc": "close, go short ETH"}),
            "SWITCH: close, go short ETH (switch ETH short)",
        )
        rec = parse_row(
            {
                "ts_ms": 1,
                "bee": "hs-breezy",
                "source": "hyperspeed",
                "style": "breezy",
                "rules_id": "breezy-cautious",
                "menu": ["HOLD_WINNER", "LONG_BTC", "SWITCH"],
                "menu_detail": [
                    {"label": "HOLD_WINNER", "kind": "hold", "desc": "keep position"},
                    {"label": "LONG_BTC", "kind": "switch", "coin": "BTC", "side": "long"},
                    {"label": "SWITCH", "kind": "switch", "coin": "ETH", "side": "short", "desc": "close, go short ETH"},
                ],
                "choice": "SWITCH",
                "probabilities": {"HOLD_WINNER": 0.2, "LONG_BTC": 0.1, "SWITCH": 0.7},
                "strategy": "You are breezy-bee, the calculated one. Trend following boilerplate that must not crowd out the rules.",
                "rules": "Capital preservation first. Avoid shorts against positive funding. Take half off when the score drops.",
                "state": {"me": {"pos": "short BTC"}, "coins": {"cols": ["score"], "rows": {"BTC": [-6], "ETH": [-5], "SOL": [1]}}},
            },
            "mem",
        )
        self.assertIn("SWITCH", rec["option_texts"][2])
        self.assertIn("ETH", rec["option_texts"][2])
        self.assertTrue(rec["text_a"].startswith("[choice]"))
        self.assertIn("breezy-cautious", rec["text_a"])
        self.assertIn("rules: Capital preservation", rec["text_a"])
        self.assertLess(rec["text_a"].find("rules:"), rec["text_a"].find("me:"))
        self.assertNotIn("You are breezy-bee", rec["text_a"])
        self.assertIn("BTC", rec["text_a"])

    def test_v2_snapshot_and_rules_holdout(self):
        from jevh_trading.ingest import ingest

        snaps = [f"2026-10-09T11:{i:02d}:00Z" for i in range(12)]
        rules = ["breezy-original", "breezy-cautious", "boozy-original", "boozy-diamond", "bizzy-original", "bizzy-alts"]
        rows = []
        n = 0
        for ts in snaps:
            for style, rid in (("breezy", rules[0]), ("breezy", rules[1]), ("boozy", rules[2]), ("boozy", rules[3]), ("bizzy", rules[4]), ("bizzy", rules[5])):
                n += 1
                rows.append(
                    {
                        "id": f"hs-{n}",
                        "source": "hyperspeed",
                        "bee": f"hs-{style}",
                        "style": style,
                        "rules_id": rid,
                        "market_ts": ts,
                        "ts_ms": 1_791_000_000_000 + n,
                        "state": {"me": {"pos": "flat", "i": n}, "coins": {"cols": ["score"], "rows": {"BTC": [n % 9]}}},
                        "menu": ["LONG_BTC", "SHORT_BTC", "WAIT"],
                        "choice": "LONG_BTC" if style != "bizzy" else "WAIT",
                        "probabilities": {"LONG_BTC": 0.5, "SHORT_BTC": 0.2, "WAIT": 0.3},
                    }
                )
        for i in range(5):
            rows.append(
                {
                    "id": f"live-{i}",
                    "source": "live_engine",
                    "bee": "bee1",
                    "ts_ms": 1_790_000_000_000 + i,
                    "state": {"me": {"pos": "short BTC", "held_min": i}, "coins": {"cols": ["score"], "rows": {"BTC": [-6]}}},
                    "menu": ["HOLD_WINNER", "LONG_BTC", "SWITCH"],
                    "choice": "HOLD_WINNER",
                    "probabilities": {"HOLD_WINNER": 0.8, "LONG_BTC": 0.1, "SWITCH": 0.1},
                }
            )
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "calls.jsonl"
            p.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
            b = ingest([str(p)], include_default=False)
        self.assertEqual(b["stats"]["protocol"], "hyperspeed_market_ts+held_rules+live_holdout")
        self.assertEqual(b["stats"]["eval_live"], 5)
        self.assertTrue(b["stats"]["held_rules"])
        train_rules = {r["rules_id"] for r in b["train"]}
        for rid in b["stats"]["held_rules"]:
            self.assertNotIn(rid, train_rules)
        train_snaps = {r["market_ts"] for r in b["train"]}
        eval_snaps = set(b["stats"]["eval_snaps"])
        self.assertTrue(eval_snaps)
        self.assertFalse(train_snaps & eval_snaps)
        live_ids = {r["id"] for r in b["eval_live"]}
        self.assertTrue(all(str(i).startswith("live") for i in live_ids))
        self.assertFalse(any(r.get("row_source") == "live_engine" for r in b["train"]))


class EncodeKeepOption(unittest.TestCase):
    def test_keep_option_on_overflow(self):
        from jevh_trading.encode import encode_pair
        from jevh_trading.paths import tokenizer_path

        try:
            tokenizer_path()
        except FileNotFoundError:
            self.skipTest("tokenizer missing")
        text_a = "[choice] " + ("state token " * 80)
        try:
            ids, mask, mode = encode_pair(text_a, "APE_STRK")
        except ModuleNotFoundError:
            self.skipTest("tokenizers missing")
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
        self.assertEqual(m["by_gold_label"]["HOLD_WINNER"]["n"], 2)

    def test_hold_baselines_on_decorated_option_text(self):
        from jevh_trading.metrics import always_hold_indices, majority_per_style_indices

        labs = [
            ["HOLD_WINNER: keep position (hold)", "LONG_BTC: open BTC long"],
            ["APE_TIA: #1 momentum (open TIA long)", "RIDE: keep position (hold)"],
            ["SHORT_BTC: open BTC short", "WAIT: not convinced (hold)"],
        ]
        self.assertEqual(always_hold_indices(labs), [0, 1, 1])
        maj = majority_per_style_indices(
            labs,
            ["breezy", "boozy", "bizzy"],
            {"breezy": "HOLD_WINNER", "boozy": "RIDE", "bizzy": "HOLD"},
        )
        self.assertEqual(maj, [0, 1, 1])


class GateTests(unittest.TestCase):
    def test_max_coverage_and_threshold(self):
        from jevh_trading.shadow_gate import apply_threshold, max_coverage

        score = np.array([0.9, 0.8, 0.7, 0.6])
        ok = np.array([True, True, False, True])
        hi = max_coverage(score, ok, 0.99)
        self.assertAlmostEqual(hi["coverage"], 0.5)
        self.assertAlmostEqual(hi["threshold"], 0.8)
        self.assertAlmostEqual(max_coverage(score, ok, 0.75)["coverage"], 1.0)
        self.assertEqual(max_coverage(score, ok, 0.99, conservative=True)["coverage"], 0.0)
        res = apply_threshold(score, ok, 0.8)
        self.assertAlmostEqual(res["coverage"], 0.5)
        self.assertAlmostEqual(res["selective_agreement"], 1.0)
        self.assertAlmostEqual(res["system_agreement_with_jev_fallback"], 1.0)

    def test_tied_scores_share_one_cut(self):
        from jevh_trading.shadow_gate import max_coverage

        score = np.array([1.0, 1.0, 0.5])
        ok = np.array([True, False, True])
        self.assertEqual(max_coverage(score, ok, 0.99)["coverage"], 0.0)

    def test_agreement_stats_top2_and_tolerance(self):
        from jevh_trading.shadow_gate import agreement_stats

        recs = [
            {"gold": 0, "probs": [0.6, 0.4], "p_jev": [0.51, 0.49], "style": "bizzy", "kinds": ["hold", "close"]},
            {"gold": 1, "probs": [0.7, 0.2, 0.1], "p_jev": [0.30, 0.65, 0.05], "style": "boozy", "kinds": ["open", "open", "open"]},
        ]
        st = agreement_stats(recs)
        self.assertAlmostEqual(st["top1_agreement"], 0.5)
        self.assertAlmostEqual(st["top2_agreement"], 1.0)
        self.assertAlmostEqual(st["action_kind_agreement"], 1.0)
        self.assertAlmostEqual(st["tolerant_agreement_within_0.05"], 0.5)
        self.assertEqual(set(st["by_rules_id"]), {"None"})

    def test_prob_rmse_and_temperature(self):
        from jevh_trading.shadow_gate import fit_rmse_temperature, prob_rmse

        same = [{"probs": [0.7, 0.3], "p_jev": [0.7, 0.3]}]
        self.assertAlmostEqual(prob_rmse(same), 0.0)
        off = [{"probs": [0.9, 0.1], "p_jev": [0.7, 0.3]}]
        self.assertAlmostEqual(prob_rmse(off), 0.2)
        sharp = [{"probs": [0.0, 0.0], "logits": [2 * np.log(0.7), 2 * np.log(0.3)], "p_jev": [0.7, 0.3]}]
        self.assertAlmostEqual(fit_rmse_temperature(sharp), 2.0)
        self.assertAlmostEqual(prob_rmse(sharp, 2.0), 0.0, places=6)

    def test_logistic_gate_prefers_confident(self):
        from jevh_trading.shadow_gate import LogisticGate

        rng = np.random.default_rng(0)
        recs, ok = [], []
        for _ in range(400):
            p = float(rng.uniform(0.5, 1.0))
            recs.append({"probs": [p, 1 - p], "style": "breezy"})
            ok.append(rng.uniform() < p)
        g = LogisticGate().fit(recs, np.asarray(ok))
        s = g.score([{"probs": [0.55, 0.45], "style": "breezy"}, {"probs": [0.95, 0.05], "style": "breezy"}])
        self.assertLess(s[0], s[1])


class CeilingTests(unittest.TestCase):
    def test_noise_agreement_zero_sigma_is_argmax(self):
        from jevh_trading.jev_ceiling import noise_agreement, sigma_for

        rows = [{"p": [0.7, 0.2, 0.1], "gold": 0}, {"p": [0.45, 0.55], "gold": 1}]
        tab = noise_agreement(rows, sigmas=(0.0, 0.05, 0.5), n_draws=64)
        self.assertAlmostEqual(tab[0]["agree_with_logged_choice"], 1.0)
        self.assertGreater(tab[0]["agree_with_logged_choice"], tab[2]["agree_with_logged_choice"])
        self.assertIsNotNone(sigma_for(tab, 0.9))

    def test_jev_mass_stats_ties_and_margin(self):
        from jevh_trading.jev_ceiling import jev_mass_stats

        rows = [
            {"p": [0.5, 0.5], "gold": 1, "menu": ["A", "B"], "confidence": 0.0},
            {"p": [0.8, 0.2], "gold": 0, "menu": ["A", "B"], "confidence": 0.6},
        ]
        st = jev_mass_stats(rows)
        self.assertAlmostEqual(st["exact_ties_at_max"], 0.5)
        self.assertAlmostEqual(st["tie_break_first_in_menu"], 0.0)
        self.assertAlmostEqual(st["E_max_p_sampling_ceiling"], 0.65)
        self.assertAlmostEqual(st["mean_top2_margin"], 0.3)


class StructuredFeatureTests(unittest.TestCase):
    def _bizzy_row(self):
        return {
            "bee_style": "bizzy",
            "rules_id": "bizzy-majors",
            "context_id": "",
            "menu": ["HOLD", "CUT_LOSS"],
            "menu_detail": [
                {"label": "HOLD", "kind": "hold", "coin": None, "side": None},
                {"label": "CUT_LOSS", "kind": "close", "coin": None, "side": None},
            ],
            "gold": 1,
            "p": [0.4, 0.6],
            "state": {
                "utc": "11:40",
                "me": {"pos": "long BTC", "usd": 50, "upl_r": -0.2, "held_min": 264, "trades": "0/1", "fee_left": 0.39},
                "coins": {
                    "cols": ["to_trigger_pct", "day_move_pct", "prev_range_pct", "r1h_pct", "fund_z", "oi1h_pct", "spread_bp"],
                    "rows": {"BTC": [0.38, 1.54, 3.85, 0.7, 1, None, 0], "ETH": [2.48, 1.16, 7.33, 0.4, 1, None, 0]},
                },
            },
        }

    def test_full_sees_trigger_packed_does_not(self):
        from jevh_trading.structured_baseline import FeatureBuilder, label_parts, parse_me

        self.assertEqual(label_parts("APE_TIA"), ("APE", "TIA", 1))
        self.assertEqual(label_parts("SHORT_ETH"), ("SHORT", "ETH", -1))
        self.assertEqual(label_parts("HOLD_WINNER")[0], "HOLD_WINNER")
        side, coin, nums = parse_me({"pos": "short ETH", "trades": "2/3"})
        self.assertEqual((side, coin), (-1, "ETH"))
        self.assertEqual(nums[-2:], [2.0, 3.0])
        row = self._bizzy_row()
        full = FeatureBuilder("full", {"bizzy-majors": 0}, {})
        packed = FeatureBuilder("packed", {"bizzy-majors": 0}, {})
        i = full.names.index("opt_to_trigger_pct")
        xf, xp = full.row(row), packed.row(row)
        self.assertEqual(xf.shape, (2, len(full.names)))
        self.assertAlmostEqual(float(xf[0, i]), 0.38, places=5)
        self.assertTrue(np.isnan(xp[0, i]))
        m = full.matrix([row])
        self.assertEqual(m["groups"].tolist(), [2])
        self.assertEqual(m["y_bin"].tolist(), [0.0, 1.0])


class OptionPackerTests(unittest.TestCase):
    BOOZY_COLS = ["r1h_pct", "r24h_pct", "r7d_pct", "attn_z", "oi1h_pct", "spread_bp", "vol_musd"]
    BIZZY_COLS = ["to_trigger_pct", "day_move_pct", "prev_range_pct", "r1h_pct", "fund_z", "oi1h_pct", "spread_bp"]

    def _raw(self, style, menu, detail, choice, state, rules=""):
        return {
            "ts_ms": 1,
            "bee": f"hs-{style}",
            "source": "hyperspeed",
            "style": style,
            "rules_id": f"{style}-test",
            "menu": menu,
            "menu_detail": detail,
            "choice": choice,
            "probabilities": {m: 1.0 / len(menu) for m in menu},
            "rules": rules,
            "state": state,
        }

    def test_option_coin(self):
        from jevh_trading.ingest import option_coin

        self.assertEqual(option_coin("SWITCH", {"coin": "eth"}, "BTC"), "ETH")
        self.assertEqual(option_coin("BREAKOUT_SOL", None, None), "SOL")
        self.assertEqual(option_coin("CUT_LOSS", {"kind": "close"}, "BTC"), "BTC")
        self.assertEqual(option_coin("HOLD_WINNER", None, "ETH"), "ETH")
        self.assertIsNone(option_coin("SWITCH", None, "BTC"))
        self.assertIsNone(option_coin("WAIT", {"kind": "hold"}, None))

    def test_each_option_carries_its_coin_row_with_ranks(self):
        from jevh_trading.ingest import parse_row

        detail = [
            {"label": "APE_STRK", "desc": "#1 momentum", "kind": "open", "coin": "STRK", "side": "long"},
            {"label": "APE_ONDO", "desc": "#2 momentum", "kind": "open", "coin": "ONDO", "side": "long"},
            {"label": "APE_BTC", "desc": "#3 momentum", "kind": "open", "coin": "BTC", "side": "long"},
            {"label": "RIDE", "kind": "hold", "coin": None},
        ]
        rows = {
            "STRK": [-1.2, 13, 33, 0.4, None, 9, 2.9],
            "ONDO": [-0.8, 1, -4, 0.2, None, 6, 14.1],
            "BTC": [-0.2, -2, -4, -0.5, None, 0, 423.9],
            "HYPE": [-0.1, -5, -4, -0.6, None, 0, 13.9],
        }
        state = {"me": {"pos": "long HYPE", "usd": 40}, "top1": "STRK x1", "coins": {"cols": self.BOOZY_COLS, "rows": rows}}
        raw = self._raw("boozy", ["APE_STRK", "APE_ONDO", "APE_BTC", "RIDE"], detail, "APE_STRK", state, "Momentum, but skip wide spreads.")
        rec = parse_row(raw, "mem", None, "option")
        a, opts = rec["text_a"], rec["option_texts"]
        self.assertTrue(a.startswith("[choice] boozy momentum boozy-test\nme: pos=long HYPE"))
        self.assertLess(a.find("me:"), a.find("rules:"))
        self.assertIn("\nSTRK r1h=-1.2#4 r24=13#1 r7d=33#1 attn=0.4#1 spr=9#1 vol=2.9#4", opts[0])
        self.assertIn("ONDO r1h=-0.8#3 r24=1#2 r7d=-4#2", opts[1])
        self.assertIn("\nHYPE r1h=-0.1#1", opts[3])
        self.assertNotIn("oi=", a + "".join(opts))
        self.assertEqual(rec["gold"], 0)

    def test_bizzy_option_rows_keep_trigger_and_split_key(self):
        from jevh_trading.ingest import ingest, parse_row

        detail = [
            {"label": "BREAKOUT_BTC", "kind": "open", "coin": "BTC", "side": "long"},
            {"label": "BREAKOUT_ETH", "kind": "open", "coin": "ETH", "side": "long"},
            {"label": "WAIT", "kind": "hold", "coin": None},
        ]
        state = {
            "me": {"pos": "flat", "trades": "0/1"},
            "coins": {"cols": self.BIZZY_COLS, "rows": {"BTC": [0.38, 1.54, 3.85, 0.7, 1, None, 0], "ETH": [2.48, 1.16, 7.33, 0.4, 1, None, 0]}},
        }
        raw = self._raw("bizzy", ["BREAKOUT_BTC", "BREAKOUT_ETH", "WAIT"], detail, "BREAKOUT_BTC", state)
        v1 = parse_row(raw, "mem", None)
        op = parse_row(raw, "mem", None, "option")
        self.assertNotIn("trig=", v1["text_a"] + "".join(v1["option_texts"]))
        self.assertIn("\nBTC trig=0.38 dmove=1.54 prng=3.85 r1h=0.7 fund=1 spr=0", op["option_texts"][0])
        self.assertNotIn("\n", op["option_texts"][2])
        self.assertEqual(v1["state_hash"], op["state_hash"])
        with self.assertRaises(ValueError):
            ingest(packer="nope")


if __name__ == "__main__":
    unittest.main()
