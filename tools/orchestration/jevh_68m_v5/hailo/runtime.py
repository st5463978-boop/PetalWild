"""Hailo-10H device probe. Inference is attempted only when the device and HailoRT import."""
from __future__ import annotations

from pathlib import Path


def probe() -> dict:
    devices = [str(path) for path in (Path("/dev/hailo0"), Path("/dev/hailo1")) if path.exists()]
    try:
        import hailo_platform
    except Exception as exc:
        return {
            "device_nodes": devices,
            "device": bool(devices),
            "hailo_platform": "",
            "import_error": f"{type(exc).__name__}: {exc}",
        }
    version = str(getattr(hailo_platform, "__version__", "imported"))
    return {
        "device_nodes": devices,
        "device": bool(devices),
        "hailo_platform": version,
        "import_error": "",
    }


def assert_ready() -> None:
    state = probe()
    if state["import_error"]:
        raise RuntimeError(state["import_error"])
    if not state["device"]:
        raise RuntimeError("no /dev/hailo0 or /dev/hailo1 node")


def infer_pairs(hef_path: str, pairs: list[tuple[list[int], list[int]]]) -> list[float]:
    """Run one (input_ids, attention_mask) pair at a time on the Hailo-10H.

    Input tensors are integer-valued float32, the same values DFC optimize
    consumes. The vstream shape, once the HEF is loaded, picks singleton axes.
    """
    assert_ready()
    import numpy as np
    from hailo.calib import fit_input
    from hailo_platform import (
        ConfigureParams,
        FormatType,
        HEF,
        HailoStreamInterface,
        InferVStreams,
        InputVStreamParams,
        OutputVStreamParams,
        VDevice,
    )

    hef = HEF(hef_path)
    logits: list[float] = []
    with VDevice() as target:
        params = ConfigureParams.create_from_hef(hef, interface=HailoStreamInterface.PCIe)
        network_group = target.configure(hef, params)[0]
        group_params = network_group.create_params()
        in_params = InputVStreamParams.make(network_group, format_type=FormatType.FLOAT32)
        out_params = OutputVStreamParams.make(network_group, format_type=FormatType.FLOAT32)
        inputs = list(hef.get_input_vstream_infos())
        with InferVStreams(network_group, in_params, out_params) as pipeline:
            with network_group.activate(group_params):
                for ids, mask in pairs:
                    feed = {}
                    for info in inputs:
                        name = info.name
                        shape = tuple(int(dim) for dim in info.shape)
                        source = mask if "mask" in name.lower() else ids
                        block = np.asarray(source, dtype=np.float32).reshape(1, -1)
                        # Batch is already 1 inside `shape` for a static HEF.
                        if shape and shape[0] == 1:
                            fitted = fit_input(block, shape)
                        else:
                            fitted = fit_input(block, (-1, *shape))
                        feed[name] = fitted
                    if not any("mask" in key.lower() for key in feed):
                        raise RuntimeError(f"HEF inputs have no attention_mask: {list(feed)}")
                    result = pipeline.infer(feed)
                    values = np.asarray(next(iter(result.values())) if isinstance(result, dict) else result)
                    logits.append(float(values.reshape(-1)[0]))
    if len(logits) != len(pairs):
        raise RuntimeError(f"HEF returned {len(logits)} logits for {len(pairs)} pairs")
    return logits
