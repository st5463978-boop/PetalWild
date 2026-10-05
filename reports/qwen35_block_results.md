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
- The unmodified RoPE block still dies in the fuser. The swap-and-sign RoPE block with the MLP included matches the official layer at max absolute error 0, parses, and quantizes. HAR `artifacts/qwen35_masked_rope_block.har` (839,475,200 bytes). Optimized HAR `artifacts/qwen35_masked_rope_block.optimized.har` (4,429,312,000 bytes). Single context fails in 25m 56s on `conv_feature_splitter1_1`, `conv_feature_splitter1_2`, and `conv4` through `conv7`. Twenty-nine contexts are accepted after 2,399 iterations (5h 37m 13s). Allocation then fails in 30m 29s: contexts 0 through 22 map, contexts 23 through 28 do not run, and the compiler reports `Splitter failed to find a possible solution` after 7h 18m 44s. No HEF. The same quantized HAR, recompiled with `compiler_optimization_level=max`, fails single context in 14m 51s on `conv5`, `conv6`, and `conv7`. Its multi-context search uses 100% control and compute caps and 85% memory, and has not accepted a partition. The no-RoPE block with the MLP included accepted 30 contexts and timed out the same way. The no-RoPE attention with the MLP removed compiled. Details are in `reports/hailo_operator_compatibility.md`.

No-RoPE attention, layer 3, MLP not included: `hailo_port/generated/clef_experimental_attention_no_mlp.hef` (39,636,992 bytes, 9 contexts, 39m 55s). Single context failed in 6m 32s on `conv4` and two feature splitters. Context 7 uses 62.5% control. Context 8 uses 72.5% memory. Against PyTorch, 64 calibration rows, optimization level 0: cosine 0.995641, MSE 1.25e-2, max absolute error 2.12. On 4 further sequences the quantized attention, host post-attention norm, quantized MLP, and residual add match the float block at cosine 0.992361. The FP32 head agrees on 3 of those 4 cases and records 0 high-confidence disagreements.
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

