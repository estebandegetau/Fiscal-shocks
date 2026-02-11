The Halterman & Keith (2025) five-stage framework is designed to move beyond simple zero-shot prompting by ensuring Large Language Models (LLMs) follow precise **codebook operationalizations** used by human coders. The framework transforms broad background concepts into **systematized constructs** through five iterative stages.

### Stage 0: Codebook Preparation

The first stage involves preparing a codebook that is readable by both humans and machines. Researchers must restructure traditional codebooks into a **machine-readable semi-structured format**. This format includes standardized components:

* **Label:** The exact string the model should return.
* **Label Definition:** A succinct, typically single-sentence description of the class.
* **Clarification & Negative Clarification:** Detailed inclusion criteria and explicit **exclusion rules** (e.g., "This category excludes education").
* **Positive & Negative Examples:** Examples of documents that do and do not fit the category to provide **in-context learning**.
* **Output Instructions:** Overall task descriptions and an "Output reminder" to ensure the model adheres to valid labels.

**Key finding:** The semi-structured format outperforms original codebook format (Table 3: +0.02 to +0.13 weighted F1) because explicit component separation helps the LLM attend to each part independently.

**Format design principles:**

* Each component serves a distinct purpose: definition for core meaning, clarification for boundary cases, examples for in-context learning
* Separating components enables **ablation testing** (removing one at a time to measure impact)
* The output reminder is critical for ensuring valid label output, especially with complex codebooks

### Stage 1: Label-Free Behavioral Testing

Before committing to manual labeling, researchers conduct **label-free behavioral tests** to assess the model's "off-the-shelf" capabilities.

**Test specifications (Table 2):**

| Test | Name | What It Measures | Implementation | Pass Criteria |
|------|------|-----------------|----------------|---------------|
| I | Legal Labels | LLM returns only valid codebook labels | Run on N documents, check if output matches valid label set | 100% |
| II | Definition Recovery | LLM can match definition to label | Provide verbatim class definition as "document," check if correct label returned | 100% |
| III | In-Context Examples | LLM can match examples to labels | Provide verbatim positive (IIIa) and negative (IIIb) examples as "documents" | 100% |
| IV | Order Invariance | Labels unchanged by category order | Run original, reversed, and shuffled codebook; measure Fleiss's kappa and % label changes | Kappa >0.8; <5% label changes |

**Test IV implementation details:**

* Create three versions of the codebook: original category order, reversed, randomly shuffled
* Run all N documents through each version
* Calculate: (a) percentage of labels identical between original and variant; (b) Fleiss's kappa across all three
* Fleiss's kappa interpretation (Landis & Koch 1977): <0.20 poor, 0.21-0.40 fair, 0.41-0.60 moderate, 0.61-0.80 substantial, 0.81-1.00 near-perfect

**Empirical findings (Figure 3, BFRS dataset):**

* Mistral-7B, Llama-8B: near-perfect on Tests I-III
* All models showed order sensitivity (Test IV), suggesting attention issues with long prompts
* OLMo-7B failed badly enough to be dropped from later stages

### Stage 2: Zero-Shot Evaluation with Labels

Once promising models are identified, researchers must hand-label a **small evaluation set** to quantitatively assess accuracy. Performance is typically measured using **weighted F1 scores** to account for class imbalances.

**Evaluation metrics:**

* **Primary:** Weighted F1 (average per-class F1 weighted by sample size)
* **Bootstrap CIs:** 500 resamples of (predicted, true) pairs for 95% confidence intervals
* **Report format:** `0.57 [0.55-0.58]`

**Empirical results (Table 3):**

| Dataset | Llama-8B | Mistral-7B |
|---------|----------|------------|
| BFRS (12 classes) | 0.57 | 0.53 |
| CCC (8 classes) | 0.61 | 0.65 |
| Manifestos (142 classes) | 0.19 | 0.15 |

These results indicate that 7-12B open-weight LLMs have significant limitations on complex codebook tasks in zero-shot settings.

### Stage 3: Zero-Shot Error Analysis

This stage involves in-depth probing of model failure modes using three complementary methods:

**Labels-Required Behavioral Tests (Tests V-VII):**

