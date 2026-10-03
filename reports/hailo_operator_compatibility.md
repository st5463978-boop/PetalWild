# Hailo operator compatibility

Target: Hailo-10H / Raspberry Pi AI HAT 2. Compiler package: Hailo Dataflow Compiler, `hailo_sdk_client`.

## Compiler stage actually reached

Dataflow Compiler 5.4.0 was installed from `hailo_dataflow_compiler-5.4.0-py3-none-linux_x86_64.whl` into `artifacts/hailo-venv`. `ClientRunner(hw_arch="hailo10h")` constructs. The wheel arrived by Tailscale Taildrop from the phone. It is not committed.

Parser and compiler results:

| Graph | Stage | Result |
|---|---|---|
| Layer-3 SwiGLU MLP | `translate_onnx_model` | HAR written. Hailo sees 1x1 conv + SiLU + ew multiply + conv. Input `[-1, 1, 8, 4096]`. 151.02M parameters in the Hailo model. |
| Same MLP | `optimize` | Finished. Hailo lowered the optimization level to 0 because the calibration set had 8 rows and no GPU was visible. Recommended calibration count is 1024. |
| Same MLP | `compile` | Single context failed in 30m 2s (`conv1`, `conv2`, `conv3` had no assignment). Multi-context search at a 60% utilization cap then found a 17-context partition after 888 iterations (17m 52s of search, 33m 31s for the partition stage). 791 of 823 failed iterations were `Automri finished with too many resources`, mostly on context_2. The compiler is still in allocation after `Partition passed at control_util 0.6`. No HEF yet. |
| One full-attention head core, sequence 8, head dim 256, packed QKV | `compile` | HEF `hailo_port/generated/clef_experimental_attn_core.hef`, 65,536 bytes, about 1s. Causal QK^T, softmax, and AV. Total control 17.5%, compute 6.3%, memory 4.7%. |
| Full layer-3 `k_proj` and `v_proj`, 4096 to 1024 | `compile` | Single-context HEFs. K: 3,067,904 bytes, 1m 17s, cosine 0.999016, max abs 0.193. V: 3,211,264 bytes, 1m 19s, cosine 0.999288, max abs 0.147. Total control 42.5%, compute 64.2%, memory 38.8%. Cluster 4 compute is 100%. |
| Full layer-3 `q_proj`, 4096 to 8192 | `compile` | Single context failed in 4m 19s: `conv1` had no successful assignment. Multi-context search then accepted 4 contexts in 3m 44s (114 iterations, 60% cap) and split `conv1` into `conv1_d0`..`conv1_d16`. Allocation of that partition started. No HEF yet. Quantized cosine 0.998160, max abs 0.376. |
| One real gate-matrix tile, 1024 to 3072 | `compile` | HEF `hailo_port/generated/clef_experimental_gate_tile.hef`, 30s. Sixteen such tiles per projection, plus a host SiLU multiply, match the full MLP within 1.2e-6. |
| Same SwiGLU formula, random weights, hidden 64, 256, 512, 1024 | `compile` | HEF written. Single context. Files in `hailo_port/generated/`. Hidden 1024 uses 68.4% memory and one cluster reaches 97.9% compute. |
| Same formula, hidden 2048 | `compile` | Stopped after 7 minutes while still building optimization options. No HEF. |
| Leading 1024×3072 tile of the real Clef layer-3 MLP weights | `compile` | HEF `hailo_port/generated/clef_experimental_mlp_h1024_tile.hef`, 50s, single context. Quantized emulator cosine 0.9953 against that tile in PyTorch. |
| Full-attention block, RoPE inside | `translate_onnx_model` | Fuser crash after a successful ONNX simplify: `_handle_neg_feature_shuffle` raises `IndexError: list assignment index out of range`. |
| Full-attention block, RoPE removed | `translate_onnx_model` | HAR written. Layer types: conv, layer_normalization, normalization, matmul, softmax, ew_mult, ew_add, feature_splitter. |
| Linear Gated DeltaNet block | `translate_onnx_model` | `StopIteration` in `_is_spatial_flatten_with_features_to_heads_reshape`. |
| Joint schema head | `translate_onnx_model` | `TypeError: object of type 'NoneType' has no len()` in `get_input_layer_shapes`. |
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
