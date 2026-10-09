"""Ettin encoder option scorer (68m recipe + 17m fallback).

Copied in spirit from tools/orchestration/jevh_68m_v5/model.py on
cursor/jevh-variant-68m-v5-f666 (not merged). Static seq 128, batch 1.
input_ids AND attention_mask are real graph inputs; the mask is an additive
attention bias. No unpadding, no flash-attn, no data-dependent shapes.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import torch
from torch import nn
from torch.nn import functional as F

SEQ_LEN = 128
VOCAB = 50368
PAD_ID = 50283
EPS = 1e-5
GLOBAL_EVERY = 3
LOCAL_WINDOW = 128
ROPE_THETA = 160000.0
ATTN_BIAS = -10000.0


@dataclass(frozen=True)
class EttinSize:
    name: str
    hf_id: str
    hidden: int
    n_layers: int
    n_heads: int
    intermediate: int

    @property
    def head_dim(self) -> int:
        return self.hidden // self.n_heads


SIZE_68M = EttinSize("68m", "jhu-clsp/ettin-encoder-68m", 512, 19, 8, 768)
SIZE_17M = EttinSize("17m", "jhu-clsp/ettin-encoder-17m", 256, 7, 4, 384)
SIZES = {"68m": SIZE_68M, "17m": SIZE_17M, "68m-v5": SIZE_68M}


def rotate_half(x: torch.Tensor) -> torch.Tensor:
    d = x.shape[-1] // 2
    x1 = x[..., :d]
    x2 = x[..., d:]
    return torch.cat((-x2, x1), dim=-1)


class BiaslessLN(nn.Module):
    def __init__(self, hidden: int, eps: float = EPS):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(hidden))
        self.eps = eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        mu = x.mean(dim=-1, keepdim=True)
        var = (x - mu).pow(2).mean(dim=-1, keepdim=True)
        return (x - mu) * torch.rsqrt(var + self.eps) * self.weight


class EncoderLayer(nn.Module):
    def __init__(self, layer_idx: int, size: EttinSize):
        super().__init__()
        self.layer_idx = layer_idx
        self.size = size
        self.is_global = (layer_idx % GLOBAL_EVERY) == 0
        self.attn_norm: nn.Module = nn.Identity() if layer_idx == 0 else BiaslessLN(size.hidden)
        self.Wqkv = nn.Linear(size.hidden, 3 * size.hidden, bias=False)
        self.Wo = nn.Linear(size.hidden, size.hidden, bias=False)
        self.mlp_norm = BiaslessLN(size.hidden)
        self.Wi = nn.Linear(size.hidden, 2 * size.intermediate, bias=False)
        self.Wo_mlp = nn.Linear(size.intermediate, size.hidden, bias=False)

    def forward(
        self,
        x: torch.Tensor,
        pad_bias: torch.Tensor,
        local_bias: torch.Tensor,
        cos: torch.Tensor,
        sin: torch.Tensor,
    ) -> torch.Tensor:
        bsz, seq, _ = x.shape
        h = self.size.n_heads
        hd = self.size.head_dim
        hid = self.size.hidden
        mid = self.size.intermediate
        hdn = self.attn_norm(x)
        qkv = self.Wqkv(hdn).reshape(bsz, seq, 3, h, hd)
        q = qkv[:, :, 0].permute(0, 2, 1, 3)
        k = qkv[:, :, 1].permute(0, 2, 1, 3)
        v = qkv[:, :, 2].permute(0, 2, 1, 3)
        q = (q * cos) + (rotate_half(q) * sin)
        k = (k * cos) + (rotate_half(k) * sin)
        attn = torch.matmul(q, k.transpose(-2, -1)) * (hd ** -0.5)
        attn = attn + pad_bias
        if not self.is_global:
            attn = attn + local_bias
        probs = torch.softmax(attn, dim=-1)
        ctx = torch.matmul(probs, v).permute(0, 2, 1, 3).reshape(bsz, seq, hid)
        x = x + self.Wo(ctx)
        m = self.mlp_norm(x)
        fused = self.Wi(m)
        inp = fused[..., :mid]
        gate = fused[..., mid:]
        x = x + self.Wo_mlp(F.gelu(inp) * gate)
        return x


class EttinScorer(nn.Module):
    """One logit per (question, option) pair. Softmax is across options outside."""

    def __init__(self, size: EttinSize = SIZE_68M, seq_len: int = SEQ_LEN):
        super().__init__()
        self.size = size
        self.seq_len = seq_len
        hid = size.hidden
        self.tok_embeddings = nn.Embedding(VOCAB, hid, padding_idx=PAD_ID)
        self.emb_norm = BiaslessLN(hid)
        self.layers = nn.ModuleList([EncoderLayer(i, size) for i in range(size.n_layers)])
        self.final_norm = BiaslessLN(hid)
        self.head_dense = nn.Linear(hid, hid, bias=False)
        self.head_norm = BiaslessLN(hid)
        self.head_out = nn.Linear(hid, 1, bias=True)
        nn.init.normal_(self.head_out.weight, std=hid ** -0.5)
        nn.init.zeros_(self.head_out.bias)
        self.grad_ckpt = False

        hd = size.head_dim
        pos = torch.arange(seq_len, dtype=torch.float32)
        inv = 1.0 / (ROPE_THETA ** (torch.arange(0, hd, 2, dtype=torch.float32) / hd))
        freqs = torch.outer(pos, inv)
        emb = torch.cat((freqs, freqs), dim=-1)
        self.register_buffer("rope_cos", emb.cos().view(1, 1, seq_len, hd), persistent=False)
        self.register_buffer("rope_sin", emb.sin().view(1, 1, seq_len, hd), persistent=False)
        ii = torch.arange(seq_len).view(seq_len, 1)
        jj = torch.arange(seq_len).view(1, seq_len)
        half = LOCAL_WINDOW // 2
        local = ((ii - jj).abs() > half).to(torch.float32) * ATTN_BIAS
        self.register_buffer("local_bias", local.view(1, 1, seq_len, seq_len), persistent=False)

    def encode(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        mask = attention_mask.to(dtype=torch.float32)
        pad_bias = (1.0 - mask).view(-1, 1, 1, self.seq_len) * ATTN_BIAS
        x = self.emb_norm(self.tok_embeddings(input_ids))
        ckpt = bool(self.training and getattr(self, "grad_ckpt", False))
        for layer in self.layers:
            if ckpt:
                x = torch.utils.checkpoint.checkpoint(
                    layer, x, pad_bias, self.local_bias, self.rope_cos, self.rope_sin, use_reentrant=False
                )
            else:
                x = layer(x, pad_bias, self.local_bias, self.rope_cos, self.rope_sin)
        return self.final_norm(x)

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.encode(input_ids, attention_mask)
        cls = hidden[:, 0, :]
        h = self.head_norm(F.gelu(self.head_dense(cls)))
        return self.head_out(h)

    def freeze_for_cpu(self, unfreeze_last: int = 6) -> None:
        n = self.size.n_layers
        if unfreeze_last < 0 or unfreeze_last >= n:
            for p in self.parameters():
                p.requires_grad = True
            return
        for p in self.parameters():
            p.requires_grad = False
        for m in (self.final_norm, self.head_dense, self.head_norm, self.head_out):
            for p in m.parameters():
                p.requires_grad = True
        start = max(0, n - unfreeze_last)
        for layer in self.layers[start:]:
            for p in layer.parameters():
                p.requires_grad = True

    def layerwise_param_groups(self, base_lr: float, head_lr: float, embed_lr: float, decay: float) -> list[dict]:
        groups = [
            {
                "params": list(self.tok_embeddings.parameters()) + list(self.emb_norm.parameters()),
                "lr": embed_lr,
            }
        ]
        n = self.size.n_layers
        for i, layer in enumerate(self.layers):
            lr = base_lr * (decay ** (n - 1 - i))
            groups.append({"params": list(layer.parameters()), "lr": lr})
        groups.append({"params": list(self.final_norm.parameters()), "lr": base_lr})
        groups.append(
            {
                "params": list(self.head_dense.parameters())
                + list(self.head_norm.parameters())
                + list(self.head_out.parameters()),
                "lr": head_lr,
            }
        )
        return groups

    def load_ettin_encoder(self, raw: dict) -> list[str]:
        own = self.state_dict()
        mapped: dict[str, torch.Tensor] = {}
        skipped = []
        for k, v in raw.items():
            nk = k[6:] if k.startswith("model.") else k
            aliases = {
                "embeddings.tok_embeddings.weight": "tok_embeddings.weight",
                "embeddings.norm.weight": "emb_norm.weight",
                "final_norm.weight": "final_norm.weight",
                "head.dense.weight": "head_dense.weight",
                "head.norm.weight": "head_norm.weight",
            }
            if nk in aliases:
                dest = aliases[nk]
            elif nk.startswith("layers."):
                dest = nk.replace(".attn.Wqkv.weight", ".Wqkv.weight")
                dest = dest.replace(".attn.Wo.weight", ".Wo.weight")
                dest = dest.replace(".attn.norm.weight", ".attn_norm.weight")
                dest = dest.replace(".mlp.Wi.weight", ".Wi.weight")
                dest = dest.replace(".mlp.Wo.weight", ".Wo_mlp.weight")
                dest = dest.replace(".mlp.norm.weight", ".mlp_norm.weight")
            else:
                skipped.append(k)
                continue
            if dest in own and own[dest].shape == v.shape:
                mapped[dest] = v
            else:
                skipped.append(k)
        missing, unexpected = self.load_state_dict(mapped, strict=False)
        _ = unexpected
        return [m for m in missing if "head_out" not in m]


def load_backbone(model: EttinScorer, hf_dir: str | Path) -> list[str]:
    path = Path(hf_dir)
    bin_path = path / "pytorch_model.bin"
    if bin_path.is_file():
        try:
            raw = torch.load(str(bin_path), map_location="cpu", weights_only=True)
        except TypeError:
            raw = torch.load(str(bin_path), map_location="cpu")
        return model.load_ettin_encoder(raw)
    st = path / "model.safetensors"
    if st.is_file():
        from safetensors.torch import load_file

        return model.load_ettin_encoder(load_file(str(st)))
    raise FileNotFoundError(f"no pytorch_model.bin or model.safetensors in {path}")


def n_params(model: nn.Module) -> tuple[int, int]:
    all_n = sum(p.numel() for p in model.parameters())
    train_n = sum(p.numel() for p in model.parameters() if p.requires_grad)
    return all_n, train_n
