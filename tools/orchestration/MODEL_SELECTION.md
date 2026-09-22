# Hailo router selection

Date: 2026-09-22

Selected model: none.

The benchmark set has 174 labeled PetalWild development tasks in `tasks.jsonl`. Scoring did not run. This VM has no Hailo device node, no PCI device with vendor `0x1e60`, no `hailortcli`, no HEF, and no local genai port.

`latest_results.json` status is `not_run`, reason `no_hailo_device`.

Do not treat a missing result as a win for Qwen3-1.7B-Instruct or Qwen2-1.5B-Instruct-FC. Re-run `run_benchmark.py` on a machine where the chip and a localhost genai server are both up. Pick the model with the highest owner accuracy, then structured-output validity, then lower mean latency.

HIGH / MEDIUM / LOW from the model are routing labels. They have not been calibrated against outcomes.
