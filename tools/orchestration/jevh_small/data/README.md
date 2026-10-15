# Sample slices (not the training set)

Full files are the Cloud Agent upload bundle:
- labels.jsonl (~4220 rows) — gold `jev_choice`
- decide_questions_dedup.jsonl (~9402 rows) — teacher soft labels, not gold
- jevh_lane_bank.jsonl (~197 rows) — unlabeled PetalWild questions

Point the trainer at them with `JEVH_DATA_DIR` / `JEVH_LABELS_PATH` / `JEVH_DECIDE_PATH` / `JEVH_LANE_PATH`.
The hashed upload names (`labels_bc1e.jsonl`, …) are also accepted.
