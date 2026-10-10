# JEV-H-trading receipt (round 3: real Jev-1.13 calls)

> **Not financial advice.** Offline research only. No live or paper order routing. No exchange or broker calls. Gold is typesafe/jev-1.13's own choice, not a traded P&L.

Seed `42`. Wall 8912.4s. Size **68m**. Backbone loaded: True. Smoke=False.

## This is not a stand-in

This does NOT meet the >=14 days / multiple-regimes bar. live_engine is ~13h of one paper session; hyperspeed is 30 minutes / 30 snapshots of one market regime. Scores mean: mimics Jev in this regime, not a stand-in.

- Calendar days: **2** (need 14). Span **12.725 h**. `enough_to_claim`: **False**.
- Unique state+menu: **105005** (raw 106258)
- Multi-option usable: **102306** (hyperspeed train pool 59160 / time-dev 8533 / time-eval 14938; live holdout 2336; unseen-rules 14515; purge 3278)
- Non-hold gold: **56131**. Varied (non-hold-wall): **66980**.
- Sources: `{"hyperspeed": 99970, "live_engine": 2336}`
- Held-out rules_id: `['breezy-cautious', 'boozy-diamond', 'bizzy-alts']`
- Time-eval snapshots (last ~6): `['2026-10-09T12:04:29.935Z', '2026-10-09T12:05:29.934Z', '2026-10-09T12:06:29.935Z', '2026-10-09T12:07:29.937Z', '2026-10-09T12:08:29.959Z', '2026-10-09T12:09:29.958Z']`
- Single-option format-check only: **2688**

## Agreement with Jev (gold = choice)

| split | scored/pool | agree | always HOLD | majority-per-style | conf-mist ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|---:|
| time-eval (last 6 hyperspeed snapshots, seen rules) | 6000/14938 | 0.7982 | 0.4930 | 0.4930 | 636 | 0.0421 |
| unseen rules_id | 6000/14515 | 0.6657 | 0.6182 | 0.6182 | 1364 | 0.1753 |
| live_engine (entire slice) | 2336/2336 | 0.8253 | 0.9927 | 0.9927 | 0 | 0.2250 |
| time-dev (T fit) | 2000/8533 | 0.8460 | 0.4875 | 0.4875 | 195 | 0.0332 |
| train subset | 400/59160 | 0.8650 | 0.4575 | 0.4575 | 24 | 0.0774 |

Majority-per-style equals always-HOLD here because the train majority gold per style is a hold-class action (`RIDE` / `HOLD_WINNER` / `HOLD`). Time-eval **beats** HOLD (student learned hyperspeed diversity). live_engine **loses** to HOLD-copy: that slice is ~99% HOLD_WINNER/RIDE, while the student was trained on hyperspeed menus where always-HOLD is ~44%.

### Time-eval by menu size / gold / style

