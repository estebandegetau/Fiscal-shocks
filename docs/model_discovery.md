# Model Discovery: Cheap LLMs for Preliminary Testing

**Date**: 2026-02-27

**Context**: S1 behavioral tests on Claude Haiku 4.5 cost ~$3–5 per run. We need cheaper models for iterative codebook development (S0/S1 cycle), reserving Haiku for S2 LOOCV and production.

## Current Baseline

| Item | Value |
|---|---|
| Model | `claude-haiku-4-5-20251001` |
| Input / Output pricing | $1.00 / $5.00 per M tokens |
| Total spend to date | ~$83–100 across ~3,000 API calls |
| Provider | Anthropic (direct) |
| Code location | `R/functions_llm.R` — `call_llm_api()` router |

The router already supports four providers: `anthropic`, `openai`, `groq`, and `ollama`. Switching models requires changing four lines in `_targets.R`:

```r
llm_provider <- "openai"      # or "groq", "ollama"
llm_model    <- "model-id"
llm_base_url <- "https://..."  # NULL for named providers
llm_api_key  <- NULL            # NULL reads from env var
```

## Hardware Constraint

No local GPU available. Ollama (local inference) is not practical — even a 7B model on CPU takes minutes per call. All options below are cloud API providers.

---

## Open-Weight Models by Tier

### Tier 1: Ultra-Cheap for S1 Iteration ($0.04–$0.20/M tokens)

These are 30–50x cheaper than Haiku. A full S1 behavioral test suite (~200 calls, ~1M tokens) costs ~$0.07–0.15 instead of $3–5.

| Model | Params | Input / Output per M | Best Provider | Strengths | Weaknesses |
|---|---|---|---|---|---|
| **Qwen 2.5 72B Instruct** | 72B | $0.04 / $0.10 | OpenRouter | Designed for JSON output; multilingual (good for Phase 2 Malaysia); cheapest 70B-class | Newer, less community testing than Llama |
| **Gemma 3 27B IT** | 27B | $0.04 / $0.15 | OpenRouter, Together | Passes JSON schema tests natively; 140+ languages; cheapest per token | Smaller model, may miss nuanced fiscal policy distinctions |
| **Mistral Small 3.2** | 24B | $0.06 / $0.18 | OpenRouter | Good instruction following for size; free tier available | 24B may struggle with complex codebook logic |
| **Phi-4** | 14B | $0.06 / $0.14 | Various | Strong reasoning for size; MIT licensed | Documented weakness at following detailed instructions |
| **Llama 3.1 8B** | 8B | $0.05 / $0.08 | Groq | Fastest inference; good for plumbing/format validation | Too small for meaningful classification quality |

**Recommendation**: Start with **Qwen 2.5 72B** — best combination of capability, price, and JSON output quality.

### Tier 2: Solid Mid-Range for Cross-Validation ($0.10–$0.60/M tokens)

Use these to cross-validate S1 results. If two 70B models agree on a failure, it's a codebook problem.

| Model | Params | Input / Output per M | Best Provider | Notes |
|---|---|---|---|---|
| **Llama 3.3 70B Instruct** | 70B | $0.10 / $0.32 | Groq, OpenRouter | Best-established instruction following (IFEval 92.1); safe choice |
| **Qwen 3 32B** | 32B | $0.29 / $0.59 | Groq | Thinking/non-thinking mode toggle; fast on Groq |
| **Llama 4 Scout** | 17Bx16E MoE | $0.11 / $0.34 | Groq | 10M context window; newer, less battle-tested |
| **Llama 4 Maverick** | 17Bx128E MoE | $0.20 / $0.60 | Groq | Strong reasoning; 1M context window |

**Recommendation**: **Llama 3.3 70B** as the cross-validation model — best instruction-following benchmark scores and widest provider support.

### Tier 3: Full Capability ($0.56–$1.70/M tokens)

Comparable in cost to Haiku but with different strengths (larger context, reasoning chains).

