# Data for JEV-H-trading

**Not financial advice. Offline research copies only.**

The trainer reads the attached upload files (hashed names) from
`/home/ubuntu/.cursor/projects/workspace/uploads/` or `$JEVH_TRADING_UPLOADS`.
Override the search root with `JEVH_TRADING_DATA_DIR`.

Do not commit the full files if they exceed ~5 MB. This folder holds small
samples so unit tests and a dry layout work without the uploads.

| Canonical name | Upload file | Full size (approx) | In git |
|---|---|---|---|
| market_BTC_15min.json | market_BTC_15min_3f23.json | 454 KB / 5000 bars | sample only (80 bars) |
| market_ETH_15min.json | market_ETH_15min_fbd5.json | 452 KB / 5000 bars | sample only |
| market_SOL_15min.json | market_SOL_15min_8cf9.json | 412 KB / 5000 bars | sample only |
| trading_paper_decisions.jsonl | trading_paper_decisions_92e3.jsonl | 1.2 MB / 1581 rows | sample only (12 rows) |
| trading_paper_ledger.json | trading_paper_ledger_388d.json | 132 KB | not copied |
| trading_strategy_edges.jsonl | trading_strategy_edges_017b.jsonl | 53 KB / 139 rows | sample only |
| tokenizer.json | jevh_student_tokenizer_94c1.json | 3.5 MB | copied to `../assets/tokenizer.json` |
| labels.jsonl | labels_ebb6.jsonl | 2.6 MB / 4220 rows | not used for trading gold |
| decide_questions_dedup.jsonl | decide_questions_dedup_f987.jsonl | 5.4 MB | not committed |

Round 2 gold is Jev's `choice` + `probabilities` from the paper (or any growing
`--log`) jsonl. Single-option `RIDE` rows are format-check only. Forward
outcomes on the 15-minute bars are optional eval, not gold. See
`../BEEBOTS_LOG_SPEC.md`.
