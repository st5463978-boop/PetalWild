# JEV-H-trading receipt

> **Not financial advice.** Offline research / backtest only. No live or paper order routing. No exchange or broker calls.

Seed `42`. Wall 165.2s. Smoke=False.

## Data

```json
{
  "market_bars_per_coin": 5000,
  "market_t0": 1787004900,
  "market_t1": 1791506700,
  "replay_after_downsample": {
    "train": 2193,
    "eval": 754
  },
  "replay_label_distribution": {
    "HOLD_WINNER": 473,
    "APE_SOL": 247,
    "LONG_ETH": 227,
    "LONG_BTC": 217,
    "SWITCH": 216,
    "SHORT_BTC": 207,
    "RIDE": 206,
    "SHORT_ETH": 205,
    "BAIL": 204,
    "APE_ETH": 156,
    "APE_BTC": 143,
    "TRIM_HALF": 86,
    "HOLD": 76,
    "DOUBLE_DOWN": 68,
    "WAIT": 52,
    "CUT_LOSS": 38,
    "BREAKOUT_SOL": 37,
    "SWITCH_COIN": 35,
    "BREAKOUT_BTC": 25,
    "FLIP_SHORT": 24,
    "BREAKOUT_ETH": 5
  },
  "eval_label_distribution": {
    "HOLD_WINNER": 122,
    "SHORT_ETH": 71,
    "LONG_BTC": 68,
    "SWITCH": 64,
    "APE_SOL": 58,
    "BAIL": 56,
    "RIDE": 55,
    "APE_BTC": 50,
    "SHORT_BTC": 45,
    "LONG_ETH": 36,
    "APE_ETH": 34,
    "TRIM_HALF": 20,
    "HOLD": 17,
    "DOUBLE_DOWN": 12,
    "SWITCH_COIN": 10,
    "WAIT": 10,
    "FLIP_SHORT": 9,
    "BREAKOUT_BTC": 7,
    "BREAKOUT_SOL": 5,
    "CUT_LOSS": 5
  },
  "train_n": 2193,
  "eval_n": 754,
  "paper_multioption_n": 522,
  "files": {
    "market_BTC_15min.json": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/market_BTC_15min_3f23.json",
      "bytes": 464223,
      "rows": 5000
    },
    "market_ETH_15min.json": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/market_ETH_15min_fbd5.json",
      "bytes": 462340,
      "rows": 5000
    },
    "market_SOL_15min.json": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/market_SOL_15min_8cf9.json",
      "bytes": 421516,
      "rows": 5000
    },
    "trading_paper_decisions.jsonl": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/trading_paper_decisions_92e3.jsonl",
      "bytes": 1222395,
      "rows": 1581
    },
    "trading_paper_ledger.json": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/trading_paper_ledger_388d.json",
      "bytes": 134854,
      "rows": null
    },
    "trading_strategy_edges.jsonl": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/trading_strategy_edges_017b.jsonl",
      "bytes": 54265,
      "rows": 139
    },
    "tokenizer.json": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/jevh_student_tokenizer_94c1.json",
      "bytes": 3583228,
      "rows": null
    },
    "labels.jsonl": {
      "path": "/home/ubuntu/.cursor/projects/workspace/uploads/labels_ebb6.jsonl",
      "bytes": 2671732,
      "rows": 4220
    }
  }
}
```

## Recipe

```json
{
  "model": "PairScorer tiny BERT-like (absolute pos, GELU, mask-additive attention)",
  "d_model": 96,
  "n_layers": 4,
  "n_heads": 4,
  "seq_len": 128,
  "epochs": 4,
  "lr": 0.0003,
  "batch_questions": 6,
  "horizon_bars": 32,
  "purge_bars": 96,
  "warmup_bars": 1600,
  "stride_bars": 6,
  "fee_bps_per_side": 5.0,
  "n_params": 5156353,
  "tokenizer": "tools/orchestration/jevh_trading/assets/tokenizer.json"
}
```

## Metrics

| split | n | accuracy | confident mistakes (p>=0.65) | ECE | always HOLD/RIDE acc | beats baseline |
|---|---:|---:|---:|---:|---:|---|
| held-out time (outcome gold) | 754 | 0.4218 | 10 | 0.0637 | 0.3939 | True |
| paper Jev agreement | 522 | 0.0019 | 0 | 0.3715 | 0.9962 | False |
| train subset | 400 | 0.5075 | 8 | 0.0567 | 0.4375 | True |

Held-out chance (mean 1/K over menus) is 0.324. The student beats both chance and always-HOLD/RIDE on the time split.

CPU latency batch-1 (PyTorch): mean **1.68 ms** (p50 1.68, p95 1.75).

Paper Jev agreement is near zero because gold in training is forward outcome, not Jev's choice, and the 1.5h paper log is ~all HOLD_WINNER/RIDE.

## ONNX (Hailo-10H DFC input, not compiled)

- path: `tools/orchestration/jevh_trading/artifacts/jevh_trading_seq128.onnx`
- sha256: `80cb1a8be6e0e9a002cd4417f0dc33ba929ba29ac96d89f0764c56021ed9312f`
- opset: 17
- inputs: `{'input_ids': [1, 128], 'attention_mask': [1, 128]}`
- outputs: `{'logit': [1, 1]}`
- PyTorch parity cos: **1.000000** (max abs 3.576e-07)
- calib: 256 rows of input_ids + attention_mask `[256, 128]`

## Known gaps

- OHLCV only for BTC/ETH/SOL: no funding, OI, news, spread, or the rest of boozy's universe (STRK, DOGE, ...).
- Paper decisions are too thin to train on (1051 single-option RIDE); used as eval-only Jev-agreement. Agreement is near zero because gold is forward outcome, not Jev imitation.
- fund_z is always missing in replayed state (null in the live snapshot schema).
- Student is a tiny from-scratch encoder (not ettin-68m). Same tokenizer and pair format; new HEF would be required.
- No HEF compile, no Pi deploy, no exchange/broker calls.
- Labels are 8h risk-adjusted forward returns with 5 bp/side fees and ATR/day-open stops — a research proxy, not a traded P&L.
- Donchian 360-bar lookback exceeds ~52d of 4h history; slicesAvailable < 9 in this window.
