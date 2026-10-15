"""Hailo-friendly static Ettin/ModernBERT encoder + option scorer.

The HuggingFace ModernBERT path unpads with NonZero and uses flash/SDPA kernels.
This module is a padded, fixed-seq eager reimplementation so training and ONNX
export share one graph: explicit input_ids + attention_mask, no data-dependent
shapes, no Loop/If/NonZero.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import torch
from torch import nn

NEG_INF = -1.0e4


def gelu_erf(x: torch.Tensor) -> torch.Tensor:
    """GELU (erf), decomposed so ONNX opset 13-17 does not emit a Gelu node."""
    return 0.5 * x * (1.0 + torch.erf(x / math.sqrt(2.0)))


def rotate_half(x: torch.Tensor) -> torch.Tensor:
    x1, x2 = x.chunk(2, dim=-1)
    return torch.cat((-x2, x1), dim=-1)


@dataclass
class EttinCfg:
    vocab_size: int = 50368
    hidden_size: int = 768
    num_hidden_layers: int = 22
    num_attention_heads: int = 12
    intermediate_size: int = 1152
    norm_eps: float = 1e-5
    pad_token_id: int = 50283
    local_attention: int = 128
    global_attn_every_n_layers: int = 3
    global_rope_theta: float = 160000.0
    local_rope_theta: float = 160000.0
    attention_bias: bool = False
    mlp_bias: bool = False
    norm_bias: bool = False
    classifier_bias: bool = False

    @property
    def head_dim(self) -> int:
        return self.hidden_size // self.num_attention_heads

    @classmethod
    def from_hf(cls, cfg: Any) -> "EttinCfg":
        return cls(
            vocab_size=int(cfg.vocab_size),
            hidden_size=int(cfg.hidden_size),
            num_hidden_layers=int(cfg.num_hidden_layers),
            num_attention_heads=int(cfg.num_attention_heads),
            intermediate_size=int(cfg.intermediate_size),
            norm_eps=float(getattr(cfg, "norm_eps", getattr(cfg, "layer_norm_eps", 1e-5))),
            pad_token_id=int(cfg.pad_token_id),
            local_attention=int(cfg.local_attention),
            global_attn_every_n_layers=int(cfg.global_attn_every_n_layers),
            global_rope_theta=float(cfg.global_rope_theta),
            local_rope_theta=float(getattr(cfg, "local_rope_theta", cfg.global_rope_theta) or cfg.global_rope_theta),
            attention_bias=bool(cfg.attention_bias),
            mlp_bias=bool(cfg.mlp_bias),
            norm_bias=bool(cfg.norm_bias),
            classifier_bias=bool(getattr(cfg, "classifier_bias", False)),
        )

    def tiny(self) -> "EttinCfg":
        return EttinCfg(
            vocab_size=128,
            hidden_size=64,
            num_hidden_layers=2,
            num_attention_heads=4,
            intermediate_size=96,
            pad_token_id=0,
            local_attention=128,
            global_attn_every_n_layers=2,
        )


class EttinMLP(nn.Module):
    def __init__(self, cfg: EttinCfg) -> None:
        super().__init__()
        self.Wi = nn.Linear(cfg.hidden_size, int(cfg.intermediate_size) * 2, bias=cfg.mlp_bias)
        self.Wo = nn.Linear(cfg.intermediate_size, cfg.hidden_size, bias=cfg.mlp_bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        u, gate = self.Wi(x).chunk(2, dim=-1)
        return self.Wo(gelu_erf(u) * gate)


class EttinAttention(nn.Module):
    def __init__(self, cfg: EttinCfg, layer_id: int, seq_len: int, export_batch: int | None = None) -> None:
        super().__init__()
        self.num_heads = cfg.num_attention_heads
        self.head_dim = cfg.head_dim
        self.hidden_size = cfg.hidden_size
        self.seq_len = seq_len
        self.export_batch = export_batch
        self.is_local = (layer_id % cfg.global_attn_every_n_layers) != 0
        theta = cfg.local_rope_theta if self.is_local else cfg.global_rope_theta
        self.Wqkv = nn.Linear(cfg.hidden_size, 3 * cfg.hidden_size, bias=cfg.attention_bias)
        self.Wo = nn.Linear(cfg.hidden_size, cfg.hidden_size, bias=cfg.attention_bias)
        inv = 1.0 / (theta ** (torch.arange(0, self.head_dim, 2, dtype=torch.float32) / self.head_dim))
        pos = torch.arange(seq_len, dtype=torch.float32)
        freqs = torch.outer(pos, inv)
        emb = torch.cat((freqs, freqs), dim=-1)
        self.register_buffer("cos", emb.cos().view(1, 1, seq_len, self.head_dim), persistent=False)
        self.register_buffer("sin", emb.sin().view(1, 1, seq_len, self.head_dim), persistent=False)
        if self.is_local:
            idx = torch.arange(seq_len)
            dist = (idx[:, None] - idx[None, :]).abs()
            inside = dist <= (cfg.local_attention // 2)
            bias = torch.zeros(seq_len, seq_len, dtype=torch.float32)
            bias = bias.masked_fill(~inside, NEG_INF)
            window = bias.view(1, 1, seq_len, seq_len)
        else:
            window = torch.zeros(1, 1, seq_len, seq_len)
        self.register_buffer("window_bias", window, persistent=False)

    def forward(self, hidden: torch.Tensor, pad_bias: torch.Tensor) -> torch.Tensor:
        # Python ints (export_batch, seq_len) fold into a constant Reshape for Hailo.
        bsz = self.export_batch if self.export_batch is not None else hidden.shape[0]
        seq = self.seq_len
        qkv = self.Wqkv(hidden).reshape(bsz, seq, 3, self.num_heads, self.head_dim)
        q = qkv[:, :, 0].permute(0, 2, 1, 3)
        k = qkv[:, :, 1].permute(0, 2, 1, 3)
        v = qkv[:, :, 2].permute(0, 2, 1, 3)
        q = (q * self.cos) + (rotate_half(q) * self.sin)
        k = (k * self.cos) + (rotate_half(k) * self.sin)
        scale = self.head_dim ** -0.5
        scores = torch.matmul(q, k.transpose(2, 3)) * scale
        scores = scores + pad_bias + self.window_bias
        probs = torch.softmax(scores, dim=-1, dtype=torch.float32).to(v.dtype)
        ctx = torch.matmul(probs, v).permute(0, 2, 1, 3).contiguous()
        ctx = ctx.reshape(bsz, seq, self.hidden_size)
        return self.Wo(ctx)


class EttinLayer(nn.Module):
    def __init__(self, cfg: EttinCfg, layer_id: int, seq_len: int, export_batch: int | None = None) -> None:
        super().__init__()
        if layer_id == 0:
            self.attn_norm = nn.Identity()
        else:
            self.attn_norm = nn.LayerNorm(cfg.hidden_size, eps=cfg.norm_eps, bias=cfg.norm_bias)
        self.attn = EttinAttention(cfg, layer_id, seq_len, export_batch=export_batch)
        self.mlp_norm = nn.LayerNorm(cfg.hidden_size, eps=cfg.norm_eps, bias=cfg.norm_bias)
        self.mlp = EttinMLP(cfg)

    def forward(self, hidden: torch.Tensor, pad_bias: torch.Tensor) -> torch.Tensor:
        hidden = hidden + self.attn(self.attn_norm(hidden), pad_bias)
        hidden = hidden + self.mlp(self.mlp_norm(hidden))
        return hidden


class StaticEttinEncoder(nn.Module):
    def __init__(self, cfg: EttinCfg, seq_len: int, export_batch: int | None = None) -> None:
        super().__init__()
        self.cfg = cfg
        self.seq_len = seq_len
        self.export_batch = export_batch
        self.embeddings = nn.ModuleDict(
            {
                "tok_embeddings": nn.Embedding(cfg.vocab_size, cfg.hidden_size, padding_idx=cfg.pad_token_id),
                "norm": nn.LayerNorm(cfg.hidden_size, eps=cfg.norm_eps, bias=cfg.norm_bias),
            }
        )
        self.layers = nn.ModuleList(
            [EttinLayer(cfg, i, seq_len, export_batch=export_batch) for i in range(cfg.num_hidden_layers)]
        )
        self.final_norm = nn.LayerNorm(cfg.hidden_size, eps=cfg.norm_eps, bias=cfg.norm_bias)
        self.gradient_checkpointing = False

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.embeddings["norm"](self.embeddings["tok_embeddings"](input_ids))
        mask_f = attention_mask.to(dtype=hidden.dtype)
        pad_bias = (1.0 - mask_f) * NEG_INF
        pad_bias = pad_bias[:, None, None, :]
        for layer in self.layers:
            if self.gradient_checkpointing and self.training:
                hidden = torch.utils.checkpoint.checkpoint(layer, hidden, pad_bias, use_reentrant=False)
            else:
                hidden = layer(hidden, pad_bias)
        return self.final_norm(hidden)

    def load_hf_encoder(self, state: dict[str, torch.Tensor]) -> tuple[list[str], list[str]]:
        mapped: dict[str, torch.Tensor] = {}
        for key, value in state.items():
            k = key[6:] if key.startswith("model.") else key
            if k.startswith("rotary_emb") or ".rotary_emb." in k:
                continue
            mapped[k] = value
        incompatible = self.load_state_dict(mapped, strict=False)
        return list(incompatible.missing_keys), list(incompatible.unexpected_keys)


class ScoreHead(nn.Module):
    """ModernBERT prediction head + scalar classifier (mean-pooled)."""

    def __init__(self, cfg: EttinCfg) -> None:
        super().__init__()
        self.dense = nn.Linear(cfg.hidden_size, cfg.hidden_size, bias=cfg.classifier_bias)
        self.norm = nn.LayerNorm(cfg.hidden_size, eps=cfg.norm_eps, bias=cfg.norm_bias)
        self.classifier = nn.Linear(cfg.hidden_size, 1, bias=True)

    def forward(self, pooled: torch.Tensor) -> torch.Tensor:
        return self.classifier(self.norm(gelu_erf(self.dense(pooled))))


class PairScorer(nn.Module):
    """One (question, option) pair -> scalar logit. Mask is used in attention and pooling."""

    def __init__(self, cfg: EttinCfg, seq_len: int, export_batch: int | None = None) -> None:
        super().__init__()
        self.cfg = cfg
        self.seq_len = seq_len
        self.export_batch = export_batch
        self.encoder = StaticEttinEncoder(cfg, seq_len, export_batch=export_batch)
        self.head = ScoreHead(cfg)

    def pool(self, hidden: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        mask = attention_mask.to(dtype=hidden.dtype).unsqueeze(-1)
        denom = mask.sum(dim=1).clamp(min=1.0)
        return (hidden * mask).sum(dim=1) / denom

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.encoder(input_ids, attention_mask)
        pooled = self.pool(hidden, attention_mask)
        return self.head(pooled)

    def freeze_bottom_layers(self, n_freeze: int, freeze_embeddings: bool = True) -> int:
        frozen = 0
        for p in self.parameters():
            p.requires_grad = True
        for i, layer in enumerate(self.encoder.layers):
            if i < n_freeze:
                for p in layer.parameters():
                    p.requires_grad = False
                    frozen += p.numel()
        if freeze_embeddings:
            for p in self.encoder.embeddings.parameters():
                p.requires_grad = False
                frozen += p.numel()
        return frozen

    def layerwise_param_groups(self, base_lr: float, head_lr: float, decay: float = 0.9) -> list[dict]:
        """Higher layers get higher LR. Frozen params are skipped."""
        n = len(self.encoder.layers)
        groups: list[dict] = []
        emb = [p for p in self.encoder.embeddings.parameters() if p.requires_grad]
        if emb:
            groups.append({"params": emb, "lr": base_lr * (decay ** n)})
        for i, layer in enumerate(self.encoder.layers):
            params = [p for p in layer.parameters() if p.requires_grad]
            if params:
                groups.append({"params": params, "lr": base_lr * (decay ** (n - 1 - i))})
        fn = [p for p in self.encoder.final_norm.parameters() if p.requires_grad]
        if fn:
            groups.append({"params": fn, "lr": base_lr})
        head = [p for p in self.head.parameters() if p.requires_grad]
        if head:
            groups.append({"params": head, "lr": head_lr})
        return groups

    def clone_for_seq(self, seq_len: int, export_batch: int | None = None) -> "PairScorer":
        other = PairScorer(self.cfg, seq_len, export_batch=export_batch)
        src = self.state_dict()
        dst = other.state_dict()
        transferred = {k: v for k, v in src.items() if k in dst and dst[k].shape == v.shape}
        other.load_state_dict(transferred, strict=False)
        return other

    def as_export(self, seq_len: int | None = None) -> "PairScorer":
        return self.clone_for_seq(seq_len or self.seq_len, export_batch=1).eval()


def count_params(model: nn.Module) -> tuple[int, int]:
    total = sum(p.numel() for p in model.parameters())
    train = sum(p.numel() for p in model.parameters() if p.requires_grad)
    return total, train
