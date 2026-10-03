# Clef quantisation results

Hailo `runner.optimize` did run on the parsed SwiGLU MLP. It used 8 random normal calibration rows of shape `(1, 8, 4096)` and then printed that it was reducing the optimization level to 0 because that is below the recommended 1024 rows and no GPU was available. Adaround, bias correction, and quantization-aware fine-tuning were skipped. The optimized HAR is `artifacts/clef_experimental_mlp.optimized.har`. No HEF output has been compared with the reference, so the decision numbers below are still the separate host-side int8 check.

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
