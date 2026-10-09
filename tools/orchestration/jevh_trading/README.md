# JEV-H-trading

Tiny JEV-H student for **agentic trading menu decisions** of the kind the paper-mode beebots make: pick one move from a compact state + menu.

**Not financial advice.** Offline research / backtest only. This package does not connect to any exchange or broker, does not place, simulate-submit, or cancel orders, and does not touch the live beebots engine. No HEF compile. No Pi / device deploy.

## One command

From this directory (pinned deps, seed 42):

```bash
./train.sh
```

Smoke (CI / budget):

```bash
./train.sh --smoke
```

Tests (indicators + split + optional ONNX, no market download):

```bash
PYTHONPATH=.. python3 -m unittest jevh_trading.test_jevh_trading
```

## What it trains on

Paper decisions (`trading_paper_decisions.jsonl`, 1581 rows) are **eval-only**. 1051 of them are a single-option `["RIDE"]` menu; most of the rest are `HOLD_WINNER`. That is not enough to train.

Training labels are rebuilt from the real 15-minute OHLCV bars (BTC, ETH, SOL; 5000 bars each, ~52 days) using the indicator / menu logic in `uploads/trading_beebots_reference.md`:

1. RSI(14), ATR(14), Bollinger %B, 1h/24h/7d returns, volume z, Larry Williams day-open breakout, 4h Donchian ensemble (breezy).
2. Menus each bee style would actually offer (flat entries + positioned management).
3. Each option is scored by **risk-adjusted forward return** over 32 bars (8h): fees 5 bp/side (from the paper fills), stop on subsequent highs/lows.
4. Gold = argmax of those outcomes.
5. **Time split** with a 96-bar (1 day) purge gap. No overlapping train/eval indices.

Text format matches live JEV-H: `text_a = "[choice] {strategy} Pick your next move.\\n{compact state}"`, each option as `text_b` (`HOLD_WINNER: keep short BTC`, …). One logit per option, softmax over the menu.

The student is a **tiny from-scratch encoder** (seq 128, d=96, 4 layers) using the live ettin tokenizer. It is not ettin-68m; a new HEF would be required later (out of scope).

## Hailo export

`artifacts/jevh_trading_seq128.onnx`

- Fully static: batch 1, seq 128
- Inputs: `input_ids` [1,128] int64, `attention_mask` [1,128] int64
- The mask is **used** (additive attention bias, pad → −1e4)
- Output: `logit` [1,1]
- opset 17, no Loop / If / NonZero
- Calib: `artifacts/calib/calib_input_ids.npy` + `calib_attention_mask.npy` (≥256 real tokenized pairs)

## Metrics

See `RECEIPT.md` (written by `train.sh`). Required scores: accuracy, confident mistakes (wrong at p≥0.65), ECE, CPU latency batch 1. Also always-HOLD/RIDE baseline on menus that contain a hold option.

## Layout

```
jevh_trading/
  train.sh              one command
  requirements.txt      pinned
  config.py             seeds + recipe
  indicators.py         beebots ports
  dataset.py            replay + time split
  encode.py             JEV-H pair tokenizer
  model.py              static pair scorer
  train.py              fit / eval / export
  artifacts/            onnx, calib npy, metrics.json, RECEIPT.md
  assets/tokenizer.json live ettin student tokenizer
  data/sample/          tiny fixtures (full files stay in uploads/)
```

Data path resolution is in `paths.py`. Full files come from the agent uploads listed in `data/README.md`.
