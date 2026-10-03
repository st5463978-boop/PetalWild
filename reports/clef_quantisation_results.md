# Clef quantisation results

Hailo `runner.optimize` ran on the parsed Clef SwiGLU MLP with 8 random normal rows of shape `(1, 8, 4096)`. It reduced the optimization level to 0 because that is below the recommended 1024 rows and no GPU was available. Adaround, bias correction, and quantization-aware fine-tuning were skipped. The optimized HAR is `artifacts/clef_experimental_mlp.optimized.har`. That HEF does not exist yet, so it was not compared with the reference.

A width-64 copy of the same SwiGLU, random weights, was quantized the same way and executed in the compiler's quantized emulator (`SDK_QUANTIZED`), not on a Hailo device. Against the PyTorch module on 4 sequences: cosine 0.9957, MSE 1.22e-4, max absolute error 0.111. Optimization level 0 and random calibration are why that error is as large as it is.

The leading tile of the real Clef layer-3 MLP (hidden 1024, intermediate 3072) scored cosine 0.9953, MSE 1.68e-5, and max absolute error 0.0184 under the same emulator and the same optimization level.

The causal attention core (one head, sequence 8, head dimension 256) was quantized and executed in `SDK_QUANTIZED`. The model script set `calibset_size=1024`. The compiler still forced optimization level 0 because no GPU is present, so Adaround, bias correction, and quantization-aware fine-tuning were skipped. Against PyTorch on 4 sequences: cosine 0.999709, MSE 2.93e-4, max absolute error 0.0755. Scrambling future V left position 0 unchanged (leak 0) in both PyTorch and the emulator.

The full layer-3 K and V projections were quantized with the same 1024-row calibration and the same level-0 limit. K versus PyTorch: cosine 0.999016, MSE 2.19e-3, max absolute error 0.193. V: cosine 0.999288, MSE 1.53e-3, max absolute error 0.147. The cosine stays high while the peak error is larger than the attention core, which is what a wide unnormalized projection does under per-tensor activation quantization.

The full Q projection, 4096 to 8192, quantized under the same settings before its compile failed single-context placement: cosine 0.998160, MSE 5.19e-3, max absolute error 0.376.

The decision numbers below are still the separate host-side int8 check on the real Clef head and layer 3.

The joint-head ONNX after host type embeddings, the folded weight transpose, and the Tile replacement of two Expands matches the official head on 4 random cases: max absolute error 4.77e-7, decision agreement 1.0. That graph is what the parser is failing on, not a numerically different head.

The parsed head prefix, quantized with 64 rows at optimization level 0, matches the float Hailo graph on five outputs with cosine 0.9996 to 0.9999 and max absolute error 0.055. That prefix did not compile.

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
