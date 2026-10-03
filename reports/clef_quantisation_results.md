# Clef quantisation results

Hailo `runner.optimize` ran on the parsed Clef SwiGLU MLP with 8 random normal rows of shape `(1, 8, 4096)`. It reduced the optimization level to 0 because that is below the recommended 1024 rows and no GPU was available. Adaround, bias correction, and quantization-aware fine-tuning were skipped. The optimized HAR is `artifacts/clef_experimental_mlp.optimized.har`. That quantized model is now `artifacts/clef_experimental_mlp.hef`. Against the PyTorch MLP on 4 sequences of shape `(4, 8, 4096)`, the quantized emulator scores cosine 0.966529, MSE 9.30e-3, and max absolute error 2.03. Eight calibration rows and optimization level 0 are why that gap is larger than the width-64 probe.

Those same quantized activations, 12 sequences, scored by the FP32 joint head: decision agreement 0.75, high-confidence disagreements 0, logit cosine min 0.9336, mean 0.9786, maximum probability change 0.247. Hidden cosine on those 12 sequences is 0.962434 and max absolute error is 1.03. Sequence 8 is repeated to fill the head's length-16 schema. This is layer 3 only.

Partial RoPE (64 of 256, host cos and sin, swap then sign) quantized at 64 rows and optimization level 0 matches the float rotate at cosine 0.999587, MSE 1.03e-3, and max absolute error 0.195. That graph compiled.

Sixteen query heads, four KV heads, sequence 8, head dimension 256, with the query packed as `[B, S, 4096]` and sliced on the last axis, match PyTorch in the native emulator at max absolute error 1.07e-6. The quantized emulator on that graph, 64 rows and optimization level 0, scores cosine 0.669818, MSE 0.331, and max absolute error 4.31. The mask on the scores is `-64`. Twelve matmul/concat pairs have a scale inconsistency. That graph did not place in one context (`lcus=244/80`). Multi-context search after 62 minutes and 2893 rejected partitions has not accepted a split: shmifo capacity is 20 and the candidates require 21 to 112.

The same rotate inside layer-3 attention, MLP removed, matches PyTorch in the float Hailo emulator at cosine 0.996791, MSE 9.27e-3, and max absolute error 2.10 on 12 sequences. Optimization level is 0 and calibration is 64 rows. The default quantized emulator then crashes in `matmul1` zero-point compensation, with dimensions 4096 and 8. The scores matmul is 16 groups of 256 features. The zero-point vector is the full 4096, and the compensation slice is `(batch, 1, 1, 4, 1, 1, 8)`. Hardware export keeps only the first of those zero points. `zp_comp_weights` fails during optimize because the predecessor is a `HailoDepthwise` with no `zp_comp_add`. `zp_comp_block_2` and `zp_comp_block_3` hit the same 4096-versus-8 crash. `zp_comp_none` on `matmul1` scores cosine 0.867365, MSE 0.402, and max absolute error 22.0. The compiled HEF uses the default compensation, so that 0.867 figure is a different quantization from the file.

That `zp_comp_none` attention, passed through the host post-attention norm and the FP32 MLP, agrees with the official block on 0.750 of the 12 fixed-schema cases. High-confidence disagreements are 0. Logit cosine min is 0.790040. The largest probability change is 0.333. The float Hailo attention through the same host MLP agrees on 0.833 of those cases, with 0 high-confidence disagreements, logit cosine min 0.997726, and largest probability change 0.054.

The no-RoPE attention without the MLP, 64 rows and optimization level 0, matches PyTorch at cosine 0.995641, MSE 1.25e-2, and max absolute error 2.12. Feeding that quantized attention through the host post-attention norm and the quantized MLP, then adding the residual, matches the float block on 4 sequences at cosine 0.992361 and max absolute error 4.54. The FP32 head then agrees on 0.75 of those 4 cases, with 0 high-confidence disagreements, logit cosine min 0.9898, and maximum probability change 0.156.

One Gated DeltaNet step, 64 rows and the same level-0 limit, matches the PyTorch loop body at state cosine 0.992339 (max absolute error 4.42) and output cosine 0.984008 (max absolute error 31.9).

Eight chained steps, same row count and level, are a different story. Decay is drawn uniformly from `[0, 1]` and the float state reaches a max of 2.5e5. The quantized emulator then scores state cosine 0.281300 and output cosine 0.467115. The output shapes match PyTorch, so the drop is the int8 range of that exploded state.

The same eight steps with Q/K L2 norm and `exp(g)` decay, `g = -softplus(normal)`, keep the float state max at 0.882. Quantized the same way, the state cosine is 0.996295 (max absolute error 0.0265) and the outputs cosine is 0.991975 (max absolute error 0.00357). That graph compiled.

