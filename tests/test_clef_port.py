"""Checks that do not need the Hailo compiler or the 9B checkpoint."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hailo_port"))

from graphs import gated_delta_scan  # noqa: E402
from transformers.models.qwen3_5.modeling_qwen3_5 import torch_recurrent_gated_delta_rule


class GatedDeltaScanTests(unittest.TestCase):
    def test_scan_matches_transformers_recurrent_reference(self) -> None:
        torch.manual_seed(7)
        query = torch.randn(1, 8, 4, 16)
        key = torch.randn(1, 8, 4, 16)
        value = torch.randn(1, 8, 4, 32)
        decay = -torch.rand(1, 8, 4)
        beta = torch.rand(1, 8, 4)
        with torch.inference_mode():
            ours = gated_delta_scan(query, key, value, decay, beta)
            reference, _ = torch_recurrent_gated_delta_rule(
                query, key, value, g=decay, beta=beta, use_qk_l2norm_in_kernel=True
            )
        self.assertLess(float((ours - reference).abs().max()), 1e-5)


class MeasurementRecordTests(unittest.TestCase):
    def test_recorded_exports_match_pytorch(self) -> None:
        path = ROOT / "reports" / "measurements.json"
        if not path.exists():
            self.skipTest("measurements.json is produced by hailo_port/run_experiments.py")
        payload = json.loads(path.read_text())
        for key in ("full_attention", "linear_attention", "mlp", "head"):
            score = payload[key]["pytorch_vs_onnx"]
            self.assertGreater(score["cosine_min"], 0.999)
            self.assertLess(score["max_abs_max"], 1e-3)
        self.assertEqual(payload["full_attention"]["future_token_leak_max_abs"], 0.0)


if __name__ == "__main__":
    unittest.main()