| Model | Params | Input / Output per M | Provider | Notes |
|---|---|---|---|---|
| **DeepSeek V3-0324** | 671B MoE (37B active) | $0.56 / $1.68 | Fireworks | Strong reasoning; geopolitical risk for World Bank project |
| **Qwen 3 235B-A22B** | 235B MoE (22B active) | TBD | API | Flagship for policy analysis; strong multilingual |
| **gpt-oss-120b** | 120B MoE | $0.15 / $0.60 | Groq, Fireworks | OpenAI open-weights, Apache 2.0; matches o4-mini on tool calling |

### Closed Models (Reference)

| Model | Input / Output per M | Notes |
|---|---|---|
| **Claude Haiku 4.5** (current) | $1.00 / $5.00 | Our baseline; best instruction following |
| **GPT-4o-mini** | $0.15 / $0.60 | OpenAI's cheap tier |
| **Gemini 2.0 Flash** | ~$0.10 / $0.40 | Google's cheap tier |

---

## Cloud API Providers

### Already in our code

| Provider | Config value | Models | Notes |
|---|---|---|---|
| **Anthropic** | `"anthropic"` | Claude family | Current default |
| **Groq** | `"groq"` | Llama 3.3/4, Qwen 3, gpt-oss | Named provider, just needs `GROQ_API_KEY` env var |
| **OpenAI** | `"openai"` | GPT-4o-mini, gpt-oss | Named provider, needs `OPENAI_API_KEY` |
| **Ollama** | `"ollama"` | Any GGUF model | Local only; not practical without GPU |

### Requires only `base_url` override

These use the OpenAI-compatible API, so they work with our existing `call_openai_api()`:

| Provider | Base URL | Pricing Model | Best For |
|---|---|---|---|
| **OpenRouter** | `https://openrouter.ai/api/v1` | Pass-through + 5.5% credit fee | Widest model selection; cheapest Qwen 2.5 72B |
| **Together AI** | `https://api.together.xyz/v1` | Per-model | Batch API; established company |
| **Fireworks AI** | `https://api.fireworks.ai/inference/v1` | Tiered by param count | JSON mode support; DeepSeek V3 |

### Provider Assessment

**Groq** — Already named in our router. Fastest inference (custom LPU hardware). Limited model selection but has all the models we'd want. No markup. Established, well-funded company. **Best choice for a provider already in our code.**

**OpenRouter** — Legitimate routing layer. SOC 2 Type I compliant. Pass-through token pricing with a 5.5% fee on credit purchases. No prompt logging by default. Trustpilot 2.3/5 (customer service complaints, not API issues). Automatic failover across backends. **Best choice for cheapest access to Qwen 2.5 72B.** No formal SLA — fine for iterative testing, not for production.

**Together AI** — Established company, good batch support. Slightly higher prices than OpenRouter for the same models. Worth considering if we need batch processing later.

**Fireworks AI** — Tiered pricing by model size. Good function calling / JSON mode support. Best option for DeepSeek V3 if we want to test it.

---

## Structured JSON Output Support

Our codebooks require JSON output. Support status:

- **Provider-level JSON mode**: Groq, Fireworks, Together AI, and OpenRouter all support JSON response format via the `response_format` parameter. Our code does not currently use this — we rely on prompting and `parse_json_response()` to extract JSON from the response text.
- **Model-level native support**: Qwen 2.5 and Qwen 3 are explicitly designed for structured JSON output. Gemma 3 27B passes complex JSON schema tests even without explicit JSON mode. Llama 3.3 supports it via constrained decoding.
- **Action needed**: Consider adding `response_format: { type: "json_object" }` to `call_openai_api()` as an optional parameter. This would improve JSON reliability for open-weight models that may be less instruction-following compliant than Claude.

---

## Recommended Strategy

### Three-model ladder for codebook development

```
S1 Behavioral Tests (iterative)
    │
    ├── Primary: Qwen 2.5 72B via OpenRouter ($0.04/$0.10)
    │   └── ~$0.08 per full S1 suite
    │
    ├── Cross-validation: Llama 3.3 70B via Groq ($0.59/$0.79)
    │   └── ~$0.70 per full S1 suite
    │
    └── If both models fail → codebook problem, not model problem

S2 LOOCV + S3 Error Analysis
    │
    └── Claude Haiku 4.5 ($1.00/$5.00)
        └── Reserve for stages where instruction fidelity matters most
```

