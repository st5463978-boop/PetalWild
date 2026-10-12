# Hailo router selection

Date: 2026-09-29

Selected model: JEV-H (ettin68m student HEF) on the Pi Hailo-10H, port 8771.

Live decide is JEV-H, not the Qwen3 chat decide service on port 8766. Set `HAILO_DECIDE_URL` (example MagicDNS: `http://piai-1:8771/v1/decide`) or `HAILO_DECIDE_DISCOVERY_URL` (`https://ntfy.sh/<NTFY_TOPIC>/raw?poll=1&since=latest`; last `https://` line, health-checked). Missing both is an error; there is no in-tree Tailscale or ntfy default. Look up a Tailscale address with `tailscale status`; do not commit it. Health is `GET /health` (also `/v1/health`). A choice is `POST /v1/decide` (also `/decide`) with `question` and `options` (at least two). The client waits 75s. Do not hardcode a trycloudflare host or the ntfy topic. Do not recompile the HEF. The 174-task file is not a local bake-off.

HIGH / MEDIUM / LOW from the model are routing labels. They have not been calibrated against outcomes.
