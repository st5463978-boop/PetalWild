# JEV-H-trading (round 3: real Jev-1.13 calls)

Local student that **mimics** `typesafe/jev-1.13` on beebots paper-mode menus, so the bees can later run cost-free on a Pi. Gold is **Jev's own `choice`** plus its `probabilities` as soft targets. Forward-outcome labels are optional eval only.

**Not financial advice.** Offline research only. This package does not connect to any exchange or broker, does not place or cancel orders, and does not touch the live beebots engine. No HEF compile. No Pi / device deploy. No paid APIs.

This run does **not** meet the ≥14 days / multiple-regimes bar. All of it is one ~13 h window (8–9 Oct 2026 UTC). The varied part is **30 minutes / 30 snapshots of one market regime**. Scores mean “mimics Jev in this regime”, not a cost-free stand-in.

**Getting to 90%:** [`PATH_TO_90.md`](PATH_TO_90.md) measures what caps agreement today (Jev's own re-query noise, input packing and truncation, training mix, data diversity, model size), proposes the recipe most likely to reach 90%, and defines the shadow-mode gate for a Hailo-10H that routes low-confidence calls to Jev, with results for the current checkpoint and ONNX.

## One command

Needs `python3-venv` (Ubuntu: `sudo apt install python3.12-venv`). From this directory:

```bash
./train.sh --size 68m
```

That ingests `trading_jev_calls_v2.jsonl.gz` (joined to `trading_jev_contexts_v2.jsonl` on `context_id` for strategy + rules), dedupes, drops single-option menus from training, splits by hyperspeed `market_ts` + held-out `rules_id` + entire `live_engine`, retrains ettin **68m** (17m only if you pass `--size 17m` or the corpus is tiny), and prints agreement-with-Jev. The defaults are the r2 recipe below.

```bash
./train.sh --size auto          # 17m if n_train < 1500, else 68m (default)
./train.sh --size 17m
./train.sh --size 68m
./train.sh --log /path/to/more.jsonl
./train.sh --ingest-only        # counts only
./train.sh --smoke
./train.sh --size 68m --epochs 1 --packer option --artifacts /tmp/ab --skip-export   # A/B run; leaves artifacts/ alone
```

Analysis (from `tools/orchestration`, after `train.sh` has built the venv; the yardstick also needs `jevh_trading/.venv/bin/pip install lightgbm==4.6.0`):

```bash
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.jev_ceiling           # Jev's own noise ceiling, margins, what the packer keeps
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.structured_baseline   # LightGBM yardstick on the parsed state
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.shadow_gate           # coverage vs agreement at confidence thresholds, ONNX parity
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

`text_a` is `[choice] {style_tag} {rules_id}`, then the strategy/rules text clipped to 180 characters (head + tail), then the compact state: the `me` position line and up to 4 menu/position coins. Rules go first so seq128 `keep_option` trims state, never rules. Each menu label is `text_b`, with `menu_detail` kind/coin/side so generic `SWITCH` is not ambiguous. One logit / option, softmax over the menu. `--packer option` (opt-in, for A/B runs) instead gives each option its own coin's full row with the coin's rank among the menu's coins, and puts the whole coin table in `text_a`, so truncation can no longer cut the gold option's numbers. At 128 tokens it scored below v1 because it pushes the rules text and the coin table out of the window ([`PATH_TO_90.md`](PATH_TO_90.md), section 5).

Encoder recipe is the 68m-v5 one (`jhu-clsp/ettin-encoder-68m`, listwise CE, pairwise hinge, option shuffle, temperature fit) copied in spirit from `cursor/jevh-variant-68m-v5-f666` / PR #31 — **not merged** — with the last 12 of 19 layers unfrozen under layer-wise LR decay 0.9 and KD temperature 2. 17m (`jhu-clsp/ettin-encoder-17m`) is the CPU / thin-data fallback.

## How much data is enough

A stand-in for discretionary Jev is **not** “copy HOLD_WINNER on a 90-minute log”. Rough bar:

- ~**2000** unique *varied* multi-option decisions
- ~**400** non-hold golds
- ≥**50** golds per action you care about
- ≥**14** calendar days, more than one regime

This v2 dump clears the count bars (66,980 varied / 56,131 non-hold) and **fails the days/regimes bar** (2 calendar days, one 30-minute hyperspeed regime). `enough_to_claim=false`. [`PATH_TO_90.md`](PATH_TO_90.md) shows that distinct market states and rules texts, not more rows of the same states, are what agreement is short of.

What the bees should keep appending: [`BEEBOTS_LOG_SPEC.md`](BEEBOTS_LOG_SPEC.md). Engine code is not edited here.

## Metrics (seed 42, ettin-68m, Jev-1.13 v2 dump)

**Not financial advice.** Gold = Jev `choice`. This is **not** a Jev stand-in. r2, on CPU: a gold-balanced 8,000 of 59,160 eligible train rows, last 12 layers with layer-wise LR decay, rules before state, best of 3 epochs = epoch 1 (dev 0.846, 0.834, 0.832). T=1.1. Scored on stratified receipt samples that weight each (style, gold, menu size) bucket equally.

| split | scored/pool | agree-with-Jev | always HOLD | majority-per-style | conf-mist ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|---:|
| time-eval (last 6 hyperspeed snapshots, seen rules) | 6000/14938 | **0.798** | 0.493 | 0.493 | 636 | 0.042 |
| unseen `rules_id` | 6000/14515 | **0.666** | 0.618 | 0.618 | 1364 | 0.175 |
| entire `live_engine` | 2336/2336 | 0.825 | **0.993** | 0.993 | 0 | 0.225 |
| time-dev (T fit) | 2000/8533 | 0.846 | 0.488 | 0.488 | 195 | 0.033 |

Majority-per-style equals always-HOLD: train majority gold is `RIDE` (boozy) / `HOLD_WINNER` (breezy) / `HOLD` (bizzy). Time-eval **beats** HOLD. live_engine **loses** to HOLD-copy because that slice is 99% HOLD_WINNER/RIDE (20 non-hold golds in the whole live log) while the student learned hyperspeed diversity from balanced rows.

Time-eval by menu size: 2→0.885, 3→0.831, 4→0.749, 5→0.679. By style: bizzy 0.868, breezy 0.839, boozy 0.746. Unseen-rules by style: boozy 0.875, breezy 0.574, bizzy 0.500 (HOLD gold n=605 and TRIM_HALF gold n=473 both 0.0). live_engine by style: breezy 1.000, boozy 0.673.

Headline time-eval golds (n≥200): BREAKOUT_BTC 1.000, WAIT 0.981, CUT_LOSS 0.958, APE_TIA 0.953, HOLD_WINNER 0.947, BAIL 0.945, SHORT_ETH 0.855, SHORT_BTC 0.781, APE_DOGE 0.779, APE_BTC 0.733, RIDE 0.730, APE_ONDO 0.575, HOLD 0.532, APE_NEAR 0.435.

Other runs on the same receipt rows (time-eval / unseen rules / live / dev): r1 (last 6 layers, state before rules, best epoch 3) 0.752 / 0.757 / 0.870 / 0.812; Kaggle s2 (T4, all layers, 256 tokens, all train rows in their natural mix, 1 epoch; checkpoint not in this workspace) 0.763 / 0.676 / 0.993 / 0.798.

On every natural call rather than the balanced sample, r2 agrees 0.800 on time-eval (top-2 0.961) and a 96% confidence threshold fit on dev answers 55% of time-eval calls at 95.0% realized agreement. A LightGBM on the parsed state reaches 0.876. See [`PATH_TO_90.md`](PATH_TO_90.md).

CPU latency batch-1: **37.2 ms** per pair in PyTorch (p50 36.9, p95 39.1), 34.2 ms as fp32 ONNX. Full tables: `RECEIPT.md`.

## Hailo export

`artifacts/jevh_trading_ettin{17m|68m}_seq128.onnx` (gitignored; rebuild locally)

- Fully static: batch 1, seq 128
- Inputs: `input_ids` [1,128] int64, `attention_mask` [1,128] int64 (mask is **used**)
- Output: `logit` [1,1]
- opset 17, no Loop / If / NonZero
- Calib: ≥256 unique real tokenized pairs
- ORT vs PyTorch cos ≥ 0.999 (r2: 1.000, max abs 1.3e-5; 300 of 300 time-eval decisions match)
- This 68m sha256: `fc126061dc8b1ab4c906339963eb14c9b04185d184be4e1b65a23286262f9a3a`

ORT dynamic int8 changes 19% of decisions (244 of 300 match). Check the Hailo-quantized model against fp32 decisions (≥99%) before any shadow run.

## Layout

```
jevh_trading/
  train.sh                 one command (distill)
  BEEBOTS_LOG_SPEC.md      log fields for the bees
  PATH_TO_90.md            what caps agreement, recipe for 90%, shadow-mode gate
  ingest.py                growing jsonl → snapshot + rules + live splits, v1 / option packers
  ettin.py                 68m + 17m static scorer
  train.py                 distill / eval / ONNX
  jev_ceiling.py           Jev's own noise ceiling and representation stats
  structured_baseline.py   LightGBM yardstick, ablations, snapshot curve
  shadow_gate.py           coverage vs agreement at thresholds, ONNX fp32/int8 parity
  train_outcome.py         round-1 outcome trainer (kept)
  artifacts/               metrics, receipt, analysis JSON, onnx, hf weights
  assets/tokenizer.json    live ettin tokenizer
```
