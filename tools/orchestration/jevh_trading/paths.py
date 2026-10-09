"""Resolve attached upload files (hashed names) or in-repo samples."""

from __future__ import annotations

import os
from pathlib import Path

PKG = Path(__file__).resolve().parent
REPO = PKG.parents[2]

UPLOAD_HINTS = (
    Path("/home/ubuntu/.cursor/projects/workspace/uploads"),
    Path(os.environ.get("JEVH_TRADING_UPLOADS", "")),
    REPO / "uploads",
    Path.home() / ".cursor/projects/workspace/uploads",
)

# Canonical name -> hashed upload filenames (agent attachments) plus unhashed aliases.
ALIASES: dict[str, tuple[str, ...]] = {
    "market_BTC_15min.json": ("market_BTC_15min_3f23.json", "market_BTC_15min.json"),
    "market_ETH_15min.json": ("market_ETH_15min_fbd5.json", "market_ETH_15min.json"),
    "market_SOL_15min.json": ("market_SOL_15min_8cf9.json", "market_SOL_15min.json"),
    "trading_paper_decisions.jsonl": (
        "trading_paper_decisions_92e3.jsonl",
        "trading_paper_decisions.jsonl",
    ),
    "trading_paper_ledger.json": ("trading_paper_ledger_388d.json", "trading_paper_ledger.json"),
    "trading_strategy_edges.jsonl": (
        "trading_strategy_edges_017b.jsonl",
        "trading_strategy_edges.jsonl",
    ),
    "tokenizer.json": ("jevh_student_tokenizer_94c1.json", "tokenizer.json"),
    "labels.jsonl": ("labels_ebb6.jsonl", "labels.jsonl"),
    "decide_questions_dedup.jsonl": (
        "decide_questions_dedup_f987.jsonl",
        "decide_questions_dedup.jsonl",
    ),
}


def _dirs() -> list[Path]:
    out: list[Path] = []
    extra = os.environ.get("JEVH_TRADING_DATA_DIR")
    if extra:
        out.append(Path(extra))
    for p in UPLOAD_HINTS:
        if p and str(p) not in ("", ".") and p.exists():
            out.append(p)
    out.append(PKG / "assets")
    out.append(PKG / "data" / "sample")  # last: tiny git samples, never shadow uploads
    # unique, preserve order
    seen: set[str] = set()
    uniq: list[Path] = []
    for p in out:
        k = str(p)
        if k not in seen:
            seen.add(k)
            uniq.append(p)
    return uniq


def find_file(canonical: str, *, required: bool = True) -> Path | None:
    names = ALIASES.get(canonical, (canonical,))
    for d in _dirs():
        for n in names:
            p = d / n
            if p.is_file():
                return p
    if required:
        searched = [str(d) for d in _dirs()]
        raise FileNotFoundError(f"{canonical} not found. Looked in {searched} for {names}")
    return None


def tokenizer_path() -> Path:
    bundled = PKG / "assets" / "tokenizer.json"
    if bundled.is_file():
        return bundled
    return find_file("tokenizer.json")  # type: ignore[return-value]


def artifacts_dir() -> Path:
    p = PKG / "artifacts"
    p.mkdir(parents=True, exist_ok=True)
    return p
