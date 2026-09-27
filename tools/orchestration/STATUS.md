# Hailo decide status

System-1 routes call the trained Qwen3-1.7B DPO CPU decide service.

- Primary: hef-dfc CPU. Discovery `HAILO_DECIDE_PRIMARY_DISCOVERY_URL`, URL `HAILO_DECIDE_PRIMARY_URL`. Timeout ~15s.
- Fallback: Pi CPU. Discovery `HAILO_DECIDE_FALLBACK_DISCOVERY_URL`, URL `HAILO_DECIDE_FALLBACK_URL`. Timeout ~60s. Used when the primary errors, times out, or returns 503 while the model is loading.
- Last resort: existing hailo-decision hop. Discovery `HAILO_DECIDE_DISCOVERY_URL`, URL `HAILO_DECIDE_LAST_URL`, then `http://100.126.22.71:8766/v1/decide`.
- Health: `GET /health`
- Choice: `POST /decide` with `{"question","options"}` (at least two options), then `/v1/decide` if that path is missing
- Response: existing keys plus `confidence` (Platt-calibrated), `margin`, `mode`, `p_yes`. No option shuffle.
- No auth
- Not used: MinoJEV, 0.6B RLCD, HEF recompile

Quick-tunnel hosts are not hardcoded. `eval "$(python3 tools/hailo_decide_url.py --export)"` at startup.

## Earlier smoke (2026-09-24)

Recorded against the previous quick-tunnel host, before the Tailscale default.

| Call | Result | Latency |
| --- | --- | --- |
| `GET /health` | HTTP 200, `ok: true`, model `Qwen3-1.7B.hef`, device Hailo-10H | 405.4 ms |
| `POST /decide` | HTTP 200 via `/decide`, choice `PETAL_03_JELLY`, index 0, raw `A` | 982.7 ms |

Server-reported `latency_ms` was 846.0. Dispatcher unit tests: 14/14 OK.
