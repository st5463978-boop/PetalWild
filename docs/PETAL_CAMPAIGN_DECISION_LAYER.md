# Petalwild campaign decision layer

Locked by the director. Do not benchmark, recompile, or pick another model.

`PETAL_DECISION_LAYER` is the trained Qwen3-1.7B DPO-merged (RLCD + Laya preference pairs), Q8_0 GGUF on llama.cpp CPU, with a Platt-calibrated `/decide` service. It scored 8/9 on the decide smoke suite. The only miss is a triangle-sides trick question. Hailo NPU chip variants scored 2–3/9 and lose the decision signal after the 8-bit compile. The chip path is not used.

JEV-H / the Hailo System-One stack is development infrastructure only. It is not a runtime requirement of the shipped game.

## Tiers

Env-configured. Discovered via ntfy. Game client: `scripts/autoload/petal_decide.gd`. Dispatcher: `tools/hailo_decide_url.py`.

| Order | Name | Latency | Discovery | Timeout |
| --- | --- | --- | --- | --- |
| 1 | hef-dfc CPU | ~0.6–1.8 s | `https://ntfy.sh/petalwild-hailojev-decide-hef-729b47676dfdd628/raw?poll=1&since=latest` | 15 s |
| 2 | Pi CPU | ~2–5 s, cold up to ~55 s | `https://ntfy.sh/petalwild-hailojev-decide-picpu-78ede63f3f827400/raw?poll=1&since=latest` | 60 s |
| 3 | hailo `:8766` hop | last resort | existing hailo topic, then `http://100.126.22.71:8766` | 75 s |

Env names: `HAILO_DECIDE_PRIMARY_DISCOVERY_URL`, `HAILO_DECIDE_PRIMARY_URL`, `HAILO_DECIDE_FALLBACK_DISCOVERY_URL`, `HAILO_DECIDE_FALLBACK_URL`, `HAILO_DECIDE_DISCOVERY_URL`, `HAILO_DECIDE_LAST_URL`.

`eval "$(python3 tools/hailo_decide_url.py --export)"` at studio startup. The game does not import `tools/orchestration/`.

## Schema

`POST /decide` then `/v1/decide` if that path is missing.

Request:

```json
{"question": "...", "context": "...", "options": ["...", "..."]}
```

At least two options. Response: `choice`, `index`, `scores`, `confidence`, `margin`, `mode`, `p_yes`. Integer `index` wins. No option shuffle on this service.

HTTP 503 with "model loading" is retryable once on the same tier, then the next tier. No auth. `PETAL_DECIDE=1` makes live calls. Offline by default (`PETAL_DECIDE` unset, or `PETAL_SMOKE=1`): first option. Log `tier`, `confidence`, `margin`, `mode`, `p_yes`.

Grok is the reasoning and escalation layer. Machine control must use this structured output, never free prose.

## In-game callers

Bounded choices only. Offline defaults keep the garden playable.

| Call | Options | Offline |
| --- | --- | --- |
| Bellhelp (and other visitors) settle | `settle`, `keep visiting` | `settle` |
| Nessa / Bram stall | `wait`, `buy` | `wait` |
| Nessa / Bram want | produce ids | first liked crop |

Settle options are `["settle", "keep visiting"]`, so offline settles. Shop options are `["wait", "buy"]`, so offline waits. Wants: Nessa's first like is peach, Bram's is bramble.

## Not this layer

MinoJEV, 0.6B RLCD-only, HEF recompile, Hailo NPU `/v1/chat/completions`, or any new bake-off.
