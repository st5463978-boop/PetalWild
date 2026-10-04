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

    def test_channel_axis_step_matches_scan_loop(self) -> None:
        from compile_scan_step import loop_step, nchw_arguments, ScanStep

        torch.manual_seed(3)
        state = torch.randn(2, 32, 128, 128)
        query = torch.randn(2, 32, 128)
        key = torch.randn(2, 32, 128)
        value = torch.randn(2, 32, 128)
        beta = torch.rand(2, 32)
        decay = torch.rand(2, 32)
        with torch.inference_mode():
            reference_state, reference_out = loop_step(state, query, key, value, beta, decay)
            arguments = nchw_arguments(state, query, key, value, beta, decay)
            got_state, got_out = ScanStep()(
                arguments["state"],
                arguments["key"],
                arguments["value"],
                arguments["query"],
                arguments["beta"],
                arguments["decay"],
            )
        got_state = got_state.permute(0, 2, 1, 3)
        got_out = got_out.squeeze(1)
        self.assertLess(float((got_state - reference_state).abs().max()), 1e-5)
        self.assertLess(float((got_out - reference_out).abs().max()), 1e-5)

    def test_eight_steps_match_the_scan_loop(self) -> None:
        from compile_scan_step import STEPS, ScanUnroll, loop_step, nchw_sequence

        torch.manual_seed(4)
        state = torch.randn(2, 32, 128, 128)
        query = torch.randn(2, STEPS, 32, 128)
        key = torch.randn(2, STEPS, 32, 128)
        value = torch.randn(2, STEPS, 32, 128)
        beta = torch.rand(2, STEPS, 32)
        decay = torch.rand(2, STEPS, 32)
        with torch.inference_mode():
            reference = state
            outputs = []
            for index in range(STEPS):
                reference, output = loop_step(
                    reference,
                    query[:, index],
                    key[:, index],
                    value[:, index],
                    beta[:, index],
                    decay[:, index],
                )
                outputs.append(output)
            arguments = nchw_sequence(state, query, key, value, beta, decay)
            got_state, got_out = ScanUnroll()(
                arguments["state"],
                arguments["key"],
                arguments["value"],
                arguments["query"],
                arguments["beta"],
                arguments["decay"],
            )
        self.assertLess(float((got_state.permute(0, 2, 1, 3) - reference).abs().max()), 1e-4)
        self.assertLess(float((got_out - torch.stack(outputs, dim=1)).abs().max()), 1e-4)

    def test_normed_eight_steps_match_gated_delta_scan(self) -> None:
        from compile_scan_step import STEPS, ScanNormed, nchw_sequence
        from graphs import gated_delta_scan

        torch.manual_seed(5)
        query = torch.randn(2, STEPS, 32, 128)
        key = torch.randn(2, STEPS, 32, 128)
        value = torch.randn(2, STEPS, 32, 128)
        beta = torch.rand(2, STEPS, 32)
        decay = -torch.nn.functional.softplus(torch.randn(2, STEPS, 32))
        with torch.inference_mode():
            reference = gated_delta_scan(query, key, value, decay, beta)
            arguments = nchw_sequence(torch.zeros(2, 32, 128, 128), query, key, value, beta, decay)
            _, got = ScanNormed()(
                arguments["state"],
                arguments["key"],
                arguments["value"],
                arguments["query"],
                arguments["beta"],
                arguments["decay"],
            )
        self.assertLess(float((got - reference).abs().max()), 1e-4)

    def test_head_stack_matches_repeat_interleave(self) -> None:
        from compile_scan_step import repeat_each_head

        torch.manual_seed(1)
        heads = torch.randn(2, 8, 16, 128)
        self.assertLess(
            float((repeat_each_head(heads) - heads.repeat_interleave(2, dim=2)).abs().max()),
            1e-6,
        )


