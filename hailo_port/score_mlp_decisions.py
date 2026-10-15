"""Score the Hailo-quantized layer-3 MLP with the FP32 Clef head.

The MLP HEF was quantized from 8 rows at optimization level 0. This checks
whether that error changes the fixed-schema decisions.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
NPZ = ROOT / "artifacts" / "clef_slice" / "mlp_decision_hidden.npz"
REPORT = ROOT / "artifacts" / "clef_slice" / "mlp_decision_agreement.json"
CASES = 12
NAMES = (["paid", "overdue", "draft"], ["true", "false"])


def reference() -> None:
    sys.path.insert(0, str(ROOT / "hailo_port"))
    sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))
    from graphs import MlpOnly
    from run_experiments import load_decoder

    layer, _ = load_decoder(3)
    module = MlpOnly(layer).eval()
    torch.manual_seed(7000)
    samples = torch.randn(CASES, 8, 4096)
    with torch.inference_mode():
        outputs = module(samples).float().numpy()
    NPZ.parent.mkdir(parents=True, exist_ok=True)
    np.savez(NPZ, samples=samples.numpy().astype(np.float32), reference=outputs.astype(np.float32))
    print(NPZ, outputs.shape, flush=True)


def hailo() -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    data = np.load(NPZ)
    runner = ClientRunner(har=str(ROOT / "artifacts" / "clef_experimental_mlp.optimized.har"))
    dataset = data["samples"][:, None, :, :]
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.asarray(runner.infer(ctx, dataset))
    while quantized.ndim > 3:
        quantized = np.squeeze(quantized, axis=1)
    quantized = quantized.reshape(data["reference"].shape).astype(np.float32)
    np.savez(NPZ, samples=data["samples"], reference=data["reference"], quantized=quantized)
    print("quantized", quantized.shape, flush=True)


def score() -> None:
    sys.path.insert(0, str(ROOT / "hailo_port"))
    sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))
    from graphs import StaticJointHead
    from joint_schema_model import JointSchemaHead
    from run_experiments import decision_from_logits
    from safetensors.torch import load_file

    data = np.load(NPZ)
    config = json.loads((ROOT / "artifacts" / "weights" / "joint_head_config.json").read_text())
    head = JointSchemaHead(**config).eval()
    head.load_state_dict(load_file(ROOT / "artifacts" / "weights" / "joint_head.safetensors"), strict=True)
    static = StaticJointHead(head.float(), (3, 2)).eval()
    torch.manual_seed(1)
    embedding = torch.randn(24, 4096)
    token_ids = torch.arange(16)
    spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
    lexical = torch.stack([embedding[token_ids[start:end]].mean(0) for start, end in spans])
    type_ids = torch.tensor([1, 0])
    agreements = 0
    high_confidence = 0
    logit_cosines = []
    prob_abs = []
    with torch.inference_mode():
        for index in range(CASES):
            fp32 = torch.from_numpy(data["reference"][index : index + 1])
            quant = torch.from_numpy(data["quantized"][index : index + 1])
            fp32_logits = static(torch.cat([fp32, fp32], dim=1), lexical, type_ids)
            quant_logits = static(torch.cat([quant, quant], dim=1), lexical, type_ids)
            left = fp32_logits.float().numpy()
            right = quant_logits.float().numpy()
            logit_cosines.append(float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right))))
            fp32_choices = []
            quant_choices = []
            for start, names in ((0, NAMES[0]), (3, NAMES[1])):
                original = decision_from_logits(fp32_logits[start : start + len(names)], names)
                changed = decision_from_logits(quant_logits[start : start + len(names)], names)
                fp32_choices.append(original["choice"])
                quant_choices.append(changed["choice"])
                prob_abs.append(
                    max(
                        abs(original["probabilities"][name] - changed["probabilities"][name])
                        for name in names
                    )
                )
                if (
                    original["choice"] != changed["choice"]
                    and original["margin"] >= 0.2
                    and original["confidence"] >= 0.7
                ):
                    high_confidence += 1
            agreements += int(fp32_choices == quant_choices)
    hidden = data["reference"].astype(np.float64).ravel()
    other = data["quantized"].astype(np.float64).ravel()
    payload = {
        "cases": CASES,
        "decision_agreement": agreements / CASES,
        "high_confidence_disagreements": high_confidence,
        "logit_cosine_min": min(logit_cosines),
        "logit_cosine_mean": float(sum(logit_cosines) / len(logit_cosines)),
        "probability_abs_max": max(prob_abs),
        "hidden_cosine": float(hidden @ other / (np.linalg.norm(hidden) * np.linalg.norm(other))),
        "hidden_max_abs": float(np.max(np.abs(hidden - other))),
        "note": "Layer-3 Hailo quantized MLP, 8 calibration rows, optimization level 0, scored by the FP32 head. Sequence 8 padded to 16 by repetition. Not a full backbone.",
    }
    REPORT.write_text(json.dumps(payload, indent=2))
    print(json.dumps(payload, indent=2), flush=True)


def main() -> None:
    command = sys.argv[1]
    if command == "reference":
        reference()
    elif command == "hailo":
        hailo()
    elif command == "score":
        score()
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main()
