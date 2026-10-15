"""Tiny static-shape pair scorer for Hailo-10H DFC.

input_ids AND attention_mask are real graph inputs. The mask is added into
every attention score (pad -> large negative). No RoPE, Loop, If, NonZero,
or data-dependent reshape. Export with batch=1, seq=128.
"""

from __future__ import annotations

import math

import torch
from torch import nn

from .config import D_FF, D_MODEL, DROPOUT, N_HEADS, N_LAYERS, PAD_ID, SEQ_LEN, VOCAB_SIZE


class EncoderLayer(nn.Module):
    def __init__(self, d: int, n_heads: int, d_ff: int, dropout: float):
        super().__init__()
        if d % n_heads != 0:
            raise ValueError("d_model must divide n_heads")
        self.n_heads = n_heads
        self.head_dim = d // n_heads
        self.scale = 1.0 / math.sqrt(self.head_dim)
        self.wq = nn.Linear(d, d)
        self.wk = nn.Linear(d, d)
        self.wv = nn.Linear(d, d)
        self.wo = nn.Linear(d, d)
        self.d1 = nn.Dropout(dropout)
        self.ln1 = nn.LayerNorm(d)
        self.ff = nn.Sequential(
            nn.Linear(d, d_ff),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_ff, d),
            nn.Dropout(dropout),
        )
        self.ln2 = nn.LayerNorm(d)

    def forward(self, x: torch.Tensor, attn_bias: torch.Tensor, static_bs: tuple[int, int] | None = None) -> torch.Tensor:
        # x: [B, S, D], attn_bias: [B, 1, 1, S]
        if static_bs is not None:
            b, s = static_bs  # python constants at ONNX export (not an ONNX If)
        else:
            b, s = x.shape[0], x.shape[1]
        h = self.n_heads
        hd = self.head_dim
        d = h * hd
        q = self.wq(x).reshape(b, s, h, hd).transpose(1, 2)
        k = self.wk(x).reshape(b, s, h, hd).transpose(1, 2)
        v = self.wv(x).reshape(b, s, h, hd).transpose(1, 2)
        scores = torch.matmul(q, k.transpose(-2, -1)) * self.scale
        scores = scores + attn_bias
        probs = torch.softmax(scores, dim=-1)
        ctx = torch.matmul(probs, v).transpose(1, 2).contiguous().reshape(b, s, d)
        x = self.ln1(x + self.d1(self.wo(ctx)))
        x = self.ln2(x + self.ff(x))
        return x


class PairScorer(nn.Module):
    def __init__(
        self,
        vocab_size: int = VOCAB_SIZE,
        d_model: int = D_MODEL,
        n_layers: int = N_LAYERS,
        n_heads: int = N_HEADS,
        d_ff: int = D_FF,
        seq_len: int = SEQ_LEN,
        dropout: float = DROPOUT,
        pad_id: int = PAD_ID,
    ):
        super().__init__()
        self.seq_len = seq_len
        self.pad_id = pad_id
        self.export_static = False
        self.tok = nn.Embedding(vocab_size, d_model, padding_idx=pad_id)
        self.pos = nn.Embedding(seq_len, d_model)
        self.emb_ln = nn.LayerNorm(d_model)
        self.emb_drop = nn.Dropout(dropout)
        self.layers = nn.ModuleList(
            [EncoderLayer(d_model, n_heads, d_ff, dropout) for _ in range(n_layers)]
        )
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model),
            nn.GELU(),
            nn.Linear(d_model, 1),
        )
        self.register_buffer("pos_ids", torch.arange(seq_len).unsqueeze(0), persistent=False)

    def _bias(self, attention_mask: torch.Tensor) -> torch.Tensor:
        # attention_mask: [B, S] 1=real 0=pad. Used in-graph (not dropped).
        m = attention_mask.to(dtype=torch.float32)
        # 0 -> -1e4, 1 -> 0
        return (m - 1.0) * 1e4

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        # input_ids, attention_mask: [B, S] -> logit [B, 1]
        # pos_ids is a fixed [1, SEQ] buffer — no data-dependent slice.
        x = self.tok(input_ids) + self.pos(self.pos_ids)
        x = self.emb_drop(self.emb_ln(x))
        bias = self._bias(attention_mask).unsqueeze(1).unsqueeze(2)  # [B,1,1,S]
        static = (1, self.seq_len) if self.export_static else None
        for layer in self.layers:
            x = layer(x, bias, static)
        cls = x[:, 0, :]
        return self.head(cls)

    def n_params(self) -> int:
        return sum(p.numel() for p in self.parameters())