```json
{
  "by_menu_size": {
    "2": {
      "n": 2327,
      "accuracy": 0.8852599914052428
    },
    "3": {
      "n": 1062,
      "accuracy": 0.8305084745762712
    },
    "4": {
      "n": 1061,
      "accuracy": 0.7492931196983977
    },
    "5": {
      "n": 1550,
      "accuracy": 0.6787096774193548
    }
  },
  "by_gold_label": {
    "HOLD_WINNER": {
      "n": 793,
      "accuracy": 0.9470365699873896
    },
    "SHORT_BTC": {
      "n": 530,
      "accuracy": 0.7811320754716982
    },
    "SHORT_ETH": {
      "n": 530,
      "accuracy": 0.8547169811320755
    },
    "RIDE": {
      "n": 422,
      "accuracy": 0.7298578199052133
    },
    "APE_NEAR": {
      "n": 283,
      "accuracy": 0.43462897526501765
    },
    "APE_BTC": {
      "n": 281,
      "accuracy": 0.7330960854092526
    },
    "APE_TIA": {
      "n": 277,
      "accuracy": 0.9530685920577617
    },
    "APE_ONDO": {
      "n": 275,
      "accuracy": 0.5745454545454546
    },
    "APE_DOGE": {
      "n": 272,
      "accuracy": 0.7794117647058824
    },
    "WAIT": {
      "n": 265,
      "accuracy": 0.9811320754716981
    },
    "BREAKOUT_BTC": {
      "n": 265,
      "accuracy": 1.0
    },
    "CUT_LOSS": {
      "n": 265,
      "accuracy": 0.9584905660377359
    },
    "HOLD": {
      "n": 265,
      "accuracy": 0.5320754716981132
    },
    "BAIL": {
      "n": 201,
      "accuracy": 0.945273631840796
    },
    "SWITCH_COIN": {
      "n": 185,
      "accuracy": 1.0
    },
    "APE_PUMP": {
      "n": 148,
      "accuracy": 0.9391891891891891
    },
    "APE_PEPE": {
      "n": 123,
      "accuracy": 0.7886178861788617
    },
    "LONG_BTC": {
      "n": 119,
      "accuracy": 0.2605042016806723
    },
    "APE_HYPE": {
      "n": 64,
      "accuracy": 0.765625
    },
    "APE_ZEC": {
      "n": 51,
      "accuracy": 0.8627450980392157
    },
    "APE_LIT": {
      "n": 42,
      "accuracy": 0.47619047619047616
    },
    "APE_SOL": {
      "n": 32,
      "accuracy": 0.71875
    },
    "APE_XRP": {
      "n": 32,
      "accuracy": 0.34375
    },
    "TRIM_HALF": {
      "n": 28,
      "accuracy": 1.0
    },
    "APE_ENA": {
      "n": 28,
      "accuracy": 0.32142857142857145
    },
    "APE_INJ": {
      "n": 23,
      "accuracy": 0.7391304347826086
    },
    "APE_AVAX": {
      "n": 21,
      "accuracy": 0.8095238095238095
    },
    "APE_GRAM": {
      "n": 19,
      "accuracy": 0.7368421052631579
    },
    "APE_ADA": {
      "n": 18,
      "accuracy": 0.5555555555555556
    },
    "APE_LTC": {
      "n": 15,
      "accuracy": 0.6666666666666666
    },
    "APE_RENDER": {
      "n": 14,
      "accuracy": 0.7857142857142857
    },
    "APE_FET": {
      "n": 13,
      "accuracy": 0.9230769230769231
    },
    "APE_ETH": {
      "n": 12,
      "accuracy": 0.5833333333333334
    },
    "APE_LINK": {
      "n": 11,
      "accuracy": 0.5454545454545454
    },
    "APE_VIRTUAL": {
      "n": 10,
      "accuracy": 0.6
    },
    "APE_HBAR": {
      "n": 10,
      "accuracy": 0.5
    },
    "APE_BNB": {
      "n": 9,
      "accuracy": 0.6666666666666666
    },
    "APE_SUI": {
      "n": 9,
      "accuracy": 0.8888888888888888
    },
    "APE_WLD": {
      "n": 7,
      "accuracy": 0.7142857142857143
    },
    "APE_TAO": {
      "n": 6,
      "accuracy": 0.8333333333333334
    },
    "DOUBLE_DOWN": {
      "n": 6,
      "accuracy": 0.3333333333333333
    },
    "APE_ARB": {
      "n": 4,
      "accuracy": 1.0
    },
    "APE_PENGU": {
      "n": 4,
      "accuracy": 0.5
    },
    "APE_BCH": {
      "n": 4,
      "accuracy": 0.25
    },
    "APE_XPL": {
      "n": 4,
      "accuracy": 0.75
    },
    "APE_TRUMP": {
      "n": 3,
      "accuracy": 0.3333333333333333
    },
    "APE_VVV": {
      "n": 1,
      "accuracy": 1.0
    },
    "APE_XLM": {
      "n": 1,
      "accuracy": 1.0
    }
  },
  "by_style": {
    "boozy": {
      "n": 2940,
      "accuracy": 0.745578231292517
    },
    "breezy": {
      "n": 2000,
      "accuracy": 0.8385
    },
    "bizzy": {
      "n": 1060,
      "accuracy": 0.8679245283018868
    }
  },
  "by_source": {
    "hyperspeed": {
      "n": 6000,
      "accuracy": 0.7981666666666667
    }
  }
}
```

### Unseen-rules by style / gold

