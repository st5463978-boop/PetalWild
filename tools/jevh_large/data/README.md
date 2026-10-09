# Sample slices (committed)

Full dumps are **not** in git (labels ~2.6 MB, decide ~5.4 MB). This folder is only a tiny fixture for `--smoke` and for anyone without `uploads/`.

Place the real files in any of:

1. `$JEVH_DATA_DIR`
2. agent `uploads/` (`labels_c563.jsonl`, `decide_questions_dedup_e594.jsonl`, `jevh_lane_bank_128a.jsonl`)
3. repo `uploads/`

The trainer glob-matches `labels*.jsonl`, `decide_questions_dedup*.jsonl`, `jevh_lane_bank*.jsonl` and prefers the non-`sample_` file.
