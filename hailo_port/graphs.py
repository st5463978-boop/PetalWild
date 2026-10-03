"""Static export wrappers around unmodified Clef / Qwen3.5 modules.

RoPE recomposition and token-span pooling stay on the host. The recurrent
gated-delta scan writes its outputs with a stack instead of in-place slices,
because the stock implementation exports those writes as ScatterElements.
"""

from __future__ import annotations

import math

import torch
import torch.nn.functional as F
from transformers.models.qwen3_5.modeling_qwen3_5 import (
    causal_conv1d_fn,
    l2norm,
)


def causal_mask(hidden: torch.Tensor) -> torch.Tensor:
    """Additive mask. Eager attention does not imply causality when the mask is absent."""

    length = hidden.shape[1]
    allowed = torch.ones(length, length, dtype=torch.bool, device=hidden.device).tril()
    return torch.zeros(1, 1, length, length, dtype=hidden.dtype, device=hidden.device).masked_fill(
        ~allowed, torch.finfo(hidden.dtype).min
    )


class FullAttentionBlock(torch.nn.Module):
    """One Qwen3.5 full-attention decoder block. cos/sin are host inputs."""

    def __init__(self, layer: torch.nn.Module):
        super().__init__()
        self.layer = layer

    def forward(self, hidden: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
        return self.layer(
            hidden,
            position_embeddings=(cos, sin),
            attention_mask=causal_mask(hidden),
        )


class FullAttentionBlockWithoutRope(torch.nn.Module):
    """Same block as ``FullAttentionBlock``, with rotary application removed.

    Hailo DFC 5.4.0 parses this graph. The unmodified block, whose RoPE uses
    ``rotate_half`` (negate one half, then concatenate), dies in the fuser at
    ``_handle_neg_feature_shuffle`` with ``IndexError: list assignment index out of range``.
    Position must be applied on the host, or the block must be split around Q and K.
    """

    def __init__(self, layer: torch.nn.Module):
        super().__init__()
        self.layer = layer

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

        attention = self.layer.self_attn
        residual = hidden
        normalized = self.layer.input_layernorm(hidden)
        input_shape = normalized.shape[:-1]
        hidden_shape = (*input_shape, -1, attention.head_dim)
        query_states, gate = torch.chunk(
            attention.q_proj(normalized).view(*input_shape, -1, attention.head_dim * 2),
            2,
            dim=-1,
        )
        gate = gate.reshape(*input_shape, -1)
        query_states = attention.q_norm(query_states.view(hidden_shape)).transpose(1, 2)
        key_states = attention.k_norm(attention.k_proj(normalized).view(hidden_shape)).transpose(1, 2)
        value_states = attention.v_proj(normalized).view(hidden_shape).transpose(1, 2)
        attended, _ = eager_attention_forward(
            attention,
            query_states,
            key_states,
            value_states,
            causal_mask(normalized),
            scaling=attention.scaling,
            dropout=0.0,
        )
        attended = attended.reshape(*input_shape, -1).contiguous()
        attended = attention.o_proj(attended * torch.sigmoid(gate))
        hidden = residual + attended
        return hidden + self.layer.mlp(self.layer.post_attention_layernorm(hidden))


class StackedFullAttention(torch.nn.Module):
    def __init__(self, layer: torch.nn.Module, repeats: int):
        super().__init__()
        self.block = FullAttentionBlock(layer)
        self.repeats = repeats

    def forward(self, hidden: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
        for _ in range(self.repeats):
            hidden = self.block(hidden, cos, sin)
        return hidden


class MlpOnly(torch.nn.Module):
    def __init__(self, layer: torch.nn.Module):
        super().__init__()
        self.mlp = layer.mlp

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        return self.mlp(hidden)


def gated_delta_scan(
    query: torch.Tensor,
    key: torch.Tensor,
    value: torch.Tensor,
    g: torch.Tensor,
    beta: torch.Tensor,
) -> torch.Tensor:
    """Recurrent gated delta rule. Matches the transformers reference scan."""

    initial_dtype = query.dtype
    query, key, value, beta, decay = [
        item.transpose(1, 2).to(torch.float32).contiguous() for item in (query, key, value, beta, g)
    ]
    query = l2norm(query, dim=-1, eps=1e-6)
    key = l2norm(key, dim=-1, eps=1e-6)
    query = query / (query.shape[-1] ** 0.5)
    state = query.new_zeros(query.shape[0], query.shape[1], key.shape[-1], value.shape[-1])
    outputs = []
    for index in range(query.shape[2]):
        query_t = query[:, :, index]
        key_t = key[:, :, index]
        value_t = value[:, :, index]
        state = state * decay[:, :, index].exp().unsqueeze(-1).unsqueeze(-1)
        beta_t = beta[:, :, index].unsqueeze(-1)
        remembered = (state * key_t.unsqueeze(-1)).sum(dim=-2)
        delta = (value_t - remembered) * beta_t
        state = state + key_t.unsqueeze(-1) * delta.unsqueeze(-2)
        outputs.append((state * query_t.unsqueeze(-1)).sum(dim=-2))
    core = torch.stack(outputs, dim=2)
    return core.transpose(1, 2).contiguous().to(initial_dtype)


def scatter_free_linear_attention(module: torch.nn.Module, hidden: torch.Tensor) -> torch.Tensor:
    batch, length, _ = hidden.shape
    mixed = module.in_proj_qkv(hidden).transpose(1, 2)
    gate = module.in_proj_z(hidden).reshape(batch, length, -1, module.head_v_dim)
    beta_input = module.in_proj_b(hidden)
    alpha_input = module.in_proj_a(hidden)
    mixed = causal_conv1d_fn(
        mixed,
        module.conv1d.weight.squeeze(1),
        module.conv1d.bias,
        activation=module.activation,
    ).transpose(1, 2)
    query, key, value = torch.split(mixed, [module.key_dim, module.key_dim, module.value_dim], dim=-1)
    query = query.reshape(batch, length, -1, module.head_k_dim)
    key = key.reshape(batch, length, -1, module.head_k_dim)
    value = value.reshape(batch, length, -1, module.head_v_dim)
    beta = beta_input.sigmoid()
    decay = -module.A_log.float().exp() * F.softplus(alpha_input.float() + module.dt_bias)
    repeat = module.num_v_heads // module.num_k_heads
    if repeat > 1:
        query = query.repeat_interleave(repeat, dim=2)
        key = key.repeat_interleave(repeat, dim=2)
    core = gated_delta_scan(query, key, value, decay, beta)
    core = module.norm(core.reshape(-1, module.head_v_dim), gate.reshape(-1, module.head_v_dim))
    return module.out_proj(core.reshape(batch, length, -1))


class ScatterFreeLinearBlock(torch.nn.Module):
    def __init__(self, layer: torch.nn.Module):
        super().__init__()
        self.layer = layer

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        residual = hidden
        mixed = scatter_free_linear_attention(self.layer.linear_attn, self.layer.input_layernorm(hidden))
        hidden = residual + mixed
        residual = hidden
        hidden = residual + self.layer.mlp(self.layer.post_attention_layernorm(hidden))
        return hidden


class StaticJointHead(torch.nn.Module):
    """Joint schema head after host-side span pooling.

    option_counts is fixed so each question softmax has a static length.
    """

    def __init__(self, head: torch.nn.Module, option_counts: tuple[int, ...]):
        super().__init__()
        self.head = head
        self.option_counts = option_counts

    def forward(
        self,
        sequence_hidden: torch.Tensor,
        lexical: torch.Tensor,
        type_ids: torch.Tensor,
    ) -> torch.Tensor:
        head = self.head
        sequence = head.hidden_norm(sequence_hidden)[0]
        question_spans = ((1, 4), (4, 6))
        option_spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
        question_vectors = torch.stack([sequence[start:end].mean(0) for start, end in question_spans])
        option_context = torch.stack([sequence[start:end].mean(0) for start, end in option_spans])
        memory = head.memory_projection(sequence).unsqueeze(0)
        global_vector = sequence[-1]
        queries = []
        offset = 0
        for question_index, count in enumerate(self.option_counts):
            context = option_context[offset : offset + count]
            words = lexical[offset : offset + count]
            queries.append(
                head.option_context_projection(context)
                + head.option_lexical_projection(words)
                + head.option_question_projection(question_vectors[question_index]).unsqueeze(0)
            )
            offset += count
        routed = torch.cat(queries, dim=0).unsqueeze(0)
        for layer in head.evidence_layers:
            routed = layer(routed, memory)
        routed = routed[0]
        fields = head.question_projection(question_vectors)
        summaries = []
        offset = 0
        for question_index, count in enumerate(self.option_counts):
            options = routed[offset : offset + count]
            weights = torch.softmax(options @ fields[question_index] / math.sqrt(options.shape[-1]), dim=0)
            summaries.append((weights.unsqueeze(-1) * options).sum(dim=0))
            offset += count
        fields = (
            fields
            + head.option_summary_norm(torch.stack(summaries))
            + head.global_projection(global_vector).unsqueeze(0)
            + head.type_embedding(type_ids)
        ).unsqueeze(0)
        for layer in head.layers:
            fields = layer(fields, memory)
        fields = head.field_norm(fields[0])
        logits = []
        offset = 0
        for question_index, count in enumerate(self.option_counts):
            field = fields[question_index]
            words = lexical[offset : offset + count]
            options = head.option_norm(routed[offset : offset + count])
            anchor = F.normalize(question_vectors[question_index] + global_vector, dim=-1)
            prior_scale = head.prior_logit_scale.clamp(max=math.log(100.0)).exp()
            prior = prior_scale * (F.normalize(words, dim=-1) @ anchor)
            repeated = field.unsqueeze(0).expand_as(options)
            cosine = F.cosine_similarity(repeated, options, dim=-1)
            features = torch.cat(
                [repeated, options, repeated * options, torch.abs(repeated - options)],
                dim=-1,
            )
            residual = head.residual_scorer(features).squeeze(-1)
            joint_scale = head.joint_logit_scale.clamp(max=math.log(100.0)).exp()
            joint = joint_scale * cosine + residual
            logits.append(prior + torch.sigmoid(head.residual_gate) * joint)
            offset += count
        return torch.cat(logits, dim=0)
