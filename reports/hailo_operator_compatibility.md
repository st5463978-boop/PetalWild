# Hailo operator compatibility

Target: Hailo-10H / Raspberry Pi AI HAT 2. Compiler package: Hailo Dataflow Compiler, `hailo_sdk_client`.

## Compiler stage actually reached

Dataflow Compiler 5.4.0 was installed from `hailo_dataflow_compiler-5.4.0-py3-none-linux_x86_64.whl` into `artifacts/hailo-venv`. `ClientRunner(hw_arch="hailo10h")` constructs. The wheel arrived by Tailscale Taildrop from the phone. It is not committed.

Parser and compiler results:

| Graph | Stage | Result |
|---|---|---|
| Layer-3 SwiGLU MLP | `translate_onnx_model` | HAR written. Hailo sees 1x1 conv + SiLU + ew multiply + conv. Input `[-1, 1, 8, 4096]`. 151.02M parameters in the Hailo model. |
| Same MLP | `optimize` | Finished. Hailo lowered the optimization level to 0 because the calibration set had 8 rows and no GPU was visible. Recommended calibration count is 1024. |
| Same MLP | `compile` | Single context failed in 30m 2s (`conv1`, `conv2`, `conv3` had no assignment). Multi-context search at a 60% cap found a 17-context partition after 888 iterations (33m 31s). Allocation succeeded in 39m 24s. The process exited while printing utilization, before kernel compilation. No HEF. The driver Python was OOM-killed at 11:17. A second compile from the quantized HAR reproduced pre-partition in 21m 44s and failed single-context placement again in 28m 33s on `conv1`, `conv2`, and `conv3`. The same search then accepted 17 contexts again in 33m 56s (888 iterations, control utilization 0.6). Allocation succeeded in 37m 11s. Kernel compilation finished in 55s. HEF `artifacts/clef_experimental_mlp.hef`, 113,999,872 bytes. End-to-end compile 2h 6m 33s. Quantized emulator versus PyTorch, the original 8 calibration rows: cosine 0.966529, max absolute error 2.03. Context 16 is the memory peak at 46.3% control, 57.1% compute, 86.1% memory. Context 11 is the control peak at 60%. Context 0 cluster 4 is at 99.2% memory. |
| One full-attention head core, sequence 8, head dim 256, packed QKV | `compile` | HEF `hailo_port/generated/clef_experimental_attn_core.hef`, 65,536 bytes, about 1s. Causal QK^T, softmax, and AV. Total control 17.5%, compute 6.3%, memory 4.7%. |
| Full layer-3 `k_proj` and `v_proj`, 4096 to 1024 | `compile` | Single-context HEFs. K: 3,067,904 bytes, 1m 17s, cosine 0.999016, max abs 0.193. V: 3,211,264 bytes, 1m 19s, cosine 0.999288, max abs 0.147. Total control 42.5%, compute 64.2%, memory 38.8%. Cluster 4 compute is 100%. |
| Full layer-3 `q_proj`, 4096 to 8192 | `compile` | Single context failed in 4m 19s: `conv1` had no assignment. Four-context partition succeeded in 3m 44s. HEF `hailo_port/generated/clef_experimental_q_proj.hef`, 28,893,184 bytes, total compile 13m 39s. Busiest context uses 62.5% control, 61.7% compute, 73.6% memory. Quantized cosine 0.998160, max abs 0.376. |
| One real gate-matrix tile, 1024 to 3072 | `compile` | HEF `hailo_port/generated/clef_experimental_gate_tile.hef`, 30s. Sixteen such tiles per projection, plus a host SiLU multiply, match the full MLP within 1.2e-6. |
| Same SwiGLU formula, random weights, hidden 64, 256, 512, 1024 | `compile` | HEF written. Single context. Files in `hailo_port/generated/`. Hidden 1024 uses 68.4% memory and one cluster reaches 97.9% compute. |
| Same formula, hidden 2048 | `compile` | Stopped after 7 minutes while still building optimization options. No HEF. |
| Leading 1024×3072 tile of the real Clef layer-3 MLP weights | `compile` | HEF `hailo_port/generated/clef_experimental_mlp_h1024_tile.hef`, 50s, single context. Quantized emulator cosine 0.9953 against that tile in PyTorch. |
| Full-attention block, RoPE inside | `translate_onnx_model` | Fuser crash after a successful ONNX simplify: `_handle_neg_feature_shuffle` raises `IndexError: list assignment index out of range`. |
| No-RoPE attention, MLP removed | `compile` | 58.75M parameters. Single context fails in 6m 32s: `conv4`, `conv_feature_splitter1_1`, and `conv_feature_splitter1_2` have no assignment. Nine contexts are accepted after 590 iterations (19m 0s). HEF `hailo_port/generated/clef_experimental_attention_no_mlp.hef`, 39,636,992 bytes, total 39m 55s. Context 7 control 62.5%. Context 8 memory 72.5%. Quantized emulator versus PyTorch, 64 rows, optimization level 0: cosine 0.995641, MSE 1.25e-2, max absolute error 2.12. Matmul equalization is skipped because it subtracts `[0, 16]` and `[0, 4]`. RoPE is not in the graph. |
| Full-attention block, RoPE removed | `compile` | HAR written. 209.79M parameters. `optimize` with matmul equalization on dies in `fix_scales_reduce_sum`: `Incompatible shapes: [0, 16] vs. [0, 4]`, the 16 query heads against the 4 KV heads. Skipping `MatmulEqualization.should_skip_algo` lets quantization finish at optimization level 0 with 64 rows. Pre-partition takes 20m 31s. Single context fails in 21m 17s because `conv4` has no assignment. Multi-context search accepts 30 contexts after 2,369 iterations (1h 35m 32s). The most common rejection was too many resources on `context_4` (2,097 of 2,265). Allocation of contexts 0 through 23 finished; contexts 24 through 29 did not run. Allocation then failed at 22m 43s. The compiler reports `Splitter failed to find a possible solution` and `Partition and Allocation Failed (Timeout, Processing time: 2h 44m 27s)`. No HEF. |
| Linear Gated DeltaNet block | `translate_onnx_model` | Connecting `conv1d.weight` directly removes the rank-3 dynamic kernel, so `get_dynamic_kernel_shape` is no longer the crash. `ConstantOfShape` matches Hailo's `Constant` prefix and `parse_raw_data` raises `IndexError` on an empty attribute. A zero initializer of shape `[1, 32, 128, 128]` gets past that. The scan is then rejected: `UnexpectedNodeError` on `Expand` `node_Expand_61` and `node_Expand_68`; `UnsupportedShuffleLayerError` on `node_repeat_interleave`, `node_repeat_interleave_1`, `node_transpose_2`, and `node_transpose_3` (perm `[0, 2, 1, 3]`); `UnsupportedReduceSumLayerError` on `node_sum_4` through `node_sum_18` (axis `-2`, keepdims 0); `UnsupportedModelError` on `node_mul_7` because constant shape `(128, 128, 32)` does not broadcast to `[128, 32, 128]`. |
| Joint schema head | `translate_onnx_model` | Rank-1 `type_ids` makes `get_input_layer_shapes` raise `TypeError: object of type 'NoneType' has no len()`. Host type embeddings match the official head at max absolute error 0. The folded graph, with that transpose stored in the weight and the two Expands replaced by Tile, matches the official head on 4 random cases: max absolute error 4.77e-7, decision agreement 1.0. Folding the constant transpose of `option_question_projection.weight` and replacing the two feature-concat Expands with Tile gets layer creation started. It then fails on `LayerNormalization` `node_layer_norm_9` (axis -1, input `Concat` `node_stack_2`) because `input_format` is empty: `_convert_axes_to_nhwc` raises `IndexError: list index out of range`. An identity reshape of that stack to `[2, 1024]` does not give the norm a format. Normalizing each summary after `Flatten`, which forces `[batch, channels]`, gets past that crash. The parser then lists unsupported batch-axis concats, batch gathers, softmax, and shuffles, and recommends a subgraph ending at `node_stack`, `node_unsqueeze_6`, `node_select_1`, `node_div_3`, and `node_linear_19`. That subgraph creates layers. Removing a redundant slice then crashes because a successor lists the slice as an input and has no matching shape slot. Padding that shape list lets the fuser finish. HAR `artifacts/clef_slice/clef_head_host_type.har` (465 MB) is the resulting prefix: hidden LayerNorm, span mean-pools, two projections, and the start of lexical L2 normalization. It does not include the evidence attention or the decision logits. Quantized emulator versus the float Hailo graph, 64 calibration rows, optimization level 0: five outputs, cosine 0.9996 to 0.9999, max absolute error 0.055. `compile()` then fails on `conv2` (8192 inputs, 1024 outputs). Memory units required 133 and 128 are available. Automatic defuse still asks for more subclusters than the split is given. Multi-context partition fails immediately. No head HEF. Splitting that matrix into two 4096-to-1024 products and adding them on the host is the same arithmetic. The published `question_projection`, which is that shape, compiles: `hailo_port/generated/clef_head_test_question_proj.hef`, 4,550,656 bytes, 1m 19s, 1024 calibration rows. Quantized emulator cosine 0.999830, max absolute error 0.0422. Resources match `k_proj`: 42.5% control, 64.2% compute, 38.8% memory, cluster 4 at 100% compute. |
| Head axis from conv channels | `translate_onnx_model` | Reshape `[1, 8, 2048]` to `[1, 8, 16, 128]`, and `[1, 8, 4096]` to `[1, 8, 32, 128]` or `[1, 8, 16, 256]`, becomes a `shortcut`. The Hailo shape stays `[-1, 1, 8, channels]`. Unsqueeze plus concat on the new axis stays a channel concat. Transpose of an existing `[1, 8, 32, 128]` with perm `(0, 3, 2, 1)` becomes `format_conversion` to `[-1, 32, 8, 128]`. The 32-head axis has to be formed before this compiler sees the tensor. |
| Depthwise conv joined to the scan up to the head-pair concat | `compile` | The full join dies on `Reshape` `node_view_1` and `node_view_3`: `[1, 8, 16, 2, 128]` to `[1, 8, 32, 128]`, `UnsupportedShuffleLayerError`. Hailo's recommended prefix parses and compiles in one context in 18s. HEF `hailo_port/generated/clef_experimental_conv_scan_8.hef`, 348,160 bytes. Layers include `external_pad`, `dw`, SiLU as `activation`, 13 slices, and two head-pair concats. Totals: control 71.3%, compute 23.8%, memory 21.7%. Clusters 3 and 4 are at 100% control. Quantized versus float Hailo, 64 rows: cosine from 0.723658 to 0.999998. |
| Eight Gated DeltaNet steps with Q/K L2 norm | `compile` | Adds `l2norm` on the channel axis, the `1/sqrt(128)` query scale, and `exp(g)`. Single context fails: `lcus=(160/80)`. Thirteen contexts are accepted after 434 iterations (15m 48s). HEF `hailo_port/generated/clef_experimental_scan_8_l2.hef`, 1,601,536 bytes, 16m 9s. Context 2 is at the 60% control cap and 22.8% memory. Quantized emulator versus `gated_delta_scan`, 64 rows, optimization level 0, zero initial state: state cosine 0.996295 max abs 0.0265, outputs cosine 0.991975 max abs 0.00357. |
| Eight Gated DeltaNet steps, sum on channels | `compile` | Single context fails in 0s: `lcus=(150/80)`. Eleven contexts are accepted after 657 iterations (23m 34s). HEF `hailo_port/generated/clef_experimental_scan_8.hef`, 1,363,968 bytes, 23m 50s. Context 3 is at the 60% control cap. The most common rejected cut is shmifo capacity 20 versus a requirement of 23 or more. Quantized emulator versus PyTorch, 64 rows, optimization level 0: state cosine 0.281300, output cosine 0.467115. The float state on these random inputs reaches a max of 2.5e5. |
| One Gated DeltaNet step, sum on channels | `compile` | The scan's `ReduceSum` on axis `-2` stays unsupported. The same sum as NCHW channel axis 1 parses as `reduce_sum` and compiles. HEF `hailo_port/generated/clef_experimental_scan_step.hef`, 192,512 bytes, 59s. Totals: control 52.5%, compute 22.1%, memory 35.3%. Cluster 2 memory is 64.8%. Quantized emulator versus one iteration of the scan loop, 64 rows, optimization level 0: state cosine 0.992339 max abs 4.42, output cosine 0.984008 max abs 31.9. Head repeat (`Expand`, `repeat_interleave`) is not in this graph. |
| QKV split, 8192 to 2048/2048/4096 | `compile` | One `Split` becomes `feature_splitter1` and cannot be a graph output: `successor name is missing, output shape is ambiguous`. Three `Slice` nodes parse as slice layers and compile in one context. HEF `hailo_port/generated/clef_experimental_qkv_slice.hef`, 36,864 bytes. Totals: control 3.8%, compute 1.7%, memory 2.5%. Quantized emulator versus the sliced input, 256 rows, optimization level 0: cosine 0.999927, max absolute error 0.0210. The same slices after the published depthwise conv and SiLU also compile: `clef_experimental_conv_qkv.hef`, 253,952 bytes, 17s. Totals: control 43.8%, compute 14.6%, memory 14.4%. Clusters 1 and 4 are at 100% control. There is no separate SiLU layer. Against PyTorch, 256 rows: query cosine 0.986650 max 0.0256, key cosine 0.992523 max 0.0260, value cosine 0.902513 max 0.0251. Value's standard deviation is 0.023. |
| Linear-scan prefix, static conv kernel, channel-first input | `compile` | The end nodes Hailo recommended, plus `net_input_format` `[batch, channels, width]` on the conv input, produce HAR `artifacts/clef_slice/clef_experimental_linear_scan.har` (3.7 MB). Layers: two inputs, two 4096-to-32 convs, `external_pad` plus `dw` (pad width 8 to 14, conv width 11, then a slice back to 8), SiLU, a QKV feature split `2048/2048/4096`, and per-step beta/decay slices. The same cut with the default rank-3 format fails on the depthwise layer: `Kernel features: 8192 Input features: 8 Groups: 0`. Quantized versus float Hailo, 256 rows, optimization level 0: 16 outputs at cosine 0.999942 or better; output 12 cosine 0.989363, max absolute error 0.0265. `compile()` fails in 30s. Pre-partition 29s. Single context and multi-context both fail immediately: `feature_splitter1` has no assignment, `one output isn't supported`. No HEF. |
| Layer-0 depthwise causal conv, static kernel | `compile` | A channels-last Conv1d is rejected: `Invalid kernel shape for base dw layer base_dw1 (translated from node_Conv_10). Kernel features: 8192 Input features: 8 Groups: 0`. The same published kernel as NCHW `Conv2d`, groups 8192, kernel `(1, 4)`, causal pad on width, parses as `external_pad` plus `dw`. Input `[-1, 1, 8, 8192]`. NCHW calibration raises `BadInputsShape` (`(8192, 1, 8)` vs `(1, 8, 8192)`). NHWC calibration quantizes at cosine 0.997265, MSE 5.37e-5, max abs 0.0320 (1024 rows, optimization level 0, no GPU). HEF `hailo_port/generated/clef_experimental_depthwise_conv.hef`, 241,664 bytes, 32s. Total control 38.8%, compute 12.9%, memory 13.3%. Cluster 2 control is 100%. The fetched shard has no conv bias. |
| Two stacked full-attention blocks | `translate_onnx_model` | `IndexError: list index out of range` in `is_null_transpose_near_torch_tile`. |

