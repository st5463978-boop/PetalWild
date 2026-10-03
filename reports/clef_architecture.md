# Clef-Flash architecture

Source: `Cloudflare/clef-flash` at `17f0b0ad64efb65d273590632833508766b2aae6`, Apache-2.0.
Base model: `Qwen/Qwen3.5-9B`. Transformers architecture: `Qwen3_5ForConditionalGeneration`.
Hub parameter count: 9,409,813,744 parameters, all BF16. Checkpoint storage: 19,083,248,461 bytes across four shards.
Local weights were not modified. This experiment downloaded individual tensors by HTTP range.

## Text backbone

- Hidden size 4096, intermediate size 12288, 32 decoder blocks.
- Block pattern: three `linear_attention` blocks, then one `full_attention` block, repeated. 24 linear blocks and 8 full-attention blocks.
- Activation: SiLU. Normalisation: RMSNorm, epsilon 1e-6. Qwen3.5 RMSNorm stores a zero-centered weight and applies `x * (1 + weight)`.
- Linear attention is a Gated DeltaNet: depthwise causal conv of kernel 4, 16 key heads of dimension 128, 32 value heads of dimension 128, softplus decay, sigmoid beta, L2-normalised Q/K, and a recurrent state of shape `[32, 128, 128]` per batch item.
- Full attention: 16 query heads, 4 key/value heads, head dimension 256, no attention bias, RMSNorm on Q and K, sigmoid output gate from the second half of `q_proj`.
- Positions: partial rotary factor 0.25, so 64 rotary dimensions. Multimodal RoPE, interleaved, sections `[11, 11, 10]`, theta 10,000,000. Maximum position 262,144.
- Vocabulary 248,320. Embeddings are untied. Final norm is RMSNorm. `lm_head` is not used by Clef decisions.

Measured from the downloaded tensors:

- Layer 0 (linear): 218,407,104 parameters.
- Layer 3 (full attention): 209,723,904 parameters.

## Vision encoder

- Depth 27, hidden size 1152, intermediate size 4304, 16 heads, patch 16, temporal patch 2, spatial merge 2.
- Activation `gelu_pytorch_tanh`. Output hidden size 4096.
- Text-only Clef decisions do not run this encoder. It was not exported in this pass.

## Joint schema head

Config: hidden 4096, width 1024, 2 evidence-routing layers, 4 transformer decoder layers, 16 heads, feed-forward 4096.
Measured parameters: 121,762,820.

The head mean-pools token spans for each question and each allowed option, projects them, cross-attends to the backbone sequence, lets fields attend jointly, and adds a lexical prior from the output embedding rows of the option text. Span bounds depend on the tokenizer and the schema, so they are host-side. The neural scoring graph exported here takes those pooled vectors as inputs.

Question types are `noul` (true/false), `choice`, and `score`. Softmax is per question.

## What executes where in the exported split

- Host: tokenization, multimodal RoPE cos/sin, span pooling, lexical embedding gather, softmax across options if it is not inside the head graph.
- Exported full-attention block: RMSNorm, partial RoPE application, grouped-query attention, sigmoid gate, SwiGLU MLP.
- Exported linear block: the same MLP plus the Gated DeltaNet, with the recurrent scan unrolled for sequence length 8.
