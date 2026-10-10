# Path to 90%: what limits the local Jev copy and how to raise it

> **Not financial advice.** Offline analysis of logged `typesafe/jev-1.13` calls. No trades, no exchange calls, no paid APIs, no HEF compile, no deploy. The beebots engine is not modified.

The question: how do we get the local Jev copy (an ettin encoder distilled from Jev's beebots menu decisions) from ~76% to at least 90% agreement with Jev on held-out calls, ideally 96%+, so it can run on a Hailo-10H in shadow mode with low-confidence calls routed to real Jev?

Everything below was measured on the v2 dump (106k Jev calls: 100k hyperspeed calls over 30 one-minute snapshots, 2.3k live-engine calls) with the splits `train.py` uses. The JSON artifacts behind each number are listed under [Reproduce](#6-reproduce).

## TL;DR

**96% on every call is not reachable.** Jev's own re-query noise caps blanket top-1 agreement at 97–98% on hyperspeed calls, so 96% would mean matching Jev's probabilities to within about 0.03 per option. 90% on every call is reachable in principle. 96% is the right target for the calls the chip answers itself. The binding constraint is data (20 training snapshots from one 30-minute market window, 13 rules texts), then the training mix and the input packing. Model size and KD temperature are minor.

- **Today (r2 checkpoint, all 14,938 natural time-eval calls):** 80.0% top-1, 96.1% top-2. With a perfect confidence threshold the chip could answer 42–44% of calls at ≥96% agreement. A threshold set on dev answers 55% of calls at 95.0% realized agreement (95% interval 93.1–96.7%). On unseen rules the student is confidently wrong (the same threshold realizes 73%), so those calls must go to Jev. When Jev holds, r2 acts on 20% of calls.
- **A LightGBM on the parsed state is the stronger copy today:** 87.6% top-1 on the same calls, and 75% of calls answerable at ≥96% with a perfect threshold. It runs on the host CPU in microseconds. It is the bar the chip model has to clear, and a useful second opinion in the gate.
- **Jev's noise:** `choice` is the argmax of `probabilities` on 99.95% of calls. The "0.41 average top probability" is the `confidence` field, which tracks the gap between Jev's top two options; the mean top probability is 0.64. Agreement under sampling (64%, or 54% between two samples) does not apply because Jev does not sample. Asking Jev the same prompt again moves each probability by a standard deviation of 0.013 (live, 1,512 pairs, no flips) to 0.022 (hyperspeed, 30 pairs, 1 flip). That caps a perfect copy at 98.2% / 97.1% top-1 and 99.9% top-2 on time-eval.
- **Where r2's gap goes (80.0% natural to the ~97.5% ceiling):** training mix about 3 points, input representation 3 to 4, more rows of the same snapshots about 1, data diversity about 9, model size and KD temperature at most 1 to 2 each, Jev's noise 2 to 3 (section 2.6).
- **Option-centric packing does not help at 128 tokens.** An A/B that moves each option's coin row into its own text (one epoch, same rows) scored 0.765 vs r2's 0.798 on time-eval, because the longer option texts push the rules text and the shared coin table out of the window. On live calls it fell to 0.561 vs 0.825 through a format shortcut (section 5). r2's packer stays.
- **Recipe:** spread the same ~100k Jev calls over 1,000+ snapshots across at least 14 days and several regimes, with 100+ rules texts, and hold out whole days and rules texts. Give the encoder room so neither the rules nor the coin numbers are cut (256 tokens or compact rows), and drop the rules id from half the training rows. Train on the natural mix with a decaying learning rate. Keep the 68m pair cross-encoder next to a host-side LightGBM; try listwise scoring and 150m only after the data step.
- **Gating:** report coverage and realized agreement at 96% and 99% with thresholds fit on dev or recent shadow logs, plus oracle coverage, top-2, tolerant agreement, hold-vs-act and per-style breakdowns. Route unseen rules texts to Jev, use stricter thresholds for picks that act, and audit 5% of chip answers.
- **Quantization:** the fp32 ONNX matches PyTorch on 300 of 300 calls. ORT's dynamic int8 changes 19% of decisions, so the Hailo-quantized model needs a ≥99% decision-agreement check against fp32 before shadow mode.

## 1. Scoreboard on the same rows

Every student run here used seed 42, so all were scored on the same stratified receipt rows: dev 2,000 of 8,533, time-eval 6,000 of 14,938, unseen rules 6,000 of 14,515, and all 2,336 live calls. The receipt sample gives each (style, Jev's choice, menu size) bucket equal weight, so it over-weights rare actions compared with how calls actually arrive.

**Receipt rows (gold-balanced):**

| run | setup | time-eval | unseen rules | live | dev |
|---|---|---:|---:|---:|---:|
| Kaggle s2 | 68m, all layers, 256 tokens, KD T=4, 1 epoch over all 59,160 train rows (natural mix), T4 GPU | 0.763 | 0.676 | 0.993 | 0.798 |
| Kaggle s2 at 128 tokens | same weights, 128-token export | 0.751 | 0.672 | | |
| CPU r1 | last 6 layers, state before rules, 128 tokens, 8,000 balanced rows, best of 4 epochs | 0.752 | 0.757 | 0.870 | 0.812 |
| CPU r2 (gated below) | last 12 layers, layer-wise LR decay 0.9, rules before state, 128 tokens, 8,000 balanced rows, best of 3 epochs (epoch 1) | 0.798 | 0.666 | 0.825 | 0.846 |
| option packer A/B | r2's recipe and rows with `--packer option`, 1 epoch (r2's best epoch was also epoch 1) | 0.765 | 0.659 | 0.561 | 0.807 |
| LightGBM, all fields | lambdarank on every structured field, all 59,160 train rows | 0.812 | 0.753 | 0.994 | 0.866 |
| LightGBM, packer fields | only the columns the 128-token packer writes | 0.818 | 0.695 | 0.994 | 0.872 |
| LightGBM, packer + truncation | minus what 128-token truncation cuts | 0.765 | 0.678 | 0.994 | 0.818 |
| always HOLD | | 0.493 | 0.618 | 0.993 | 0.488 |
| Jev re-query ceiling | Jev's own noise, sd 0.022 / 0.013 per option | 0.968 / 0.979 | 0.964 / 0.977 | 0.994 / 0.997 | 0.976 / 0.985 |

**Natural pools (every call as logged):**

| run | time-eval | unseen rules | live | dev |
|---|---:|---:|---:|---:|
| CPU r2 student | 0.800 | 0.634 | 0.825 | 0.832 |
| LightGBM, all fields, all train rows | 0.876 | 0.807 | 0.994 | 0.910 |
| LightGBM, all fields, r2's 8,000 balanced rows | 0.838 | 0.778 | 0.994 | 0.876 |
| LightGBM, all fields, 8,000 natural rows | 0.867 | 0.797 | 0.994 | 0.891 |
| always HOLD | 0.580 | 0.668 | 0.993 | 0.578 |
| Jev re-query ceiling | 0.971 / 0.982 | 0.971 / 0.983 | 0.995 / 0.997 | 0.976 / 0.986 |

r2 scores about the same on natural calls as on the receipt rows (0.800 vs 0.798) because it was trained on balanced rows. Models trained on the natural mix score higher on natural calls (the LightGBM: 0.876 vs 0.812). Dev numbers are optimistic for every model, because dev picks the student's epoch and temperature and the LightGBM's tree count. The Kaggle checkpoint is not in this workspace, so the natural-pool and gating numbers are for r2; `shadow_gate.py --ckpt <kaggle ckpt> --seq 256` produces the same report for it.

## 2. Diagnosis

### 2.1 Jev's own noise: about 2 to 3 points

- Jev's logged `choice` is the argmax of its `probabilities` on 99.95% of hyperspeed calls and on every live call. Exact ties at the top happen on 1.5% of calls, and the tie-break looks like a coin flip (first in menu 52% of the time).
- The "average top probability 0.41" is Jev's `confidence` field. It tracks the gap between Jev's top two probabilities (correlation 0.96, mean gap 0.36), not the top probability (correlation 0.86). Jev's mean top probability is **0.64**.
- If Jev sampled its choice from its probabilities, even a perfect copy would agree only 64% of the time (E[max p] = 0.643; two independent samples agree 54%). That is not what happens: Jev takes the argmax, so a copy that predicts Jev's probabilities well can agree far more often.
- What does limit a perfect copy is that Jev's probabilities move when it is asked the same thing again. Live engine: 745 repeated prompts (1,512 pairs, about 10 s apart) gave 0 choice flips and a per-option standard deviation of 0.0128. Hyperspeed: 30 repeated prompts gave 1 flip and 0.0221.
- Adding that noise to Jev's logged probabilities and comparing argmaxes gives the ceiling for a student that predicts Jev's mean probabilities exactly:

| natural pool | time-eval | unseen rules | live | dev |
|---|---:|---:|---:|---:|
| top-1 ceiling, live-style noise (0.0128) | 0.982 | 0.983 | 0.997 | 0.986 |
| top-1 ceiling, hyperspeed noise (0.0221) | 0.971 | 0.971 | 0.995 | 0.976 |
| top-2 ceiling (either noise level) | 0.999 | 0.997 | 1.000 | 1.000 |
| Jev agreeing with itself (two noisy copies, 0.0221) | 0.961 | 0.961 | 0.993 | 0.968 |
| per-option error a copy can afford for 90% top-1 | 0.085 | 0.077 | 0.180 | 0.100 |
| per-option error a copy can afford for 96% top-1 | 0.031 | 0.031 | 0.104 | 0.039 |

- The noise only matters where Jev is nearly indifferent: all of the loss sits on calls whose top-two gap is under about 0.05 (11.4% of time-eval calls). On the 80% of calls with a gap of 0.10 or more the ceiling is essentially 100%.

So Jev's noise costs a perfect copy 2 to 3 points on hyperspeed calls and under 1 point on live calls. **96% blanket top-1 is right at the ceiling**: it needs the copy's per-option probabilities within about 0.03 of Jev's, only 1.4 times Jev's own re-query jitter. 90% blanket needs about 0.085. For comparison, r2's per-option error against Jev is 0.118 on time-eval (at its best-fitting temperature), and its errors are concentrated on whole classes, so it lands at 80% instead of the ~87% that random noise of that size would give.

### 2.2 Input truncation and representation: about 3 to 4 points

What the student sees compared with Jev:

- Jev's prompt is a median 736 tokens (p10 678, p90 845). The student gets 128 tokens per (state, option) pair.
- The 128-token packer keeps only some of each coin's columns. Breezy keeps score, long_on, short_on, r24h_pct and fund_z, and drops slices, stop_dist_atr, rv90_pct and at_10d. Boozy drops oi1h_pct and spread_bp and keeps at most 4 coins, which drops a menu coin on half of boozy rows. Bizzy keeps only r1h_pct and oi1h_pct and drops to_trigger_pct, day_move_pct, prev_range_pct, fund_z and spread_bp.
- Token truncation then trims the state on 59% of time-eval pairs. 31% of rows lose some menu coin's line in some pair (boozy 70%, breezy 20%, bizzy 0%), and on **32% of gold pairs the gold option's own coin line is cut**. The rules line is never cut (rules go first since r2), but rules are clipped at 180 characters, which truncates the four `setup-*` texts (259 to 444 characters).

What that costs, measured with LightGBM on structured features over the same splits (natural / receipt):

| features | time-eval | unseen rules |
|---|---:|---:|
| every field | 0.876 / 0.812 | 0.807 / 0.753 |
| only what the packer writes | 0.874 / 0.818 | 0.710 / 0.695 |
| packer, then 128-token truncation | 0.845 / 0.765 | 0.679 / 0.678 |

Truncation costs about 3 points natural and 5 on the receipt rows for seen rules. The packer's column choice costs about 10 points on unseen rules, where the model cannot lean on the rules identity and needs the numbers.

Which inputs carry the signal (LightGBM with every field, one group removed and refit; change in agreement):

| group removed | features | time-eval natural | time-eval receipt | unseen rules natural |
|---|---:|---:|---:|---:|
| none (0.876 / 0.812 / 0.807) | 96 | | | |
| rules identity (id code, source, rotating flag) | 3 | −4.7 | −3.5 | −5.1 |
| engine hints (description rank, top-1 coin flag) | 2 | −3.6 | −7.2 | −2.8 |
| coin numbers (every per-coin column) | 72 | −3.4 | −5.8 | −6.4 |
| position and account (the `me` line) | 9 | −2.7 | −2.1 | −0.4 |
| option label and kind | 3 | +0.1 | −0.1 | −1.2 |
| menu position | 1 | +0.1 | +0.4 | −1.4 |

Option order carries nothing on seen rules, so the permutation-invariant pair scorer loses nothing by not seeing it. (On unseen rules it is worth 1.4 points as a fallback: Jev picks the first of five options 80% of the time.)

Trained on the same 8,000 balanced rows, r2 trails the all-fields LightGBM by 3.8 points on natural time-eval (0.800 vs 0.838) and 1.7 on the receipt rows (0.798 vs 0.815). It still beats the LightGBM limited to the packed and truncated fields on the receipt rows (0.798 vs 0.765), so it gets more out of its text than those fields hold (rules wording, option descriptions); it is capped by what the packer and the 128-token window let through. On the Kaggle weights, 256 tokens was worth 1.2 points over 128 (0.763 vs 0.751).

Moving each option's coin row into the option text does not fix this at 128 tokens. In an A/B with r2's recipe (section 5), the option packer always shows the gold option's numbers, but its ~49-token option texts push the rules text out of 27% of gold pairs and the shared coin table out of nearly all of them. It lands 3.3 points below r2 on time-eval and 3.9 on dev. The window is the constraint, not the order inside it.

### 2.3 Data diversity: the largest lever

- The varied data is 30 one-minute snapshots of a single 30-minute market window (20 train, 3 dev, 1 purge, 6 time-eval). Each snapshot carries about 3,000 menus: many bees, rules and synthetic books on the same market state, and consecutive snapshots share most of that state.
- **Distinct market states matter far more than row count.** LightGBM agreement on natural time-eval, trained on k random training snapshots (mean of 3 draws):

| training snapshots | 1 | 2 | 5 | 10 | 20 |
|---|---:|---:|---:|---:|---:|
| all their rows | 0.775 | 0.844 | 0.840 | 0.867 | 0.876 |
| a fixed 2,762 rows | 0.767 | 0.832 | 0.823 | 0.846 | 0.853 |

  At a fixed row budget, 20 times more snapshots adds 8.6 points. 21 times more rows from the same 20 snapshots adds 2.3. Past 2 snapshots the gain is about 1 point per doubling of snapshots.
- Every model overfits the 20 training states. The LightGBM scores 0.956 on training rows and 0.876 on time-eval. Kaggle s2 scored 0.928 on training rows and 0.798 on dev after a single epoch.
- Agreement varies between market states more than it drifts over time. Per-minute agreement on time-eval ranges from 0.81 to 0.90 for the LightGBM and 0.73 to 0.83 for r2, with no steady decline across the 6 minutes, and both find the same minutes hard.
- Rules: 23 `rules_id`s carry only 15 non-empty texts (each `+rotating` id reuses its base text), 13 of them in training. With that few, a model learns "this id behaves like this" instead of reading the rules. The unseen-rules score is therefore a lottery over which three ids were held out. r2 by id: bizzy-alts 0.485, boozy-diamond 0.917 (its text is in training through boozy-diamond+rotating), breezy-cautious 0.627; the LightGBM: 0.960, 0.918, 0.581. Students swing by 9 points depending on where the rules sit in the input (r1, state first: 0.757 on the receipt rows; r2, rules first: 0.666), and r2 gets whole classes wrong on unseen rules (HOLD 0 of 605, TRIM_HALF 0 of 473).

### 2.4 Training mix and schedule

- **Gold-balancing the training rows costs about 3 points on natural calls.** Same LightGBM, same features: trained on r2's 8,000 balanced rows it scores 0.838 natural / 0.815 receipt on time-eval; on 8,000 natural rows 0.867 / 0.809; on all 59,160 natural rows 0.876 / 0.812. The mix is worth 2.9 natural points; 7 times more rows of the same states is worth 0.9.
- Balanced training also makes a model act when Jev holds: the balanced LightGBM acts on 9.1% of Jev's holds (5.4% natural), r2 on 19.9%. On live calls, where 99.3% of Jev's choices are holds, r2 agrees on only 0.825 while Kaggle s2, trained on the natural mix, agrees on 0.993.
- More epochs on the same states do not help. With a constant learning rate, r2's dev agreement peaked after epoch 1 (0.846, then 0.834, then 0.832) while training loss kept falling (0.72, 0.54, 0.47). r1, with half as many trainable layers, peaked at epoch 3.
- KD temperature is not a lever. The Kaggle sweep (T=1, 2, 4: 0.8135, 0.829, 0.832 on 2,000 dev rows) is within about one standard error (0.8 points) between T=2 and T=4. The KL term has no T² factor, so T=4 mostly means a weaker KL term.

### 2.5 Model size: not the binding constraint yet

| | ettin 68m | ettin 150m |
|---|---:|---:|
| layers x hidden | 19 x 512 | 22 x 768 |
| non-embedding parameters | ~42M | ~110M |
| GFLOP per pair at 128 tokens | ~10.9 | ~28 |
| GFLOP per 4-option menu | ~44 | ~112 |

r2 runs one pair in 34 ms on this CPU as fp32 ONNX (batch 1); 150m would be about 2.6 times that. Capacity is not what fails today: every model fits the training states far better than held-out ones, including a LightGBM over hand-built features that has no capacity problem at all. A larger pretrained encoder helps most with reading unseen text such as new rules, which first needs many more rules texts. Expect at most 1 to 2 points from 150m on today's data; test it again after the data step.

### 2.6 Where the gap goes

Rough budget for time-eval, from the measurements above:

| | natural | receipt rows |
|---|---:|---:|
| r2 today | 0.800 | 0.798 |
| training mix (balanced to natural) | about +3 | about 0 |
| input representation (packing, truncation) | +3 to +4 | +1.5 to +5 |
| more rows of the same 20 snapshots | about +1 | under +0.5 |
| model size, KD temperature | at most +1 to +2 | at most +1 to +2 |
| more distinct market states and rules texts | the rest, about +9 | the rest, about +10 |
| Jev's noise (no student recovers it) | 2 to 3 | 2 to 3 |

The data line is the residual: the LightGBM with every field and every row fits training rows at 96% and still lands at 88% (natural) and 81% (receipt) on market states 2 to 7 minutes later.

## 3. Recipe most likely to reach 90%

**Step 0: measure what deployment will see.** Make the headline natural-mix agreement on held-out *days*, with the gold-balanced receipt as a secondary "hard decisions" view. Hold out rules *texts*, not ids that share a text with a training id. Report coverage at 96% (section 4) next to blanket agreement, and track picks that act separately from holds.

**Step 1: data, the main lever.**

- Spread the same Jev budget over many more market states. For example, one hyperspeed snapshot every 15 minutes for at least 14 days (about 1,300 snapshots) with about 100 menus each costs roughly the same 100k Jev calls as today's dump and gives about 40 times more distinct states.
- Cover regimes on purpose: trending up, trending down, range-bound, and high-volatility event days, a few days of each.
- Rotate 100 or more distinct rules texts (paraphrases and new constraints) across styles, and hold out about 20% of the texts.
- Keep logging live-engine calls and train on earlier days of them; they are the distribution the chip will actually see.
- Hold out the last 2 to 3 days entirely for evaluation.
- Keep about 1% repeated prompts so Jev's noise stays measured ([`BEEBOTS_LOG_SPEC.md`](BEEBOTS_LOG_SPEC.md)).
- Back-of-envelope from the in-regime snapshot curve (about +1.1 points per doubling of snapshots for the LightGBM): about 100 snapshots for 90% natural time-eval and about 700 for 93%. The curve must flatten toward the 97% ceiling, and held-out days will be harder than held-out minutes, so treat these as optimistic.

**Step 2: input packing.**

- Make room before reordering. Per-option coin rows at 128 tokens (`--packer option`) lost 3.3 points on time-eval and collapsed on live calls in the A/B (section 5), because they push the rules text and the shared coin table out of the window. Use 256 tokens if the chip budget allows (worth 1.2 points on the Kaggle weights), or compact per-option rows: the few columns per style that carry signal, plus the coin's rank in the menu.
- Give every option the same structure, with a placeholder row when an option names no coin, so the presence of a row cannot stand in for its content.
- Rules first and never cut. Raise the 180-character clip so the `setup-*` rules fit.
- Drop the `rules_id` token from the header on about half of the training rows so the model has to read the rules text instead of memorising ids.
- Keep the engine hints (description rank, top-1 coin) and the position/account line; they are worth 3 to 7 points in the LightGBM.

**Step 3: model and architecture.**

- Keep the 68m pair cross-encoder for now: it ignores option order (which carries no signal on seen rules), has static shapes, and is already exported with PyTorch/ONNX parity checked.
- Run the LightGBM next to it on the host CPU (it takes microseconds) as the yardstick and second opinion. A log-probability blend fit on dev currently puts all the weight on the LightGBM, so r2 adds nothing on natural calls, but the two are right on different calls (one of them is right on 92.7% of time-eval calls). Re-fit the blend after the student is retrained on the natural mix; if it then helps, feed the structured numbers to the encoder as a second input.
- If pair scoring stalls, try listwise next: one sequence per menu with a fixed token slot per option, scored at each slot's first token. Options can then compare with each other directly (the LightGBM's strongest coin signals are relative: distance from the menu's best value, rank among the menu's coins). A 256-token menu costs about half the FLOPs of four 128-token pairs, and fixed slot positions keep the graph static for Hailo.
- 150m only after step 1, either as a teacher for the 68m or if the 68m saturates on the larger data.

**Step 4: training.**

- All training rows in their natural mix; report the gold-balanced view as well.
- 2 to 3 epochs, 5% warmup then linear decay, layer-wise decay 0.9, all layers on GPU.
- Loss: cross-entropy on Jev's choice plus 0.5 × T² × KL at T=2 to Jev's probabilities; the pairwise hinge is optional.
- Early-stop on a natural-mix dev block that is separate from evaluation, and fit gate thresholds on a further calibration block.

**Step 5: gate**, as in section 4.

**What to expect.** On today's data, steps 2 to 4 should bring a 68m student to about the all-fields LightGBM: roughly 0.87 to 0.88 natural and 0.81 to 0.83 on the receipt rows for time-eval, with about three quarters of calls answerable at 96%. 90% natural on held-out minutes is borderline. 90% on held-out days, on gold-balanced rows or on unseen rules needs step 1. At any data size, 96% is a coverage target, not a blanket one: a copy at 92 to 93% blanket agreement should be able to answer roughly 80 to 90% of calls at 96%.

## 4. Shadow-mode gating

### 4.1 Metrics

All on natural pools, with thresholds chosen on dev and applied unchanged to the held-out splits (`shadow_gate.py`):

- **Top-1 agreement**: the chip's pick is Jev's choice.
- **Top-2 agreement**: Jev's choice is among the chip's top two, i.e. how often "chip proposes two, Jev picks" would contain Jev's answer.
- **Tolerant agreement (0.05)**: Jev rated the chip's pick within 0.05 of its own top option, so the disagreement is one Jev itself is nearly indifferent about.
- **Coverage and selective agreement at a threshold**: the share of calls whose confidence clears the threshold, and agreement on those calls. Confidence scores: the chip's top probability, its top-two margin, and a small logistic gate fit on dev (top probability, margin, entropy, menu size, style).
- **Dev threshold for a target** (90%, 96%, 99%): the lowest threshold whose dev selective agreement reaches the target, plain and with a Wilson 95% lower bound. The report gives realized coverage and agreement on each held-out split, with cluster-bootstrap intervals (clusters are snapshot × rules id).
- **Oracle coverage**: the largest coverage that reaches the target if the threshold were tuned on the held-out split itself; the upper bound for that confidence score.
- **System agreement**: coverage × selective agreement + (1 − coverage), with routed calls answered by Jev.
- **Hold vs act**: when Jev acted, how often the chip picked the same option or held instead; when Jev held, how often the chip acted.
- **Calibration**: ECE and per-option RMSE between the chip's and Jev's probabilities, which maps onto the noise table in 2.1.

### 4.2 r2 on natural pools

| | time-eval | unseen rules | live | dev |
|---|---:|---:|---:|---:|
| calls | 14,938 | 14,515 | 2,336 | 8,533 |
| top-1 | 0.800 | 0.634 | 0.825 | 0.832 |
| top-2 | 0.961 | 0.967 | 1.000 | 0.985 |
| tolerant (0.05) | 0.855 | 0.692 | 0.832 | 0.874 |
| same action kind | 0.909 | 0.759 | 0.825 | 0.878 |
| Jev acted: chip picked the same option | 0.800 | 0.719 | 9 of 20 | |
| Jev held: chip acted | 0.199 | 0.478 | 0.171 | |
| 96% threshold from dev (top probability): coverage / realized | 0.548 / 0.950 | 0.328 / 0.732 | 0.000 / – | 0.576 / 0.960 |
| 96% threshold from dev (logistic gate): coverage / realized | 0.624 / 0.942 | 0.477 / 0.727 | 0.214 / 1.000 | 0.661 / 0.960 |
| oracle coverage at 96% (top probability / logistic) | 0.420 / 0.439 | 0.062 / 0.128 | 0.554 / 0.554 | |
| 90% threshold from dev (top probability): coverage / realized | 0.776 / 0.902 | 0.509 / 0.734 | 0.113 / 1.000 | 0.859 / 0.900 |
| system agreement at the 96% top-probability threshold | 0.973 | 0.912 | 1.000 | |

Agreement when the chip answers only its most confident calls (time-eval, ranked by top probability):

| share answered | 10% | 20% | 30% | 40% | 50% | 60% | 70% | 80% | 90% | 100% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| agreement | 0.992 | 0.974 | 0.974 | 0.967 | 0.956 | 0.946 | 0.927 | 0.890 | 0.843 | 0.800 |

What this says:

- On seen rules, r2 can answer about 40% of calls at 96% and about 78% at 90%. The 90% threshold transfers from dev (realized 0.902); the 96% one falls just short (0.950, interval 0.931 to 0.967), mostly because of boozy (covered 49% at 0.906, against bizzy 51% at 0.974 and breezy 66% at 0.967). Per-style thresholds are needed.
- On unseen rules, confidence means little: at the 96% dev threshold breezy-cautious is covered 55% at 0.60, and the best possible coverage at 96% is 6 to 13%. Calls whose rules text was not in training go to Jev.
- On live calls r2 is less confident than on hyperspeed, so the top-probability threshold takes nothing; the logistic gate (which knows the style) takes 21% at 100%.
- Top-2 is 96 to 100% everywhere, close to the 99.9% ceiling, so a "chip shortlists two, Jev picks" mode would rarely lose Jev's answer.
- r2 acts on 20% of the calls where Jev holds (48% on unseen rules). For a trading bee that is the costly error, so act picks need their own, stricter threshold.

For comparison, the all-fields LightGBM on the same time-eval calls: top-1 0.876, top-2 0.976, tolerant 0.925, oracle coverage at 96% 0.75 to 0.76. Its dev-set thresholds do not transfer (96% target: coverage 0.866 at 0.925 realized), because dev also chose its tree count; thresholds should come from a separate calibration block or from recent shadow logs.

### 4.3 ONNX and quantization

| r2, 300 time-eval calls | decisions matching PyTorch | agreement with Jev | max logit difference | ms per pair (CPU, batch 1) |
|---|---:|---:|---:|---:|
| PyTorch | | 0.743 | | |
| fp32 ONNX (sha256 `fc126061…`) | 300 of 300 | 0.743 | 0.00003 | 34.2 |
| ORT dynamic int8 | 244 of 300 | 0.687 | 8.4 | 20.8 |

The fp32 export is exact. Naive dynamic int8 changes 19% of decisions, some of them on calls PyTorch was 95%+ sure of. Hailo's compiler quantizes statically with calibration data (256 real tokenized pairs ship with the export), which usually does better than ORT's dynamic mode, but this model is clearly sensitive. Before shadow mode, the compiled model should match the fp32 model's decisions on at least 99% of a few thousand held-out calls; if it does not, keep the sensitive layers at higher precision or fine-tune with quantization in the loop.

### 4.4 Proposed shadow policy

**Phase A, pure shadow** (now, and until the pass criterion holds on new days):

- The chip scores every call and Jev decides every call. Log both probability vectors, the gate score, and the model and threshold versions.
- Daily, on that day's calls: top-1, top-2 and tolerant agreement, coverage and realized agreement at the frozen 96% threshold with its Wilson interval, hold-vs-act, all per style and per rules text (seen or unseen).
- Move to phase B only when, on at least 2 consecutive held-out days, agreement on covered calls has a Wilson 95% lower bound of at least 0.96 and the chip acts on at most 0.5% of the covered calls where Jev held.

**Phase B, selective:**

- The chip answers a call only if all hold: its rules text is one it was trained on; its confidence clears the per-style threshold (Wilson lower bound ≥ 0.96 on recent shadow logs); a pick that acts (open, close, switch, trim, add) clears a stricter threshold than a hold; no drift alarm is active. Everything else goes to Jev.
- Audit: also send a random 5% of chip-answered calls to Jev. Confirming 96% to within about ±2 points (Wilson 95%) takes about 400 audited calls per window.
- Drift alarms: audited agreement below the threshold's lower bound; coverage moving more than 10 points from its calibration value; a rising share of unseen rules texts or new menu labels.
- Re-fit thresholds on recent shadow logs, not on the training dev split.
- On live-engine traffic, 99.3% of Jev's choices are holds, so always-HOLD already agrees 99.3% of the time and blanket agreement says little. Judge live by the act calls; the current live log has only 20 of them.

## 5. Option packer A/B

`--packer option` was the first candidate for step 2. Each option's text carries its own coin's full row, with the coin's rank among the menu's coins after each value, and `text_a` becomes header, position, rules, `top1` and then the whole coin table. The A/B reran r2's recipe on the same 8,000 rows with only the packer changed, for 1 epoch. r2's best dev epoch was also its first, and the learning rate is constant, so r2's receipt numbers are its epoch-1 numbers.

What a 128-token pair keeps under each packer (`jev_ceiling.json`, `representation.packer_truncation`; 3,000 natural time-eval rows, receipt rows in brackets):

| | v1 (r2) | option |
|---|---:|---:|
| tokens per option text | 12 | 49 |
| pairs whose `text_a` is trimmed | 59% | 100% |
| gold pairs that show the gold option's coin numbers | 77% (63%) | 100% (100%) |
| gold pairs whose rules text is cut | 0% | 27% (28%) |
| boozy gold pairs whose `top1` hint is cut | 4.5% (6.1%) | 36% (43%) |
| coin-table lines left in `text_a` | 52% | 3% |

The option packer fixes one blind spot and opens two. The rules id in the header always survives, but the rules text is cut on 27% of seen-rules gold pairs (boozy 37%, bizzy 31%, breezy 12%), and the coin table that let the model compare options is gone. The unseen-rules texts are short and are cut on 1% of pairs.

Result on the receipt rows:

| | time-eval | unseen rules | live | dev | train loss |
|---|---:|---:|---:|---:|---:|
| r2 packer, epoch 1 | 0.798 | 0.666 | 0.825 | 0.846 | 0.719 |
| option packer, epoch 1 | 0.765 | 0.659 | 0.561 | 0.807 | 0.771 |

| time-eval | boozy | breezy | bizzy | 2 options | 3 | 4 | 5 |
|---|---:|---:|---:|---:|---:|---:|---:|
| r2 packer | 0.746 | 0.839 | 0.868 | 0.885 | 0.831 | 0.749 | 0.679 |
| option packer | 0.713 | 0.784 | 0.874 | 0.887 | 0.779 | 0.637 | 0.659 |

- **Seen rules: 3.3 points worse**, well outside sampling error (about 0.7 points for a difference on 6,000 rows). The loss sits on boozy and breezy and on 3- and 4-option menus, where options have to be compared with each other and the coin table no longer fits. Bizzy, whose v1 view kept only 2 of its 7 coin columns but never lost a coin line, is level (+0.6).
- **Unseen rules: level** (−0.7; boozy +2.7, breezy −3.6, bizzy unchanged).
- **Live: collapses from 0.825 to 0.561, through a format shortcut.** In training, the only options without a coin row are `WAIT` (1.5% of options), and Jev picks them 77% of the time. Live rows carry no `menu_detail`, so there the only options without a coin row are bare `SWITCH` (17% of options), which Jev never picks. The model learned "the option without numbers is usually the answer" and picks `SWITCH` on 546 breezy live calls where Jev held, all of which r2 got right. On boozy it adds 211 `RIDE` → `DOUBLE_DOWN` errors to the 256 it shares with r2.

So per-option rows only pay with room for them, and every option needs the same structure. Next to try, in order: 256 tokens with the v1 layout; compact per-option rows with a placeholder row for options that name no coin; the listwise layout from step 3, which keeps one shared state block and short per-option slots. v1 stays the default.

## 6. Reproduce

From `tools/orchestration`:

```bash
# Jev noise ceiling, margins, representation stats, v1 vs option packer truncation
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.jev_ceiling
# LightGBM yardstick: field variants, drop-one-group, training mix, snapshot curve, student-vs-GBM blend
# (train.sh does not install LightGBM: jevh_trading/.venv/bin/pip install lightgbm==4.6.0)
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.structured_baseline --threads 4
# gate the r2 checkpoint (scores whole pools, then ONNX fp32/int8 parity)
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.shadow_gate
# recompute the report from saved predictions
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.shadow_gate --recs jevh_trading/artifacts/preds_68m.jsonl.gz
# gate the Kaggle 256-token checkpoint without touching r2's files
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading.shadow_gate --ckpt runs/s2/student_68m.pt --seq 256 \
  --onnx runs/s2/jevh_trading_ettin68m_seq256.onnx --out runs/s2/shadow_gate.json
# option packer A/B (r2's recipe, 1 epoch)
PYTHONPATH=. jevh_trading/.venv/bin/python -m jevh_trading --size 68m --epochs 1 --unfreeze-last 12 \
  --packer option --artifacts /tmp/jevh_ab_option --skip-export
```

Artifacts: `artifacts/jev_ceiling.json`, `artifacts/structured_baseline.json`, `artifacts/shadow_gate.json`, `artifacts/RECEIPT.md`, `artifacts/metrics.json`. Predictions (`preds_*.jsonl.gz`), checkpoints and ONNX files are gitignored.

## 7. Caveats

- One market regime. All varied data is one 30-minute window and time-eval sits 2 to 7 minutes after training, so every number here is in-regime interpolation. Held-out days will be lower.
- The hyperspeed re-query noise rests on 30 repeats and the live estimate on 1,512 pairs. The ceiling moves by about a point between them.
- The Kaggle runs are summarized from the uploaded receipt and summary; their checkpoints were not available here.
- The unseen-rules split has three rules ids, one per style, and one of them shares its text with a training id. Treat its numbers as anecdotes until there are many held-out rules texts.
- Live engine has 20 non-hold Jev choices in total, so act agreement on live is not measurable yet.
- The option packer A/B is one seed and one epoch. Its training loss was still above r2's, so more epochs might close part of the seen-rules gap; they would not remove the live format shortcut.