These are parser crashes with file and function names, not a statement that Qwen3.5 is absent from a support list.

## ONNX operators produced from real Clef-Flash weights

Sequence length is static at 8 for the backbone blocks. The head uses sequence 16 and option counts (3, 2).

### Full-attention block, layer 3, RoPE tables supplied by the host

{
  "Mul": 16,
  "Add": 9,
  "MatMul": 9,
  "Reshape": 8,
  "Slice": 8,
  "Transpose": 5,
  "Pow": 4,
  "ReduceMean": 4,
  "Sqrt": 4,
  "Reciprocal": 4,
  "Unsqueeze": 4,
  "Concat": 4,
  "Neg": 2,
  "Expand": 2,
  "Sigmoid": 2,
  "Split": 1,
  "Softmax": 1
}

PyTorch versus ONNX Runtime: cosine min 1.00000000, max absolute error 1.907e-05.
Future-token leak on the PyTorch block (max abs change in positions `0..S-2` after perturbing the last token): 0.000e+00.

Host-side multimodal RoPE was removed from this graph after an earlier export of the rotary module itself produced `ScatterND` and `ScatterElements` from in-place frequency recomposition. Those writes are the interleaved mRoPE layout, not the attention matmul.

### Linear-attention block, layer 0, scatter-free recurrent scan

