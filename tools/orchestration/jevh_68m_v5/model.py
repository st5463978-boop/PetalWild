"""Static-shape ettin-68m option scorer (ModernBERT encoder + CLS GELU head).

Forward always takes input_ids AND attention_mask. The mask is an additive
bias on attention scores (and therefore present in the ONNX graph). Seq len
and export batch are fixed at 128 and 1. No unpadding, no flash-attn, no
data-dependent shapes.
"""
from __future__ import annotations

import math
from pathlib import Path

import torch
from torch import nn
from torch.nn import functional as F

SEQ_LEN = 128
HIDDEN = 512
N_LAYERS = 19
N_HEADS = 8
HEAD_DIM = HIDDEN // N_HEADS  # 64
INTERMEDIATE = 768
VOCAB = 50368
PAD_ID = 50283
EPS = 1e-5
GLOBAL_EVERY = 3
LOCAL_WINDOW = 128  # tokens; half-window 64 each side
ROPE_THETA = 160000.0
ATTN_BIAS = -10000.0


def rotate_half(x: torch.Tensor) -> torch.Tensor:
    x1 = x[..., : HEAD_DIM // 2]
    x2 = x[..., HEAD_DIM // 2 :]
    return torch.cat((-x2, x1), dim=-1)


class BiaslessLN(nn.Module):
    def __init__(self, hidden: int = HIDDEN, eps: float = EPS):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(hidden))
        self.eps = eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        mu = x.mean(dim=-1, keepdim=True)
        var = (x - mu).pow(2).mean(dim=-1, keepdim=True)
        return (x - mu) * torch.rsqrt(var + self.eps) * self.weight


class EncoderLayer(nn.Module):
    def __init__(self, layer_idx: int):
        super().__init__()
        self.layer_idx = layer_idx
        self.is_global = (layer_idx % GLOBAL_EVERY) == 0
        self.attn_norm: nn.Module = nn.Identity() if layer_idx == 0 else BiaslessLN()
        self.Wqkv = nn.Linear(HIDDEN, 3 * HIDDEN, bias=False)
        self.Wo = nn.Linear(HIDDEN, HIDDEN, bias=False)
        self.mlp_norm = BiaslessLN()
        self.Wi = nn.Linear(HIDDEN, 2 * INTERMEDIATE, bias=False)
        self.Wo_mlp = nn.Linear(INTERMEDIATE, HIDDEN, bias=False)

    def forward(self, x: torch.Tensor, pad_bias: torch.Tensor, local_bias: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
        bsz, seq, _ = x.shape
        h = self.attn_norm(x)
        qkv = self.Wqkv(h).reshape(bsz, seq, 3, N_HEADS, HEAD_DIM)
        q = qkv[:, :, 0].permute(0, 2, 1, 3)
        k = qkv[:, :, 1].permute(0, 2, 1, 3)
        v = qkv[:, :, 2].permute(0, 2, 1, 3)
        q = (q * cos) + (rotate_half(q) * sin)
        k = (k * cos) + (rotate_half(k) * sin)
        attn = torch.matmul(q, k.transpose(-2, -1)) * (HEAD_DIM ** -0.5)
        attn = attn + pad_bias
        if not self.is_global:
            attn = attn + local_bias
        probs = torch.softmax(attn, dim=-1)
        ctx = torch.matmul(probs, v).permute(0, 2, 1, 3).reshape(bsz, seq, HIDDEN)
        x = x + self.Wo(ctx)
        m = self.mlp_norm(x)
        fused = self.Wi(m)
        inp = fused[..., :INTERMEDIATE]
        gate = fused[..., INTERMEDIATE:]
        x = x + self.Wo_mlp(F.gelu(inp) * gate)
        return x


class Ettin68mScorer(nn.Module):
    """One logit per (question, option) pair. Softmax is applied across options outside."""

    def __init__(self, seq_len: int = SEQ_LEN):
        super().__init__()
        self.seq_len = seq_len
        self.tok_embeddings = nn.Embedding(VOCAB, HIDDEN, padding_idx=PAD_ID)
        self.emb_norm = BiaslessLN()
        self.layers = nn.ModuleList([EncoderLayer(i) for i in range(N_LAYERS)])
        self.final_norm = BiaslessLN()
        self.head_dense = nn.Linear(HIDDEN, HIDDEN, bias=False)
        self.head_norm = BiaslessLN()
        self.head_out = nn.Linear(HIDDEN, 1, bias=True)
        nn.init.normal_(self.head_out.weight, std=HIDDEN ** -0.5)
        nn.init.zeros_(self.head_out.bias)
        self.grad_ckpt = False

        pos = torch.arange(seq_len, dtype=torch.float32)
        inv = 1.0 / (ROPE_THETA ** (torch.arange(0, HEAD_DIM, 2, dtype=torch.float32) / HEAD_DIM))
        freqs = torch.outer(pos, inv)
        emb = torch.cat((freqs, freqs), dim=-1)
        self.register_buffer("rope_cos", emb.cos().view(1, 1, seq_len, HEAD_DIM), persistent=False)
        self.register_buffer("rope_sin", emb.sin().view(1, 1, seq_len, HEAD_DIM), persistent=False)

        ii = torch.arange(seq_len).view(seq_len, 1)
        jj = torch.arange(seq_len).view(1, seq_len)
        half = LOCAL_WINDOW // 2
        local = ((ii - jj).abs() > half).to(torch.float32) * ATTN_BIAS
        self.register_buffer("local_bias", local.view(1, 1, seq_len, seq_len), persistent=False)

    def encode(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        """hidden [B, S, H]; attention_mask is 1 for real tokens, 0 for pad."""
        mask = attention_mask.to(dtype=torch.float32)
        pad_bias = (1.0 - mask).view(-1, 1, 1, self.seq_len) * ATTN_BIAS
        x = self.emb_norm(self.tok_embeddings(input_ids))
        cos = self.rope_cos
        sin = self.rope_sin
        local_bias = self.local_bias
        ckpt = bool(self.training and getattr(self, "grad_ckpt", False))
        for layer in self.layers:
            if ckpt:
                x = torch.utils.checkpoint.checkpoint(
                    layer, x, pad_bias, local_bias, cos, sin, use_reentrant=False
                )
            else:
                x = layer(x, pad_bias, local_bias, cos, sin)
        return self.final_norm(x)

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.encode(input_ids, attention_mask)
        cls = hidden[:, 0, :]
        h = self.head_norm(F.gelu(self.head_dense(cls)))
        return self.head_out(h)

    def freeze_for_cpu(self, unfreeze_last: int = 6) -> None:
        if unfreeze_last < 0 or unfreeze_last >= N_LAYERS:
            for p in self.parameters():
                p.requires_grad = True
            return
        for p in self.parameters():
            p.requires_grad = False
        keep = {self.final_norm, self.head_dense, self.head_norm, self.head_out}
        for m in keep:
            for p in m.parameters():
                p.requires_grad = True
        start = max(0, N_LAYERS - unfreeze_last)
        for layer in self.layers[start:]:
            for p in layer.parameters():
                p.requires_grad = True

    def layerwise_param_groups(
        self,
        base_lr: float,
        head_lr: float,
        embed_lr: float,
        decay: float,
    ) -> list[dict]:
        groups = [
            {
                "params": list(self.tok_embeddings.parameters()) + list(self.emb_norm.parameters()),
                "lr": embed_lr,
            }
        ]
        for i, layer in enumerate(self.layers):
            lr = base_lr * (decay ** (N_LAYERS - 1 - i))
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

    def load_ettin_encoder(self, bin_path: str | Path) -> list[str]:
        raw = torch.load(str(bin_path), map_location="cpu", weights_only=True)
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
                dest = dest.replace(".mlp.Wi.weight", ".Wi.weight")
                dest = dest.replace(".mlp.Wo.weight", ".Wo_mlp.weight")
            else:
                skipped.append(k)
                continue
            if dest in own and own[dest].shape == v.shape:
                mapped[dest] = v
            else:
                skipped.append(k)
        missing, unexpected = self.load_state_dict(mapped, strict=False)
        return [m for m in missing if "head_out" not in m] + skipped[:0]


def load_backbone(model: Ettin68mScorer, hf_dir: str | Path) -> list[str]:
    path = Path(hf_dir) / "pytorch_model.bin"
    if not path.is_file():
        raise FileNotFoundError(path)
    return model.load_ettin_encoder(path)
