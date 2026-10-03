# Final status

1. Highest level reached for a full Clef-Flash block: **LEVEL 2**. The full layer-3 SwiGLU fails single-context placement after 30m 2s. Multi-context search then fails every tried split with `Automri finished with too many resources` on contexts 0 through 5 (hundreds of iterations, no success yet). The same MLP rebuilds, within float32 error, from 48 matmul tiles plus host adds and the SiLU multiply. One real gate tile is a HEF.
2. Architecture executed: Qwen3.5-9B decoder layer 3 (full attention) and layer 0 (Gated DeltaNet), plus the Clef joint schema head, all from the published Clef-Flash checkpoint. Sequence length 8 for blocks. Head schema is one 3-way choice and one true/false question, sequence 16.
3. Parts that run on Hailo hardware: none. `/dev/hailo0` is absent. The quantized emulator ran a width-64 SwiGLU. The real MLP graph is still in the compiler.
4. Parts that remain on CPU: tokenization, mRoPE, span pooling, the exported blocks, and the decision head. Vision encoder not run.
5. Parser results, DFC 5.4.0, `hw_arch=hailo10h`:
   - SwiGLU MLP: parsed. HAR `artifacts/clef_experimental_mlp.har`. Layers are 1x1 conv, SiLU, elementwise multiply, conv. Input shape `[-1, 1, 8, 4096]`.
   - Full-attention block with RoPE: failed in the fuser, `fuser.py _handle_neg_feature_shuffle`, `IndexError: list assignment index out of range`. ONNX simplify succeeded first and did not avoid the crash.
   - Full-attention block with `rotate_half` removed: parsed. HAR `artifacts/clef_experimental_full_attention_no_rope.har`. Hailo layer types include conv, layer_normalization, normalization, matmul, softmax, ew_mult, ew_add.
   - Scatter-free linear block: failed while classifying a reshape, `onnx_graph.py _is_spatial_flatten_with_features_to_heads_reshape`, `StopIteration`.
   - Joint schema head: failed while adding inputs, `onnx_graph.py get_input_layer_shapes`, `TypeError: object of type 'NoneType' has no len()`.
   - Two stacked full-attention blocks: failed in transpose shape inference, `IndexError: list index out of range`.
6. Graph modifications: host mRoPE, host span pooling, recurrent scan stacked instead of in-place scatter, no KV cache inside the graph.
7. Quantisation: Hailo optimization level 0 on the real MLP, and the same setting on a width-64 SwiGLU. Emulator cosine against PyTorch for that probe is 0.9957, max absolute error 0.111. Host int8 of the real head kept decision agreement at 1.000. Details are in `reports/clef_quantisation_results.md`.
8. Decision agreement with reference Clef: the static head matches the official head on 1.000 of the fixed-schema cases (logit cosine min 1.00000000). End-to-end Clef-Flash decisions were not run, because the full backbone was not resident.
9. Hailo resource usage, single context: a random hidden-1024 SwiGLU uses 53.8% control, 76.3% compute, and 68.4% memory, with one cluster at 97.9% compute. One real Clef gate tile uses 42.5% control, 65.4% compute, and 39.2% memory. The full 4096-wide MLP has no successful allocation.
10. Compile latency on the workstation, not on a Hailo device: 5s, 18s, 33s, and 1m 7s for hidden 64, 256, 512, and 1024. Hidden 2048 was stopped after 7 minutes still building optimization options. The real MLP spent 21m 37s on pre-partition, then 30m 2s failing single-context placement of `conv1`, `conv2`, and `conv3`.
11. HEF paths:
    - Real Clef gate-matrix tile, input 1024, output 3072: `hailo_port/generated/clef_experimental_gate_tile.hef` (2,543,616 bytes, compile 30s). Quantized emulator cosine 0.9994, max absolute error 0.057.
    - Real Clef SwiGLU subspace tile, hidden 1024: `hailo_port/generated/clef_experimental_mlp_h1024_tile.hef`. Quantized emulator cosine 0.9953, max absolute error 0.0184.
    - Random-weight SwiGLU probes: `hailo_port/generated/clef_width_h64.hef`, `clef_width_h256.hef`, `clef_width_h512.hef`, `clef_width_h1024.hef`.
    - Full Clef MLP HAR, not a HEF: `artifacts/clef_experimental_mlp.optimized.har`. The compiler is in multi-context search for that graph.
12. Next experiment: let the 4096-wide Clef MLP allocator finish or fail. Re-quantize with 1024 calibration rows before treating accuracy as meaningful. Do not deploy this over JEV-H.

## Smoke records

20 official encodings are stored in `tests/reference/smoke_records.json`.
