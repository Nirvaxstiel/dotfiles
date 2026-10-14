---
name: serving-llms
description: "LLM inference serving: vLLM (high-throughput GPU serving, OpenAI-compatible API, PagedAttention, quantization) and llama.cpp (local GGUF inference, CPU/GPU, Apple Silicon, HuggingFace model discovery)."
version: 1.0.0
author: Hermes Agent (consolidated)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [llm-serving, inference, vllm, llama-cpp, gguf, quantization, deployment]
---

# Serving LLMs — Inference Runtimes

Two primary LLM inference runtimes for different deployment scenarios.

## vLLM — High-Throughput GPU Serving

Use for production serving, batch inference, and GPU-based deployments. 24x higher throughput than standard transformers.

### Quick Start

```bash
pip install vllm
```

```python
from vllm import LLM, SamplingParams
llm = LLM(model="meta-llama/Llama-3-8B-Instruct")
sampling = SamplingParams(temperature=0.7, max_tokens=256)
outputs = llm.generate(["Explain quantum computing"], sampling)
print(outputs[0].outputs[0].text)
```

### OpenAI-Compatible Server

```bash
vllm serve meta-llama/Llama-3-8B-Instruct --port 8000

# Query with OpenAI SDK
from openai import OpenAI
client = OpenAI(base_url='http://localhost:8000/v1', api_key='EMPTY')
print(client.chat.completions.create(
    model='meta-llama/Llama-3-8B-Instruct',
    messages=[{"role": "user", "content": "Hello"}]
))
```

### Key Features
- **PagedAttention**: Block-based KV cache for efficient memory usage
- **Continuous batching**: Mix prefill/decode requests
- **Quantization**: GPTQ, AWQ, FP8, INT4, INT8
- **Tensor parallelism**: Scale across GPUs
- **Prefix caching**: Reuse KV cache across requests
- **Speculative decoding**: Draft-then-verify for speedup
- **Multi-LoRA**: Serve multiple adapters simultaneously

### Performance Tips
- `--max-model-len` for memory optimization
- `--gpu-memory-utilization 0.9` for busy servers
- `--enable-prefix-caching` for repeated prefixes
- `--speculative-model` for speculative decoding
- Use `--dtype auto` (bfloat16 on Ampere+, float16 otherwise)
- For single GPU: `--tensor-parallel-size 1`
- Monitor with `--enable-chunked-prefill` for long prompts

## llama.cpp — Local GGUF Inference

Use for CPU inference, Apple Silicon, edge deployment, or when GPU memory is limited.

### Quick Start

```bash
pip install llama-cpp-python
```

```python
from llama_cpp import Llama
llm = Llama(model_path="path/to/model.gguf", n_ctx=4096)
output = llm("Q: What is quantum computing? A:", max_tokens=256)
print(output["choices"][0]["text"])
```

### Model Discovery Workflow

1. Search HuggingFace: `https://huggingface.co/models?apps=llama.cpp&sort=trending`
2. Open `https://huggingface.co/<repo>?local-app=llama.cpp` for recommended quants and commands
3. Verify with tree API: `https://huggingface.co/api/models/<repo>/tree/main?recursive=true`

### Quant Selection Guide

| Quant | Bits/Weight | Quality | Use Case |
|-------|-------------|---------|----------|
| Q4_K_M | 4.5 | Good | Default for most users |
| Q5_K_M | 5.5 | Better | More quality, ~30% larger |
| Q6_K | 6.5 | Best | Max quality on CPU |
| IQ4_NL | 4.5 | Good | Newer format, better for small models |
| Q8_0 | 8.0 | Near-lossless | For large RAM |
| F16 | 16.0 | Full | GPU with tons of VRAM |

Always prefer `Q4_K_M` unless user has specific quality or size constraints.

### Server Mode

```bash
llama-server -m model.gguf --host 0.0.0.0 --port 8080 --n-gpu-layers -1
# Compatible with OpenAI SDK
```

## Decision Guide

| Scenario | Runtime |
|----------|---------|
| Production serving, many concurrent users | vLLM |
| Single-user interactive, CPU-only | llama.cpp |
| Apple Silicon (Metal) | llama.cpp |
| Edge / low-power device | llama.cpp |
| Batch inference, large dataset | vLLM |
| Need OpenAI-compatible API | Both |
| Need speculative decoding | vLLM |
| Need tensor parallelism | vLLM |
