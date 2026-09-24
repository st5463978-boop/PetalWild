# Hailo decide status

System-1 routes call the Pi `hailo-decision` service through the Cloudflare quick tunnel.

- `HAILO_DECIDE_URL` default: `https://fibre-especially-theaters-aerospace.trycloudflare.com`
- On-tailnet override only: `http://100.126.22.71:8766`
- Health: `GET /health`
- Choice: `POST /decide` with `{"question","options"}` (at least two options), then `/v1/decide` if that path is missing
- Client timeout on decide: 75s
- Model: `Qwen3-1.7B.hef` on Hailo-10H (`qwen3:1.7b`)
- No auth
- Not used: MinoJEV, 0.6B RLCD, local CPU Qwen, HEF recompile

The quick-tunnel hostname can change if `hailo-decide-tunnel.service` restarts. If health fails, read `CLOUDFLARE-DECIDE-URL.txt` on the Pi and set `HAILO_DECIDE_URL` to that host.

## Smoke from this cloud VM (2026-09-24)

Not on the tailnet. Both calls hit the Cloudflare URL above and succeeded.

| Call | Result | Latency |
| --- | --- | --- |
| `GET /health` | HTTP 200, `ok: true`, model `Qwen3-1.7B.hef`, device Hailo-10H | 405.4 ms |
| `POST /decide` | HTTP 200 via `/decide`, choice `PETAL_03_JELLY`, index 0, raw `A` | 982.7 ms |

Server-reported `latency_ms` was 846.0. Dispatcher unit tests: 14/14 OK.