The depthwise conv through the head-pair concat, stopping before the unsupported `[16, 2]` to `32` reshape, was quantized with 64 rows at optimization level 0. Against the float Hailo graph, twelve outputs score cosine 0.723658 to 0.999998, with max absolute error about 0.029. That prefix compiled. It does not include the scan.

A width-64 copy of the same SwiGLU, random weights, was quantized the same way and executed in the compiler's quantized emulator (`SDK_QUANTIZED`), not on a Hailo device. Against the PyTorch module on 4 sequences: cosine 0.9957, MSE 1.22e-4, max absolute error 0.111. Optimization level 0 and random calibration are why that error is as large as it is.

The leading tile of the real Clef layer-3 MLP (hidden 1024, intermediate 3072) scored cosine 0.9953, MSE 1.68e-5, and max absolute error 0.0184 under the same emulator and the same optimization level.

The causal attention core (one head, sequence 8, head dimension 256) was quantized and executed in `SDK_QUANTIZED`. The model script set `calibset_size=1024`. The compiler still forced optimization level 0 because no GPU is present, so Adaround, bias correction, and quantization-aware fine-tuning were skipped. Against PyTorch on 4 sequences: cosine 0.999709, MSE 2.93e-4, max absolute error 0.0755. Scrambling future V left position 0 unchanged (leak 0) in both PyTorch and the emulator.

The full layer-3 K and V projections were quantized with the same 1024-row calibration and the same level-0 limit. K versus PyTorch: cosine 0.999016, MSE 2.19e-3, max absolute error 0.193. V: cosine 0.999288, MSE 1.53e-3, max absolute error 0.147. The cosine stays high while the peak error is larger than the attention core, which is what a wide unnormalized projection does under per-tensor activation quantization.

The full Q projection, 4096 to 8192, quantized under the same settings before its compile failed single-context placement: cosine 0.998160, MSE 5.19e-3, max absolute error 0.376.

The decision numbers below are still the separate host-side int8 check on the real Clef head and layer 3.

The joint-head ONNX after host type embeddings, the folded weight transpose, and the Tile replacement of two Expands matches the official head on 4 random cases: max absolute error 4.77e-7, decision agreement 1.0. That graph is what the parser is failing on, not a numerically different head.

The parsed head prefix, quantized with 64 rows at optimization level 0, matches the float Hailo graph on five outputs with cosine 0.9996 to 0.9999 and max absolute error 0.055. That prefix did not compile.

The published `question_projection` (4096 to 1024), quantized with 1024 rows at optimization level 0, matches PyTorch at cosine 0.999830 and max absolute error 0.0422. That projection did compile.

The published layer-0 depthwise causal conv (8192 channels, kernel 4, sequence 8, bias left at zero) was quantized with 1024 rows. Optimization level stayed 0 because no GPU is present. Against PyTorch on 4 sequences: cosine 0.997265, MSE 5.37e-5, max absolute error 0.0320. That conv did compile.

The linear-scan prefix (depthwise conv, SiLU, QKV split, beta and decay projections) was quantized with 256 rows, again at optimization level 0. The comparison is the quantized emulator against the float Hailo graph, not against PyTorch. Sixteen outputs score cosine 0.999942 or better. Output 12 scores cosine 0.989363 and max absolute error 0.0265. That prefix did not compile.

The QKV widths as three slices, same 256 rows and level 0, match the sliced activation at cosine 0.999927 and max absolute error 0.0210. That graph did compile. The published depthwise conv plus SiLU plus those slices, same calibration, matches PyTorch at query cosine 0.986650 (max 0.0256), key cosine 0.992523 (max 0.0260), and value cosine 0.902513 (max 0.0251). Value's standard deviation is 0.023. That graph also compiled.

## Decision head weights rounded to int8

- Cases: 12, fixed schema (3-way choice plus true/false).
- Decision agreement with the FP32 head: 1.000
- High-confidence disagreements (FP32 margin >= 0.2 and confidence >= 0.7, choice changed): 0

## Layer-3 hidden state after the same int8 rounding, scored by the FP32 head

{
  "hidden_cosine_min": 0.9999498286471249,
  "hidden_cosine_mean": 0.9999527315523942,
  "decision_agreement": 1.0,
  "note": "Layer 3 only, sequence 8, per-channel int8 weights. Not a full-backbone Hailo quantization."
}

A drop in decision agreement here would mean the head is reading features that this rounding damaged. Agreement near 1 with a lower hidden-state cosine means the decision survived even though the activation moved.

Full-backbone Clef decisions were not compared. The 9.4B backbone does not fit in this machine's memory as a single resident model, and only layers 0 and 3 were downloaded. Token-level smoke inputs are in `tests/reference/smoke_records.json` (20 records, token length min 234, max 253). Those records are encoded with the official Clef tokenizer and `encode_record`. They were not passed through the backbone.
