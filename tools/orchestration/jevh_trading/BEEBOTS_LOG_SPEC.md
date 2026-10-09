# Beebots decision log spec (Jev distill)

**Not financial advice. Do not change the beebots engine in this PR.** This is only the record the student needs so a later Pi build can copy `typesafe/jev-1.13` offline.

Append-only JSONL, one object per Jev call. Same schema as `trading_paper_decisions.jsonl`. The trainer (`./train.sh`) discovers that file (or `--log path.jsonl`), dedupes on `(bee, menu, state)`, drops 1-option menus from **training** (keeps them for format checks), and time-splits with a purge gap.

## Required per decision

| field | type | why |
|---|---|---|
| `ts_ms` | int | Unix ms. Time split + purge. Do not reuse timestamps out of order. |
| `bee` | string | e.g. `bee1`. Dedup key. |
| `state` | object | **Exactly the state Jev saw.** Keep `me` (pos, usd, upl_r, held_min, trades, fee_left, …) and `coins.cols` + `coins.rows`. Extra keys (`utc`, `attn`, `top1`) are packed into text. |
| `menu` | string[] | Options in the order Jev scored them. ≥2 for training. Labels only (`HOLD_WINNER`, `APE_STRK`, …), not post-hoc fills. |
| `choice` | string | **Gold.** Jev's argmax, must be a member of `menu`. Not the engine's executed action. |
| `probabilities` | object | **Soft targets.** Map every menu label → probability. Trainer renormalizes. |

## Strongly recommended

| field | type | why |
|---|---|---|
| `confidence` | float | Jev's reported p(choice). Used in ECE / confident-mistake eval. |
| `conviction` | float | Logged as metadata; not gold. |
| `jev_error` | null or string | Non-null rows are dropped from training. |
| `id` | int or string | Stable row id; later write wins on the same state hash. |
| `teacher` | string | e.g. `typesafe/jev-1.13` so mixed-teacher logs can be filtered later. |

## Execution metadata (not gold)

Keep these if the engine already logs them. Distill **ignores** them for the label. They are useful later to measure “Jev said X, engine did Y”.

- `action` — `{kind, instId, side, notionalUsd, …}` or `{kind:"none"}`
- `vetoed_by` — string or null
- `forced_by` — string or null
- `status` — executed or skipped label
- `latency_ms` — teacher latency, not a training target

Do **not** substitute `status` or `action.kind` for `choice`. If `forced_by=max_flat` and Jev picked `SHORT_BTC`, gold is still `SHORT_BTC`.

## What to log more of (this is the bottleneck)

Single-option `["RIDE"]` ticks are cheap format checks and **do not count** toward a stand-in. Collapsed 10-second `HOLD_WINNER` / `LONG_BTC` / `SWITCH` repeats after a position is on are near-duplicates; we keep the latest state hash only.

Roughly enough to *claim* a cost-free Jev stand-in (not a traded edge):

- **~2000** unique multi-option decisions whose menu is not the hold-wall (or whose gold is not HOLD/RIDE/WAIT)
- **~400** of those with a non-hold gold (`APE_*`, `SWITCH`, `LONG_*`, `SHORT_*`, `BREAKOUT_*`, `CUT_LOSS`, …)
- **≥50** golds per offered action that you actually care about mimicking
- **≥14 calendar days**, more than one regime

Until then the pipeline still runs, but a high agreement-with-Jev number is mostly “copy HOLD_WINNER”.

## Example (valid)

```json
{
  "id": 1,
  "ts_ms": 1791503162029,
  "bee": "bee2",
  "teacher": "typesafe/jev-1.13",
  "state": {
    "utc": "23:46",
    "me": {"pos": "flat", "flat_min": 0, "trades": "0/3", "fee_left": 3},
    "coins": {
      "cols": ["r1h_pct", "r24h_pct", "r7d_pct", "attn_z", "oi1h_pct", "spread_bp", "vol_musd"],
      "rows": {"STRK": [-1.2, 13, 33, 0.4, null, 9, 2.9], "BTC": [-0.2, -2, -4, -0.5, null, 0, 423.9]}
    },
    "attn": "volume_z",
    "top1": "STRK x1"
  },
  "menu": ["APE_STRK", "APE_ONDO", "APE_BTC"],
  "choice": "APE_STRK",
  "probabilities": {"APE_STRK": 0.72, "APE_ONDO": 0.19, "APE_BTC": 0.09},
  "confidence": 0.72,
  "conviction": 0.77,
  "jev_error": null,
  "action": {"kind": "open", "instId": "STRK-USD_UM_XPERP-310919", "side": "long", "notionalUsd": 42.68},
  "vetoed_by": null,
  "forced_by": null,
  "status": "APE_STRK"
}
```

Optional later (not required for distill): a follow-up fill / mark so `--aux-outcome` can score 8h forward return. Do not block logging on that.

No exchange payloads, no secrets, no API keys in this file.