The published post-attention RMSNorm joined to the first 256 intermediate channels of that same SwiGLU compiles in one context in 39s: `hailo_port/generated/clef_experimental_post_norm_mlp256.hef` (2,957,312 bytes). The weights are `gate_proj[:256]`, `up_proj[:256]`, and `down_proj[:, :256]`. Hailo layers are `layer_normalization`, `normalization`, two convs, `ew_mult`, and a third conv. Totals: control 23.8%, compute 17.9%, memory 23.6%. Cluster 2 is 56.3% control, 62.5% compute, and 90.6% memory. Quantized emulator, 64 rows, optimization level 0: cosine 0.998074, MSE 8.01e-6, max absolute error 0.0147. A unit test checks that a thin SwiGLU equals the same channels inside a wider SwiGLU whose extra channels are zero. This file is 256 of 12288 intermediate channels. The first 512 channels also compile in one context: `hailo_port/generated/clef_experimental_post_norm_mlp512.hef` (5,251,072 bytes, 21s). Totals: control 31.3%, compute 29.2%, memory 43.4%. Cluster 4 is 56.3% control, 62.5% compute, and 92.2% memory. Quantized emulator, 64 rows, optimization level 0: cosine 0.997373, MSE 2.15e-5, max absolute error 0.0458. The first 1024 channels also compile in one context: `hailo_port/generated/clef_experimental_post_norm_mlp1024.hef` (10,383,360 bytes, 2m 17s). All five clusters are used. Totals: control 48.8%, compute 33.8%, memory 76.6%. Clusters 2 and 4 are at 94.5% memory. Cluster 3 is at 93.8% control. Quantized emulator cosine 0.997220, MSE 4.46e-5, max absolute error 0.0652. The first 2048 channels do not fit one context: L3 weights are 792 against 480 available, and LCUs are 49/60. Three contexts are accepted after 165 iterations (2m 45s). HEF `hailo_port/generated/clef_experimental_post_norm_mlp2048.hef` is 26,927,104 bytes, total 6m 58s. Context 2 uses 67.5% control, 62.5% compute, and 57.5% memory, with cluster 1 at 100% control and cluster 4 at 100% compute. Quantized emulator cosine 0.994089, MSE 1.95e-4, max absolute error 0.124. The first 4096 channels fail single context in 3m 5s because `conv3` has no assignment. Seven contexts are accepted after 316 iterations (3m 53s). HEF `hailo_port/generated/clef_experimental_post_norm_mlp4096.hef` is 42,160,128 bytes, total 26m 45s. Context 6 uses 61.3% control, 60.4% compute, and 61.6% memory. Context 5 cluster 2 is at 97.7% memory. Quantized emulator cosine 0.993932, MSE 4.06e-4, max absolute error 0.209. The first 8192 channels fail single context in 17m 51s because `conv1`, `conv2`, and `conv3` have no assignment. Thirteen contexts are accepted after 660 iterations (12m 3s). HEF `hailo_port/generated/clef_experimental_post_norm_mlp8192.hef` is 73,752,576 bytes, total 1h 4m 34s. Contexts 2, 5, and 6 use 62.5% control and 61.7% compute. Context 4 cluster 4 is at 100% memory. Quantized emulator cosine 0.988212, MSE 1.62e-3, max absolute error 0.190. The full 12288 intermediate channels, still behind the published post-attention RMSNorm, fail single context in 32m 43s because `conv3`, `conv1`, and `conv2` have no assignment. Nineteen contexts are accepted after 1,203 iterations (43m 0s). HEF `artifacts/clef_experimental_post_norm_mlp12288.hef` is 111,546,368 bytes, total 3h 46m 5s. It is not in the repository because it is over 100MB. Context 12 uses 62.5% control, 47.1% compute, and 88.6% memory. Context 17 cluster 3 is at 100% memory. Quantized emulator, 4 reference rows, optimization level 0: cosine 0.988319, MSE 2.46e-3, max absolute error 0.224. On 12 real layer-3 sequences the residual that enters this norm is taken from the official attention. Adding the quantized MLP back to that residual matches the official block at cosine 0.990099 and max absolute error 5.96. The FP32 head agrees on 1.000 of those sequences, with 0 high-confidence disagreements, logit cosine min 0.970262, and largest probability change 0.132. The attention itself is not in this HEF.

## Layer-0 depthwise causal conv

The linear-block ONNX passes this conv's kernel as a dynamic input, and Hailo dies in `get_dynamic_kernel_shape`. Isolated, the published kernel is a parameter. A channels-last Conv1d is rejected (`Kernel features: 8192 Input features: 8 Groups: 0` on `node_Conv_10`). An NCHW `Conv2d` with groups 8192 and kernel `(1, 4)` parses as `external_pad` then `dw`. The Hailo input is `[-1, 1, 8, 8192]`. Calibration has to be NHWC; NCHW raises `BadInputsShape`.

With 1024 rows and optimization level 0, the quantized emulator matches PyTorch at cosine 0.997265, MSE 5.37e-5, and max absolute error 0.0320. Compile took 32s. `hailo_port/generated/clef_experimental_depthwise_conv.hef` is 241,664 bytes. Totals: control 38.8%, compute 12.9%, memory 13.3%. Cluster 2 is at 100% control, 33.3% compute, and 35.2% memory. The fetched layer-0 shard has no conv bias, so this HEF is the published kernel with bias zero. It is not the rest of the Gated DeltaNet.

## One Gated DeltaNet step

The exported scan's `ReduceSum` uses axis `-2`, and Hailo rejects it. Summing that same key axis as NCHW channels is the loop body with the axes permuted. A unit test checks the permute against one iteration of `gated_delta_scan` at max absolute error under 1e-5. L2 normalization of Q and K is not in this graph. Decay is the multiplier `exp(g)`, already applied.

