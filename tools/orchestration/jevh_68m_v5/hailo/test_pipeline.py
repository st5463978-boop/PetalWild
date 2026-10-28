"""Pipeline tests that do not need a Hailo device, the DFC, or a checkpoint."""
from __future__ import annotations

import ast
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from hailo.calib import CalibError, fit_input, load_pair, validate_pair
from hailo.compile_hef import run
from hailo.contract import (
    AGREEMENT_FLOOR,
    ART,
    CLS_ID,
    MODEL_PY,
    PAD_ID,
    SEQ_LEN,
    accept_agreement,
    architecture_constants,
    confident_wrong,
    decide_from_logits,
    decision_agreement,
    expected_calibration_error,
)
from hailo.decide import normalize_qtype, run_decision
from hailo.parity import evaluate
from hailo.serve import decide_body, health_body, port_allowed

HERE = Path(__file__).resolve().parent


def _real_pair() -> tuple[np.ndarray, np.ndarray]:
    ids = np.load(ART / "calib_input_ids.npy")
    mask = np.load(ART / "calib_attention_mask.npy")
    return ids, mask


class CalibTests(unittest.TestCase):
    def test_committed_pair_is_real_tokens(self):
        ids, mask = load_pair(ART / "calib_input_ids.npy", ART / "calib_attention_mask.npy")
        self.assertEqual(ids.shape, (256, SEQ_LEN))
        self.assertEqual(int(ids[0, 0]), CLS_ID)
        self.assertTrue(np.array_equal(ids == PAD_ID, mask == 0))
        self.assertGreater(len({row.tobytes() for row in ids}), 200)
        self.assertLess(float(mask.mean()), 0.5)

    def test_noise_and_dropped_mask_are_rejected(self):
        ids, mask = _real_pair()
        noise = np.random.default_rng(0).normal(size=ids.shape).astype(np.float32)
        with self.assertRaises(CalibError):
            validate_pair(noise, mask.astype(np.float32))
        broken = np.ones_like(mask)
        with self.assertRaises(CalibError):
            validate_pair(ids, broken)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            code = run(
                root / "missing.onnx",
                root / "no_ids.npy",
                root / "no_mask.npy",
                root / "out.hef",
                root / "receipt.json",
            )
            self.assertEqual(code, 2)
            receipt = json.loads((root / "receipt.json").read_text())
            self.assertIn("Refusing to invent", receipt["error"])
            self.assertFalse(receipt["hardware_tested"])

    def test_fit_inserts_singleton_axes_without_changing_values(self):
        ids, _ = _real_pair()
        block = ids[:4].astype(np.float32)
        fitted = fit_input(block, [-1, 1, SEQ_LEN, 1])
        self.assertEqual(fitted.shape, (4, 1, SEQ_LEN, 1))
        self.assertTrue(np.array_equal(fitted[:, 0, :, 0], block))
        with self.assertRaises(CalibError):
            fit_input(block, [-1, 7, SEQ_LEN])