| Test | Name | What It Measures | Implementation |
|------|------|-----------------|----------------|
| V | Exclusion Criteria Consistency | LLM follows specific exclusion rules | Add trigger word ("elephant") to document and exclusion criterion to codebook; test all 4 combos: (normal/modified doc) × (normal/modified codebook). Pass requires all 4 correct. |
| VI | Generic Label Accuracy | LLM doesn't rely on label names | Replace labels with non-informative terms (LABEL_1, LABEL_2, etc.); measure F1 |
| VII | Swapped Label Accuracy | LLM follows definitions over names | Permute labels across definitions; measure F1 |

**Test V detail:** The four conditions that must all be correct:
1. Normal codebook + normal document → classify correctly
2. Normal codebook + modified document ("elephant" added) → classify correctly (no exclusion rule)
3. Modified codebook (elephant exclusion) + normal document → classify correctly (trigger absent)
4. Modified codebook + modified document → apply exclusion rule

**Critical finding (Tests VI/VII):** LLMs rely heavily on **label names** rather than definitions. When labels are replaced with generic terms, F1 drops significantly. When labels are swapped across definitions, models follow the label name rather than the definition. This is critical for projects where category names are semantically loaded (e.g., "deficit-driven").

**Ablation Studies (Table 4):**

Systematically remove codebook components one at a time, measure impact on weighted F1:

| Ablated Component | Dev F1 | Change |
|-------------------|--------|--------|
| None (full codebook) | 0.53 | baseline |
| Negative Example | 0.42 | -0.11 |
| Positive Example | 0.46 | -0.07 |
| Negative Clarification | 0.43 | -0.10 |
| All clarification + examples | 0.20 | -0.33 |
| Definition (labels only) | 0.29 | -0.24 |

**Key findings:**
* All components contribute; removing any decreases F1
* Negative examples had the largest single-component impact
* Removing the definition (labels only) still yielded F1 = 0.29, confirming label name reliance
* Full codebook yielded best performance overall

**Manual Analysis (Table 5):**

Six error categories for classifying model outputs:

| Category | Description | BFRS | CCC | Manifestos |
|----------|------------|------|-----|------------|
| A. LLM correct | Prediction matches gold standard | 38% | 48% | 11% |
| B. Incorrect gold | Human label wrong | 4% | 10% | 8% |
| C. Document error | Scraping/context issue | 4% | 2% | 3% |
| D. Non-compliance | Invalid format, hallucinated label | 0% | 2% | 45% |
| E. Semantics error | Wrong definition applied or heuristic used | 50% | 26% | 29% |
| F. Other | Uncategorizable | 4% | 10% | 2% |

**Error patterns identified:**

* **Lexical overlap heuristics:** Models select labels whose words appear in the text (e.g., "rally" in text → "rally" label, even when "demonstration" is correct)
* **Background concept reliance:** Model predicts based on pretraining knowledge, not codebook (e.g., education passage → "WELFARE POSITIVE" despite explicit codebook exclusion of education)
* **Non-compliance** is highly variable by dataset (0% to 45%)

### Stage 4: Supervised Fine-Tuning

If zero-shot performance is inadequate, the final stage involves **instruction-tuning** the model directly on human-coded examples. Because updating all weights is costly, researchers should use **parameter-efficient techniques**:

* **Quantization (Q):** Reducing the numerical precision of weights to save memory (4-bit).
* **Low-Rank Adaptation (LoRA):** Updating only a small fraction of weights (rank 16 ≈ 0.5% of parameters).
* **Data Structure:** Training on tuples of (Instruction + Codebook, Document, correct Natural-Language Label).
* **Loss masking:** Compute loss only on the output tokens, not on the prompt (codebook + document).

**Results (Table 6):**

| Dataset | LLM | Zero-shot F1 | Tuned F1 | Improvement |
|---------|-----|-------------|----------|-------------|
| BFRS | Mistral-7B | 0.53 | 0.82 | +55% |
| CCC | Mistral-7B | 0.65 | 0.72 | +11% |
| Manifestos | Mistral-7B | 0.15 | 0.38 | +153% |

This stage can improve performance by up to **55%** relative to zero-shot baselines. Loss plateaued after ~10% of training examples.

**Note for our project:** S4 is a last resort. Claude (API-only) cannot be fine-tuned with LoRA/QLoRA. If S4 is needed, it would require switching to an open-weight model, losing Claude's advantages. Prefer iterating on S0 codebook quality.
