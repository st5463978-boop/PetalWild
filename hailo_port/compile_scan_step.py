"""One Gated DeltaNet step with the sum on the channel axis.

The exported scan reduces axis -2 and Hailo rejects that ReduceSum. Summing
the key dimension as NCHW channels is the same arithmetic.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
ONNX = ROOT / "artifacts" / "onnx" / "qwen35_scan_step.onnx"
HEADS = 32
DIM = 128
STEPS = 8


class ScanStep(torch.nn.Module):
    def forward(
        self,
        state: torch.Tensor,
        key: torch.Tensor,
        value: torch.Tensor,
        query: torch.Tensor,
        beta: torch.Tensor,
        decay: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        # state [B, key, heads, value]. decay is already exp(g).
        state = state * decay
        remembered = (state * key).sum(dim=1, keepdim=True)
        delta = (value - remembered) * beta
        state = state + key * delta
        output = (state * query).sum(dim=1, keepdim=True)
        return state, output


class ScanUnroll(torch.nn.Module):
    """Eight steps. Time is sliced off the last axis, or off axis 1 for values."""

    def forward(
        self,
        state: torch.Tensor,
        key: torch.Tensor,
        value: torch.Tensor,
        query: torch.Tensor,
        beta: torch.Tensor,
        decay: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        step = ScanStep()
        outputs = []
        for index in range(STEPS):
            state, output = step(
                state,
                key[:, :, :, index : index + 1],
                value[:, index : index + 1],
                query[:, :, :, index : index + 1],
                beta[:, :, :, index : index + 1],
                decay[:, :, :, index : index + 1],
            )
            outputs.append(output)
        return state, torch.cat(outputs, dim=1)


def nchw_sequence(state, query, key, value, beta, decay):
    """query, key are [B, T, heads, dim]. value is [B, T, heads, dim]. beta and decay are [B, T, heads]."""
    return {
        "state": state.permute(0, 2, 1, 3),
        "key": key.permute(0, 3, 2, 1),
        "value": value,
        "query": query.permute(0, 3, 2, 1),
        "beta": beta.permute(0, 2, 1).unsqueeze(1),
        "decay": decay.permute(0, 2, 1).unsqueeze(1),
    }


def loop_step(state, query_t, key_t, value_t, beta_t, decay_t):
    """One iteration of ``gated_delta_scan``, without the L2 norm."""
    state = state * decay_t.unsqueeze(-1).unsqueeze(-1)
    remembered = (state * key_t.unsqueeze(-1)).sum(dim=-2)
    delta = (value_t - remembered) * beta_t.unsqueeze(-1)
    state = state + key_t.unsqueeze(-1) * delta.unsqueeze(-2)
    output = (state * query_t.unsqueeze(-1)).sum(dim=-2)
    return state, output


def nchw_arguments(state, query_t, key_t, value_t, beta_t, decay_t):
    """Permute one scan iteration into NCHW. beta_t and decay_t are [B, heads]."""
    return {
        "state": state.permute(0, 2, 1, 3),
        "key": key_t.permute(0, 2, 1).unsqueeze(-1),
        "value": value_t.unsqueeze(1),
        "query": query_t.permute(0, 2, 1).unsqueeze(-1),
        "beta": beta_t.unsqueeze(1).unsqueeze(-1),
        "decay": decay_t.unsqueeze(1).unsqueeze(-1),
    }


def export_step() -> None:
    ONNX.parent.mkdir(parents=True, exist_ok=True)
    example = (
        torch.zeros(1, DIM, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, 1),
        torch.zeros(1, 1, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, 1),
        torch.zeros(1, 1, HEADS, 1),
        torch.zeros(1, 1, HEADS, 1),
    )
    torch.onnx.export(ScanStep().eval(), example, ONNX, dynamo=True, opset_version=18, external_data=False)
    print(ONNX, ONNX.stat().st_size, flush=True)


def compile_step(calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(ONNX), "clef_experimental_scan_step", disable_onnx_simplifier=True)
    for layer in runner._hn:
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    count = max(calibration_rows, 4)
    arguments = nchw_arguments(
        torch.randn(count, HEADS, DIM, DIM),
        torch.randn(count, HEADS, DIM),
        torch.randn(count, HEADS, DIM),
        torch.randn(count, HEADS, DIM),
        torch.rand(count, HEADS),
        torch.rand(count, HEADS),
    )
    with torch.inference_mode():
        expected = ScanStep().eval()(*(arguments[name][:4] for name in ("state", "key", "value", "query", "beta", "decay")))
    calib = {}
    for layer in runner._hn.get_input_layers():
        source = next(name for name in arguments if name in " ".join(layer.original_names))
        flat = arguments[source].numpy().astype(np.float32)
        # NCHW [N,C,H,W] -> NHWC [N,H,W,C], which is how Hailo stores rank 4.
        calib[layer.name] = np.transpose(flat[:calibration_rows], (0, 2, 3, 1))
        print(f"CALIB {layer.name} {source} {calib[layer.name].shape}", flush=True)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    sample = {name: value[:4] for name, value in calib.items()}
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = runner.infer(ctx, sample)
    outputs = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (got, expect) in enumerate(zip(outputs, expected)):
        got_v = np.asarray(got, dtype=np.float64)
        print(f"output {index} shape {got_v.shape} expect {tuple(expect.shape)}", flush=True)
        got_v = np.transpose(got_v, (0, 3, 1, 2))
        expect_v = expect.numpy().astype(np.float64)
        got_v = got_v.reshape(expect_v.shape)
        cosine = float(got_v.ravel() @ expect_v.ravel() / (np.linalg.norm(got_v) * np.linalg.norm(expect_v)))
        print(
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(got_v - expect_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    path = ROOT / "artifacts" / "clef_slice" / "clef_experimental_scan_step.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def export_unroll() -> None:
    path = ROOT / "artifacts" / "onnx" / "qwen35_scan_8.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    example = (
        torch.zeros(1, DIM, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, STEPS),
        torch.zeros(1, STEPS, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, STEPS),
        torch.zeros(1, 1, HEADS, STEPS),
        torch.zeros(1, 1, HEADS, STEPS),
    )
    torch.onnx.export(ScanUnroll().eval(), example, path, dynamo=True, opset_version=18, external_data=False)
    print(path, path.stat().st_size, flush=True)


def compile_unroll(calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = ROOT / "artifacts" / "onnx" / "qwen35_scan_8.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), "clef_experimental_scan_8", disable_onnx_simplifier=True)
    ops = {}
    for layer in runner._hn:
        ops[str(layer.op)] = ops.get(str(layer.op), 0) + 1
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    print("LAYERS", ops, flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    count = max(calibration_rows, 4)
    arguments = nchw_sequence(
        torch.randn(count, HEADS, DIM, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.rand(count, STEPS, HEADS),
        torch.rand(count, STEPS, HEADS),
    )
    with torch.inference_mode():
        expected = ScanUnroll().eval()(
            *(arguments[name][:4] for name in ("state", "key", "value", "query", "beta", "decay"))
        )
    calib = {}
    for layer in runner._hn.get_input_layers():
        source = next(name for name in arguments if name in " ".join(layer.original_names))
        flat = arguments[source].numpy().astype(np.float32)
        calib[layer.name] = np.transpose(flat[:calibration_rows], (0, 2, 3, 1))
        print(f"CALIB {layer.name} {source} {calib[layer.name].shape}", flush=True)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    sample = {name: value[:4] for name, value in calib.items()}
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = runner.infer(ctx, sample)
    outputs = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (got, expect) in enumerate(zip(outputs, expected)):
        got_v = np.transpose(np.asarray(got, dtype=np.float64), (0, 3, 1, 2))
        expect_v = expect.numpy().astype(np.float64)
        print(f"output {index} shape {got_v.shape} expect {expect_v.shape}", flush=True)
        got_v = got_v.reshape(expect_v.shape)
        cosine = float(got_v.ravel() @ expect_v.ravel() / (np.linalg.norm(got_v) * np.linalg.norm(expect_v)))
        print(
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(got_v - expect_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_scan_8.hef"
    out.write_bytes(hef)
    print(f"HEF {out} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    try:
        if command == "export":
            export_step()
        elif command == "compile":
            compile_step(int(sys.argv[2]) if len(sys.argv) > 2 else 64)
        elif command == "export-8":
            export_unroll()
        elif command == "compile-8":
            compile_unroll(int(sys.argv[2]) if len(sys.argv) > 2 else 64)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()