class ContractTests(unittest.TestCase):
    def test_model_constants_and_hailo_patterns(self):
        constants = architecture_constants()
        self.assertEqual(constants["SEQ_LEN"], SEQ_LEN)
        self.assertEqual(constants["PAD_ID"], PAD_ID)
        self.assertEqual(constants["CLS_ID"], CLS_ID)
        source = MODEL_PY.read_text()
        self.assertIn("def gelu_erf", source)
        self.assertNotIn("F.gelu", source)
        self.assertNotIn("torch.cat((-x2, x1)", source)
        tree = ast.parse(source)
        names = [node.name for node in tree.body if isinstance(node, ast.FunctionDef)]
        self.assertIn("rotate_half", names)
        self.assertIn("gelu_erf", names)

    def test_decision_math_and_floor(self):
        body = decide_from_logits([0.0, 2.0], ["no", "yes"])
        self.assertEqual(body["index"], 1)
        self.assertAlmostEqual(sum(body["probs"]), 1.0)
        self.assertEqual(decision_agreement([0, 1, 1], [0, 1, 0]), 2 / 3)
        self.assertEqual(confident_wrong([0.9, 0.2], [1, 0], [0, 0]), 1)
        ece = expected_calibration_error([0.9, 0.2], [False, True])
        self.assertGreater(ece, 0.0)
        self.assertFalse(accept_agreement(None)["accepted"])
        self.assertFalse(accept_agreement(0.217)["accepted"])
        self.assertTrue(accept_agreement(AGREEMENT_FLOOR)["accepted"])
        report = evaluate(None, None)
        self.assertIsNone(report["cpu_hef_agreement"])
        self.assertFalse(report["hardware_tested"])

    def test_qtypes_and_handler_without_a_model(self):
        self.assertEqual(normalize_qtype(None, ["yes", "no"]), "noul")
        self.assertEqual(normalize_qtype("score", ["yes", "no"]), "score")
        self.assertEqual(normalize_qtype(None, ["reed", "bramble"]), "choice")

        def encode(question, options, context, qtype):
            self.assertEqual(qtype, "choice")
            return [([1, 0], [1, 0]), ([0, 1], [1, 0])]

        class Scorer:
            name = "fake"

            def score_pair(self, ids, mask):
                return float(ids[0])

        body = run_decision("Which crop?", ["reed", "bramble"], encode, Scorer().score_pair, qtype="choice")
        self.assertEqual(body["choice"], "reed")
        wrapped = decide_body(
            {"question": "Which crop?", "options": ["reed", "bramble"], "qtype": "choice"},
            Scorer(),
            encode,
        )
        self.assertEqual(wrapped["backend"], "fake")
        self.assertNotIn("cpu_fallback", wrapped)
        health = health_body(ART / "missing.onnx", ART / "missing.hef")
        self.assertFalse(health["onnx"])
        self.assertFalse(health["hardware_tested"])
        self.assertFalse(health["live_port_touched"])
        with self.assertRaises(SystemExit):
            port_allowed(8771)
        port_allowed(8772)


class CompileReceiptTests(unittest.TestCase):
    def test_missing_onnx_records_blockers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            code = run(
                root / "missing.onnx",
                ART / "calib_input_ids.npy",
                ART / "calib_attention_mask.npy",
                root / "out.hef",
                root / "receipt.json",
            )
            self.assertEqual(code, 3)
            receipt = json.loads((root / "receipt.json").read_text())
            self.assertEqual(receipt["stage"], "onnx_missing")
            probe = receipt["structure_probe"]
            self.assertTrue(probe["ran"])
            self.assertTrue(probe["contract_ok"])
            self.assertEqual(probe["neg_into_concat"], [])
            self.assertNotIn("Gelu", probe["ops"])
            self.assertNotIn("Neg", probe["ops"])
            self.assertNotEqual(probe["random_onnx_sha256"], receipt["expected_onnx_sha256"])
            self.assertFalse(receipt["dfc"]["installed"])
            self.assertIn("hailo_sdk_client", receipt["dfc"]["error"])
            self.assertIn("Neg-into-Concat", receipt["error"])
            self.assertEqual(receipt["calib"]["rows"], 256)
            self.assertFalse(receipt["hardware_tested"])
            self.assertFalse((root / "out.hef").exists())


class OnnxRewriteTests(unittest.TestCase):
    def test_gelu_rewrite_and_neg_concat(self):
        try:
            import onnx
            from onnx import TensorProto, helper
        except ImportError:
            self.skipTest("onnx is not installed")
        from hailo.onnx_graph import make_gelu_probe, neg_into_concat, rewrite_gelu, summarize

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src = root / "probe.onnx"
            dest = root / "rewritten.onnx"
            make_gelu_probe(src)
            notes = rewrite_gelu(src, dest)
            self.assertEqual(notes["rewritten_gelu"], 1)
            summary = summarize(dest)
            self.assertNotIn("Gelu", summary["ops"])
            self.assertIn("Erf", summary["ops"])
            neg = helper.make_node("Neg", ["x"], ["nx"], name="neg")
            cat = helper.make_node("Concat", ["nx", "x"], ["y"], name="cat", axis=0)
            graph = helper.make_graph(
                [neg, cat],
                "rope",
                [helper.make_tensor_value_info("x", TensorProto.FLOAT, [2])],
                [helper.make_tensor_value_info("y", TensorProto.FLOAT, [2])],
            )
            model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
            self.assertEqual(neg_into_concat(model), ["cat"])
            del onnx


if __name__ == "__main__":
    unittest.main()
