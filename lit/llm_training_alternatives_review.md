# LLM Training Alternatives for Cross-Country Fiscal Shock Transfer: A Targeted Literature Review

**Authors:** Esteban Degetau and Agustín Samano
**Date:** January 2026
**Context:** Fiscal Shocks Project, Phase 0 → Phase 1 Planning

---

## Executive Summary

This review surveys recent literature (2023-2025) on alternatives to the project's current few-shot prompting approach for LLM-based fiscal shock classification. Given our constraints—44 labeled US fiscal acts for training and no ground truth labels for Malaysia—we evaluate methods along three dimensions:

1. **Performance with limited data** (<100 labeled examples)
2. **Cross-country/domain transfer capability**
3. **Validation strategies without target-domain labels**

**Key findings:**

- Fine-tuned smaller models (BERT, RoBERTa) outperform zero-shot large models in most text classification tasks, but this advantage disappears with extremely small datasets (<64 examples)
- Parameter-efficient fine-tuning (LoRA) enables fine-tuning with minimal overfitting risk and is viable with our 44-example constraint
- Self-consistency prompting and chain-of-thought reasoning can improve few-shot classification without any model training
- RAG with dynamic example retrieval can ground predictions in similar cases
- Active learning and human-in-the-loop validation are the recommended approaches when no ground truth exists
- Recent economics-specific LLM applications (monetary policy, central bank communication) demonstrate successful cross-country transfer

**Recommendation:** A hybrid approach combining few-shot prompting with self-consistency, retrieval-augmented example selection, and expert validation loop.

---

## 1. Few-Shot vs Fine-Tuning with Small Data

### 1.1 The General Finding: Fine-Tuning Usually Wins

Recent empirical studies consistently find that **fine-tuned smaller models outperform zero-shot or few-shot large models** in text classification:

