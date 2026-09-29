# Hailo decide status

System-1 routes call JEV-H on the Pi Hailo-10H (port 8771). That is the small Hailo student, not the Qwen3 chat decide service on port 8766.

- Discovery: `https://ntfy.sh/jevh-decide-05923aed092556ed/raw?poll=1&since=latest` (last `https://` line is the live tunnel base). Override: `HAILO_DECIDE_DISCOVERY_URL`
- `HAILO_DECIDE_URL` overrides when set on purpose
- Tailscale fallback: `http://100.126.22.71:8771/v1/decide`
- MagicDNS equivalent: `http://piai-1:8771/v1/decide`
- Health: `GET /health` (also `/v1/health`)
- Choice: `POST /v1/decide` (also `/decide`) with `{"question","options"}` (at least two options)
- Client timeout on decide: 75s
- Model: JEV-H on Hailo-10H
- No auth
- Do not hardcode a trycloudflare host; the public base changes when the tunnel restarts

A health check alone is not proof. A real decide must return a choice.

## Earlier smoke (2026-09-24)

Recorded against the previous Qwen3 chat decide service on port 8766.

| Call | Result | Latency |
| --- | --- | --- |
| `GET /health` | HTTP 200, `ok: true`, model `Qwen3-1.7B.hef`, device Hailo-10H | 405.4 ms |
| `POST /decide` | HTTP 200 via `/decide`, choice `PETAL_03_JELLY`, index 0, raw `A` | 982.7 ms |

Server-reported `latency_ms` was 846.0. Dispatcher unit tests: 14/14 OK.