{
  "Unsqueeze": 59,
  "Mul": 56,
  "Gather": 40,
  "ReduceSum": 18,
  "Add": 16,
  "MatMul": 8,
  "Transpose": 8,
  "Reshape": 8,
  "Exp": 8,
  "Sub": 8,
  "Sqrt": 5,
  "Reciprocal": 5,
  "Sigmoid": 4,
  "Pow": 3,
  "ReduceMean": 3,
  "Expand": 2,
  "Squeeze": 1,
  "Conv": 1,
  "Slice": 1,
  "Split": 1,
  "Softplus": 1,
  "Greater": 1,
  "Where": 1,
  "Div": 1,
  "ConstantOfShape": 1,
  "Concat": 1
}

Official chunked Gated DeltaNet versus this rewrite, before ONNX: cosine min 1.00000000, max absolute error 7.629e-06.
PyTorch rewrite versus ONNX Runtime: cosine min 1.00000000, max absolute error 3.052e-05.

The stock chunked implementation exports `ScatterElements`, `ScatterND`, `Trilu`, and `CumSum` because the triangular solve is lowered to a serial substitution and the chunk loop writes the state in place. The rewrite uses the mathematically equivalent recurrent form and stacks timestep outputs. Any `Gather` or `Scatter` counts above are what this unrolled scan still emitted.

