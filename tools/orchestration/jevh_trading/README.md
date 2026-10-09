# JEV-H-trading (round 3: real Jev-1.13 calls)

Local student that **mimics** `typesafe/jev-1.13` on beebots paper-mode menus, so the bees can later run cost-free on a Pi. Gold is **Jev's own `choice`** plus its `probabilities` as soft targets. Forward-outcome labels are optional eval only.

**Not financial advice.** Offline research only. This package does not connect to any exchange or broker, does not place or cancel orders, and does not touch the live beebots engine. No HEF compile. No Pi / device deploy. No paid APIs.

This run does **not** meet the ≥14 days / multiple-regimes bar. All of it is one ~13 h window (8–9 Oct 2026 UTC). The varied part is **30 minutes / 30 snapshots of one market regime**. Scores mean “mimics Jev in this regime”, not a cost-free stand-in.

## One command

Needs `python3-venv` (Ubuntu: `sudo apt install python3.12-venv`). From this directory:

```bash
./train.sh --size 68m
```

That ingests `trading_jev_calls_v2.jsonl.gz` (joined to `trading_jev_contexts_v2.jsonl` on `context_id` for strategy + rules), dedupes, drops single-option menus from training, splits by hyperspeed `market_ts` + held-out `rules_id` + entire `live_engine`, retrains ettin **68m** (17m only if you pass `--size 17m` or the corpus is tiny), and prints agreement-with-Jev.

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

| | round 1 | round 2–3 (this) |
|---|---|---|
| gold | 8h forward outcome on 15m bars | **Jev `choice`** (never `status` / `action`) |
| soft | — | **Jev `probabilities`** (KL) |
| train rows | rebuilt menus | multi-option log rows only |
| 1-option `RIDE` | unused | format-check only |

`text_a` is `[choice] {style_tag} {rules_id}` then compact state, then clipped strategy/rules (state first so seq128 `keep_option` does not trim it). Each menu label is `text_b`, with `menu_detail` kind/coin/side so generic `SWITCH` is not ambiguous. One logit / option, softmax over the menu. Encoder recipe is the 68m-v5 one (`jhu-clsp/ettin-encoder-68m`, listwise CE, pairwise hinge, option shuffle, temperature fit, last-N unfreeze) copied in spirit from `cursor/jevh-variant-68m-v5-f666` / PR #31 — **not merged**. 17m (`jhu-clsp/ettin-encoder-17m`) is the CPU / thin-data fallback.

## How much data is enough

A stand-in for discretionary Jev is **not** “copy HOLD_WINNER on a 90-minute log”. Rough bar:

- ~**2000** unique *varied* multi-option decisions
- ~**400** non-hold golds
- ≥**50** golds per action you care about
- ≥**14** calendar days, more than one regime

This v2 dump clears the count bars (66,980 varied / 56,131 non-hold) and **fails the days/regimes bar** (2 calendar days, one 30-minute hyperspeed regime). `enough_to_claim=false`.

What the bees should keep appending: [`BEEBOTS_LOG_SPEC.md`](BEEBOTS_LOG_SPEC.md). Engine code is not edited here.

## Metrics (seed 42, ettin-68m, Jev-1.13 v2 dump)

**Not financial advice.** Gold = Jev `choice`. This is **not** a Jev stand-in. CPU scored a stratified 8,000 of 59,160 eligible train rows (last-6 unfreeze, 4 epochs, best epoch 3). T=1.2.

| split | scored/pool | agree-with-Jev | always HOLD | majority-per-style | conf-mist ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|---:|
| time-eval (last 6 hyperspeed snapshots, seen rules) | 6000/14938 | **0.752** | 0.493 | 0.493 | 601 | 0.059 |
| unseen `rules_id` | 6000/14515 | **0.757** | 0.618 | 0.618 | 1302 | 0.217 |
| entire `live_engine` | 2336/2336 | 0.870 | **0.993** | 0.993 | 25 | 0.213 |
| time-dev (T fit) | 2000/8533 | 0.812 | 0.488 | 0.488 | 219 | 0.044 |

Majority-per-style equals always-HOLD: train majority gold is `RIDE` (boozy) / `HOLD_WINNER` (breezy) / `HOLD` (bizzy). Time-eval **beats** HOLD. live_engine **loses** to HOLD-copy because that slice is 99% HOLD_WINNER/RIDE (20 non-hold golds in the whole live log) while the student learned hyperspeed diversity.

Time-eval by menu size: 2→0.845, 3→0.832, 4→0.602, 5→0.659. By style: bizzy 0.874, boozy 0.740, breezy 0.705. Unseen-rules by style: bizzy 0.921, boozy 0.864, breezy 0.597 (TRIM_HALF gold n=473 acc=0.0). live_engine by style: breezy 0.999, boozy 0.757.

Headline time-eval golds (n≥200): HOLD_WINNER 0.975, WAIT 0.981, BREAKOUT_BTC 0.992, SWITCH_COIN 0.995, RIDE 0.882, BAIL 0.881, HOLD 0.845, CUT_LOSS 0.675, APE_TIA 0.964, APE_DOGE 0.676, APE_ONDO 0.556, SHORT_BTC 0.464, SHORT_ETH 0.466, APE_NEAR 0.311.

CPU latency batch-1: **41.5 ms** (p50 41.6, p95 44.3). ONNX/ORT cos **1.000** (max abs 1.6e-5). Calib 256 unique pairs. `attention_mask` is a real graph input. Full tables: `RECEIPT.md`.

## Hailo export

`artifacts/jevh_trading_ettin{17m|68m}_seq128.onnx` (gitignored; rebuild locally)

- Fully static: batch 1, seq 128
- Inputs: `input_ids` [1,128] int64, `attention_mask` [1,128] int64 (mask is **used**)
- Output: `logit` [1,1]
- opset 17, no Loop / If / NonZero
- Calib: ≥256 unique real tokenized pairs
- ORT vs PyTorch cos ≥ 0.999
- This 68m sha256: `5031d09557d896679ed3092c5a67877aa076ce65cd4e664ac104ffaf67e1c597`

## Layout

```
jevh_trading/
  train.sh                 one command (distill)
  BEEBOTS_LOG_SPEC.md      log fields for the bees
  ingest.py                growing jsonl → snapshot + rules + live splits
  ettin.py                 68m + 17m static scorer
  train.py                 distill / eval / ONNX
  train_outcome.py         round-1 outcome trainer (kept)
  artifacts/               metrics, receipt, onnx, hf weights
  assets/tokenizer.json    live ettin tokenizer
```
