# JEV-H-trading receipt (round 2: Jev distill)

> **Not financial advice.** Offline research only. No live or paper order routing. No exchange or broker calls. Gold is typesafe/jev-1.13's own choice, not a traded P&L.

Seed `42`. Wall 41.1s. Size **17m**. Backbone loaded: True. Smoke=False.

## Honest data verdict

- Unique state+menu rows: **1260** (raw 1581)
- Multi-option usable for train/dev/eval: **253** (train 177 / dev 38 / eval 24, purge 14 @ 300000 ms)
- Single-option (format-check only, dropped from train): **1004**
- Genuinely varied multi-option: **4** (need ~2000; shortfall 1996)
- Non-hold gold: **4** (need ~400; shortfall 396)
- Calendar days: **2** (need 14)
- Gold distribution: `{"HOLD_WINNER": 249, "APE_STRK": 1, "APE_DOGE": 1, "SHORT_BTC": 1, "DOUBLE_DOWN": 1}`
- Enough to claim a cost-free Jev stand-in: **False**

A 68m student can copy a collapsed HOLD_WINNER teacher from a few hundred near-duplicate ticks. Mimicking discretionary Jev (when to leave HOLD, which APE_*, when to SWITCH) wants thousands of *varied* multi-option rows, with each offered action as gold at least ~50 times, over more than one regime.

## Agreement with Jev (gold = choice)

| split | n | agree | varied n/acc | collapsed n/acc | conf-mist ≥0.65 | ECE | always HOLD/RIDE |
|---|---:|---:|---|---|---:|---:|---:|
| time-split eval | 24 | 1.0000 | 0/None | 24/1.0 | 0 | 0.0000 | 1.0000 |
| time-split dev (T fit) | 38 | 1.0000 | 1/1.0 | 37/1.0 | 0 | 0.0031 | 0.9737 |
| train | 177 | 1.0000 | 3/1.0 | 174/1.0 | 0 | 0.0000 | 0.9944 |

### Per menu size (eval)

```json
{
  "3": {
    "n": 24,
    "accuracy": 1.0
  }
}
```

### Per action (eval, gold label)

```json
{
  "HOLD_WINNER": {
    "n": 24,
    "accuracy": 1.0
  }
}
```

## Recipe

```json
{
  "gold": "jev_choice",
  "soft_targets": "probabilities (KL) + listwise CE + pairwise hinge",
  "option_shuffle": true,
  "size": "17m",
  "hf_id": "jhu-clsp/ettin-encoder-17m",
  "hidden": 256,
  "n_layers": 7,
  "n_heads": 4,
  "seq_len": 128,
  "unfreeze_last": 4,
  "lr_encoder": 2e-05,
  "lr_head": 8e-05,
  "lr_embed": 5e-06,
  "layer_decay": 0.9,
  "pair_coef": 0.4,
  "pair_margin": 0.5,
  "soft_kl_coef": 0.5,
  "epochs_run": 6,
  "epochs_requested": 6,
  "microbatch": 8,
  "temperature": 0.3,
  "n_params": 16863489,
  "n_trainable": 2296577,
  "backbone_loaded": true,
  "missing_keys": [],
  "keep_option_rows": 3,
  "tokenizer": "/workspace/tools/orchestration/jevh_trading/assets/tokenizer.json",
  "train_minutes": 0.54,
  "source_recipe": "cursor/jevh-variant-68m-v5-f666 (read, not merged)"
}
```

CPU latency batch-1 (PyTorch, one option): mean **8.59 ms** (p50 8.54, p95 9.03).

## ONNX (Hailo-10H DFC input, not compiled)

- path: `/workspace/tools/orchestration/jevh_trading/artifacts/jevh_trading_ettin17m_seq128.onnx`
- sha256: `b5f2170e30da9282f70d7979daa691ddbdc92a8628576e451535947e4dc95725`
- opset: 17
- inputs: `{'input_ids': [1, 128], 'attention_mask': [1, 128]}`
- outputs: `{'logit': [1, 1]}`
- attention_mask used: True
- PyTorch/ORT cos: **0.9999999999990233** (max abs 1.621246337890625e-05)
- calib: 256 unique tokenized pairs `[256, 128]`

## Outcome aux (not gold)

{
  "n_mapped": 0,
  "paper_span_hours": 1.472,
  "horizon_hours": 8,
  "note": "Forward-outcome labels are an optional auxiliary/eval signal, not gold. This log spans ~1.5h of decisions; an 8h forward window is not available for almost every row. Do not treat outcome-argmax as a Jev stand-in."
}

## Known gaps

- Gold is Jev's logged choice + probabilities, not forward PnL. Not financial advice.
- Genuinely varied multi-option rows: 4 (need ~2000).
- Non-hold gold: 4 (need ~400).
- Single-option RIDE menus are format-check only and never enter the train loss.
- Collapsed HOLD_WINNER+LONG_BTC+SWITCH ticks dominate; a student can copy HOLD without mimicking discretionary Jev.
- Backbone 17m (jhu-clsp/ettin-encoder-17m); recipe from 68m-v5, not merged. 17m is the thin-data/CPU fallback.
- No HEF compile, no Pi deploy, no exchange/broker/trading API calls, no paid APIs.
- Beebots engine is not modified; see BEEBOTS_LOG_SPEC.md for the log schema.
- Forced/vetoed execution is metadata; gold stays Jev's choice even when the engine overrode the fill.
- seq128 keep_option: 3 encoded rows overflowed; option tokens are kept and state is trimmed from the end.