```json
{
  "by_style": {
    "breezy": {
      "n": 2665,
      "accuracy": 0.5737335834896811
    },
    "boozy": {
      "n": 2124,
      "accuracy": 0.8752354048964218
    },
    "bizzy": {
      "n": 1211,
      "accuracy": 0.500412881915772
    }
  },
  "by_gold_label": {
    "HOLD_WINNER": {
      "n": 806,
      "accuracy": 1.0
    },
    "RIDE": {
      "n": 685,
      "accuracy": 1.0
    },
    "SHORT_ETH": {
      "n": 606,
      "accuracy": 0.7541254125412541
    },
    "CUT_LOSS": {
      "n": 606,
      "accuracy": 1.0
    },
    "APE_TIA": {
      "n": 605,
      "accuracy": 1.0
    },
    "HOLD": {
      "n": 605,
      "accuracy": 0.0
    },
    "LONG_BTC": {
      "n": 605,
      "accuracy": 0.16033057851239668
    },
    "TRIM_HALF": {
      "n": 473,
      "accuracy": 0.0
    },
    "APE_STRK": {
      "n": 241,
      "accuracy": 1.0
    },
    "APE_NEAR": {
      "n": 217,
      "accuracy": 0.11059907834101383
    },
    "SHORT_BTC": {
      "n": 169,
      "accuracy": 1.0
    },
    "APE_PUMP": {
      "n": 154,
      "accuracy": 0.8506493506493507
    },
    "SWITCH_COIN": {
      "n": 149,
      "accuracy": 1.0
    },
    "APE_ONDO": {
      "n": 21,
      "accuracy": 0.0
    },
    "DOUBLE_DOWN": {
      "n": 20,
      "accuracy": 0.0
    },
    "APE_JUP": {
      "n": 18,
      "accuracy": 1.0
    },
    "SWITCH": {
      "n": 6,
      "accuracy": 0.0
    },
    "APE_GRAM": {
      "n": 6,
      "accuracy": 1.0
    },
    "APE_LIT": {
      "n": 5,
      "accuracy": 0.0
    },
    "APE_BTC": {
      "n": 3,
      "accuracy": 0.0
    }
  }
}
```

### live_engine by style / gold

```json
{
  "by_style": {
    "boozy": {
      "n": 1247,
      "accuracy": 0.6728147554129912
    },
    "breezy": {
      "n": 1089,
      "accuracy": 1.0
    }
  },
  "by_gold_label": {
    "RIDE": {
      "n": 1229,
      "accuracy": 0.6769731489015459
    },
    "HOLD_WINNER": {
      "n": 1087,
      "accuracy": 1.0
    },
    "DOUBLE_DOWN": {
      "n": 15,
      "accuracy": 0.26666666666666666
    },
    "APE_DOGE": {
      "n": 2,
      "accuracy": 1.0
    },
    "APE_STRK": {
      "n": 1,
      "accuracy": 1.0
    },
    "SHORT_BTC": {
      "n": 1,
      "accuracy": 1.0
    },
    "SHORT_ETH": {
      "n": 1,
      "accuracy": 1.0
    }
  }
}
```

## Recipe

