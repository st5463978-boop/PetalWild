"""Compile the JEV-H 68M v5 student with Hailo DFC for hailo10h.

Exit 0 only when a HEF file has been written. That file is not hardware-tested.
This script does not download the Dataflow Compiler and does not invent
calibration tensors.
"""
from __future__ import annotations

import argparse
import json
import sys
import traceback
from pathlib import Path

from hailo.calib import CalibError, load_pair, stats
from hailo.contract import (
    ART,
    CKPT_NAMES,
    EXPECTED_ONNX_BYTES,
    EXPECTED_ONNX_SHA256,
    ONNX_NAME,
    ROOT,
)
from hailo.onnx_graph import GraphError, assert_contract, rewrite_gelu, summarize
from hailo.runtime import probe as device_probe

BASE_SCRIPT = """\
model_optimization_config(calibration, batch_size=8, calibset_size={rows})
pre_quantization_optimization(equalization, policy=enabled)
pre_quantization_optimization(bias_correction, policy=enabled)
"""

HIGH_PREC_OPS = {"matmul", "conv", "ew_add", "softmax"}


def _write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def _fail(receipt_path: Path, payload: dict, code: int) -> int:
    payload["hardware_tested"] = False
    payload["hef_sha256"] = None
    _write(receipt_path, payload)
    print(json.dumps({"status": payload["status"], "stage": payload["stage"], "error": payload["error"]}), flush=True)
    return code


def prepare_onnx(onnx_path: Path, work: Path) -> tuple[Path, dict]:
    summary = summarize(onnx_path)
    notes = {"source": summary, "rewritten_gelu": 0}
    graph_path = onnx_path
    if "Gelu" in summary["ops"]:
        graph_path = work / "jevh_68m_v5_seq128.gelu_erf.onnx"
        notes.update(rewrite_gelu(onnx_path, graph_path))
        summary = summarize(graph_path)
        notes["after_gelu_rewrite"] = summary
    assert_contract(summary)
    notes["compile_graph"] = str(graph_path)
    return graph_path, notes


def _input_layers(runner):
    hn = runner._hn
    if hasattr(hn, "get_input_layers"):
        return list(hn.get_input_layers())
    return [layer for layer in hn if str(getattr(layer, "op", "")).lower() in {"input_layer", "input"}]


def _script(runner, rows: int) -> str:
    lines = [BASE_SCRIPT.format(rows=rows).rstrip()]
    for layer in runner._hn:
        op = str(getattr(layer, "op", "")).lower()
        if op in HIGH_PREC_OPS:
            lines.append(f"quantization_param([{layer.name}], precision_mode=a16_w16)")
    return "\n".join(lines) + "\n"


def _calib_feed(runner, ids, mask):
    import numpy as np

    from hailo.calib import fit_input

    layers = _input_layers(runner)
    names = [layer.name for layer in layers]
    if not any("mask" in name.lower() for name in names):
        raise CalibError(
            "DFC parse has no attention_mask input "
            f"(inputs={names}). Refusing to quantize; this is the dropped-mask failure."
        )
    feed = {}
    used = set()
    for layer in layers:
        name = layer.name.lower()
        if "mask" in name:
            source = mask
        elif "input" in name or name.endswith("ids") or "ids" in name:
            source = ids
        else:
            raise CalibError(f"parsed input {layer.name!r} is neither input_ids nor attention_mask")
        if id(source) in used and len(layers) > 1:
            raise CalibError(f"two parsed inputs resolved to the same tensor ({layer.name})")
        shape = list(layer.output_shapes[0])
        values = np.asarray(source, dtype=np.float32)
        feed[layer.name] = fit_input(values, shape)
        used.add(id(source))
    if len(feed) < 2:
        raise CalibError(f"expected input_ids and attention_mask, parsed {names}")
    return feed


def compile_with_dfc(graph: Path, ids, mask, hef_path: Path, net_name: str) -> dict:
    try:
        from hailo_sdk_client import ClientRunner
    except ImportError as exc:
        raise ImportError(
            "ModuleNotFoundError: No module named 'hailo_sdk_client'. "
            "Hailo DFC is not installed in this environment. "
            "The proprietary wheel is not downloaded or committed by this script. "
            f"Original error: {exc}"
        ) from exc
    if hef_path.exists():
        raise FileExistsError(f"refusing to overwrite {hef_path}")
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(graph), net_name, disable_onnx_simplifier=True)
    script = _script(runner, rows=int(ids.shape[0]))
    runner.load_model_script(script)
    feed = _calib_feed(runner, ids, mask)
    runner.optimize(feed)
    hef = runner.compile()
    if not isinstance(hef, (bytes, bytearray)) or len(hef) < 64:
        raise RuntimeError(f"DFC compile returned {type(hef).__name__} length={getattr(hef, '__len__', lambda: 0)()}")
    hef_path.parent.mkdir(parents=True, exist_ok=True)
    hef_path.write_bytes(hef)
    import hashlib

    return {
        "hef_path": str(hef_path),
        "hef_bytes": hef_path.stat().st_size,
        "hef_sha256": hashlib.sha256(hef_path.read_bytes()).hexdigest(),
        "model_script": script,
        "hardware_tested": False,
    }


