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
- `compile()` on the real Clef MLP (hidden 4096) passed pre-partition in 21m 37s. Single-context placement then failed in 30m 2s because `conv1`, `conv2`, and `conv3` had no successful assignment. No HEF. `/dev/hailo0` is not present, so nothing was timed on device.

The same SwiGLU formula, with random weights and intermediate size 3 × hidden, compiles in one context:

| Hidden | Compile time | HEF bytes | Control | Compute | Memory |
|---|---|---|---|---|---|
| 64 | 5s | 172,032 | 33.8% | 30.8% | 17.2% |
| 256 | 18s | 856,064 | 65% | 67.1% | 32.7% |
| 512 | 33s | 2,719,744 | 57.5% | 73.8% | 30.6% |
| 1024 | 1m 7s | 9,904,128 | 53.8% | 76.3% | 68.4% |

At hidden 1024 the busiest cluster was at 97.9% compute and 85.2% memory. Files are under `hailo_port/generated/`. Hidden 2048 had not left "Building optimization options" after 7 minutes.

The leading 1024-by-3072 tile of the real Clef layer-3 gate, up, and down matrices compiled in 50 seconds to `hailo_port/generated/clef_experimental_mlp_h1024_tile.hef`. Against that same tile in PyTorch, the Hailo quantized emulator scored cosine 0.9953 and max absolute error 0.0184. The tile does not reproduce the full 4096-wide MLP.

Splitting every real projection into 1024-input by 3072-output tiles does reproduce it. Sixteen gate tiles, sixteen up tiles, a host SiLU multiply, and sixteen down tiles match the full MLP at cosine 0.99999999999976 and max absolute error 1.2e-6. One real gate tile compiled in 30 seconds to `hailo_port/generated/clef_experimental_gate_tile.hef` (quantized emulator cosine 0.9994, max absolute error 0.057, total memory 39.2%). The full-MLP multi-context search then accepted a 17-context partition (`Successful Multi Context Partition`, 33m 31s, control utilization 0.6). Allocation was still running after that, and `artifacts/clef_experimental_mlp.hef` was not written.

## Attention core, one head

The softmax core of one full-attention head is a separate graph: packed Q, K, and V, sequence 8, head dimension 256. Host code still owns Q/K/V projection, Q/K RMSNorm, partial RoPE, and the sigmoid output gate. `hailo_port/compile_attn_core.py` exports that core.

Two parser fixes were required before `optimize` would finish:

- The causal mask is stored as `[8, 8]`. The post-fuser builds a constant of shape `[-1, *mask.shape]` and then crashes in `is_spatial_broadcast` because that rank-3 constant cannot broadcast onto scores of shape `[-1, 1, 8, 8]`. Reshaping the mask parameter to `[1, 8, 8]` makes the constant match the scores.
- Both matmul inputs are activations. The default zero-point correction (`zp_comp_block`) walks backward looking for a weight producer and raises `No predecessor with weight for layer linear_matmul1`. The model script sets `correction_type=zp_comp_none` on `matmul1` and `matmul2`.

With those two changes the core compiles in one context in about 1 second. The HEF is `hailo_port/generated/clef_experimental_attn_core.hef` (65,536 bytes). Cluster 2 is the busiest, at 75% control, 27.1% compute, and 20.3% memory. The network total is 17.5% control, 6.3% compute, and 4.7% memory.

On the quantized emulator, four sequences against the PyTorch core scored cosine 0.999709, MSE 2.93e-4, and max absolute error 0.0755. Calibration used 1024 rows. Optimization level stayed 0 because this machine has no GPU, so Adaround and bias correction were skipped. Scrambling V at positions 1..7 left position 0 unchanged in both PyTorch and the emulator (`future_token_leak` 0). A rank-4 mask of shape `[1, 1, 8, 8]` never parsed: matmul shape inference raised `IndexError: list index out of range` on `input_shapes[1]`. A three-input ONNX (separate Q, K, V) was rewritten by the simplifier into one input. The packed QKV tensor is the input that parses.

## Full K and V projections, layer 3

`k_proj` and `v_proj` are the published matrices, hidden 4096 to 1024, bias-free. Hailo parses each as one conv. Both compiled in a single context: K in 1m 17s (`hailo_port/generated/clef_experimental_k_proj.hef`, 3,067,904 bytes) and V in 1m 19s (`hailo_port/generated/clef_experimental_v_proj.hef`, 3,211,264 bytes). The resource table is the same for both, because the shapes match: total control 42.5%, compute 64.2%, memory 38.8%, with cluster 4 at 100% compute and 60.2% memory.

Quantized emulator versus PyTorch, 1024 calibration rows, optimization level 0: K cosine 0.999016, MSE 2.19e-3, max absolute error 0.193. V cosine 0.999288, MSE 1.53e-3, max absolute error 0.147. Q/K RMSNorm and RoPE are not in these HEFs. `q_proj` is 4096 to 8192 and has not been compiled.
