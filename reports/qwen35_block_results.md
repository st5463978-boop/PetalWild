# Qwen3.5 block results

Weights: Clef-Flash layer 0 and layer 3, cast from BF16 to FP32 for the reference. Sequence length 8. Cases: 12. Device: CPU. Hailo hardware is not present on this machine (`/dev/hailo0` missing).

## Layer 3 full attention

- Parameters: 209,723,904
- ONNX: `/workspace/artifacts/onnx/qwen35_full_attention_block.onnx` (839,111,803 bytes including external data)
- PyTorch vs ONNX Runtime: {"cases": 12, "cosine_min": 0.9999999999998963, "mse_max": 3.3135775297751157e-13, "max_abs_max": 1.9073486328125e-05}
- Causal check, max abs leak from the final token into earlier positions: 0.000e+00

## Repeated full-attention blocks

Same layer-3 weights, applied sequentially. This measures export of a deeper graph, not distinct Clef layers.

{
  "2": {
    "onnx": "/workspace/artifacts/onnx/qwen35_full_attention_x2.onnx",
    "onnx_bytes": 839412445,
    "operators": {
      "Mul": 32,
      "Add": 18,
      "MatMul": 18,
      "Transpose": 17,
      "Reshape": 16,
      "Slice": 16,
      "Pow": 8,
      "ReduceMean": 8,
      "Sqrt": 8,
      "Reciprocal": 8,
      "Concat": 8,
      "Unsqueeze": 6,
      "Neg": 4,
      "Expand": 4,
      "Sigmoid": 4,
      "Split": 2,
      "Softmax": 2
    },
    "pytorch_vs_onnx": {
      "cases": 1,
      "cosine_min": 0.9999999999998678,
      "mse_max": 7.101133257371052e-13,
      "max_abs_max": 1.52587890625e-05
    }
  },
  "4": {
    "onnx": "/workspace/artifacts/onnx/qwen35_full_attention_x4.onnx",
    "onnx_bytes": 839872208,
    "operators": {
      "Mul": 64,
      "Add": 36,
      "MatMul": 36,
      "Reshape": 32,
      "Slice": 32,
      "Transpose": 27,
      "Pow": 16,
      "ReduceMean": 16,
      "Sqrt": 16,
      "Reciprocal": 16,
      "Concat": 16,
      "Unsqueeze": 10,
      "Neg": 8,
      "Expand": 8,
      "Sigmoid": 8,
      "Split": 4,
      "Softmax": 4
    },
    "pytorch_vs_onnx": {
      "cases": 1,
      "cosine_min": 0.9999999999998289,
      "mse_max": 2.4338436377857595e-12,
      "max_abs_max": 2.288818359375e-05
    }
  }
}

## Layer 0 linear attention

- Parameters: 218,407,104
- ONNX: `/workspace/artifacts/onnx/qwen35_linear_block_scatter_free.onnx` (873,851,681 bytes including external data)
- Official block vs scatter-free rewrite: {"cases": 12, "cosine_min": 0.9999999999999929, "mse_max": 1.938532938561155e-14, "max_abs_max": 7.62939453125e-06}
- Rewrite vs ONNX Runtime: {"cases": 12, "cosine_min": 0.999999999999958, "mse_max": 1.2483360846086258e-13, "max_abs_max": 3.0517578125e-05}

## MLP only

{"cases": 12, "cosine_min": 0.999999999999679, "mse_max": 1.0075788942571692e-13, "max_abs_max": 2.1457672119140625e-06}

## Hailo compile

DFC 5.4.0, architecture `hailo10h`.

- MLP HAR: `artifacts/clef_experimental_mlp.har` (parsed). Optimized HAR: `artifacts/clef_experimental_mlp.optimized.har`.
- No-RoPE full-attention HAR: `artifacts/clef_experimental_full_attention_no_rope.har` (parsed).
- RoPE full-attention, linear block, decision head, and the 2-block stack did not parse. The exceptions are in `reports/hailo_operator_compatibility.md`.
- `compile()` on the optimized MLP was still inside `hailo_tools/build/compiler` when this report was written. No HEF, no on-device latency, and no Hailo resource counters were produced. `/dev/hailo0` is not present.
