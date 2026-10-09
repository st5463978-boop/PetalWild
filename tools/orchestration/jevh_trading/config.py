"""Pinned recipe knobs. Change these only with a receipt update."""

from __future__ import annotations

SEED = 42
SEQ_LEN = 128
OPSET = 17
CONFIDENT_MISTAKE_P = 0.65

# Tiny encoder (CPU / Hailo-static). Not ettin-68m; same tokenizer + pair format.
D_MODEL = 96
N_LAYERS = 4
N_HEADS = 4
D_FF = 192
DROPOUT = 0.1
VOCAB_SIZE = 50368  # ettin tokenizer max id 50367

PAD_ID = 50283
CLS_ID = 50281
SEP_ID = 50282
UNK_ID = 50280

# Replay
WARMUP_BARS = 1600  # ~16.7d of 15m; covers 90 x 4h RV and 7d returns
HORIZON_BARS = 32  # 8 hours
PURGE_BARS = 96  # 1 day gap between train and eval
STRIDE_BARS = 6
TRAIN_FRAC = 0.72
FEE_BPS = 5.0  # per side, from paper fills (~5 bp taker)
BARS_PER_4H = 16
DONCHIAN_LOOKBACKS = (5, 10, 20, 30, 60, 90, 150, 250, 360)

# Train (round-1 tiny outcome student)
MAX_TRAIN_EXAMPLES = 4800
MAX_EVAL_EXAMPLES = 1600
HOLD_GOLD_CAP = 0.40  # downsample HOLD/RIDE golds in train only
EPOCHS = 4
LR = 3e-4
WEIGHT_DECAY = 0.01
BATCH_QUESTIONS = 6
GRAD_CLIP = 1.0
LOG_EVERY = 20

# Distill (round 2): gold = Jev choice; probabilities are soft targets.
# Recipe reused from cursor/jevh-variant-68m-v5-f666 (not merged).
DISTILL_SIZE_AUTO_N = 1500  # below this, --size auto picks 17m
PAIR_COEF = 0.4
PAIR_MARGIN = 0.5
SOFT_KL_COEF = 0.50
UNFREEZE_LAST_68M = 6
UNFREEZE_LAST_17M = 4
LR_ENCODER = 2e-5
LR_HEAD = 8e-5
LR_EMBED = 5e-6
LAYER_DECAY = 0.9
MICROBATCH = 8
DISTILL_EPOCHS = 6
DISTILL_PATIENCE = 2
AUTO_17M = True

# Latency
LATENCY_WARMUP = 8
LATENCY_N = 64

COINS = ("BTC", "ETH", "SOL")
BREEZY_COINS = ("BTC", "ETH")
BIZZY_BREAKOUT_COINS = ("BTC", "ETH", "SOL")

BEE_STRATEGY = {
    "breezy": (
        "You are breezy-bee, the calculated one. Trend following on BTC and ETH "
        "with a Donchian ensemble (score -9..+9). Ride winners, trade rarely, stay positioned."
    ),
    "boozy": (
        "You are boozy-bee, the degen. Back the week's hottest coin (7-day momentum) "
        "and ride it. Enter at 1x, add into winners, commit 24h before rotating."
    ),
    "bizzy": (
        "You are bizzy-bee, the grinder. One Larry Williams volatility breakout a day: "
        "UTC open plus 0.5 x yesterday's range, long only. Ride to the day close; cut a failed breakout."
    ),
}

# Short tags for seq128 pair encoding (full BEE_STRATEGY ate the token budget).
BEE_TAG = {
    "breezy": "breezy Donchian",
    "boozy": "boozy momentum",
    "bizzy": "bizzy breakout",
}

HOLD_LABELS = frozenset({"HOLD", "RIDE", "HOLD_WINNER", "WAIT"})