Hailo parses it as `resize`, `ew_mult`, `reduce_sum`, `ew_sub`, and `ew_add`. Both reductions are `reduce_sum` with keepdims. The HEF is `hailo_port/generated/clef_experimental_scan_step.hef` (192,512 bytes, 59s). Totals: control 52.5%, compute 22.1%, memory 35.3%. Cluster 2 is the busiest at 87.5% control, 39.6% compute, and 64.8% memory. Against PyTorch, 64 rows, optimization level 0: the updated state scores cosine 0.992339 and max absolute error 4.42. The step output scores cosine 0.984008 and max absolute error 31.9. Those peaks are on a sum of 128 products. Eight of those steps are `hailo_port/generated/clef_experimental_scan_8.hef` (1,363,968 bytes). The ONNX is 16 `ReduceSum`s, 40 multiplies, and one concat. Hailo parses that as 16 `reduce_sum`, 40 `ew_mult`, 32 `resize`, 32 `slice`, one `feature_splitter`, and one `concat`. Single context fails immediately: `lcus=(150/80)`. Multi-context search accepts 11 contexts after 657 iterations (23m 34s). Allocation is 4s and the HEF is written at 23m 50s. Context 3 is the busiest, at the 60% control cap, with clusters 2, 3, and 4 each at 100% control. Context 2 cluster 2 is also at 100% control. The most common rejected partition was shmifo capacity 20 versus 23 or more.

The float reference on the same random inputs reaches a state max of 2.5e5 and an output max of 1.1e6, because decay is uniform on `[0, 1]` and the sum runs for eight steps. Quantized versus that reference, 64 rows, optimization level 0: state cosine 0.281300, max absolute error 5.41e5; output cosine 0.467115, max absolute error 6.35e6. Shapes match, so this is the int8 range, not a transposed layout. One step of the same input family stayed near cosine 0.99. `Expand` and `repeat_interleave` are still not in this HEF.

The same eight steps with the scan's Q/K L2 norm, the `1/sqrt(128)` query scale, and `exp(g)` inside the graph are `hailo_port/generated/clef_experimental_scan_8_l2.hef` (1,601,536 bytes). Decay is `-softplus` of a normal draw, so `exp(g)` stays in `(0, 1)`. The float state max on the scored batch is 0.882 and the output max is 0.057. Hailo adds two more `reduce_sum` layers, three `normalization` layers, and one `activation`. Single context needs 160 LCUs. Thirteen contexts are accepted after 434 iterations (15m 48s). The HEF is written at 16m 9s. Context 2 is at the 60% control cap and is also the memory peak at 22.8%. Quantized emulator versus PyTorch, 64 rows, optimization level 0: state cosine 0.996295, max absolute error 0.0265; the eight outputs cosine 0.991975, max absolute error 0.00357. A unit test matches `gated_delta_scan` at max absolute error under 1e-4, starting from a zero state.

Putting the published depthwise conv in front of that scan stops at the head repeat. Stacking each of the 16 key heads with a copy of itself is a concat Hailo accepts. Reshaping `[1, 8, 16, 2, 128]` into `[1, 8, 32, 128]` is `UnsupportedShuffleLayerError` on `node_view_1` and `node_view_3`. The prefix Hailo names, through that concat and the time slices, compiles in one context in 18s to `hailo_port/generated/clef_experimental_conv_scan_8.hef` (348,160 bytes). Totals: control 71.3%, compute 23.8%, memory 21.7%. Clusters 3 and 4 are at 100% control. Quantized versus the float Hailo graph, 64 rows, twelve outputs: cosine 0.723658 to 0.999998, max absolute error about 0.029. The normed scan is not in this HEF.

Isolated layout probes, same compiler, show why that reshape cannot be swapped for another grouping of the conv channels. A reshape of `[1, 8, 2048]` to `[1, 8, 16, 128]` parses as `shortcut` and the output shape stays `[-1, 1, 8, 2048]`. The same happens for `[1, 8, 4096]` to `[1, 8, 32, 128]` and to `[1, 8, 16, 256]`. Four channel slices, each unsqueezed and concatenated on the new axis, come back as a channel concat to `[-1, 1, 8, 16]`. A transpose that starts from `[1, 8, 32, 128]` with perm `(0, 3, 2, 1)` parses as `format_conversion` and the Hailo shape is `[-1, 32, 8, 128]`. That is the normed scan's layout, but only when the head axis already exists.

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