def structure_probe() -> dict:
    """Export an untrained student and record operator types. Not a checkpoint."""
    try:
        import torch
    except ImportError as exc:
        return {"ran": False, "weights": "none", "error": f"{type(exc).__name__}: {exc}"}
    from model import Ettin68mScorer
    from train import export_onnx

    from hailo.onnx_graph import assert_contract, summarize

    path = ART / "_structure_probe.onnx"
    try:
        torch.manual_seed(0)
        model = Ettin68mScorer().eval()
        export_onnx(model, path, torch.device("cpu"))
        summary = summarize(path)
        assert_contract(summary)
    except Exception as exc:
        return {"ran": False, "weights": "random Ettin68mScorer init, not a checkpoint", "error": f"{type(exc).__name__}: {exc}"}
    finally:
        if path.exists():
            path.unlink()
        external = Path(str(path) + ".data")
        if external.exists():
            external.unlink()
    summary["ran"] = True
    summary["weights"] = "random Ettin68mScorer init, not a checkpoint"
    summary["contract_ok"] = True
    summary["error"] = ""
    summary["random_onnx_sha256"] = summary.pop("sha256")
    summary["random_onnx_bytes"] = summary.pop("bytes")
    summary["note"] = "Deleted after inspection. This sha is not the round-2 student."
    return summary


def missing_onnx_message(path: Path) -> str:
    ckpts = [str(ART / name) for name in CKPT_NAMES]
    present = [item for item in ckpts if Path(item).is_file()]
    return (
        f"ONNX not found at {path}. The round-2 receipt names {ONNX_NAME} "
        f"sha256 {EXPECTED_ONNX_SHA256} size {EXPECTED_ONNX_BYTES}, and .gitignore excludes artifacts/*.onnx. "
        "The PyTorch source of that export is cat(-x2, x1), which lowers to Neg-into-Concat "
        "and crashes DFC 5.4.0 in _handle_neg_feature_shuffle. "
        "model.py now uses a sign-swap RoPE and gelu_erf, so the next export is the one to compile. "
        f"Re-export from a round-2 checkpoint ({', '.join(CKPT_NAMES)}); found on disk: {present or 'none'}. "
        "Refusing to synthesize a graph or a calibration set."
    )


def _dfc_probe() -> dict:
    try:
        import hailo_sdk_client
    except Exception as exc:
        return {"installed": False, "error": f"{type(exc).__name__}: {exc}"}
    return {"installed": True, "error": "", "module": getattr(hailo_sdk_client, "__file__", "hailo_sdk_client")}


def run(onnx_path: Path, ids_path: Path, mask_path: Path, hef_path: Path, receipt_path: Path) -> int:
    payload: dict = {
        "status": "blocked",
        "stage": "start",
        "target": "hailo10h",
        "net_name": "jevh_68m_v5_seq128",
        "hardware_tested": False,
        "error": "",
        "expected_onnx_sha256": EXPECTED_ONNX_SHA256,
        "device": device_probe(),
        "dfc": _dfc_probe(),
        "checkpoints_present": [name for name in CKPT_NAMES if (ART / name).is_file()],
    }
    try:
        ids, mask = load_pair(ids_path, mask_path)
    except CalibError as exc:
        payload["stage"] = "calib"
        payload["error"] = str(exc)
        return _fail(receipt_path, payload, 2)
    payload["calib"] = stats(ids, mask, ids_path, mask_path)
    if not onnx_path.is_file():
        payload["stage"] = "onnx_missing"
        payload["structure_probe"] = structure_probe()
        payload["error"] = missing_onnx_message(onnx_path)
        return _fail(receipt_path, payload, 3)
    try:
        graph, notes = prepare_onnx(onnx_path, ART)
    except GraphError as exc:
        payload["stage"] = "onnx_graph"
        payload["error"] = str(exc)
        return _fail(receipt_path, payload, 3)
    payload["onnx"] = notes
    try:
        compiled = compile_with_dfc(graph, ids, mask, hef_path, payload["net_name"])
    except ImportError as exc:
        payload["stage"] = "dfc_missing"
        payload["error"] = str(exc)
        return _fail(receipt_path, payload, 4)
    except Exception as exc:
        payload["stage"] = "dfc"
        payload["error"] = f"{type(exc).__name__}: {exc}\n{traceback.format_exc()}"
        return _fail(receipt_path, payload, 4)
    payload.update(compiled)
    payload["status"] = "hef_written"
    payload["stage"] = "compile"
    payload["error"] = ""
    payload["hardware_tested"] = False
    payload["note"] = "HEF bytes were written by the DFC. Accuracy and latency on a Hailo-10H were not measured."
    _write(receipt_path, payload)
    print(json.dumps({"status": payload["status"], "hef_sha256": payload["hef_sha256"], "hardware_tested": False}))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Compile JEV-H 68M v5 to a Hailo-10H HEF")
    parser.add_argument("--onnx", type=Path, default=ART / ONNX_NAME)
    parser.add_argument("--calib-ids", type=Path, default=ART / "calib_input_ids.npy")
    parser.add_argument("--calib-mask", type=Path, default=ART / "calib_attention_mask.npy")
    parser.add_argument("--hef", type=Path, default=ART / "jevh_68m_v5_seq128.hef")
    parser.add_argument("--receipt", type=Path, default=ART / "hailo_compile_receipt.json")
    args = parser.parse_args(argv)
    return run(args.onnx, args.calib_ids, args.calib_mask, args.hef, args.receipt)


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    raise SystemExit(main())
