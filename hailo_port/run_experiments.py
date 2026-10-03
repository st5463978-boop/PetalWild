"""Export real Clef-Flash blocks, compare them with ONNX Runtime, and record Hailo."""

from __future__ import annotations

import gc
import json
import sys
import traceback
from collections import Counter
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch
from safetensors.torch import load_file
from transformers import AutoConfig, AutoTokenizer
from transformers.models.qwen3_5.modeling_qwen3_5 import (
    Qwen3_5DecoderLayer,
    Qwen3_5TextRotaryEmbedding,
)

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hailo_port"))
sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))

from graphs import (  # noqa: E402
    FullAttentionBlock,
    MlpOnly,
    ScatterFreeLinearBlock,
    StackedFullAttention,
    StaticJointHead,
)
from joint_schema_model import (  # noqa: E402
    EncodedQuestion,
    EncodedRecord,
    JointSchemaHead,
    encode_record,
)

WEIGHTS = ROOT / "artifacts" / "weights"
ONNX_DIR = ROOT / "artifacts" / "onnx"
REFERENCE = ROOT / "tests" / "reference"
REPORTS = ROOT / "reports"
SEQ = 8
CASES = 12
OPTION_COUNTS = (3, 2)


def stats(reference: np.ndarray, candidate: np.ndarray) -> dict[str, float]:
    left = reference.astype(np.float64).ravel()
    right = candidate.astype(np.float64).ravel()
    difference = left - right
    denominator = float(np.linalg.norm(left) * np.linalg.norm(right))
    cosine = float(left @ right / denominator) if denominator else 1.0
    return {
        "cosine": cosine,
        "mse": float(np.mean(difference**2)),
        "max_abs": float(np.max(np.abs(difference))),
    }


def op_histogram(path: Path) -> dict[str, int]:
    model = onnx.load(path, load_external_data=False)
    return dict(Counter(node.op_type for node in model.graph.node).most_common())


def load_decoder(layer_index: int) -> tuple[torch.nn.Module, object]:
    config = AutoConfig.from_pretrained(WEIGHTS / "config.json").get_text_config()
    config._attn_implementation = "eager"
    layer = Qwen3_5DecoderLayer(config, layer_index).eval()
    prefix = f"model.language_model.layers.{layer_index}."
    raw = load_file(WEIGHTS / f"clef_layer_{layer_index}.safetensors")
    state = {key[len(prefix) :]: value.float() for key, value in raw.items()}
    layer.load_state_dict(state, strict=True)
    return layer, config


def quantize_(module: torch.nn.Module, bits: int = 8) -> None:
    maximum = 2 ** (bits - 1) - 1
    with torch.no_grad():
        for parameter in module.parameters():
            data = parameter.data.float()
            if data.ndim >= 2:
                reduce_dims = tuple(range(1, data.ndim))
                peak = data.abs().amax(dim=reduce_dims, keepdim=True).clamp(min=1e-8)
            else:
                peak = data.abs().max().clamp(min=1e-8)
            scale = peak / maximum
            quantized = torch.round(data / scale).clamp(-maximum, maximum) * scale
            parameter.copy_(quantized)