## Partial RoPE

`rotate_half` negates one half and concatenates. On a rank-3 probe, query `[1, 8, 256]` and host cos/sin `[1, 8, 64]`, DFC 5.4.0 enters `_handle_neg_feature_shuffle` and raises `TypeError: object of type 'NoneType' has no len()` because `concat.group_sizes` is `None`. The full block hits the same function and raises `IndexError: list assignment index out of range`.

The same values as a swap of the two halves times `[-1] * 32 + [1] * 32` parse. Hailo keeps the sign as `normalization` after the concat, which is outside the fuser pattern. That probe compiles in one context in about 2s to `hailo_port/generated/qwen35_rope_masked_rank3.hef` (57,344 bytes). Totals: control 12.5%, compute 5%, memory 5.8%. Cluster 0 is 56.3% control, 20.8% compute, and 20.3% memory. Quantized emulator, 64 rows, optimization level 0: cosine 0.999587, MSE 1.03e-3, max absolute error 0.195.

A rank-4 input `[1, 16, 8, 256]` in the default NCHW format does not parse. The stock tail concat reports `[-1, 8, 64, 64]` against `[-1, 8, 192, 16]`.

Layer-3 attention with this swap, MLP removed, matches official `self_attn` plus the residual at max absolute error 0 on one sequence of the published weights and the real mRoPE cos/sin. The ONNX contains no `Neg`. Parse takes 7.33s. HAR `artifacts/qwen35_attention_masked_rope.har` is 235,274,240 bytes. The query splitter has `groups=16` and cuts 4096 features into 1024 and 3072, which is 64 rotary dimensions and 192 pass-through dimensions on each head. The key splitter has `groups=4` and cuts 1024 into 256 and 768. Single context fails in 6m 31s because `conv_feature_splitter1_1` has no assignment. Ten contexts are accepted after 926 iterations. The partitioner took 27m 5s and the multi-context stage 31m 54s. The most common rejection was too many resources on `context_2` (546 of 681). The next was shmifo capacity 20 versus 21 on `context_6`. Allocation took 4m 35s and kernel compilation 32s. The HEF is `hailo_port/generated/clef_experimental_attention_masked_rope.hef` (39,940,096 bytes, total 53m 56s). Context 9 is the peak: control 68.8%, compute 62.9%, memory 73.9%. Cluster 3 there is at 87.5% control, 70.8% compute, and 91.4% memory.

