# JEV-H-trading (round 2: Jev distill)

Local student that **mimics** `typesafe/jev-1.13` on beebots paper-mode menus, so the bees can later run cost-free on a Pi. Gold is **Jev's own choice** plus its `probabilities` as soft targets. Forward-outcome labels are optional eval only.

**Not financial advice.** Offline research only. This package does not connect to any exchange or broker, does not place or cancel orders, and does not touch the live beebots engine. No HEF compile. No Pi / device deploy. No paid APIs.

## One command

Needs `python3-venv` (Ubuntu: `sudo apt install python3.12-venv`). From this directory:

```bash
./train.sh
```

That ingests `trading_paper_decisions.jsonl` (or extra `--log` files), dedupes, drops single-option menus from training, time-splits with a purge gap, retrains ettin **17m** (fallback) or **68m**, and prints agreement-with-Jev.

```bash
./train.sh --size auto          # 17m if n_train < 1500, else 68m (default)
./train.sh --size 17m
./train.sh --size 68m
./train.sh --log /path/to/more.jsonl
./train.sh --ingest-only        # counts only
./train.sh --smoke
```

Tests (no market download, no HF):

```bash
PYTHONPATH=.. python3 -m unittest jevh_trading.test_jevh_trading
```

Round-1 outcome trainer (not default): `PYTHONPATH=.. python -m jevh_trading.train_outcome`

## What gold is

| | round 1 | round 2 (this) |
|---|---|---|
| gold | 8h forward outcome on 15m bars | **Jev `choice`** |
| soft | — | **Jev `probabilities`** (KL) |
| train rows | rebuilt menus | multi-option log rows only |
| 1-option `RIDE` | unused | format-check only |

Text format matches live JEV-H: `text_a = "[choice] {strategy} Pick your next move.\n{compact state}"`, each menu label as `text_b`. One logit / option, softmax over the menu. Encoder recipe is the 68m-v5 one (`jhu-clsp/ettin-encoder-68m`, listwise CE, pairwise hinge, option shuffle, temperature fit, last-N unfreeze) copied in spirit from `cursor/jevh-variant-68m-v5-f666` / PR #31 — **not merged**. 17m (`jhu-clsp/ettin-encoder-17m`) is the CPU / thin-data fallback.

## How much data is enough

A stand-in for discretionary Jev is **not** “copy HOLD_WINNER on a 90-minute log”. Rough bar:

- ~**2000** unique *varied* multi-option decisions
- ~**400** non-hold golds
- ≥**50** golds per action you care about
- ≥**14** calendar days

`./train.sh` always prints the current counts and the shortfall. Until `enough_to_claim` is true, treat a high eval agreement as HOLD-copying.

What the bees should keep appending: [`BEEBOTS_LOG_SPEC.md`](BEEBOTS_LOG_SPEC.md). Engine code is not edited here.

## Hailo export

`artifacts/jevh_trading_ettin{17m|68m}_seq128.onnx` (gitignored; rebuild locally)

- Fully static: batch 1, seq 128
- Inputs: `input_ids` [1,128] int64, `attention_mask` [1,128] int64 (mask is **used**)
- Output: `logit` [1,1]
- opset 17, no Loop / If / NonZero
- Calib: ≥256 unique real tokenized pairs
- ORT vs PyTorch cos ≥ 0.999

## Layout

```
jevh_trading/
  train.sh                 one command (distill)
  BEEBOTS_LOG_SPEC.md      log fields for the bees
  ingest.py                growing jsonl → time split
  ettin.py                 68m + 17m static scorer
  train.py                 distill / eval / ONNX
  train_outcome.py         round-1 outcome trainer (kept)
  artifacts/               metrics, receipt, onnx, hf weights
  assets/tokenizer.json    live ettin tokenizer
```
