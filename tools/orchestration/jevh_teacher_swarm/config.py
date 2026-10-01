"""Flat config reader. PyYAML is not required."""

from __future__ import annotations

from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE / "config.yaml"


def load_config(path: Path | None = None) -> dict:
    raw = (path or DEFAULT_CONFIG).read_text(encoding="utf-8")
    cfg: dict = {}
    for line in raw.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        cfg[key.strip()] = _coerce(value.strip().strip('"').strip("'"))
    return cfg


def _coerce(value: str):
    lower = value.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False
    if value.isdigit() or (value.startswith("-") and value[1:].isdigit()):
        return int(value)
    try:
        return float(value)
    except ValueError:
        return value