Float Hailo, both the native graph and the fp-optimized graph, matches PyTorch on 12 sequences at cosine 0.996791, MSE 9.27e-3, and max absolute error 2.10. The quantized emulator with the compiler's default zero-point compensation raises inside `matmul1`: a 4096-vector is multiplied by a length-8 tensor. The scores matmul is `groups=16` with a 256-wide tile, so the 4096 zero points are sixteen groups of 256. The compensation slice after the transpose is `(batch, 1, 1, 4, 1, 1, 8)`. `matmul2` does not add compensation. Hailo's hardware parameter export stores only the first zero point and leaves grouped zero points unimplemented, so the HEF is still produced. A width slice of one query head, returned as the graph output, matches PyTorch at max absolute error 0. The same kind of slice on keys, with the query left unsliced, matches at max absolute error 2.2e-5. A width slice of the query heads into the matmul does not: Hailo stores it as `[-1, 8, 1, 256]`, spatial-reshapes it to `[-1, 1, 8, 256]`, and the native emulator scores cosine 0.145. Packing the query as `[1, 8, 4096]` and slicing the last axis, with key and value still width-sliced, matches in the native emulator at max absolute error 1.07e-6 and cosine 0.99999994. All 32 matmuls have `transpose_matmul_input`. The mask added to the scores is `-64`. The quantized emulator, 64 rows, optimization level 0, scores cosine 0.669818, MSE 0.331, and max absolute error 4.31. The optimizer reports a scale inconsistency on twelve `concat_matmul` / `matmul` pairs. Single-context placement fails immediately: `lcus=(244/80)`. Multi-context search ran 1h 52m, rejected 3378 partitions, reached context 29, and never accepted a split. The closest cut needed 21 boundary streams and the cap is 20. The search was stopped. No 16-head HEF was written. Four of those heads, each with its own KV head, compile in one context in 4s: `hailo_port/generated/clef_experimental_attn_unrolled_4h_4kv.hef`, 245,760 bytes. Totals: control 75%, compute 25%, memory 21.9%. Quantized emulator cosine 0.790845, MSE 0.184, max absolute error 3.64. `zp_comp_none` scores cosine 0.669990 and is rejected because matmul1 through matmul4 see negative inputs. The inconsistent pairs match on scale and disagree on zero point: a length-257 vector of 64 against a scalar 0. Copying 64 drops cosine to 0.373898. 1024 calibration rows score cosine 0.806588. HEF `hailo_port/generated/clef_experimental_attn_unrolled_4h_4kv_c1024.hef`. Eight heads with eight KV heads score cosine 0.775991 and compile in 4 contexts: `hailo_port/generated/clef_experimental_attn_unrolled_8h_8kv.hef`, 778,240 bytes, 39s. Single context needs 124 LCUs. Twelve heads with twelve KV heads score cosine 0.759893 and compile in 10 contexts: `hailo_port/generated/clef_experimental_attn_unrolled_12h_12kv.hef`, 1,163,264 bytes, 7m 45s. Single context needs 184 LCUs. Sixteen heads with sixteen KV heads score cosine 0.759346 and compile in 21 contexts: `hailo_port/generated/clef_experimental_attn_unrolled_16h_16kv.hef`, 2,088,960 bytes, 43m 27s. Single context needs 244 LCUs. That file gives each query its own KV head, so it is not the four-KV grouped-query core. One real KV group, four query heads sharing one KV head, compiles when the ONNX optimizer is left off: `hailo_port/generated/clef_experimental_attn_unrolled_4h_1kv.hef`, 237,568 bytes, one context, 4s. Quantized cosine 0.730406 on random inputs and 0.596688 on 12 real layer-3 sequences. Substituting that quantized group into the block, the FP32 head agrees on 0.750 of those sequences, with 0 high-confidence disagreements. Two quantized groups agree on 0.583 of the same 12 sequences, also with 0 high-confidence disagreements. Block cosine is 0.941394. With the optimizer on, that graph is a bare Squeeze and does not parse. Two KV groups compile in 3 contexts: `hailo_port/generated/clef_experimental_attn_unrolled_8h_2kv.hef`, 724,992 bytes, 12s. Single context needs 124 LCUs. Quantized cosine 0.657733. Three KV groups score cosine 0.662239. Single context needs 184 LCUs. An 18-context partition was accepted after 1,503 iterations (25m 50s), and allocation then failed with `Splitter failed to find a possible solution`. No HEF. Pinning each group to its own context crashes the compiler with `_Map_base::at`. Moving an internal activation onto that width axis is `UnsupportedShuffleLayerError` on the permute, and slicing axis 1 is rejected. A feature slice followed by a transpose loses its successor when that transpose is fused into the matmul. `zp_comp_weights` dies earlier, in optimize, because the matmul predecessor is a depthwise layer and has no `zp_comp_add`. `zp_comp_block_2` and `zp_comp_block_3` reach the same 4096-versus-8 multiply. `zp_comp_none` on `matmul1` lets the emulator finish and scores cosine 0.867365, MSE 0.402, and max absolute error 22.0. The HEF was compiled with the default compensation, so 0.867 is not a measurement of the file.

Passing the float Hailo attention through the host post-attention norm and the FP32 MLP matches the official block at cosine 0.996419 and max absolute error 2.11. The FP32 head then agrees on 0.833 of the 12 cases, with 0 high-confidence disagreements, logit cosine min 0.997726, and largest probability change 0.054. The `zp_comp_none` attention through that same host MLP agrees on 0.750 of the cases, with 0 high-confidence disagreements, logit cosine min 0.790040, and largest probability change 0.333. mRoPE scatter stays on the host. The MLP is not in this HEF.

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
