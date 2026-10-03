# Final status

1. Highest level reached: **LEVEL 2**. The SwiGLU MLP from Clef-Flash layer 3, and a full-attention block with RoPE removed, both parse to Hailo-10H HAR files with Dataflow Compiler 5.4.0. The MLP was quantized (Hailo optimization level 0). Compilation of that MLP into a HEF was still running in the Hailo allocator when this status was written. No HEF file exists yet.
2. Architecture executed: Qwen3.5-9B decoder layer 3 (full attention) and layer 0 (Gated DeltaNet), plus the Clef joint schema head, all from the published Clef-Flash checkpoint. Sequence length 8 for blocks. Head schema is one 3-way choice and one true/false question, sequence 16.
3. Parts that run on Hailo: none yet. The compiler produced HARs. `/dev/hailo0` is absent, so nothing has been executed on a device. The MLP graph is in the compiler now.
4. Parts that remain on CPU: tokenization, mRoPE, span pooling, the exported blocks, and the decision head. Vision encoder not run.
5. Parser results, DFC 5.4.0, `hw_arch=hailo10h`:
   - SwiGLU MLP: parsed. HAR `artifacts/clef_experimental_mlp.har`. Layers are 1x1 conv, SiLU, elementwise multiply, conv. Input shape `[-1, 1, 8, 4096]`.
   - Full-attention block with RoPE: failed in the fuser, `fuser.py _handle_neg_feature_shuffle`, `IndexError: list assignment index out of range`. ONNX simplify succeeded first and did not avoid the crash.
   - Full-attention block with `rotate_half` removed: parsed. HAR `artifacts/clef_experimental_full_attention_no_rope.har`. Hailo layer types include conv, layer_normalization, normalization, matmul, softmax, ew_mult, ew_add.
   - Scatter-free linear block: failed while classifying a reshape, `onnx_graph.py _is_spatial_flatten_with_features_to_heads_reshape`, `StopIteration`.
   - Joint schema head: failed while adding inputs, `onnx_graph.py get_input_layer_shapes`, `TypeError: object of type 'NoneType' has no len()`.
   - Two stacked full-attention blocks: failed in transpose shape inference, `IndexError: list index out of range`.
6. Graph modifications: host mRoPE, host span pooling, recurrent scan stacked instead of in-place scatter, no KV cache inside the graph.
7. Quantisation: Hailo quantizer not run. Host int8 sensitivity is in `reports/clef_quantisation_results.md`. Head decision agreement under that rounding: 1.000. Layer-3 hidden cosine min after the same rounding: 0.999950. Decision agreement when that hidden state is scored by the FP32 head: 1.000.
8. Decision agreement with reference Clef: the static head matches the official head on 1.000 of the fixed-schema cases (logit cosine min 1.00000000). End-to-end Clef-Flash decisions were not run, because the full backbone was not resident.
9. Hailo resource usage: not measured.
10. Latency: not measured on Hailo. CPU ONNX checks were correctness checks, not a latency study.
11. HEF paths: none yet. Optimized MLP HAR: `artifacts/clef_experimental_mlp.optimized.har`.
12. Next experiment: finish or restart `ClientRunner.compile()` on the optimized MLP HAR and record the allocator error if 4096-channel 1x1 convolutions do not fit Hailo-10H. If a HEF appears, compare it with the FP32 MLP on the 12 saved cases. Then split the full-attention block so RoPE stays on the host and only the parsed no-RoPE graph is compiled. Do not replace JEV-H or any HEF already on the Pi.

## Smoke records

20 official encodings are stored in `tests/reference/smoke_records.json`.