class RopeTests(unittest.TestCase):
    def test_masked_rotate_matches_transformers(self) -> None:
        from graphs import rotate_half_masked
        from transformers.models.qwen3_5.modeling_qwen3_5 import rotate_half

        torch.manual_seed(0)
        value = torch.randn(2, 16, 8, 64)
        self.assertLess(float((rotate_half_masked(value) - rotate_half(value)).abs().max()), 1e-6)

    def test_partial_rope_matches_transformers(self) -> None:
        from graphs import apply_partial_rope
        from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb

        torch.manual_seed(1)
        query = torch.randn(2, 16, 8, 256)
        key = torch.randn(2, 4, 8, 256)
        cos = torch.randn(2, 8, 64)
        sin = torch.randn(2, 8, 64)
        with torch.inference_mode():
            got_query = apply_partial_rope(query, cos.unsqueeze(1), sin.unsqueeze(1))
            got_key = apply_partial_rope(key, cos.unsqueeze(1), sin.unsqueeze(1))
            ref_query, ref_key = apply_rotary_pos_emb(query, key, cos, sin)
        self.assertLess(float((got_query - ref_query).abs().max()), 1e-6)
        self.assertLess(float((got_key - ref_key).abs().max()), 1e-6)

    def test_unrolled_heads_match_eager(self) -> None:
        from graphs import causal_mask, unrolled_attention
        from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

        class Probe:
            num_key_value_groups = 4
            training = False

        torch.manual_seed(2)
        query = torch.randn(2, 16, 8, 32)
        key = torch.randn(2, 4, 8, 32)
        value = torch.randn(2, 4, 8, 32)
        mask = causal_mask(query[:, 0])
        with torch.inference_mode():
            got = unrolled_attention(query, key, value, mask, 32**-0.5, 4)
            ref, _ = eager_attention_forward(Probe(), query, key, value, mask, 32**-0.5, 0.0)
        self.assertLess(float((got - ref).abs().max()), 1e-5)
        from graphs import UnrolledAttentionCore

        core = UnrolledAttentionCore().eval()
        with torch.inference_mode():
            packed_query = query.permute(0, 2, 1, 3).reshape(query.shape[0], query.shape[2], -1)
            packed = core(packed_query, key, value)
        self.assertLess(float((packed - ref.reshape(2, 8, -1)).abs().max()), 1e-5)

    def test_one_kv_group_matches_eager(self) -> None:
        from graphs import UnrolledAttentionCore
        from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

        class Probe:
            num_key_value_groups = 4
            training = False

        torch.manual_seed(3)
        query = torch.randn(2, 4, 8, 256)
        key = torch.randn(2, 1, 8, 256)
        value = torch.randn(2, 1, 8, 256)
        length = query.shape[2]
        allowed = torch.ones(length, length, dtype=torch.bool).tril()
        mask = torch.zeros(1, 1, length, length).masked_fill(~allowed, -64.0)
        with torch.inference_mode():
            ref, _ = eager_attention_forward(Probe(), query, key, value, mask, 256**-0.5, 0.0)
            packed_query = query.permute(0, 2, 1, 3).reshape(query.shape[0], query.shape[2], -1)
            packed = UnrolledAttentionCore()(packed_query, key, value)
        self.assertLess(float((packed - ref.reshape(2, 8, -1)).abs().max()), 1e-5)

    def test_four_independent_heads_match_eager(self) -> None:
        from graphs import UnrolledAttentionCore
        from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

        class Probe:
            num_key_value_groups = 1
            training = False

        torch.manual_seed(4)
        query = torch.randn(2, 4, 8, 256)
        key = torch.randn(2, 4, 8, 256)
        value = torch.randn(2, 4, 8, 256)
        length = query.shape[2]
        allowed = torch.ones(length, length, dtype=torch.bool).tril()
        mask = torch.zeros(1, 1, length, length).masked_fill(~allowed, -64.0)
        with torch.inference_mode():
            ref, _ = eager_attention_forward(Probe(), query, key, value, mask, 256**-0.5, 0.0)
            packed_query = query.permute(0, 2, 1, 3).reshape(query.shape[0], query.shape[2], -1)
            packed = UnrolledAttentionCore()(packed_query, key, value)
        self.assertLess(float((packed - ref.reshape(2, 8, -1)).abs().max()), 1e-5)


class DepthwiseConvTests(unittest.TestCase):
    def test_nchw_conv_matches_causal_conv1d(self) -> None:
        from compile_depthwise_conv import CHANNELS, KERNEL, SEQUENCE, CausalDepthwise

        torch.manual_seed(0)
        module = CausalDepthwise().eval()
        hidden = torch.randn(2, CHANNELS, 1, SEQUENCE)
        weight = module.conv.weight[:, 0, 0, :].unsqueeze(1)
        with torch.inference_mode():
            got = module(hidden)[:, :, 0, :]
            reference = torch.nn.functional.conv1d(
                torch.nn.functional.pad(hidden[:, :, 0, :], (KERNEL - 1, 0)),
                weight,
                groups=CHANNELS,
            )
        self.assertLess(float((got - reference).abs().max()), 1e-6)


class AttentionCoreTests(unittest.TestCase):
    def test_causal_core_hides_future_values(self) -> None:
        from compile_attn_core import HEAD, SEQUENCE, PackedAttention

        torch.manual_seed(0)
        module = PackedAttention("mask3").eval()
        base = torch.randn(2, SEQUENCE, HEAD * 3)
        scrambled = base.clone()
        scrambled[:, 1:, HEAD * 2 :] = torch.randn_like(scrambled[:, 1:, HEAD * 2 :])
        with torch.inference_mode():
            left = module(base)
            right = module(scrambled)
        self.assertLess(float((left[:, 0] - right[:, 0]).abs().max()), 1e-6)
        self.assertGreater(float((left[:, -1] - right[:, -1]).abs().max()), 1e-3)


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
