"""Representative calibration for the 68M v5 student.

The committed pair is real tokenized (question, option) rows. This module
checks that shape and refuses gaussian noise, all-ones masks, and float
arrays. It never synthesizes a replacement set.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np

from hailo.contract import CLS_ID, PAD_ID, SEQ_LEN, VOCAB

MIN_ROWS = 64
REQUIRED_ROWS = 256


class CalibError(ValueError):
    """The calibration set is missing or not representative training data."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_pair(ids_path: Path, mask_path: Path) -> tuple[np.ndarray, np.ndarray]:
    if not ids_path.is_file() or not mask_path.is_file():
        raise CalibError(
            f"calibration npy missing: ids={ids_path} exists={ids_path.is_file()} "
            f"mask={mask_path} exists={mask_path.is_file()}. "
            "Refusing to invent random calibration data."
        )
    ids = np.load(ids_path)
    mask = np.load(mask_path)
    validate_pair(ids, mask)
    return ids, mask


def validate_pair(ids: np.ndarray, mask: np.ndarray) -> None:
    if ids.dtype.kind not in "iu" or mask.dtype.kind not in "iu":
        raise CalibError(
            f"calibration must be integer token ids and a 0/1 mask, got ids={ids.dtype} mask={mask.dtype}. "
            "Float arrays are the random-noise failure mode and are rejected."
        )
    if ids.ndim != 2 or mask.ndim != 2:
        raise CalibError(f"calibration rank must be 2, got ids={ids.shape} mask={mask.shape}")
    if ids.shape != mask.shape:
        raise CalibError(f"calibration shapes differ: ids={ids.shape} mask={mask.shape}")
    if ids.shape[1] != SEQ_LEN:
        raise CalibError(f"calibration seq is {ids.shape[1]}, contract is {SEQ_LEN}")
    if ids.shape[0] < MIN_ROWS:
        raise CalibError(f"calibration has {ids.shape[0]} rows, need at least {MIN_ROWS}")
    if int(ids.min()) < 0 or int(ids.max()) >= VOCAB:
        raise CalibError(f"token id outside [0, {VOCAB}): min={int(ids.min())} max={int(ids.max())}")
    mask_values = {int(v) for v in np.unique(mask)}
    if not mask_values <= {0, 1} or mask_values != {0, 1}:
        raise CalibError(f"attention mask must contain both 0 and 1, got {sorted(mask_values)}")
    pad = ids == PAD_ID
    masked = mask == 0
    if not np.array_equal(pad, masked):
        mismatch = int(np.count_nonzero(pad != masked))
        raise CalibError(
            f"attention mask does not match PAD id {PAD_ID} on {mismatch} positions. "
            "A mask that ignores padding is the Laya failure mode."
        )
    if int(np.count_nonzero(ids[:, 0] != CLS_ID)):
        raise CalibError(f"every calibration row must start with CLS {CLS_ID}")
    unique = len({row.tobytes() for row in np.ascontiguousarray(ids)})
    if unique < MIN_ROWS:
        raise CalibError(f"only {unique} unique calibration rows")
    density = float(mask.mean())
    if not 0.05 < density < 0.95:
        raise CalibError(
            f"mask mean {density:.4f} is degenerate. All-ones masks drop padding semantics."
        )


def stats(ids: np.ndarray, mask: np.ndarray, ids_path: Path, mask_path: Path) -> dict:
    return {
        "rows": int(ids.shape[0]),
        "seq": int(ids.shape[1]),
        "unique_rows": len({row.tobytes() for row in np.ascontiguousarray(ids)}),
        "mask_mean": float(mask.mean()),
        "pad_rate": float((ids == PAD_ID).mean()),
        "cls_id": CLS_ID,
        "pad_id": PAD_ID,
        "ids_sha256": sha256_file(ids_path),
        "mask_sha256": sha256_file(mask_path),
        "source": "committed tokenized pairs, not random noise",
        "required_rows": REQUIRED_ROWS,
    }


def fit_input(array: np.ndarray, rank_shape: tuple[int, ...] | list[int]) -> np.ndarray:
    """Match a Hailo input rank by inserting singleton axes. Never resamples values.

    `array` is (N, seq). A dynamic leading dim (-1 or 0) becomes N. Every other
    non-singleton dim must be seq, in order.
    """
    values = np.asarray(array)
    if values.ndim != 2:
        raise CalibError(f"calibration row block must be rank 2, got {values.shape}")
    if not rank_shape:
        raise CalibError("parsed input shape is empty")
    rows, seq = int(values.shape[0]), int(values.shape[1])
    target: list[int] = []
    for index, dim in enumerate(rank_shape):
        dim = int(dim)
        if index == 0 and dim in (-1, 0):
            target.append(rows)
        elif dim in (-1, 0):
            raise CalibError(f"only the batch dimension may be dynamic, got {rank_shape}")
        elif dim < 1:
            raise CalibError(f"cannot fit calibration into shape {rank_shape}")
        else:
            target.append(dim)
    if target[0] != rows:
        raise CalibError(f"parsed batch {target[0]} != calibration rows {rows}")
    reshape: list[int] = [rows]
    seq_used = False
    for dim in target[1:]:
        if dim == 1:
            reshape.append(1)
        elif dim == seq and not seq_used:
            reshape.append(seq)
            seq_used = True
        else:
            raise CalibError(f"calibration shape {values.shape} does not match parsed input {rank_shape}")
    if not seq_used:
        raise CalibError(f"parsed input {rank_shape} has no axis of length {seq}")
    fitted = values.reshape(reshape)
    if list(fitted.shape) != target:
        raise CalibError(f"fitted {fitted.shape} != parsed {target}")
    return np.ascontiguousarray(fitted)