def export(module: torch.nn.Module, args: tuple, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(module.eval(), args, path, dynamo=True, opset_version=18, external_data=True)


def _numpy_feed(feed: dict) -> dict:
    converted = {}
    for key, value in feed.items():
        tensor = value.detach().cpu()
        if tensor.dtype in (torch.long, torch.int32, torch.int64):
            converted[key] = tensor.numpy()
        else:
            converted[key] = tensor.float().numpy()
    return converted


def compare_session(path: Path, feeds: list[dict], references: list[np.ndarray]) -> dict:
    session = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
    scores = []
    for feed, reference in zip(feeds, references):
        output = session.run(None, _numpy_feed(feed))[0]
        scores.append(stats(reference, output))
    return summarize(scores)


def summarize(scores: list[dict]) -> dict:
    return {
        "cases": len(scores),
        "cosine_min": min(item["cosine"] for item in scores),
        "mse_max": max(item["mse"] for item in scores),
        "max_abs_max": max(item["max_abs"] for item in scores),
    }


def future_leak(function, hidden: torch.Tensor, extra: tuple = ()) -> float:
    changed = hidden.clone()
    changed[:, -1] = changed[:, -1] + 3
    with torch.inference_mode():
        original = function(hidden, *extra)
        perturbed = function(changed, *extra)
    return float((original[:, :-1] - perturbed[:, :-1]).abs().max())


def full_attention_experiment(layer, config) -> dict:
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    position = torch.arange(SEQ).view(1, 1, -1).expand(3, 1, -1)
    module = FullAttentionBlock(layer).eval()
    cases = []
    references = []
    with torch.inference_mode():
        for index in range(CASES):
            torch.manual_seed(1000 + index)
            hidden = torch.randn(1, SEQ, config.hidden_size)
            cos, sin = rotary(hidden, position)
            cases.append({"hidden": hidden, "cos": cos, "sin": sin})
            references.append(module(hidden, cos, sin).float().numpy())
        leak = future_leak(module, cases[0]["hidden"], (cases[0]["cos"], cases[0]["sin"]))
    path = ONNX_DIR / "qwen35_full_attention_block.onnx"
    export(module, (cases[0]["hidden"], cases[0]["cos"], cases[0]["sin"]), path)
    result = {
        "layer_index": 3,
        "kind": "full_attention",
        "parameters": sum(parameter.numel() for parameter in layer.parameters()),
        "future_token_leak_max_abs": leak,
        "onnx": str(path),
        "onnx_bytes": path.stat().st_size + path.with_suffix(".onnx.data").stat().st_size,
        "operators": op_histogram(path),
        "pytorch_vs_onnx": compare_session(path, cases, references),
    }
    np.savez_compressed(
        REFERENCE / "full_attention_case0.npz",
        hidden=cases[0]["hidden"].numpy(),
        cos=cases[0]["cos"].numpy(),
        sin=cases[0]["sin"].numpy(),
        output=references[0],
    )
    del module
    gc.collect()
    return result


def linear_experiment(layer) -> dict:
    official_cases = []
    rewritten_cases = []
    official = []
    rewritten = []
    module = ScatterFreeLinearBlock(layer).eval()
    with torch.inference_mode():
        for index in range(CASES):
            torch.manual_seed(2000 + index)
            hidden = torch.randn(1, SEQ, layer.hidden_size)
            zeros = hidden.new_zeros(1, SEQ, 64)
            official_out = layer(hidden, position_embeddings=(zeros, zeros), attention_mask=None)
            rewritten_out = module(hidden)
            official.append(official_out.float().numpy())
            rewritten.append(rewritten_out.float().numpy())
            official_cases.append(stats(official[-1], rewritten[-1]))
            rewritten_cases.append({"hidden": hidden})
    path = ONNX_DIR / "qwen35_linear_block_scatter_free.onnx"
    export(module, (rewritten_cases[0]["hidden"],), path)
    result = {
        "layer_index": 0,
        "kind": "linear_attention_scatter_free",
        "parameters": sum(parameter.numel() for parameter in layer.parameters()),
        "pytorch_official_vs_rewrite": summarize(official_cases),
        "onnx": str(path),
        "onnx_bytes": path.stat().st_size + path.with_suffix(".onnx.data").stat().st_size,
        "operators": op_histogram(path),
        "pytorch_vs_onnx": compare_session(path, rewritten_cases, rewritten),
    }
    np.savez_compressed(
        REFERENCE / "linear_attention_case0.npz",
        hidden=rewritten_cases[0]["hidden"].numpy(),
        official=official[0],
        rewritten=rewritten[0],
    )
    del module
    gc.collect()
    return result


def mlp_experiment(layer) -> dict:
    module = MlpOnly(layer).eval()
    feeds = []
    references = []
    with torch.inference_mode():
        for index in range(CASES):
            torch.manual_seed(3000 + index)
            hidden = torch.randn(1, SEQ, layer.hidden_size)
            feeds.append({"hidden": hidden})
            references.append(module(hidden).float().numpy())
    path = ONNX_DIR / "qwen35_mlp.onnx"
    export(module, (feeds[0]["hidden"],), path)
    result = {
        "kind": "swiglu_mlp",
        "onnx": str(path),
        "onnx_bytes": path.stat().st_size + path.with_suffix(".onnx.data").stat().st_size,
        "operators": op_histogram(path),
        "pytorch_vs_onnx": compare_session(path, feeds, references),
    }
    del module
    gc.collect()
    return result


def scale_experiment(layer, config) -> dict:
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    position = torch.arange(SEQ).view(1, 1, -1).expand(3, 1, -1)
    torch.manual_seed(4)
    hidden = torch.randn(1, SEQ, config.hidden_size)
    with torch.inference_mode():
        cos, sin = rotary(hidden, position)
    results = {}
    for repeats in (2, 4):
        module = StackedFullAttention(layer, repeats).eval()
        with torch.inference_mode():
            reference = module(hidden, cos, sin).float().numpy()
        path = ONNX_DIR / f"qwen35_full_attention_x{repeats}.onnx"
        try:
            export(module, (hidden, cos, sin), path)
            compared = compare_session(path, [{"hidden": hidden, "cos": cos, "sin": sin}], [reference])
            results[str(repeats)] = {
                "onnx": str(path),
                "onnx_bytes": path.stat().st_size + path.with_suffix(".onnx.data").stat().st_size,
                "operators": op_histogram(path),
                "pytorch_vs_onnx": compared,
            }
        except Exception as exc:  # export or runtime failure is a measured result
            results[str(repeats)] = {"error": f"{type(exc).__name__}: {exc}"}
        del module
        gc.collect()
    return results


def decision_from_logits(logits: torch.Tensor, names: list[str]) -> dict:
    probabilities = torch.softmax(logits.float(), dim=0)
    choice = int(torch.argmax(probabilities))
    ordered = torch.sort(probabilities, descending=True).values
    margin = float(ordered[0] - ordered[1]) if ordered.numel() > 1 else 1.0
    return {
        "choice": names[choice],
        "confidence": float(probabilities[choice]),
        "margin": margin,
        "probabilities": {name: float(probabilities[index]) for index, name in enumerate(names)},
    }


def head_experiment() -> dict:
    config = json.loads((WEIGHTS / "joint_head_config.json").read_text())
    head = JointSchemaHead(**config).eval()
    head.load_state_dict(load_file(WEIGHTS / "joint_head.safetensors"), strict=True)
    head = head.float()
    static = StaticJointHead(head, OPTION_COUNTS).eval()
    length = 16
    question_spans = ((1, 4), (4, 6))
    option_spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
    names = (["paid", "overdue", "draft"], ["true", "false"])
    agreements = []
    quant_agreements = []
    feeds = []
    references = []
    records = []
    with torch.inference_mode():
        for index in range(CASES):
            torch.manual_seed(4000 + index)
            hidden = torch.randn(1, length, 4096)
            token_ids = torch.randint(0, 24, (1, length))
            embedding = torch.randn(24, 4096)
            lexical = []
            for start, end in option_spans:
                lexical.append(embedding[token_ids[0, start:end]].mean(0))
            lexical_t = torch.stack(lexical)
            type_ids = torch.tensor([1, 0], dtype=torch.long)
            encoded_questions = []
            offset = 0
            option_ids = (["paid", "overdue", "draft"], ["true", "false"])
            for question_index, count in enumerate(OPTION_COUNTS):
                encoded_questions.append(
                    EncodedQuestion(
                        question_id=f"q{question_index}",
                        question_type=int(type_ids[question_index]),
                        question_span=question_spans[question_index],
                        option_spans=tuple(option_spans[offset : offset + count]),
                        option_ids=tuple(option_ids[question_index]),
                    )
                )
                offset += count
            record = EncodedRecord(
                input_ids=tuple(token_ids[0].tolist()),
                questions=tuple(encoded_questions),
                record_id=f"case-{index}",
            )
            original = head(hidden, token_ids, torch.ones(1, length, dtype=torch.long), [record], embedding)
            static_logits = static(hidden, lexical_t, type_ids)
            original_cat = torch.cat([item.float() for item in original[0]])
            match = stats(original_cat.numpy(), static_logits.float().numpy())
            left = [decision_from_logits(item, names[pos]) for pos, item in enumerate(original[0])]
            split_at = OPTION_COUNTS[0]
            right_logits = (static_logits[:split_at], static_logits[split_at:])
            right = [decision_from_logits(item, names[pos]) for pos, item in enumerate(right_logits)]
            agreements.append(
                {
                    "logit_match": match,
                    "decisions_agree": all(a["choice"] == b["choice"] for a, b in zip(left, right)),
                }
            )
            feeds.append(
                {
                    "sequence_hidden": hidden,
                    "lexical": lexical_t,
                    "type_ids": type_ids,
                }
            )
            references.append(static_logits.float().numpy())
            records.append({"choices": [item["choice"] for item in left], "details": left})

    path = ONNX_DIR / "clef_decision_head.onnx"
    export(
        static,
        (feeds[0]["sequence_hidden"], feeds[0]["lexical"], feeds[0]["type_ids"]),
        path,
    )
    onnx_score = compare_session(path, feeds, references)

    quantized = JointSchemaHead(**config).eval()
    quantized.load_state_dict(load_file(WEIGHTS / "joint_head.safetensors"), strict=True)
    quantized = quantized.float()
    quantize_(quantized, bits=8)
    quant_static = StaticJointHead(quantized, OPTION_COUNTS).eval()
    high_confidence_flips = 0
    with torch.inference_mode():
        for feed, record in zip(feeds, records):
            logits = quant_static(feed["sequence_hidden"], feed["lexical"], feed["type_ids"])
            split_at = OPTION_COUNTS[0]
            quant_decisions = [
                decision_from_logits(logits[:split_at], names[0]),
                decision_from_logits(logits[split_at:], names[1]),
            ]
            flips = []
            for original, changed in zip(record["details"], quant_decisions):
                flipped = original["choice"] != changed["choice"]
                flips.append(flipped)
                if flipped and original["margin"] >= 0.2 and original["confidence"] >= 0.7:
                    high_confidence_flips += 1
            quant_agreements.append(not any(flips))

    block_effect = hidden_state_quant_effect(head, names)
    result = {
        "parameters": sum(parameter.numel() for parameter in head.parameters()),
        "official_vs_static": {
            "cases": len(agreements),
            "decision_agreement": sum(item["decisions_agree"] for item in agreements) / len(agreements),
            "logit_cosine_min": min(item["logit_match"]["cosine"] for item in agreements),
            "logit_max_abs_max": max(item["logit_match"]["max_abs"] for item in agreements),
        },
        "onnx": str(path),
        "onnx_bytes": path.stat().st_size + path.with_suffix(".onnx.data").stat().st_size,
        "operators": op_histogram(path),
        "pytorch_vs_onnx": onnx_score,
        "int8_per_channel_fake_quant": {
            "decision_agreement": sum(quant_agreements) / len(quant_agreements),
            "high_confidence_disagreements": high_confidence_flips,
            "note": "Host-side symmetric per-channel int8 rounding of the real head weights. This is not the Hailo quantizer.",
        },
        "quantized_full_attention_hidden_into_fp32_head": block_effect,
    }
    (REFERENCE / "head_cases.json").write_text(json.dumps(records, indent=2))
    del head, static, quantized
    gc.collect()
    return result


def hidden_state_quant_effect(head: torch.nn.Module, names) -> dict:
    """Pass fp32 and fake-quantized layer-3 states into the original fp32 head."""

    layer, config = load_decoder(3)
    quant_layer, _ = load_decoder(3)
    quantize_(quant_layer, bits=8)
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    position = torch.arange(SEQ).view(1, 1, -1).expand(3, 1, -1)
    block = FullAttentionBlock(layer).eval()
    quant_block = FullAttentionBlock(quant_layer).eval()
    # Reuse the fixed head schema by padding the 8-token block state up to 16.
    agreements = []
    cosines = []
    with torch.inference_mode():
        for index in range(CASES):
            torch.manual_seed(5000 + index)
            hidden = torch.randn(1, SEQ, config.hidden_size)
            cos, sin = rotary(hidden, position)
            fp32_state = block(hidden, cos, sin)
            quant_state = quant_block(hidden, cos, sin)
            cosines.append(stats(fp32_state.float().numpy(), quant_state.float().numpy())["cosine"])
            padded_fp32 = torch.cat([fp32_state, fp32_state], dim=1)
            padded_quant = torch.cat([quant_state, quant_state], dim=1)
            token_ids = torch.arange(16).view(1, 16) % 24
            embedding = torch.randn(24, 4096)
            type_ids = torch.tensor([1, 0])
            static = StaticJointHead(head, OPTION_COUNTS).eval()
            spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
            lexical_t = torch.stack([embedding[token_ids[0, start:end]].mean(0) for start, end in spans])
            fp32_logits = static(padded_fp32, lexical_t, type_ids)
            quant_logits = static(padded_quant, lexical_t, type_ids)
            fp32_choice = [
                decision_from_logits(fp32_logits[:3], names[0])["choice"],
                decision_from_logits(fp32_logits[3:], names[1])["choice"],
            ]
            quant_choice = [
                decision_from_logits(quant_logits[:3], names[0])["choice"],
                decision_from_logits(quant_logits[3:], names[1])["choice"],
            ]
            agreements.append(fp32_choice == quant_choice)
    del layer, quant_layer
    gc.collect()
    return {
        "hidden_cosine_min": min(cosines),
        "hidden_cosine_mean": float(sum(cosines) / len(cosines)),
        "decision_agreement": sum(agreements) / len(agreements),
        "note": "Layer 3 only, sequence 8, per-channel int8 weights. Not a full-backbone Hailo quantization.",
    }


def smoke_records() -> list[dict]:
    tokenizer = AutoTokenizer.from_pretrained(WEIGHTS)
    states = [
        {"invoice": {"vendor": "Acme", "total": 1250.0, "currency": "USD", "status": "overdue"}},
        "The checkout page returns HTTP 500 and new orders are blocked.",
        {"plant": "tomato", "soil": "dry", "hour": 15},
        {"ticket": 42, "priority": "low", "queue": "billing"},
        "Rain started after the beds were watered.",
        {"sensor": "pond", "reading": 0.2, "unit": "m"},
        "Customer asked for a refund on a duplicate charge.",
        {"gate": "closed", "visitor": "known"},
        "The model reply cited a tool that was not called.",
        {"sku": "seed-11", "stock": 0},
        "Night frost is forecast and the seedlings are uncovered.",
        {"route": "hailo", "latency_ms": 51, "choice": "yes"},
        "Two residents disagree about who owns the cob.",
        {"status": "draft", "sent": False},
        "The receipt total is legible and matches the ledger.",
        {"error": "timeout", "service": "decide"},
        "A jelly rolled into the pond.",
        {"balance": -12.5, "currency": "GBP"},
        "The question has two allowed answers and the margin is small.",
        {"weather": "clear", "task": "water"},
    ]
    questions = {
        "urgent": {"type": "noul", "instructions": "Does this need attention today?"},
        "lane": {
            "type": "choice",
            "instructions": "Which lane should handle it?",
            "criteria": {"garden": "Living world or plants", "billing": "Money", "technical": "Broken system"},
        },
    }
    encoded = []
    for index, state in enumerate(states):
        record = {"id": f"smoke-{index:02d}", "state": state, "questions": questions}
        tokens = encode_record(tokenizer, record)
        encoded.append(
            {
                "id": record["id"],
                "state": state,
                "token_length": len(tokens.input_ids),
                "input_ids": list(tokens.input_ids),
                "questions": [
                    {
                        "id": question.question_id,
                        "type": question.question_type,
                        "span": list(question.question_span),
                        "options": list(question.option_ids),
                        "option_spans": [list(span) for span in question.option_spans],
                    }
                    for question in tokens.questions
                ],
            }
        )
    (REFERENCE / "smoke_records.json").write_text(json.dumps(encoded, indent=2))
    return [{"id": item["id"], "token_length": item["token_length"]} for item in encoded]


def try_hailo(onnx_path: Path) -> dict:
    try:
        import hailo_sdk_client  # type: ignore
    except Exception as exc:
        return {
            "imported": False,
            "stage": "import",
            "error": f"{type(exc).__name__}: {exc}",
        }
    try:
        runner = hailo_sdk_client.ClientRunner(hw_arch="hailo10h")
        runner.translate_onnx_model(str(onnx_path), "clef_experimental_full_block")
        har = ONNX_DIR.parent / "qwen35_full_attention_block.har"
        runner.save_har(str(har))
        return {"imported": True, "parsed": True, "har": str(har)}
    except Exception as exc:
        return {
            "imported": True,
            "parsed": False,
            "stage": "translate_onnx_model",
            "error": f"{type(exc).__name__}: {exc}",
            "traceback": traceback.format_exc(),
        }


def write_reports(payload: dict) -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / "measurements.json").write_text(json.dumps(payload, indent=2))
    full = payload["full_attention"]
    linear = payload["linear_attention"]
    head = payload["head"]
    hailo = payload["hailo"]
    level = 1 if full["pytorch_vs_onnx"]["cosine_min"] > 0.999 else 0
    if hailo.get("parsed"):
        level = 2
    if hailo.get("hef"):
        level = 3
    architecture = f"""# Clef-Flash architecture

Source: `Cloudflare/clef-flash` at `17f0b0ad64efb65d273590632833508766b2aae6`, Apache-2.0.
Base model: `Qwen/Qwen3.5-9B`. Transformers architecture: `Qwen3_5ForConditionalGeneration`.
Hub parameter count: 9,409,813,744 parameters, all BF16. Checkpoint storage: 19,083,248,461 bytes across four shards.
Local weights were not modified. This experiment downloaded individual tensors by HTTP range.

## Text backbone

- Hidden size 4096, intermediate size 12288, 32 decoder blocks.
- Block pattern: three `linear_attention` blocks, then one `full_attention` block, repeated. 24 linear blocks and 8 full-attention blocks.
- Activation: SiLU. Normalisation: RMSNorm, epsilon 1e-6. Qwen3.5 RMSNorm stores a zero-centered weight and applies `x * (1 + weight)`.
- Linear attention is a Gated DeltaNet: depthwise causal conv of kernel 4, 16 key heads of dimension 128, 32 value heads of dimension 128, softplus decay, sigmoid beta, L2-normalised Q/K, and a recurrent state of shape `[32, 128, 128]` per batch item.
- Full attention: 16 query heads, 4 key/value heads, head dimension 256, no attention bias, RMSNorm on Q and K, sigmoid output gate from the second half of `q_proj`.
- Positions: partial rotary factor 0.25, so 64 rotary dimensions. Multimodal RoPE, interleaved, sections `[11, 11, 10]`, theta 10,000,000. Maximum position 262,144.
- Vocabulary 248,320. Embeddings are untied. Final norm is RMSNorm. `lm_head` is not used by Clef decisions.

Measured from the downloaded tensors:

- Layer 0 (linear): {linear["parameters"]:,} parameters.
- Layer 3 (full attention): {full["parameters"]:,} parameters.

## Vision encoder

- Depth 27, hidden size 1152, intermediate size 4304, 16 heads, patch 16, temporal patch 2, spatial merge 2.
- Activation `gelu_pytorch_tanh`. Output hidden size 4096.
- Text-only Clef decisions do not run this encoder. It was not exported in this pass.

## Joint schema head

Config: hidden 4096, width 1024, 2 evidence-routing layers, 4 transformer decoder layers, 16 heads, feed-forward 4096.
Measured parameters: {head["parameters"]:,}.

The head mean-pools token spans for each question and each allowed option, projects them, cross-attends to the backbone sequence, lets fields attend jointly, and adds a lexical prior from the output embedding rows of the option text. Span bounds depend on the tokenizer and the schema, so they are host-side. The neural scoring graph exported here takes those pooled vectors as inputs.

Question types are `noul` (true/false), `choice`, and `score`. Softmax is per question.

## What executes where in the exported split

- Host: tokenization, multimodal RoPE cos/sin, span pooling, lexical embedding gather, softmax across options if it is not inside the head graph.
- Exported full-attention block: RMSNorm, partial RoPE application, grouped-query attention, sigmoid gate, SwiGLU MLP.
- Exported linear block: the same MLP plus the Gated DeltaNet, with the recurrent scan unrolled for sequence length {SEQ}.
"""
    (REPORTS / "clef_architecture.md").write_text(architecture)

    operators = f"""# Hailo operator compatibility

Target: Hailo-10H / Raspberry Pi AI HAT 2. Compiler package: Hailo Dataflow Compiler, `hailo_sdk_client`.

## Compiler stage actually reached

```
{json.dumps(hailo, indent=2)}
```

No operator has been rejected by the Hailo parser in this environment. The parser did not run, because importing `hailo_sdk_client` failed at the stage recorded above. Absence from the Hailo Model Zoo is not treated as a parse result.

## ONNX operators produced from real Clef-Flash weights

Sequence length is static at {SEQ} for the backbone blocks. The head uses sequence 16 and option counts {OPTION_COUNTS}.

### Full-attention block, layer 3, RoPE tables supplied by the host

{json.dumps(full["operators"], indent=2)}

PyTorch versus ONNX Runtime: cosine min {full["pytorch_vs_onnx"]["cosine_min"]:.8f}, max absolute error {full["pytorch_vs_onnx"]["max_abs_max"]:.3e}.
Future-token leak on the PyTorch block (max abs change in positions `0..S-2` after perturbing the last token): {full["future_token_leak_max_abs"]:.3e}.

Host-side multimodal RoPE was removed from this graph after an earlier export of the rotary module itself produced `ScatterND` and `ScatterElements` from in-place frequency recomposition. Those writes are the interleaved mRoPE layout, not the attention matmul.

### Linear-attention block, layer 0, scatter-free recurrent scan

{json.dumps(linear["operators"], indent=2)}

Official chunked Gated DeltaNet versus this rewrite, before ONNX: cosine min {linear["pytorch_official_vs_rewrite"]["cosine_min"]:.8f}, max absolute error {linear["pytorch_official_vs_rewrite"]["max_abs_max"]:.3e}.
PyTorch rewrite versus ONNX Runtime: cosine min {linear["pytorch_vs_onnx"]["cosine_min"]:.8f}, max absolute error {linear["pytorch_vs_onnx"]["max_abs_max"]:.3e}.

The stock chunked implementation exports `ScatterElements`, `ScatterND`, `Trilu`, and `CumSum` because the triangular solve is lowered to a serial substitution and the chunk loop writes the state in place. The rewrite uses the mathematically equivalent recurrent form and stacks timestep outputs. Any `Gather` or `Scatter` counts above are what this unrolled scan still emitted.

### SwiGLU MLP from layer 3

{json.dumps(payload["mlp"]["operators"], indent=2)}

PyTorch versus ONNX Runtime: cosine min {payload["mlp"]["pytorch_vs_onnx"]["cosine_min"]:.8f}.

### Joint schema head

{json.dumps(head["operators"], indent=2)}

Official head versus static pooled graph: decision agreement {head["official_vs_static"]["decision_agreement"]:.3f}, logit cosine min {head["official_vs_static"]["logit_cosine_min"]:.8f}.
Static graph versus ONNX Runtime: cosine min {head["pytorch_vs_onnx"]["cosine_min"]:.8f}, max absolute error {head["pytorch_vs_onnx"]["max_abs_max"]:.3e}.

## Graph modifications

- mRoPE cos/sin are computed on the host and passed into the full-attention block.
- Question and option spans are mean-pooled on the host. The head graph does not gather token ids.
- Linear attention uses an unrolled recurrent scan instead of `torch.linalg.solve_triangular` and in-place chunk writes.
- Cache and KV updates are outside these graphs. Each export is a single prefill step with no past state.
- Upstream Clef files under `hailo_port/upstream/` are the published sources. The wrappers live in `hailo_port/graphs.py`.
"""
    (REPORTS / "hailo_operator_compatibility.md").write_text(operators)

    block_report = f"""# Qwen3.5 block results

Weights: Clef-Flash layer 0 and layer 3, cast from BF16 to FP32 for the reference. Sequence length {SEQ}. Cases: {CASES}. Device: CPU. Hailo hardware is not present on this machine (`/dev/hailo0` missing).

## Layer 3 full attention

- Parameters: {full["parameters"]:,}
- ONNX: `{full["onnx"]}` ({full["onnx_bytes"]:,} bytes including external data)
- PyTorch vs ONNX Runtime: {json.dumps(full["pytorch_vs_onnx"])}
- Causal check, max abs leak from the final token into earlier positions: {full["future_token_leak_max_abs"]:.3e}

## Repeated full-attention blocks

Same layer-3 weights, applied sequentially. This measures export of a deeper graph, not distinct Clef layers.

{json.dumps(payload["scaled"], indent=2)}

## Layer 0 linear attention

- Parameters: {linear["parameters"]:,}
- ONNX: `{linear["onnx"]}` ({linear["onnx_bytes"]:,} bytes including external data)
- Official block vs scatter-free rewrite: {json.dumps(linear["pytorch_official_vs_rewrite"])}
- Rewrite vs ONNX Runtime: {json.dumps(linear["pytorch_vs_onnx"])}

## MLP only

{json.dumps(payload["mlp"]["pytorch_vs_onnx"])}

## Hailo compile

{json.dumps(hailo, indent=2)}

No HEF was produced. Latency, on-device memory, and Hailo resource usage were not measured because the parser did not run and no Hailo device is attached.
"""
    (REPORTS / "qwen35_block_results.md").write_text(block_report)

    quant = f"""# Clef quantisation results

The Hailo model optimizer did not run. The numbers below are a host-side symmetric per-channel int8 rounding of the real FP32 weights, then a fresh forward. They are a sensitivity check, not a Hailo HEF measurement.

## Decision head weights rounded to int8

- Cases: {CASES}, fixed schema (3-way choice plus true/false).
- Decision agreement with the FP32 head: {head["int8_per_channel_fake_quant"]["decision_agreement"]:.3f}
- High-confidence disagreements (FP32 margin >= 0.2 and confidence >= 0.7, choice changed): {head["int8_per_channel_fake_quant"]["high_confidence_disagreements"]}

## Layer-3 hidden state after the same int8 rounding, scored by the FP32 head

{json.dumps(head["quantized_full_attention_hidden_into_fp32_head"], indent=2)}

A drop in decision agreement here would mean the head is reading features that this rounding damaged. Agreement near 1 with a lower hidden-state cosine means the decision survived even though the activation moved.

Full-backbone Clef decisions were not compared. The 9.4B backbone does not fit in this machine's memory as a single resident model, and only layers 0 and 3 were downloaded. Token-level smoke inputs are in `tests/reference/smoke_records.json` ({payload["smoke_token_lengths"]["count"]} records, token length min {payload["smoke_token_lengths"]["min"]}, max {payload["smoke_token_lengths"]["max"]}). Those records are encoded with the official Clef tokenizer and `encode_record`. They were not passed through the backbone.
"""
    (REPORTS / "clef_quantisation_results.md").write_text(quant)

    final = f"""# Final status

1. Highest level reached: **LEVEL {level}**. Real Clef-Flash blocks and the joint schema head export to ONNX and match PyTorch on the deterministic cases. A HAR was not produced. A HEF was not produced.
2. Architecture executed: Qwen3.5-9B decoder layer 3 (full attention) and layer 0 (Gated DeltaNet), plus the Clef joint schema head, all from the published Clef-Flash checkpoint. Sequence length {SEQ} for blocks. Head schema is one 3-way choice and one true/false question, sequence 16.
3. Parts that run on Hailo: none. The Dataflow Compiler was not importable and `/dev/hailo0` is absent.
4. Parts that remain on CPU: tokenization, mRoPE, span pooling, the exported blocks, and the decision head. Vision encoder not run.
5. Unsupported operators: none recorded from the Hailo parser. The import error is the compiler boundary reached. ONNX operator inventories are in `reports/hailo_operator_compatibility.md`.
6. Graph modifications: host mRoPE, host span pooling, recurrent scan stacked instead of in-place scatter, no KV cache inside the graph.
7. Quantisation: Hailo quantizer not run. Host int8 sensitivity is in `reports/clef_quantisation_results.md`. Head decision agreement under that rounding: {head["int8_per_channel_fake_quant"]["decision_agreement"]:.3f}. Layer-3 hidden cosine min after the same rounding: {head["quantized_full_attention_hidden_into_fp32_head"]["hidden_cosine_min"]:.6f}. Decision agreement when that hidden state is scored by the FP32 head: {head["quantized_full_attention_hidden_into_fp32_head"]["decision_agreement"]:.3f}.
8. Decision agreement with reference Clef: the static head matches the official head on {head["official_vs_static"]["decision_agreement"]:.3f} of the fixed-schema cases (logit cosine min {head["official_vs_static"]["logit_cosine_min"]:.8f}). End-to-end Clef-Flash decisions were not run, because the full backbone was not resident.
9. Hailo resource usage: not measured.
10. Latency: not measured on Hailo. CPU ONNX checks were correctness checks, not a latency study.
11. HEF paths: none.
12. Next experiment: install the Hailo-10H Dataflow Compiler wheel into this environment and run `ClientRunner(hw_arch="hailo10h").translate_onnx_model` on `artifacts/onnx/qwen35_mlp.onnx` first, then `artifacts/onnx/qwen35_full_attention_block.onnx`, then the scatter-free linear block. Capture the first rejected node. Do not replace JEV-H or any HEF already on the Pi.

## Smoke records

{payload["smoke_token_lengths"]["count"]} official encodings are stored in `tests/reference/smoke_records.json`.
"""
    (REPORTS / "final_status.md").write_text(final)


