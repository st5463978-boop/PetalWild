# Hailo decide status

System-1 routes call the Pi `hailo-decision` service.

- `HAILO_DECIDE_URL` default: `http://100.126.22.71:8766`
- Health: `GET /health`
- Choice: `POST /decide` with `{"question","options"}`, then `/v1/decide` if that path is missing
- Model: `Qwen3-1.7B.hef` on Hailo-10H (`qwen3:1.7b`)
- Not used: MinoJEV, 0.6B RLCD, local CPU Qwen, HEF recompile

## Smoke from this cloud VM (2026-09-24)

The VM is not on the tailnet. Both calls timed out. No choice was taken.

| Call | Result | Latency |
| --- | --- | --- |
| `GET /health` | `URLError: timed out` | 8025.5 ms |
| `POST /decide` | `URLError: timed out` | 12012.6 ms |

The wiring stays pointed at `http://100.126.22.71:8766`. Set `HAILO_DECIDE_URL` if a tunnel is the reachable address from this host.
