"""Download only the Clef-Flash tensors this experiment needs.

The full checkpoint is about 19 GB. Safetensors stores a JSON header plus
contiguous tensor bytes, so each tensor is fetched with an HTTP range request.
Original Hub files are never modified.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import httpx
import torch
from huggingface_hub import hf_hub_url
from safetensors.torch import save_file

REPO = "Cloudflare/clef-flash"
ROOT = Path(__file__).resolve().parents[1]
WEIGHTS = ROOT / "artifacts" / "weights"


def _header(client: httpx.Client, url: str) -> tuple[int, dict]:
    size = struct.unpack("<Q", client.get(url, headers={"Range": "bytes=0-7"}).content)[0]
    raw = client.get(url, headers={"Range": f"bytes=8-{8 + size - 1}"}).content
    return size, json.loads(raw)


_DTYPE = {
    "BF16": torch.bfloat16,
    "F16": torch.float16,
    "F32": torch.float32,
    "F64": torch.float64,
    "I64": torch.int64,
    "I32": torch.int32,
    "U8": torch.uint8,
}


def _fetch_tensor(client: httpx.Client, url: str, header_size: int, spec: dict) -> torch.Tensor:
    start, end = spec["data_offsets"]
    absolute = 8 + header_size + start
    raw = client.get(url, headers={"Range": f"bytes={absolute}-{absolute + (end - start) - 1}"}).content
    if len(raw) != end - start:
        raise RuntimeError(f"short read {len(raw)} != {end - start}")
    dtype = _DTYPE[spec["dtype"]]
    tensor = torch.frombuffer(bytearray(raw), dtype=dtype).reshape(spec["shape"])
    return tensor.clone()


def fetch_keys(shard: str, keys: list[str], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    url = hf_hub_url(REPO, shard)
    with httpx.Client(follow_redirects=True, timeout=300) as client:
        header_size, meta = _header(client, url)
        missing = [key for key in keys if key not in meta]
        if missing:
            raise KeyError(missing)
        tensors = {}
        for key in keys:
            tensors[key] = _fetch_tensor(client, url, header_size, meta[key])
            print(f"  {key} {tuple(tensors[key].shape)}", flush=True)
    save_file(tensors, destination)
    print(f"wrote {destination} ({destination.stat().st_size / 1e6:.1f} MB, {len(tensors)} tensors)")


def layer_keys(index_path: Path, layer: int) -> tuple[str, list[str]]:
    weight_map = json.loads(index_path.read_text())["weight_map"]
    prefix = f"model.language_model.layers.{layer}."
    chosen = [(key, shard) for key, shard in weight_map.items() if key.startswith(prefix)]
    shards = {shard for _, shard in chosen}
    if len(shards) != 1:
        raise RuntimeError(f"layer {layer} spans shards {shards}")
    return shards.pop(), [key for key, _ in chosen]


def main() -> None:
    index = WEIGHTS / "model.safetensors.index.json"
    if not index.exists():
        from huggingface_hub import hf_hub_download

        hf_hub_download(REPO, "model.safetensors.index.json", local_dir=WEIGHTS)
    for layer in (0, 3):
        shard, keys = layer_keys(index, layer)
        fetch_keys(shard, keys, WEIGHTS / f"clef_layer_{layer}.safetensors")


if __name__ == "__main__":
    main()
