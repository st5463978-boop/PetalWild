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

Splitting every real projection into 1024-input by 3072-output tiles does reproduce it. Sixteen gate tiles, sixteen up tiles, a host SiLU multiply, and sixteen down tiles match the full MLP at cosine 0.99999999999976 and max absolute error 1.2e-6. One real gate tile compiled in 30 seconds to `hailo_port/generated/clef_experimental_gate_tile.hef` (quantized emulator cosine 0.9994, max absolute error 0.057, total memory 39.2%). The full-MLP multi-context search then accepted a 17-context partition (`Successful Multi Context Partition`, 33m 31s, control utilization 0.6). Allocation of all 17 contexts succeeded in 39m 24s. Context 16 is the busiest at 46.3% control, 57.1% compute, and 86.1% memory. The first compiler printed those tables and exited before kernel compilation. The driver Python had been OOM-killed at 11:17 while that compiler was still mapping. A second compile from the quantized HAR failed single context again in 28m 33s, then accepted 17 contexts in 33m 56s. Allocation of that partition succeeded in 37m 11s. Kernel compilation of all 17 contexts finished in 55s. `artifacts/clef_experimental_mlp.hef` is 113,999,872 bytes. The compile took 2h 6m 33s. Context totals are unchanged from the first allocation: context 16 is 46.3% control, 57.1% compute, and 86.1% memory. Context 11 is the control peak at 60%. Context 0 cluster 4 is at 99.2% memory. The calibration set is still the original 8 rows, optimization level 0. Against PyTorch on 4 sequences, the quantized emulator scores cosine 0.966529, MSE 9.30e-3, and max absolute error 2.03.

## Layer-0 depthwise causal conv

The linear-block ONNX passes this conv's kernel as a dynamic input, and Hailo dies in `get_dynamic_kernel_shape`. Isolated, the published kernel is a parameter. A channels-last Conv1d is rejected (`Kernel features: 8192 Input features: 8 Groups: 0` on `node_Conv_10`). An NCHW `Conv2d` with groups 8192 and kernel `(1, 4)` parses as `external_pad` then `dw`. The Hailo input is `[-1, 1, 8, 8192]`. Calibration has to be NHWC; NCHW raises `BadInputsShape`.

With 1024 rows and optimization level 0, the quantized emulator matches PyTorch at cosine 0.997265, MSE 5.37e-5, and max absolute error 0.0320. Compile took 32s. `hailo_port/generated/clef_experimental_depthwise_conv.hef` is 241,664 bytes. Totals: control 38.8%, compute 12.9%, memory 13.3%. Cluster 2 is at 100% control, 33.3% compute, and 35.2% memory. The fetched layer-0 shard has no conv bias, so this HEF is the published kernel with bias zero. It is not the rest of the Gated DeltaNet.

## One Gated DeltaNet step

The exported scan's `ReduceSum` uses axis `-2`, and Hailo rejects it. Summing that same key axis as NCHW channels is the loop body with the axes permuted. A unit test checks the permute against one iteration of `gated_delta_scan` at max absolute error under 1e-5. L2 normalization of Q and K is not in this graph. Decay is the multiplier `exp(g)`, already applied.

Hailo parses it as `resize`, `ew_mult`, `reduce_sum`, `ew_sub`, and `ew_add`. Both reductions are `reduce_sum` with keepdims. The HEF is `hailo_port/generated/clef_experimental_scan_step.hef` (192,512 bytes, 59s). Totals: control 52.5%, compute 22.1%, memory 35.3%. Cluster 2 is the busiest at 87.5% control, 39.6% compute, and 64.8% memory. Against PyTorch, 64 rows, optimization level 0: the updated state scores cosine 0.992339 and max absolute error 4.42. The step output scores cosine 0.984008 and max absolute error 31.9. Those peaks are on a sum of 128 products. The unrolled eight-step scan, `Expand`, and `repeat_interleave` are still not in a HEF.

## Gated DeltaNet scan

The scatter-free block's conv kernel was a Squeeze/Unsqueeze around the weight, so Hailo treated it as a dynamic rank-3 kernel and died in `get_dynamic_kernel_shape`. Pointing the conv at `layer.linear_attn.conv1d.weight` removes that crash. The scan's initial state is a `ConstantOfShape`. Hailo matches that op as a `Constant` (`startswith`) and `parse_raw_data` indexes an attribute the node does not have. A zero tensor of shape `[1, 32, 128, 128]` replaces it.

Layer creation then rejects the recurrence:

- `Expand` `node_Expand_61` and `node_Expand_68` (`UnexpectedNodeError`). The repeat of key heads is `[1, 1, 1, 2, 1]`.
- `node_repeat_interleave` and `node_repeat_interleave_1` (`UnsupportedShuffleLayerError`).
- `node_transpose_2` and `node_transpose_3`, perm `[0, 2, 1, 3]` (`UnsupportedShuffleLayerError`).
- `ReduceSum` `node_sum_4` through `node_sum_18`, axis `-2`, keepdims 0 (`UnsupportedReduceSumLayerError`). That axis is the key dimension of the state, not a feature axis.
- `node_mul_7`: the zero state is rearranged to `(128, 128, 32)` and does not broadcast onto `[128, 32, 128]`.

Hailo's own end-node list, with the conv input format set to `[batch, channels, width]`, parses. Default rank-3 format makes the same conv `Kernel features: 8192 Input features: 8 Groups: 0`. The HAR is `artifacts/clef_slice/clef_experimental_linear_scan.har`. It contains the depthwise conv, SiLU, the QKV split, and the beta/decay projections. It does not contain the state update.

