"""One Gated DeltaNet step with the sum on the channel axis.

The exported scan reduces axis -2 and Hailo rejects that ReduceSum. Summing
the key dimension as NCHW channels is the same arithmetic.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import torch
import torch.nn.functional as F


def l2norm(x: torch.Tensor, dim: int = -1, eps: float = 1e-6) -> torch.Tensor:
    inv_norm = torch.rsqrt((x * x).sum(dim=dim, keepdim=True) + eps)
    return x * inv_norm

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


class ScanNormed(torch.nn.Module):
    """Eight steps plus the scan's Q/K L2 norm and ``exp(g)`` decay."""

    def forward(
        self,
        state: torch.Tensor,
        key: torch.Tensor,
        value: torch.Tensor,
        query: torch.Tensor,
        beta: torch.Tensor,
        decay: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        key = l2norm(key, dim=1, eps=1e-6)
        query = l2norm(query, dim=1, eps=1e-6) * (DIM ** -0.5)
        return ScanUnroll()(state, key, value, query, beta, decay.exp())


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


def _normed_arguments(count: int) -> dict[str, torch.Tensor]:
    return nchw_sequence(
        torch.zeros(count, HEADS, DIM, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.randn(count, STEPS, HEADS, DIM),
        torch.rand(count, STEPS, HEADS),
        -F.softplus(torch.randn(count, STEPS, HEADS)),
    )


def export_normed() -> None:
    path = ROOT / "artifacts" / "onnx" / "qwen35_scan_8_l2.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    example = (
        torch.zeros(1, DIM, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, STEPS),
        torch.zeros(1, STEPS, HEADS, DIM),
        torch.zeros(1, DIM, HEADS, STEPS),
        torch.zeros(1, 1, HEADS, STEPS),
        torch.zeros(1, 1, HEADS, STEPS),
    )
    torch.onnx.export(ScanNormed().eval(), example, path, dynamo=True, opset_version=18, external_data=False)
    print(path, path.stat().st_size, flush=True)


def compile_normed(calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = ROOT / "artifacts" / "onnx" / "qwen35_scan_8_l2.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), "clef_experimental_scan_8_l2", disable_onnx_simplifier=True)
    ops = {}
    for layer in runner._hn:
        ops[str(layer.op)] = ops.get(str(layer.op), 0) + 1
    print("LAYERS", ops, flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    arguments = _normed_arguments(max(calibration_rows, 4))
    with torch.inference_mode():
        expected = ScanNormed().eval()(
            *(arguments[name][:4] for name in ("state", "key", "value", "query", "beta", "decay"))
        )
        print(
            f"reference state max {float(expected[0].abs().max()):.4e} "
            f"output max {float(expected[1].abs().max()):.4e}",
            flush=True,
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
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_scan_8_l2.hef"
    out.write_bytes(hef)
    print(f"HEF {out} bytes={len(hef)}", flush=True)


def repeat_each_head(heads: torch.Tensor) -> torch.Tensor:
    """Repeat every head twice. ``stack`` is a concat, not ``repeat_interleave``."""
    paired = torch.stack((heads, heads), dim=3)
    return paired.reshape(heads.shape[0], heads.shape[1], heads.shape[2] * 2, heads.shape[3])


class ConvIntoScan(torch.nn.Module):
    """Layer-0 depthwise conv, SiLU, Q/K/V slices, head repeat, then the normed scan."""

    def __init__(self) -> None:
        super().__init__()
        from compile_depthwise_conv import load_conv

        self.conv = load_conv().conv

    def forward(
        self,
        mixed: torch.Tensor,
        state: torch.Tensor,
        beta: torch.Tensor,
        decay: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        activated = F.silu(self.conv(F.pad(mixed, (3, 0, 0, 0))))
        channels = activated.squeeze(2).transpose(1, 2)
        query = repeat_each_head(channels[:, :, :2048].reshape(channels.shape[0], STEPS, 16, DIM))
        key = repeat_each_head(channels[:, :, 2048:4096].reshape(channels.shape[0], STEPS, 16, DIM))
        value = channels[:, :, 4096:].reshape(channels.shape[0], STEPS, 32, DIM)
        laid = nchw_sequence(state, query, key, value, beta, decay)
        return ScanNormed()(
            laid["state"], laid["key"], laid["value"], laid["query"], laid["beta"], laid["decay"]
        )


def export_conv_scan() -> None:
    path = ROOT / "artifacts" / "onnx" / "qwen35_conv_scan_8.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    example = (
        torch.zeros(1, 8192, 1, STEPS),
        torch.zeros(1, HEADS, DIM, DIM),
        torch.zeros(1, STEPS, HEADS),
        torch.zeros(1, STEPS, HEADS),
    )
    torch.onnx.export(ConvIntoScan().eval(), example, path, dynamo=True, opset_version=18, external_data=False)
    print(path, path.stat().st_size, flush=True)


# Hailo accepts the conv, the Q/K/V slices, and the head-pair concat.
# The following reshape of [1, 8, 16, 2, 128] into [1, 8, 32, 128] is the shuffle it rejects.
CONV_SCAN_ENDS = [
    "node_slice_10",
    "node_slice_15",
    "node_slice_30",
    "node_slice_25",
    "node_slice_23",
    "node_slice_5",
    "node_slice_20",
    "node_slice_40",
    "node_slice_42",
    "node_stack_1",
    "node_stack",
    "node_slice_35",
]


def compile_conv_scan(calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = ROOT / "artifacts" / "onnx" / "qwen35_conv_scan_8.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(path),
        "clef_experimental_conv_scan_8",
        start_node_names=["mixed", "decay", "beta"],
        end_node_names=CONV_SCAN_ENDS,
        disable_onnx_simplifier=True,
    )
    ops = {}
    for layer in runner._hn:
        ops[str(layer.op)] = ops.get(str(layer.op), 0) + 1
    print("LAYERS", ops, flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    count = max(calibration_rows, 4)
    mixed = torch.randn(count, 8192, 1, STEPS)
    beta = torch.rand(count, STEPS, HEADS)
    decay = -F.softplus(torch.randn(count, STEPS, HEADS))
    tensors = {"mixed": mixed, "beta": beta, "decay": decay}
    calib = {}
    for layer in runner._hn.get_input_layers():
        source = next(name for name in tensors if name in " ".join(layer.original_names))
        flat = tensors[source][:calibration_rows].numpy().astype(np.float32)
        if flat.ndim == 4:
            flat = np.transpose(flat, (0, 2, 3, 1))
        want = tuple(calibration_rows if dim < 0 else dim for dim in layer.output_shapes[0])
        calib[layer.name] = flat.reshape(want)
        print(f"INPUT {layer.name} {source} {calib[layer.name].shape}", flush=True)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    sample = {name: value[:4] for name, value in calib.items()}
    with runner.infer_context(InferenceContext.SDK_FP_OPTIMIZED) as native_ctx:
        native = runner.infer(native_ctx, sample)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as quant_ctx:
        quantized = runner.infer(quant_ctx, sample)
    natives = native if isinstance(native, (list, tuple)) else [native]
    quants = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (left, right) in enumerate(zip(natives, quants)):
        left_v = np.asarray(left, dtype=np.float64).ravel()
        right_v = np.asarray(right, dtype=np.float64).ravel()
        denom = np.linalg.norm(left_v) * np.linalg.norm(right_v)
        cosine = float(left_v @ right_v / denom) if denom else 0.0
        print(
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(left_v - right_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_conv_scan_8.hef"
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
        elif command == "export-8-l2":
            export_normed()
        elif command == "compile-8-l2":
            compile_normed(int(sys.argv[2]) if len(sys.argv) > 2 else 64)
        elif command == "export-conv-scan":
            export_conv_scan()
        elif command == "compile-conv-scan":
            compile_conv_scan(int(sys.argv[2]) if len(sys.argv) > 2 else 16)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()