### SwiGLU MLP from layer 3

{
  "MatMul": 3,
  "Mul": 2,
  "Sigmoid": 1
}

PyTorch versus ONNX Runtime: cosine min 1.00000000.

### Joint schema head

{
  "Transpose": 96,
  "Reshape": 88,
  "Add": 67,
  "MatMul": 57,
  "Mul": 48,
  "Gather": 31,
  "Unsqueeze": 27,
  "LayerNormalization": 23,
  "Gemm": 20,
  "Div": 18,
  "Slice": 13,
  "Split": 12,
  "Softmax": 12,
  "Squeeze": 10,
  "Erf": 8,
  "ReduceL2": 8,
  "Clip": 8,
  "ReduceMean": 7,
  "Concat": 7,
  "Expand": 6,
  "ReduceSum": 4,
  "Sub": 2,
  "Abs": 2
}

Official head versus static pooled graph: decision agreement 1.000, logit cosine min 1.00000000.
Static graph versus ONNX Runtime: cosine min 1.00000000, max absolute error 1.431e-06.

## Graph modifications

- mRoPE cos/sin are computed on the host and passed into the full-attention block.
- Question and option spans are mean-pooled on the host. The head graph does not gather token ids.
- Linear attention uses an unrolled recurrent scan instead of `torch.linalg.solve_triangular` and in-place chunk writes.
- Cache and KV updates are outside these graphs. Each export is a single prefill step with no past state.
- Upstream Clef files under `hailo_port/upstream/` are the published sources. The wrappers live in `hailo_port/graphs.py`.