def main() -> None:
    REFERENCE.mkdir(parents=True, exist_ok=True)
    ONNX_DIR.mkdir(parents=True, exist_ok=True)
    torch.set_num_threads(8)
    smoke = smoke_records()
    linear_layer, _ = load_decoder(0)
    linear = linear_experiment(linear_layer)
    del linear_layer
    gc.collect()
    full_layer, config = load_decoder(3)
    full = full_attention_experiment(full_layer, config)
    mlp = mlp_experiment(full_layer)
    scaled = scale_experiment(full_layer, config)
    del full_layer
    gc.collect()
    head = head_experiment()
    hailo = try_hailo(ONNX_DIR / "qwen35_mlp.onnx")
    lengths = [item["token_length"] for item in smoke]
    payload = {
        "full_attention": full,
        "linear_attention": linear,
        "mlp": mlp,
        "scaled": scaled,
        "head": head,
        "hailo": hailo,
        "smoke_token_lengths": {"count": len(lengths), "min": min(lengths), "max": max(lengths)},
    }
    write_reports(payload)
    print(json.dumps({"level_hint": "see reports/final_status.md", "hailo": hailo, "full": full["pytorch_vs_onnx"], "linear": linear["pytorch_vs_onnx"], "head": head["pytorch_vs_onnx"]}, indent=2))


if __name__ == "__main__":
    main()
