# Hailo operator compatibility

Target: Hailo-10H / Raspberry Pi AI HAT 2. Compiler package: Hailo Dataflow Compiler, `hailo_sdk_client`.

## Compiler stage actually reached

Dataflow Compiler 5.4.0 was installed from `hailo_dataflow_compiler-5.4.0-py3-none-linux_x86_64.whl` into `artifacts/hailo-venv`. `ClientRunner(hw_arch="hailo10h")` constructs. The wheel arrived by Tailscale Taildrop from the phone. It is not committed.

Parser and compiler results:

| Graph | Stage | Result |
|---|---|---|
| Layer-3 SwiGLU MLP | `translate_onnx_model` | HAR written. Hailo sees 1x1 conv + SiLU + ew multiply + conv. Input `[-1, 1, 8, 4096]`. 151.02M parameters in the Hailo model. |
| Same MLP | `optimize` | Finished. Hailo lowered the optimization level to 0 because the calibration set had 8 rows and no GPU was visible. Recommended calibration count is 1024. |
| Same MLP | `compile` | Hailo allocator process started (`hailo_tools/build/compiler hailo10h`) and was still running when this report was written. No HEF yet. |
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