### Why this works

1. **Qwen 2.5 72B** is 30–50x cheaper than Haiku. If the codebook can't get a 72B model to produce legal outputs and recover definitions, the codebook needs work regardless of model.

2. **Llama 3.3 70B** as a second opinion. Different training data, different failure modes. Agreement between Qwen and Llama on failures is strong evidence of a codebook issue.

3. **Haiku** for the stages that matter most: LOOCV evaluation against labeled data (S2) and error analysis (S3), where instruction-following fidelity directly affects our metrics.

### Cost projection

| Activity | Model | Est. Calls | Est. Cost |
|---|---|---|---|
| 10 S1 iterations during codebook dev | Qwen 2.5 72B | 2,000 | ~$0.80 |
| 2 cross-validation runs | Llama 3.3 70B | 400 | ~$1.40 |
| 1 S2 LOOCV run (44 acts) | Haiku 4.5 | ~500 | ~$5.00 |
| 1 S3 error analysis | Haiku 4.5 | ~300 | ~$3.00 |
| **Total per codebook** | | | **~$10.20** |

Compare to running everything on Haiku: 10 S1 iterations alone would cost ~$30–50.

---

## Setup Checklist

To use OpenRouter or Groq:

1. **Get API key**: Sign up at [openrouter.ai](https://openrouter.ai) or [groq.com](https://groq.com)
2. **Add to `.env`**:
   ```
   OPENROUTER_API_KEY=sk-or-...
   GROQ_API_KEY=gsk_...
   ```
3. **Update `_targets.R`** (example for OpenRouter + Qwen 2.5 72B):
   ```r
   llm_provider <- "openai"
   llm_model    <- "qwen/qwen-2.5-72b-instruct"
   llm_base_url <- "https://openrouter.ai/api/v1"
   llm_api_key  <- Sys.getenv("OPENROUTER_API_KEY")
   ```
4. **Update pricing** in `get_model_pricing()` for cost tracking (currently returns $0 for non-Claude models)
5. **Consider adding** `response_format` JSON mode support to `call_openai_api()`

---

## Next Steps

1. Sign up for Groq (free tier, already in code) and/or OpenRouter
2. Run a single C1 S1 behavioral test on Qwen 2.5 72B to compare quality vs. Haiku
3. If quality is acceptable for S1 purposes, adopt the three-model ladder
4. Update `get_model_pricing()` to track costs across providers

---

## Sources

- [OpenRouter Pricing](https://openrouter.ai/pricing)
- [OpenRouter Trustpilot Reviews](https://www.trustpilot.com/review/openrouter.ai)
- [Groq Pricing](https://groq.com/pricing)
- [Together AI Pricing](https://www.together.ai/pricing)
- [Fireworks AI Pricing](https://fireworks.ai/pricing)
- [LLM API Price Aggregator — pricepertoken.com](https://pricepertoken.com/)
- [Qwen 2.5 vs Llama 3.3 Comparison](https://llm-stats.com/models/compare/llama-3.3-70b-instruct-vs-qwen-2.5-72b-instruct)
- [Qwen 3 GitHub](https://github.com/QwenLM/Qwen3)
- [Gemma 3 on Hugging Face](https://huggingface.co/google/gemma-3-27b-it)
- [Best Open Source LLMs Feb 2026 — whatllm.org](https://whatllm.org/blog/best-open-source-models-february-2026)
- [Best Open Source LLMs 2026 — BentoML](https://www.bentoml.com/blog/navigating-the-world-of-open-source-large-language-models)
- [OpenRouter Review 2025: Multi-Model Gateway](https://skywork.ai/blog/openrouter-review-2025/)
- [AI Cost Optimization: OpenRouter vs Direct APIs](https://softwarelogic.co/en/blog/ai-cost-optimization-openrouterai-vs-direct-model-apis-facts)
