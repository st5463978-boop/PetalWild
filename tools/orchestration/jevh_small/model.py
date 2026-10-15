"""Static-shape Ettin/ModernBERT encoder + option scorer.

Written so the ONNX graph is Hailo-10H DFC friendly:
  - batch=1, seq=128 at export
  - input_ids and attention_mask are real graph inputs
  - attention_mask is added into attention scores (no Where/If/NonZero)
  - local-window bias is a constant buffer
  - no unpadding, flash-attn, Loop, or data-dependent reshape
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import torch
from torch import nn
from torch.nn import functional as F

SEQ_LEN = 128
# ettin-encoder-17m (jhu-clsp), ModernBERT-style
ETTIN17 = {
    "hidden_size": 256,
    "intermediate_size": 384,
    "num_attention_heads": 4,
    "num_hidden_layers": 7,
    "vocab_size": 50368,
    "pad_token_id": 50283,
    "norm_eps": 1e-5,
    "norm_bias": False,
    "mlp_bias": False,
    "attention_bias": False,
    "local_attention": 128,
    "global_attn_every_n_layers": 3,
    "rope_theta": 10000.0,
    "hidden_activation": "gelu",
}

# ettin-encoder-68m, for size/latency comparison in the receipt
ETTIN68 = {
    "hidden_size": 512,
    "intermediate_size": 768,
    "num_attention_heads": 8,
    "num_hidden_layers": 19,
    "vocab_size": 50368,
}


def _gelu(x: torch.Tensor) -> torch.Tensor:
    return F.gelu(x, approximate="none")


def rotate_half(x: torch.Tensor, half: int) -> torch.Tensor:
    x1 = x[..., :half]
    x2 = x[..., half:]
    return torch.cat((-x2, x1), dim=-1)


class EttinLayer(nn.Module):
    def __init__(self, cfg: dict, layer_idx: int, seq_len: int = SEQ_LEN):
        super().__init__()
        h = cfg["hidden_size"]
        n_heads = cfg["num_attention_heads"]
        self.hidden = h
        self.n_heads = n_heads
        self.head_dim = h // n_heads
        self.seq_len = seq_len
        self.layer_idx = layer_idx
        self.global_layer = (layer_idx % int(cfg["global_attn_every_n_layers"])) == 0
        self.attn_norm = (
            nn.Identity()
            if layer_idx == 0
            else nn.LayerNorm(h, eps=cfg["norm_eps"], bias=cfg["norm_bias"])
        )
        self.Wqkv = nn.Linear(h, 3 * h, bias=cfg["attention_bias"])
        self.Wo = nn.Linear(h, h, bias=cfg["attention_bias"])
        self.mlp_norm = nn.LayerNorm(h, eps=cfg["norm_eps"], bias=cfg["norm_bias"])
        self.intermediate = int(cfg["intermediate_size"])
        self.Wi = nn.Linear(h, self.intermediate * 2, bias=cfg["mlp_bias"])
        self.Wo_mlp = nn.Linear(self.intermediate, h, bias=cfg["mlp_bias"])
        half = int(cfg["local_attention"]) // 2
        win = torch.zeros(seq_len, seq_len, dtype=torch.float32)
        if not self.global_layer:
            pos = torch.arange(seq_len)
            dist = (pos[:, None] - pos[None, :]).abs()
            win = win.masked_fill(dist > half, -10000.0)
        self.register_buffer("window_bias", win.view(1, 1, seq_len, seq_len), persistent=False)
        self.static_shapes = False

    def forward(
        self,
        x: torch.Tensor,
        pad_bias: torch.Tensor,
        cos: torch.Tensor,
        sin: torch.Tensor,
    ) -> torch.Tensor:
        h = x
        a = self.attn_norm(x)
        half = self.head_dim // 2
        if self.static_shapes:
            qkv = self.Wqkv(a).view(1, self.seq_len, 3, self.n_heads, self.head_dim)
            q = qkv[:, :, 0].permute(0, 2, 1, 3)
            k = qkv[:, :, 1].permute(0, 2, 1, 3)
            v = qkv[:, :, 2].permute(0, 2, 1, 3)
            cos_u = cos.unsqueeze(0).unsqueeze(0)
            sin_u = sin.unsqueeze(0).unsqueeze(0)
            q = (q * cos_u) + (rotate_half(q, half) * sin_u)
            k = (k * cos_u) + (rotate_half(k, half) * sin_u)
            scale = self.head_dim ** -0.5
            scores = torch.matmul(q, k.transpose(-2, -1)) * scale
            scores = scores + pad_bias + self.window_bias
            attn = torch.softmax(scores, dim=-1)
            ctx = torch.matmul(attn, v).permute(0, 2, 1, 3).contiguous().view(1, self.seq_len, self.hidden)
        else:
            bsz, seq, hid = a.shape
            qkv = self.Wqkv(a).reshape(bsz, seq, 3, self.n_heads, self.head_dim)
            q = qkv[:, :, 0].permute(0, 2, 1, 3)
            k = qkv[:, :, 1].permute(0, 2, 1, 3)
            v = qkv[:, :, 2].permute(0, 2, 1, 3)
            cos_u = cos.unsqueeze(0).unsqueeze(0)
            sin_u = sin.unsqueeze(0).unsqueeze(0)
            q = (q * cos_u) + (rotate_half(q, half) * sin_u)
            k = (k * cos_u) + (rotate_half(k, half) * sin_u)
            scale = self.head_dim ** -0.5
            scores = torch.matmul(q, k.transpose(-2, -1)) * scale
            scores = scores + pad_bias + self.window_bias
            attn = torch.softmax(scores, dim=-1)
            ctx = torch.matmul(attn, v).permute(0, 2, 1, 3).reshape(bsz, seq, hid)
        h = h + self.Wo(ctx)
        mid = self.mlp_norm(h)
        wide = self.Wi(mid)
        inp = wide[..., : self.intermediate]
        gate = wide[..., self.intermediate :]
        h = h + self.Wo_mlp(_gelu(inp) * gate)
        return h


class EttinEncoder(nn.Module):
    def __init__(self, cfg: dict | None = None, seq_len: int = SEQ_LEN):
        super().__init__()
        cfg = dict(cfg or ETTIN17)
        self.cfg = cfg
        self.seq_len = seq_len
        h = cfg["hidden_size"]
        n_heads = cfg["num_attention_heads"]
        self.n_heads = n_heads
        self.head_dim = h // n_heads
        self.tok_embeddings = nn.Embedding(cfg["vocab_size"], h, padding_idx=cfg["pad_token_id"])
        self.embed_norm = nn.LayerNorm(h, eps=cfg["norm_eps"], bias=cfg["norm_bias"])
        self.layers = nn.ModuleList([EttinLayer(cfg, i, seq_len) for i in range(cfg["num_hidden_layers"])])
        self.final_norm = nn.LayerNorm(h, eps=cfg["norm_eps"], bias=cfg["norm_bias"])
        self._init_rope(cfg, seq_len)

    def _init_rope(self, cfg: dict, seq_len: int) -> None:
        dim = cfg["hidden_size"] // cfg["num_attention_heads"]
        theta = float(cfg["rope_theta"])
        inv = 1.0 / (theta ** (torch.arange(0, dim, 2, dtype=torch.float32) / dim))
        pos = torch.arange(seq_len, dtype=torch.float32)
        freqs = torch.outer(pos, inv)
        emb = torch.cat((freqs, freqs), dim=-1)
        self.register_buffer("rope_cos", emb.cos(), persistent=False)
        self.register_buffer("rope_sin", emb.sin(), persistent=False)

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        # attention_mask: [B, S] 1=token 0=pad. MUST affect the graph (Hailo DFC).
        mask = attention_mask.to(dtype=torch.float32)
        pad_bias = (mask - 1.0) * 10000.0
        pad_bias = pad_bias.unsqueeze(1).unsqueeze(2)
        x = self.embed_norm(self.tok_embeddings(input_ids))
        cos, sin = self.rope_cos, self.rope_sin
        for layer in self.layers:
            x = layer(x, pad_bias, cos, sin)
        return self.final_norm(x)


class OptionScorer(nn.Module):
    """One logit per (question, option) pair. Softmax is outside, over options."""

    def __init__(self, cfg: dict | None = None, seq_len: int = SEQ_LEN):
        super().__init__()
        cfg = dict(cfg or ETTIN17)
        self.encoder = EttinEncoder(cfg, seq_len)
        h = cfg["hidden_size"]
        self.head_fc = nn.Linear(h, h, bias=True)
        self.head_norm = nn.LayerNorm(h, eps=1e-5, bias=True)
        self.head_out = nn.Linear(h, 1, bias=True)
        nn.init.xavier_uniform_(self.head_fc.weight)
        nn.init.zeros_(self.head_fc.bias)
        nn.init.xavier_uniform_(self.head_out.weight)
        nn.init.zeros_(self.head_out.bias)

    def freeze_embeddings(self) -> None:
        for p in self.encoder.tok_embeddings.parameters():
            p.requires_grad = False

    def set_static_shapes(self, flag: bool = True) -> None:
        for layer in self.encoder.layers:
            layer.static_shapes = bool(flag)

    def n_params(self, trainable_only: bool = False) -> int:
        ps = self.parameters() if not trainable_only else (p for p in self.parameters() if p.requires_grad)
        return int(sum(p.numel() for p in ps))

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.encoder(input_ids, attention_mask)
        cls = hidden[:, 0]
        x = _gelu(self.head_fc(cls))
        x = self.head_norm(x)
        return self.head_out(x).squeeze(-1)


def remap_state_key(key: str) -> str | None:
    k = key
    for prefix in ("model.", "encoder."):
        if k.startswith(prefix):
            k = k[len(prefix) :]
    skip = ("decoder.", "head.", "cls.", "predictions.", "rotary_emb.")
    if any(k.startswith(s) or s in k for s in skip):
        if k.startswith("head.") or k.startswith("decoder.") or "rotary" in k:
            return None
    mapping = {
        "embeddings.tok_embeddings.weight": "tok_embeddings.weight",
        "embeddings.norm.weight": "embed_norm.weight",
        "embeddings.norm.bias": "embed_norm.bias",
        "final_norm.weight": "final_norm.weight",
        "final_norm.bias": "final_norm.bias",
    }
    if k in mapping:
        return mapping[k]
    # layers.N.attn.Wqkv.weight -> layers.N.Wqkv.weight
    if k.startswith("layers."):
        k = k.replace(".attn.Wqkv.", ".Wqkv.")
        k = k.replace(".attn.Wo.", ".Wo.")
        k = k.replace(".mlp.Wi.", ".Wi.")
        k = k.replace(".mlp.Wo.", ".Wo_mlp.")
        k = k.replace(".attn_norm.", ".attn_norm.")
        k = k.replace(".mlp_norm.", ".mlp_norm.")
        return k
    return None


def load_ettin_encoder_weights(encoder: EttinEncoder, blob: dict) -> dict[str, int]:
    if any(k.startswith("state_dict") for k in blob):
        blob = blob.get("state_dict", blob)
    remapped = {}
    skipped = 0
    for k, v in blob.items():
        nk = remap_state_key(k)
        if nk is None:
            skipped += 1
            continue
        remapped[nk] = v
    missing, unexpected = encoder.load_state_dict(remapped, strict=False)
    missing = [m for m in missing if "window_bias" not in m and "rope_" not in m]
    return {
        "loaded": len(remapped),
        "skipped": skipped,
        "missing": len(missing),
        "unexpected": len(unexpected),
        "missing_keys": missing[:20],
        "unexpected_keys": list(unexpected)[:20],
    }


def load_pretrained(scorer: OptionScorer, path: str | Path) -> dict[str, int]:
    path = Path(path)
    if path.suffix == ".safetensors":
        from safetensors.torch import load_file

        blob = load_file(str(path))
    else:
        try:
            blob = torch.load(str(path), map_location="cpu", weights_only=True)
        except Exception:
            blob = torch.load(str(path), map_location="cpu", weights_only=False)
        if not isinstance(blob, dict):
            raise TypeError(type(blob))
        if "model" in blob and isinstance(blob["model"], dict):
            blob = blob["model"]
    return load_ettin_encoder_weights(scorer.encoder, blob)


def ettin_param_count(cfg: dict) -> int:
    """Rough encoder parameter count (embeddings + layers + final norm)."""
    h = cfg["hidden_size"]
    i = cfg["intermediate_size"]
    v = cfg["vocab_size"]
    L = cfg["num_hidden_layers"]
    emb = v * h
    # Wqkv  h*3h, Wo h*h, Wi h*2i, Wo i*h, 2 LayerNorms (~h each, no bias)
    per = (h * 3 * h) + (h * h) + (h * 2 * i) + (i * h) + (2 * h)
    # layer 0 has no attn_norm
    return emb + L * per - h + h  # final norm


def write_config(path: Path, extra: dict | None = None) -> None:
    cfg = dict(ETTIN17)
    cfg["seq_len"] = SEQ_LEN
    cfg["backbone"] = "jhu-clsp/ettin-encoder-17m"
    cfg["pooling"] = "cls"
    cfg["head"] = "linear_gelu_ln_linear"
    if extra:
        cfg.update(extra)
    path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