That HAR quantizes. Against the float Hailo graph, 256 calibration rows, optimization level 0: 16 of 17 outputs score cosine 0.999942 or better, with max absolute error up to 0.0117. Output 12 scores cosine 0.989363 and max absolute error 0.0265. Compile then fails in 30s. Pre-partition takes 29s. Single-context and multi-context placement both fail in 0s on `feature_splitter1`: `one output isn't supported`. The QKV split is 2048, 2048, and 4096. No HEF.

The same channel split, with nothing after it, is three `Slice` nodes rather than one `Split`. A lone `Split` still becomes a feature splitter and fails because a graph output has no successor name. The slices compile to `hailo_port/generated/clef_experimental_qkv_slice.hef` (36,864 bytes). Quantized emulator versus the input slices: cosine 0.999927, max absolute error 0.0210.

Putting the published depthwise kernel and SiLU in front of those slices also compiles: `hailo_port/generated/clef_experimental_conv_qkv.hef` (253,952 bytes, 17s). Hailo shows `external_pad`, `dw`, a format conversion, and three slices. No SiLU layer is listed. Against the PyTorch module that does include SiLU, 256 rows and optimization level 0: query cosine 0.986650 max absolute error 0.0256, key cosine 0.992523 max 0.0260, value cosine 0.902513 max 0.0251. Value's standard deviation on these four sequences is 0.023, so the absolute error is about the size of the value signal. Totals: control 43.8%, compute 14.6%, memory 14.4%. Clusters 1 and 4 are at 100% control.

## Attention core, one head

The softmax core of one full-attention head is a separate graph: packed Q, K, and V, sequence 8, head dimension 256. Host code still owns Q/K/V projection, Q/K RMSNorm, partial RoPE, and the sigmoid output gate. `hailo_port/compile_attn_core.py` exports that core.

Two parser fixes were required before `optimize` would finish:

- The causal mask is stored as `[8, 8]`. The post-fuser builds a constant of shape `[-1, *mask.shape]` and then crashes in `is_spatial_broadcast` because that rank-3 constant cannot broadcast onto scores of shape `[-1, 1, 8, 8]`. Reshaping the mask parameter to `[1, 8, 8]` makes the constant match the scores.
- Both matmul inputs are activations. The default zero-point correction (`zp_comp_block`) walks backward looking for a weight producer and raises `No predecessor with weight for layer linear_matmul1`. The model script sets `correction_type=zp_comp_none` on `matmul1` and `matmul2`.

With those two changes the core compiles in one context in about 1 second. The HEF is `hailo_port/generated/clef_experimental_attn_core.hef` (65,536 bytes). Cluster 2 is the busiest, at 75% control, 27.1% compute, and 20.3% memory. The network total is 17.5% control, 6.3% compute, and 4.7% memory.

On the quantized emulator, four sequences against the PyTorch core scored cosine 0.999709, MSE 2.93e-4, and max absolute error 0.0755. Calibration used 1024 rows. Optimization level stayed 0 because this machine has no GPU, so Adaround and bias correction were skipped. Scrambling V at positions 1..7 left position 0 unchanged in both PyTorch and the emulator (`future_token_leak` 0). A rank-4 mask of shape `[1, 1, 8, 8]` never parsed: matmul shape inference raised `IndexError: list index out of range` on `input_shapes[1]`. A three-input ONNX (separate Q, K, V) was rewritten by the simplifier into one input. The packed QKV tensor is the input that parses.

## Full K and V projections, layer 3

`k_proj` and `v_proj` are the published matrices, hidden 4096 to 1024, bias-free. Hailo parses each as one conv. Both compiled in a single context: K in 1m 17s (`hailo_port/generated/clef_experimental_k_proj.hef`, 3,067,904 bytes) and V in 1m 19s (`hailo_port/generated/clef_experimental_v_proj.hef`, 3,211,264 bytes). The resource table is the same for both, because the shapes match: total control 42.5%, compute 64.2%, memory 38.8%, with cluster 4 at 100% compute and 60.2% memory.

Quantized emulator versus PyTorch, 1024 calibration rows, optimization level 0: K cosine 0.999016, MSE 2.19e-3, max absolute error 0.193. V cosine 0.999288, MSE 1.53e-3, max absolute error 0.147. Q/K RMSNorm and RoPE are not in these HEFs. `q_proj` is 4096 to 8192. It parsed as one conv and quantized at cosine 0.998160, MSE 5.19e-3, max absolute error 0.376 (1024 rows, optimization level 0). Pre-partition took 2m 37s. Single-context placement then failed in 4m 19s: `conv1` had no successful assignment. Multi-context search at a 60% utilization cap accepted a 4-context partition after 114 iterations (3m 44s). The compiler split `conv1` into slices `conv1_d0` through `conv1_d16` and spread them across those contexts. Allocation of all four contexts then succeeded in 1m 29s, kernel compilation took 17s, and the HEF was written. `hailo_port/generated/clef_experimental_q_proj.hef` is 28,893,184 bytes. End-to-end compile time was 13m 39s. Per-context totals:

| Context | Control | Compute | Memory | Busiest cluster |
|---|---|---|---|---|
| 0 | 51.3% | 54.6% | 68.8% | cluster 4 memory 93.8% |
| 1 | 61.3% | 61.3% | 74.5% | cluster 0 memory 96.9% |
| 2 | 62.5% | 61.7% | 73.6% | cluster 4 compute 97.9%, memory 96.1% |
| 3 | 55% | 52.1% | 45.2% | cluster 0 control 100% |
