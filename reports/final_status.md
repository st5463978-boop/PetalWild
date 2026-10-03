# Final status

1. Highest level reached for a full Clef-Flash block: **LEVEL 2**. The full layer-3 SwiGLU fails single-context placement after 30m 2s. Multi-context search then accepted a 17-context partition after 888 iterations (33m 31s). Allocation of that partition is still running, and there is no full-MLP HEF. The same MLP rebuilds, within float32 error, from 48 matmul tiles plus host adds and the SiLU multiply. One real gate tile is a HEF. Separately, one causal attention head core (QK^T, mask, softmax, AV) is a HEF.
2. Architecture executed: Qwen3.5-9B decoder layer 3 (full attention) and layer 0 (Gated DeltaNet), plus the Clef joint schema head, all from the published Clef-Flash checkpoint. Sequence length 8 for blocks. Head schema is one 3-way choice and one true/false question, sequence 16.
3. Parts that run on Hailo hardware: none. `/dev/hailo0` is absent. The quantized emulator ran the attention-head core and a width-64 SwiGLU. The real MLP graph is still in the compiler.
4. Parts that remain on CPU: tokenization, mRoPE, Q/K/V projection, span pooling, the rest of each exported block, and the decision head. Vision encoder not run.
5. Parser results, DFC 5.4.0, `hw_arch=hailo10h`:
   - SwiGLU MLP: parsed. HAR `artifacts/clef_experimental_mlp.har`. Layers are 1x1 conv, SiLU, elementwise multiply, conv. Input shape `[-1, 1, 8, 4096]`.
   - Full-attention block with RoPE: failed in the fuser, `fuser.py _handle_neg_feature_shuffle`, `IndexError: list assignment index out of range`. ONNX simplify succeeded first and did not avoid the crash.
   - Full-attention block with `rotate_half` removed: parsed. HAR `artifacts/clef_experimental_full_attention_no_rope.har`. Hailo layer types include conv, layer_normalization, normalization, matmul, softmax, ew_mult, ew_add.
   - Scatter-free linear block: failed while classifying a reshape, `onnx_graph.py _is_spatial_flatten_with_features_to_heads_reshape`, `StopIteration`.
   - Joint schema head: failed while adding inputs, `onnx_graph.py get_input_layer_shapes`, `TypeError: object of type 'NoneType' has no len()`.
   - Two stacked full-attention blocks: failed in transpose shape inference, `IndexError: list index out of range`.
   - One attention head core, sequence 8, head dimension 256, packed QKV: compiled. The rank-3 causal mask had to be widened to `[1, 8, 8]` or the post-fuser crashed in `is_spatial_broadcast`. Dynamic-dynamic matmul needed `zp_comp_none`. HEF `hailo_port/generated/clef_experimental_attn_core.hef`.
6. Graph modifications: host mRoPE, host span pooling, recurrent scan stacked instead of in-place scatter, no KV cache inside the graph.
7. Quantisation: Hailo optimization level 0, because this machine has no GPU. The attention-head core, calibrated on 1024 rows, scored emulator cosine 0.999709 and max absolute error 0.0755 against PyTorch, with future-token leak 0. A width-64 SwiGLU scored cosine 0.9957 and max absolute error 0.111. Host int8 of the real head kept decision agreement at 1.000. Details are in `reports/clef_quantisation_results.md`.
8. Decision agreement with reference Clef: the static head matches the official head on 1.000 of the fixed-schema cases (logit cosine min 1.00000000). End-to-end Clef-Flash decisions were not run, because the full backbone was not resident.
9. Hailo resource usage, single context: a random hidden-1024 SwiGLU uses 53.8% control, 76.3% compute, and 68.4% memory, with one cluster at 97.9% compute. One real Clef gate tile uses 42.5% control, 65.4% compute, and 39.2% memory. The attention-head core uses 17.5% control, 6.3% compute, and 4.7% memory. The full 4096-wide MLP has a 17-context partition and no finished allocation.
10. Compile latency on the workstation, not on a Hailo device: about 1s for the attention-head core. 5s, 18s, 33s, and 1m 7s for hidden 64, 256, 512, and 1024. Hidden 2048 was stopped after 7 minutes still building optimization options. The real MLP spent 21m 37s on pre-partition, 30m 2s failing single-context placement of `conv1`, `conv2`, and `conv3`, then 33m 31s to accept a 17-context partition. Allocation of context 2 of 16 was still running after that.
11. HEF paths:
    - Real Clef gate-matrix tile, input 1024, output 3072: `hailo_port/generated/clef_experimental_gate_tile.hef` (2,543,616 bytes, compile 30s). Quantized emulator cosine 0.9994, max absolute error 0.057.
    - Real Clef SwiGLU subspace tile, hidden 1024: `hailo_port/generated/clef_experimental_mlp_h1024_tile.hef`. Quantized emulator cosine 0.9953, max absolute error 0.0184.
    - Random-weight SwiGLU probes: `hailo_port/generated/clef_width_h64.hef`, `clef_width_h256.hef`, `clef_width_h512.hef`, `clef_width_h1024.hef`.
    - Causal attention core, one head: `hailo_port/generated/clef_experimental_attn_core.hef` (65,536 bytes, compile about 1s). Quantized emulator cosine 0.999709, max absolute error 0.0755, future-token leak 0, 1024 calibration rows, optimization level 0.
    - Full Clef MLP HAR, not a HEF: `artifacts/clef_experimental_mlp.optimized.har`. The compiler has a 17-context partition and is still allocating it.
12. Next experiment: let the 17-context MLP allocation finish or fail. The attention core's Q, K, and V projections are still host-side; the next graph to compile is one of those projections, tiled the same way as the gate matrix. Do not deploy this over JEV-H.

## Smoke records

20 official encodings are stored in `tests/reference/smoke_records.json`.