> "Smaller, fine-tuned LLMs (still) consistently and significantly outperform larger, zero-shot prompted models in text classification... fine-tuning with application-specific training data achieves superior performance in all cases." — [Bucher & Martini, 2024](https://arxiv.org/abs/2406.08660)

A comprehensive study compared ChatGPT (GPT-3.5/GPT-4) and Claude against fine-tuned LLMs across sentiment, emotions, and party positions classification. Fine-tuning won in every case.

### 1.2 The Exception: Extremely Small Data

However, when training data is as scarce as ours (44 examples):

> "Only in the extremely resource-constrained setting, where the models are fine-tuned with the same number of samples as are used for in-context learning (e.g., 4-64 samples), zero and few-shot prompting is able to outperform the smaller models." — [Chae & Davidson, 2025](https://journals.sagepub.com/doi/10.1177/00491241251325243)

This is directly relevant to our situation with 44 labeled acts. With such limited data:

- Fine-tuning risks overfitting (memorizing training examples)
- Large models' pretrained knowledge becomes more valuable
- Few-shot prompting leverages analogical reasoning without gradient updates

### 1.3 Parameter-Efficient Fine-Tuning (PEFT) as Middle Ground

**LoRA** (Low-Rank Adaptation) and related PEFT methods offer a compelling middle ground:

> "In data-scarce environments, the adoption of PEFT is not merely an efficiency choice, but a prerequisite for achieving robust model generalization. Attempting to fine-tune all parameters of a large pre-trained model on a small dataset can lead to catastrophic model failure." — [Frontiers, 2025](https://www.frontiersin.org/journals/big-data/articles/10.3389/fdata.2025.1677331/full)

Key advantages of LoRA for our setting:

- Reduces trainable parameters by 10,000x (only 0.1% of weights trained)
- Acts as strong regularization, preventing overfitting
- Can achieve high-quality results with as few as 5,000 examples (we have ~44)
- Optimal settings: r=8, targeting all linear transformer layers

**Verdict:** LoRA fine-tuning is worth exploring but may still struggle with only 44 examples. Testing against few-shot prompting on held-out US data is essential.

### 1.4 LLMs as Data Generators

An emerging approach uses LLMs to **generate synthetic training data** rather than classify directly:

> "Recent research analyzes whether it is more efficient for classification in low-resource settings to use large language models as generators of synthetic samples instead of classifiers, aiming to distill the LLM into smaller models." — [arXiv, 2025](https://arxiv.org/html/2601.16278)

**Application to our project:** Have GPT-4/Claude generate additional synthetic "exogenous" and "endogenous" fiscal policy narratives based on our 44 real examples, then fine-tune a smaller model on the combined real + synthetic data.

---

## 2. Cross-Domain/Cross-Country Transfer Learning

### 2.1 Zero-Shot Domain Transfer

The key question: Can models trained on US fiscal policy documents classify Malaysian documents without retraining?

**Compositional Zero-Shot Domain Transfer (DoT5):**

> "Without access to in-domain labels, DoT5 jointly learns domain knowledge (from masked language modelling of unlabelled in-domain free text) and task knowledge (from task training on more readily available general-domain data) in a multi-task manner." — [MIT TACL, 2023](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00585/117443/Compositional-Zero-Shot-Domain-Transfer-with-Text)

**Application:** Pre-train on unlabeled Malaysian budget documents (masked LM) while training on labeled US task data. This could help bridge the US→Malaysia domain gap.

### 2.2 Cross-Lingual Transfer

While our documents are in English, Malaysian government documents may use different terminology. Recent work on cross-lingual transfer is relevant:

> "To address the high computational and memory costs of full model finetuning, recent advances in PeFT techniques focus on updating only a small subset of model parameters while keeping the majority of the pretrained weights frozen." — [arXiv, 2024](https://arxiv.org/html/2510.24619v1)

Prefix-based adaptation methods preserve the model's multilingual/cross-domain knowledge while adapting to task-specific patterns.

### 2.3 Curriculum Meta-Learning

For handling the source→target domain gap:

> "The approach based on meta-learning for zero-shot cross-lingual transfer faces challenges such as task distribution and negative transfer between source and target tasks." — [ScienceDirect, 2024](https://www.sciencedirect.com/science/article/abs/pii/S0950705124008724)

**Key insight:** Negative transfer (where source domain hurts target performance) is a real risk. Our US prompts may embed US-specific assumptions that mislead the model on Malaysian documents. The expert validation loop is critical for detecting this.

### 2.4 Domain-Adaptive Pretraining (DAPT)

The foundational DAPT paper (Gururangan et al., 2020) remains highly relevant:

> "A second phase of pretraining in-domain (domain-adaptive pretraining) leads to performance gains, under both high- and low-resource settings." — [ACL, 2020](https://aclanthology.org/2020.acl-main.740/)

**Application:** Collect unlabeled Malaysian budget speeches, Economic Reports, and Treasury documents. Continue pretraining BERT/RoBERTa on this corpus before fine-tuning on the classification task. This helps the model learn Malaysian fiscal policy terminology.

**Caveat:**

> "While Gururangan et al. claims that DAPT applies to both high-resource and low-resource settings, the smallest dataset they used had thousands of unique training datapoints. It is unknown whether this approach will apply to truly low-resource settings (i.e., less than 500 unique examples)." — [Stanford CS224N Report](https://web.stanford.edu/class/archive/cs/cs224n/cs224n.1214/reports/final_reports/report268.pdf)

---

## 3. Improving Few-Shot Without Fine-Tuning

Given our data constraints, techniques that improve prompting without training are valuable.

### 3.1 Self-Consistency Prompting

**Core idea:** Sample multiple reasoning paths, select the most consistent answer.

> "Self-consistency is a decoding strategy that first samples a diverse set of reasoning paths instead of only taking the greedy one, and then selects the most consistent answer by marginalizing out the sampled reasoning paths." — [Wang et al., 2022](https://arxiv.org/abs/2203.11171)

**Performance gains:**

- GSM8K: +17.9%
- AQuA: +12.2%
- StrategyQA: +6.4%

**Application to fiscal shocks:** For each fiscal act, run the classification 5-10 times with temperature > 0, take majority vote. This reduces noise from prompt sensitivity.

### 3.2 Chain-of-Thought (CoT) Prompting

Ask the model to explain its reasoning before classifying:

> "Encouraging the model to reason stepwise can lead to more accurate final answers (because it can correct itself mid-reasoning)... This interpretability boost is appealing to economists." — Existing lit review

**Application:** Our prompts should include: "First, identify the stated motivation for this fiscal policy change. Then, determine whether this motivation relates to current economic conditions (endogenous) or long-term structural goals (exogenous). Finally, provide your classification."

### 3.3 Retrieval-Augmented Generation (RAG)

Dynamic example selection based on similarity:

> "Few-shot evaluations reveal that retrieval narrows the data gap: ATLAS and RETRO deliver strong accuracy with under 100 task examples, whereas closed-book baselines require orders of magnitude more data." — [JMLR, Atlas paper](https://arxiv.org/pdf/2312.10997)

**Application to fiscal shocks:**

1. Embed all 44 US fiscal acts
2. For each new Malaysian document, retrieve the 3-5 most similar US examples
3. Include these as few-shot examples in the prompt

This ensures the model sees relevant precedents rather than fixed examples that may not match the current case.

### 3.4 Automatic Prompt Optimization

Rather than manually engineering prompts, use optimization:

**DSPy Framework:**

> "DSPy allows you to iterate fast on building modular AI systems and offers algorithms for optimizing their prompts and weights... With a good metric and some ability to calculate it (either ground truth data or an LLM judge), one can automatically optimize the prompt." — [DSPy GitHub](https://github.com/stanfordnlp/dspy)

**MIPROv2 optimizer** can discover better prompts than human-written ones:

> "APE discovered a better zero-shot CoT prompt than the human-engineered 'Let's think step by step' prompt." — [Prompt Engineering Guide](https://www.promptingguide.ai/techniques/ape)

**Application:** Use DSPy to optimize our Model A/B/C prompts on the US validation set before deploying to Malaysia.

---

## 4. Validation Without Ground Truth Labels

This is our central challenge for Phase 1: How do we know if Malaysia classifications are correct?

### 4.1 Uncertainty Quantification

**SPUQ (Sampling with Perturbation for Uncertainty Quantification):**

> "SPUQ uses a perturbation module that varies input prompts to gauge the sensitivity of the LLM to these types of changes, including paraphrasing prompts, adding dummy tokens, and replacing system messages. This method was able to reduce Expected Calibration Error (ECE) by 50%." — [Intuit/EACL 2024](https://medium.com/intuit-engineering/intuit-presents-innovative-approach-to-quantifying-llm-uncertainty-at-eacl-2024-f839a8f1b89b)

**Application:** For Malaysia classifications, measure how much the output changes under prompt perturbations. High instability = flag for expert review.

### 4.2 Calibration Without Labels

**LM-Polygraph Benchmark:**

> "LM-Polygraph develops methods for producing normalized and bounded confidence scores that preserve the performance of raw uncertainty scores while providing better calibration and improved interpretability for end users." — [MIT TACL](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00737/128713/Benchmarking-Uncertainty-Quantification-Methods)

**Multi-LLM Ensembles (MUSE):**

> "MUSE is a simple information-theoretic method that uses Jensen-Shannon Divergence to identify and aggregate well-calibrated subsets of LLMs, showing improved calibration and predictive performance." — [PMC, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC12702469/)

**Application:** Run classifications with multiple models (Claude, GPT-4, Llama). Where they agree, high confidence. Where they disagree, flag for expert review.

### 4.3 Active Learning for Expert Validation

**Hybrid LLM + Human Annotation:**

> "Combining Large Language Models with human annotators in an Active Learning framework significantly enhances text classification tasks. This hybrid approach, which selectively employs either GPT-3.5 or human annotations based on confidence thresholds, efficiently balances cost and accuracy." — [arXiv, 2024](https://arxiv.org/html/2406.12114v1)

**ActiveLLM (2024):**

> "ActiveLLM uses an LLM (like GPT-4) to guide active learning for a smaller model. GPT-4 can evaluate unlabeled candidates and predict which would be most useful to label, overcoming cold start by injecting its prior knowledge." — [Bayer et al., 2024]

**Application to Malaysia:**

1. LLM classifies all ~30 candidate acts
2. Calculate uncertainty scores for each
3. Expert reviews highest-uncertainty cases first (most informative)
4. Use expert corrections to refine prompts
5. Re-classify, repeat

This focuses expert time on the cases where human judgment adds most value.

### 4.4 Proxy Validation

> "This research introduces the concept of proxy validation, which effectively estimates the quality of the entire unlabeled dataset, proving useful in optimizing the annotation process." — [arXiv, 2024](https://arxiv.org/html/2406.12114v1)

**Application:** Use known major Malaysian fiscal events as proxy validation:

- 1997-98 Asian Crisis measures (should be classified as endogenous/countercyclical)
- 2015 GST introduction (should be classified as exogenous/structural)
- 2020 COVID-19 packages (should be classified as endogenous/countercyclical)

If the model gets these wrong, we know transfer failed.

### 4.5 Economic Validation

As noted in our existing lit review:

> "Use the model's classifications to recompute the tax shock series and run an impulse response or regression analysis. Do we get that GDP falls after an exogenous tax increase? If yes, the classification aligns with expectations."

This provides external validation through economic theory even without ground truth labels.

---

## 5. Economics-Specific Applications

### 5.1 Monetary Policy: Natural Language Approach

**Aruoba & Drechsel (2024):**

> "Using machine learning on text-derived features from Federal Reserve staff reports, they predict the intended federal funds rate change from the text and use the prediction error as a monetary policy shock measure. The narrative text contains essential information beyond what is in the Fed's numerical forecasts." — [NBER WP 32417](https://www.nber.org/papers/w32417)

**Key insight:** Text-based shocks yielded better impulse responses than traditional measures, validating the approach economically.

### 5.2 IMF Cross-Country Fiscal Policy Uncertainty (2024)

**Highly relevant precedent:**

> "Researchers constructed a novel database of news-based fiscal policy uncertainty for 189 countries... employing the news-based methodology as in Baker, Bloom, and Davis (2016), drawing from over 47 million news articles archived in Dow Jones Factiva." — [IMF WP 2024/209](https://www.imf.org/en/publications/wp/issues/2024/09/27/the-economic-impact-of-fiscal-policy-uncertainty-evidence-from-a-new-cross-country-database-555564)

This demonstrates successful cross-country transfer of text-based economic measurement methodology.

### 5.3 Central Bank Communication Analysis

**IMF Working Paper (2025):**

> "Using a fine-tuned large language model trained on central bank documents, they classify individual sentences... applied to a multilingual dataset of 74,882 documents from 169 central banks spanning 1884 to 2025." — [IMF, 2025](https://www.imf.org/en/publications/wp/issues/2025/06/06/from-text-to-quantified-insights-a-large-scale-llm-analysis-of-central-bank-communication-567522)

**BIS CB-LMs:**

> "ChatGPT-4 and Llama-3 70B Instruct achieved 80% and 81% accuracy respectively in classifying expected rate decisions, even without additional fine-tuning." — [BIS WP 1215](https://www.bis.org/publ/work1215.pdf)

### 5.4 Multi-Agent LLM Framework for Narrative Shocks

**Fernández-Fuertes (2025):**

> "A multi-agent LLM framework processes Federal Reserve communications to construct narrative monetary policy surprises... By analyzing Beige Books and Minutes, the system generates conditional expectations that yield less noisy surprises than market-based measures." — [Job Market Paper](https://rubenfernandezfuertes.com/papers/2025/2025__fernandez-fuertes__jmp.pdf)

**Key insight:** The framework "systematically processes 256 FOMC meetings' worth of documents (1996–2025), solving the scale constraint that limited earlier narrative approaches to small samples."

### 5.5 Financial Domain LLMs

**AdaptLLM Finance:**

> "By transforming large-scale pre-training corpora into reading comprehension texts, they consistently improved prompting performance across tasks in biomedicine, finance, and law domains. Their 7B model competes with much larger domain-specific models like BloombergGPT-50B." — [HuggingFace](https://huggingface.co/AdaptLLM/finance-LLM)

**FinBERT and FinLLMs:**

> "Leading FinLLMs surpass general LLMs by 10–30% absolute in domain tasks, with hybrid and instruction-tuned variants yielding consistent top-3 rankings across tasks." — [FinLLMs Survey](https://www.emergentmind.com/topics/financial-large-language-models-finllms)

---

## 6. Methods Comparison Table

| Method | Data Required | Cross-Country Transfer | Validation Approach | Effort | Applicability to Our Setting |
|--------|---------------|----------------------|--------------------|---------|-----------------------------|
| **Few-shot prompting** | 5-20 examples | Good (uses pretrained knowledge) | Self-consistency, expert review | Low | **High** - Current approach |
| **LoRA fine-tuning** | 50-500 examples | Moderate (task-specific adaptation) | Hold-out validation | Medium | **Medium** - May overfit with 44 examples |
| **Full fine-tuning** | 1,000+ examples | Poor (catastrophic forgetting) | Train/test split | High | **Low** - Insufficient data |
| **Domain-adaptive pretraining** | Large unlabeled corpus | Good (learns domain vocabulary) | Downstream task performance | High | **Medium** - Need Malaysia documents |
| **RAG with dynamic examples** | 20-50 examples | Good (retrieves relevant precedents) | Expert review of retrieved examples | Medium | **High** - Recommended addition |
| **Self-consistency** | Same as base method | N/A (enhancement) | Built-in voting | Low | **High** - Easy to implement |
| **Chain-of-thought** | Same as base method | N/A (enhancement) | Rationale inspection | Low | **High** - Already using |
| **Synthetic data augmentation** | 20+ seed examples | Moderate | Expert review of synthetic examples | Medium | **Medium** - Worth exploring |
| **Active learning + expert** | 0 labeled target | N/A (creates labels) | Expert provides labels | High | **High** - Required for Malaysia |

---

## 7. Transfer Learning Strategies Ranked

For the US → Malaysia setting, ranked by expected effectiveness:

### Tier 1: Recommended

1. **Few-shot prompting with self-consistency**
   - Use 10-20 US examples, sample 5 paths, majority vote
   - Minimal risk, easy to implement
   - Expected improvement: 5-15% over single-shot

2. **RAG with dynamic example retrieval**
   - Embed US examples, retrieve most similar for each Malaysia case
   - Handles terminology differences automatically
   - Expected improvement: 10-20% on diverse cases

3. **Active learning with expert validation loop**
   - LLM classifies → uncertainty quantification → expert reviews high-uncertainty cases
   - Only way to gain confidence without ground truth
   - Essential for Phase 1 success

### Tier 2: Worth Exploring

4. **LoRA fine-tuning on US data**
   - Fine-tune BERT/RoBERTa with LoRA on 44 examples
   - Risk of overfitting; test on held-out US data first
   - Only pursue if outperforms few-shot on US validation

5. **Domain-adaptive pretraining on Malaysia corpus**
   - Collect unlabeled Malaysia budget documents
   - Continue pretraining before classification
   - High effort but addresses terminology gap

6. **Automatic prompt optimization (DSPy)**
   - Optimize prompts on US validation set
   - May discover better formulations than manual engineering
   - Medium effort, potentially high reward

### Tier 3: Lower Priority

7. **Synthetic data augmentation**
   - Generate additional examples with GPT-4
   - Useful if fine-tuning approach is pursued
   - Quality of synthetic examples uncertain

8. **Multi-model ensembles**
   - Run Claude + GPT-4 + Llama, aggregate predictions
   - Higher cost, moderate benefit
   - Useful for uncertainty quantification

---

## 8. Validation Approaches for Malaysia

Without Malaysian ground truth labels, we propose a multi-layered validation strategy:

### 8.1 Layer 1: Known Event Validation (Proxy Ground Truth)

| Event | Year | Expected Classification |
|-------|------|------------------------|
| Asian Financial Crisis response | 1997-98 | Endogenous (countercyclical) |
| GST introduction | 2015 | Exogenous (structural reform) |
| GST repeal | 2018 | Potentially mixed |
| PRIHATIN COVID stimulus | 2020 | Endogenous (countercyclical) |

If Model A misses 2+ of these, transfer has failed.

### 8.2 Layer 2: Uncertainty-Based Expert Sampling

1. Compute uncertainty scores for all classifications
2. Expert reviews top 30% highest-uncertainty cases
3. Iterate prompts based on error patterns
4. Re-classify and repeat

### 8.3 Layer 3: Cross-Model Agreement

- Run with Claude, GPT-4, and a fine-tuned BERT
- Cases where all agree: high confidence
- Cases where models disagree: prioritize for expert review

### 8.4 Layer 4: Economic Validation

- Construct Malaysia fiscal shock series from classifications
- Estimate impulse responses using local projections
- Check: Does an exogenous tax increase reduce output?
- If responses are theoretically inconsistent, classification has failed

### 8.5 Layer 5: Coverage Analysis

- Does the model find known major Malaysian fiscal acts?
- Are there suspicious gaps (e.g., nothing during 1997 crisis)?
- Expert confirms face validity of final list

---

## 9. Recommendations

### Immediate Actions (Phase 0)

1. **Implement self-consistency** for Models A/B/C
   - Sample 5 reasoning paths with temperature=0.7
   - Take majority vote for classification
   - Low effort, expected to improve robustness

2. **Test LoRA fine-tuning** on US data
   - Fine-tune BERT with LoRA (r=8) on 35 examples
   - Evaluate on held-out 9 examples
   - Compare to few-shot prompting baseline

3. **Build RAG retrieval system**
   - Embed all US fiscal act texts
   - For each classification, retrieve 3 most similar US examples
   - Include dynamically in prompt

### Phase 1 Preparation

4. **Collect unlabeled Malaysia documents**
   - Budget speeches, Economic Reports (1980-2022)
   - Consider domain-adaptive pretraining if corpus is large enough

5. **Design active learning protocol**
   - Define uncertainty metrics (self-consistency disagreement, model confidence)
   - Create expert review interface
   - Plan 3-4 iteration cycles

6. **Prepare proxy validation checklist**
   - List 5-10 known major Malaysian fiscal events
   - Define expected classifications
   - Track pass/fail rate as overall transfer success metric

### What NOT to Prioritize

- **Full fine-tuning**: Insufficient data for this approach
- **Building custom "EconBERT"**: High effort, uncertain benefit given our timeline
- **Targeting 100% automation**: Expert validation is essential, not a fallback

---

## 10. Key Papers by Topic

### Few-Shot vs Fine-Tuning

- Bucher & Martini (2024). [Fine-Tuned 'Small' LLMs (Still) Significantly Outperform Zero-Shot Models](https://arxiv.org/abs/2406.08660)
- Chae & Davidson (2025). [Large Language Models for Text Classification: From Zero-Shot to Instruction-Tuning](https://journals.sagepub.com/doi/10.1177/00491241251325243)

### Parameter-Efficient Fine-Tuning

- Hu et al. (2021). [LoRA: Low-Rank Adaptation of Large Language Models](https://arxiv.org/abs/2106.09685)
- Frontiers (2025). [PEFT for Low-Resource Text Classification: LoRA, IA3, and ReFT](https://www.frontiersin.org/journals/big-data/articles/10.3389/fdata.2025.1677331/full)

### Domain Adaptation

- Gururangan et al. (2020). [Don't Stop Pretraining: DAPT](https://aclanthology.org/2020.acl-main.740/)
- DoT5 (2023). [Compositional Zero-Shot Domain Transfer](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00585/117443/)

### Prompting Techniques

- Wang et al. (2022). [Self-Consistency Improves Chain of Thought Reasoning](https://arxiv.org/abs/2203.11171)
- Zhou et al. (2022). [Automatic Prompt Engineer (APE)](https://www.promptingguide.ai/techniques/ape)
- DSPy Framework. [GitHub](https://github.com/stanfordnlp/dspy)

### Uncertainty and Validation

- LM-Polygraph (2024). [Benchmarking UQ Methods for LLMs](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00737/128713/)
- SPUQ (2024). [Perturbation-Based Uncertainty Quantification](https://medium.com/intuit-engineering/intuit-presents-innovative-approach-to-quantifying-llm-uncertainty-at-eacl-2024-f839a8f1b89b)

### Active Learning

- Enhancing Text Classification (2024). [LLM-Driven Active Learning and Human Annotation](https://arxiv.org/html/2406.12114v1)
- Bayer et al. (2024). ActiveLLM

### Economics Applications

- Aruoba & Drechsel (2024). [Identifying Monetary Policy Shocks: A Natural Language Approach](https://www.nber.org/papers/w32417)
- IMF (2024). [Fiscal Policy Uncertainty: Cross-Country Database](https://www.imf.org/en/publications/wp/issues/2024/09/27/the-economic-impact-of-fiscal-policy-uncertainty-evidence-from-a-new-cross-country-database-555564)
- IMF (2025). [LLM Analysis of Central Bank Communication](https://www.imf.org/en/publications/wp/issues/2025/06/06/from-text-to-quantified-insights-a-large-scale-llm-analysis-of-central-bank-communication-567522)
- BIS (2024). [CB-LMs: Language Models for Central Banking](https://www.bis.org/publ/work1215.pdf)
- Fernández-Fuertes (2025). [Multi-Agent LLM Framework for Monetary Policy Shocks](https://rubenfernandezfuertes.com/papers/2025/2025__fernandez-fuertes__jmp.pdf)
- Latifi et al. (2024). [Fiscal Policy in the Bundestag: Textual Analysis](https://www.econstor.eu/bitstream/10419/277624/1/vfs-2023-pid-86550.pdf)

---

## 11. Conclusion

The literature supports our current few-shot prompting approach as reasonable given data constraints, while suggesting several enhancements:

1. **Self-consistency and CoT reasoning** can improve classification without additional training
2. **RAG with dynamic example retrieval** can help handle terminology differences between US and Malaysia
3. **LoRA fine-tuning** is worth testing but may not beat few-shot with only 44 examples
4. **Active learning with expert validation** is essential—there is no substitute for human judgment when ground truth is unavailable
5. **Proxy validation** using known major events provides a sanity check on transfer success

The key insight from recent economics NLP literature (monetary policy shocks, central bank communication, fiscal uncertainty) is that **cross-country transfer works when combined with domain expertise**. The IMF, BIS, and Fed researchers all emphasize expert validation as integral to their methodologies, not as a fallback.

**Bottom line:** LLMs can assist experts in fiscal shock identification, but the contribution is reducing effort from months to weeks, not eliminating human judgment entirely. This framing—"LLM-assisted methodology with expert validation"—is both honest about limitations and aligned with best practices in the literature.

---

*This review was prepared to inform the Phase 1 Malaysia deployment strategy. For the original comprehensive literature review, see `lit/Using LLMs to Classify Narrative Fiscal Shocks_ A Literature Review.pdf`.*