```json
{
  "gold": "jev_choice",
  "soft_targets": "probabilities (KL) + listwise CE + pairwise hinge",
  "option_shuffle": true,
  "size": "68m",
  "hf_id": "jhu-clsp/ettin-encoder-68m",
  "hidden": 512,
  "n_layers": 19,
  "n_heads": 8,
  "seq_len": 128,
  "unfreeze_last": 12,
  "lr_encoder": 2e-05,
  "lr_head": 8e-05,
  "lr_embed": 5e-06,
  "layer_decay": 0.9,
  "pair_coef": 0.4,
  "pair_margin": 0.5,
  "soft_kl_coef": 0.5,
  "kd_temp": 2.0,
  "temperature_nll": 1.0,
  "temperature_ece": 1.1,
  "temperature_note": "Eval uses temperature_ece. Scalar T does not change argmax agreement. kd_temp softens teacher probs in the KL term.",
  "layer_lrs": [
    {
      "layer": 7,
      "lr": 6.28e-06
    },
    {
      "layer": 8,
      "lr": 6.97e-06
    },
    {
      "layer": 9,
      "lr": 7.75e-06
    },
    {
      "layer": 10,
      "lr": 8.61e-06
    },
    {
      "layer": 11,
      "lr": 9.57e-06
    },
    {
      "layer": 12,
      "lr": 1.063e-05
    },
    {
      "layer": 13,
      "lr": 1.181e-05
    },
    {
      "layer": 14,
      "lr": 1.312e-05
    },
    {
      "layer": 15,
      "lr": 1.458e-05
    },
    {
      "layer": 16,
      "lr": 1.62e-05
    },
    {
      "layer": 17,
      "lr": 1.8e-05
    },
    {
      "layer": 18,
      "lr": 2e-05
    }
  ],
  "epochs_run": 3,
  "epochs_requested": 4,
  "microbatch": 4,
  "temperature": 1.1,
  "n_params": 68407809,
  "n_trainable": 27014657,
  "backbone_loaded": true,
  "missing_keys": [],
  "keep_option_rows": 14223,
  "tokenizer": "/workspace/tools/orchestration/jevh_trading/assets/tokenizer.json",
  "train_minutes": 121.26,
  "source_recipe": "cursor/jevh-variant-68m-v5-f666 (read, not merged)",
  "n_train_scored": 8000,
  "n_train_pool": 59160,
  "n_dev_scored": 2000,
  "n_dev_pool": 8533,
  "grad_ckpt": true,
  "train_majority_by_style": {
    "boozy": "RIDE",
    "breezy": "HOLD_WINNER",
    "bizzy": "HOLD"
  },
  "text_a": "[choice] {style_tag} {rules_id} + owner rules prefix (head+tail) + me + up to 4 menu/position coins",
  "option_text": "label plus menu_detail kind/coin/side/desc when present"
}
```

CPU latency batch-1 (PyTorch, one option): mean **37.24 ms** (p50 36.87, p95 39.08).

## ONNX (Hailo-10H DFC input, not compiled)

- path: `/workspace/tools/orchestration/jevh_trading/artifacts/jevh_trading_ettin68m_seq128.onnx`
- sha256: `fc126061dc8b1ab4c906339963eb14c9b04185d184be4e1b65a23286262f9a3a`
- opset: 17
- inputs: `{'input_ids': [1, 128], 'attention_mask': [1, 128]}`
- outputs: `{'logit': [1, 1]}`
- attention_mask used: True
- PyTorch/ORT cos: **0.9999999999991102** (max abs 1.2874603271484375e-05)
- calib: 256 unique tokenized pairs `[256, 128]`

## Outcome aux (not gold)

{
  "n_mapped": 0,
  "paper_span_hours": 0.492,
  "horizon_hours": 8,
  "note": "Forward-outcome labels are an optional auxiliary/eval signal, not gold. This log spans ~0.5h of decisions; an 8h forward window is not available for almost every row. Do not treat outcome-argmax as a Jev stand-in."
}

## Known gaps

- Gold is Jev's logged choice + probabilities, never status/action. Not financial advice.
- This does NOT meet the >=14 days / multiple-regimes bar. live_engine is ~13h of one paper session; hyperspeed is 30 minutes / 30 snapshots of one market regime. Scores mean: mimics Jev in this regime, not a stand-in.
- Calendar days 2 (need 14); span 12.725 h.
- Non-hold gold: 56131. Varied: 66980.
- live_engine is held out of train when v2 hyperspeed is present.
- Held-out rules_id: ['breezy-cautious', 'boozy-diamond', 'bizzy-alts']. Time-eval snapshots: ['2026-10-09T12:04:29.935Z', '2026-10-09T12:05:29.934Z', '2026-10-09T12:06:29.935Z', '2026-10-09T12:07:29.937Z', '2026-10-09T12:08:29.959Z', '2026-10-09T12:09:29.958Z'].
- CPU 68m train cap: scored 8000 of pool 59160 (stratified).
- Backbone 68m (jhu-clsp/ettin-encoder-68m); 68m-v5 recipe (not merged). last-N unfreeze=12.
- No HEF compile, no Pi deploy, no exchange/broker/trading API calls, no paid APIs.
- Beebots engine is not modified; see BEEBOTS_LOG_SPEC.md.
- seq128 keep_option: 14223 encoded rows overflowed; option kept, state trimmed.
