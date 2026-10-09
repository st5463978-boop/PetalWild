# JEV-H-68m-v5 data

The trainer prefers the cloud-agent **uploads** directory (hashed filenames), then
falls back to the files in this folder. Override any path with env vars.

| Role | Env | Uploads glob | Bundled |
|---|---|---|---|
| Gold labels (`jev_choice`) | `JEVH_LABELS_PATH` | `labels_*.jsonl` | `labels.jsonl` (full, 4,220 rows, 2.6 MB) |
| Decide log (teacher soft labels, never gold) | `JEVH_DECIDE_PATH` | `decide_questions_dedup*.jsonl` | `decide_questions.sample.jsonl` (40 rows) |
| Hard PetalWild questions | `JEVH_LANE_PATH` | `jevh_lane_bank*.jsonl` | `lane_bank.jsonl` (full, 197 rows) |
| Live student tokenizer | `JEVH_TOKENIZER_PATH` | `jevh_student_tokenizer*.json` | `tokenizer.json` (3.5 MB) |
| JEV-H-large soft labels on decide | `JEVH_LARGE_SOFT_PATH` | `jevh_large_soft*.jsonl.gz` | `external/jevh_large_soft_on_decide_questions_dedup.jsonl.gz` (copied from `cursor/jevh-variant-large-819a`, not merged) |

`JEVH_UPLOADS_DIR` defaults to `/home/ubuntu/.cursor/projects/workspace/uploads`.

The full decide dump is ~5.4 MB so it is **not** committed. When uploads are
present the trainer reads `decide_questions_dedup_*.jsonl` (9,402 rows). The
sample is only a fallback so `run.sh` still starts without uploads.

`labels.sample.jsonl` and `lane_bank.sample.jsonl` are tiny fixtures for smoke
tests; training uses the full bundled labels / lane bank (or uploads).
