"""Compile the parsed no-RoPE full-attention block.

This is one decoder block with rotary application removed. The HAR is the
parse result. RoPE still crashes the fuser in the unmodified block.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HAR = ROOT / "artifacts" / "clef_experimental_full_attention_no_rope.har"


def compile_block(calibration_rows: int, onnx_path: Path | None = None, net_name: str = "") -> None:
    from hailo_sdk_client import ClientRunner

    if onnx_path is None:
        runner = ClientRunner(har=str(HAR))
    else:
        runner = ClientRunner(hw_arch="hailo10h")
        runner.translate_onnx_model(str(onnx_path), net_name, disable_onnx_simplifier=True)
    print("STATE", runner.state, flush=True)
    for layer in runner._hn.get_input_layers():
        print(f"INPUT {layer.name} {layer.output_shapes}", flush=True)
    if "quant" not in str(runner.state):
        from hailo_model_optimization.algorithms.matmul_equalization.matmul_equalization import (
            MatmulEqualization,
        )

        # Grouped attention is 16 query heads against 4 KV heads. Equalization
        # then subtracts encodings of shape [0, 16] and [0, 4].
        MatmulEqualization.should_skip_algo = lambda self: True
        runner.load_model_script(
            "model_optimization_config(calibration, batch_size=8, "
            f"calibset_size={calibration_rows})\n"
        )
        inputs = list(runner._hn.get_input_layers())
        if len(inputs) == 1:
            shape = [calibration_rows, *inputs[0].output_shapes[0][1:]]
            calib = np.random.default_rng(0).standard_normal(shape).astype(np.float32)
            print("CALIB", calib.shape, flush=True)
        else:
            rng = np.random.default_rng(0)
            calib = {}
            for layer in inputs:
                shape = [calibration_rows, *layer.output_shapes[0][1:]]
                calib[layer.name] = rng.standard_normal(shape).astype(np.float32)
                print("CALIB", layer.name, calib[layer.name].shape, flush=True)
        runner.optimize(calib)
        print("OPTIMIZED", runner.state, flush=True)
    hef = runner.compile()
    name = net_name or "clef_experimental_full_attention_no_rope"
    path = ROOT / "artifacts" / f"{name}.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def export_attention_only() -> None:
    """No-RoPE attention, stopping before the MLP that already has a HEF."""
    import sys as _sys
    import torch
    from pathlib import Path as _Path

    root = _Path(__file__).resolve().parents[1]
    _sys.path.insert(0, str(root / "hailo_port"))
    _sys.path.insert(0, str(root / "hailo_port" / "upstream"))
    from graphs import FullAttentionBlockWithoutRope, causal_mask

    class AttentionOnly(FullAttentionBlockWithoutRope):
        def forward(self, hidden: torch.Tensor) -> torch.Tensor:
            from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

            attention = self.layer.self_attn
            residual = hidden
            normalized = self.layer.input_layernorm(hidden)
            input_shape = normalized.shape[:-1]
            hidden_shape = (*input_shape, -1, attention.head_dim)
            query_states, gate = torch.chunk(
                attention.q_proj(normalized).view(*input_shape, -1, attention.head_dim * 2),
                2,
                dim=-1,
            )
            gate = gate.reshape(*input_shape, -1)
            query_states = attention.q_norm(query_states.view(hidden_shape)).transpose(1, 2)
            key_states = attention.k_norm(attention.k_proj(normalized).view(hidden_shape)).transpose(1, 2)
            value_states = attention.v_proj(normalized).view(hidden_shape).transpose(1, 2)
            attended, _ = eager_attention_forward(
                attention,
                query_states,
                key_states,
                value_states,
                causal_mask(normalized),
                scaling=attention.scaling,
                dropout=0.0,
            )
            attended = attended.reshape(*input_shape, -1).contiguous()
            attended = attention.o_proj(attended * torch.sigmoid(gate))
            return residual + attended

    from run_experiments import load_decoder

    layer, _ = load_decoder(3)
    path = root / "artifacts" / "onnx" / "qwen35_attention_no_rope_no_mlp.onnx"
    torch.onnx.export(
        AttentionOnly(layer).eval(),
        (torch.zeros(1, 8, 4096),),
        path,
        dynamo=True,
        opset_version=18,
        external_data=True,
    )
    print(path, path.stat().st_size, flush=True)


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "export-attention":
        try:
            export_attention_only()
        except Exception:
            traceback.print_exc()
            raise SystemExit(1)
        return
    if len(sys.argv) > 1 and sys.argv[1] == "compile-attention":
        rows = int(sys.argv[2]) if len(sys.argv) > 2 else 64
        try:
            compile_block(
                rows,
                ROOT / "artifacts" / "onnx" / "qwen35_attention_no_rope_no_mlp.onnx",
                "clef_experimental_attention_no_mlp",
            )
        except Exception:
            traceback.print_exc()
            raise SystemExit(1)
        return
    rows = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    try:
        compile_block(rows)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()
