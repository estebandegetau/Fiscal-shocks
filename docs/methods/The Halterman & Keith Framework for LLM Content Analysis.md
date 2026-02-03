The Halterman & Keith (2025) five-stage framework is designed to move beyond simple zero-shot prompting by ensuring Large Language Models (LLMs) follow precise **codebook operationalizations** used by human coders 1, 2, 3\. The framework transforms broad background concepts into **systematized constructs** through five iterative stages 4, 5\.

### Stage 0: Codebook Preparation

The first stage involves preparing a codebook that is readable by both humans and machines 5, 6\. Researchers must restructure traditional codebooks into a **machine-readable semi-structured format** 7, 3\. This format includes standardized components:

* **Label:** The exact string the model should return 8\.  
* **Label Definition:** A succinct, typically single-sentence description of the class 8\.  
* **Clarification & Negative Clarification:** Detailed inclusion criteria and explicit **exclusion rules** (e.g., "This category excludes education") 9, 10\.  
* **Positive & Negative Examples:** Examples of documents that do and do not fit the category to provide **in-context learning** 9\.  
* **Output Instructions:** Overall task descriptions and an "Output reminder" to ensure the model adheres to valid labels 11\.

### Stage 1: Label-Free Behavioral Testing

Before committing to manual labeling, researchers conduct **label-free behavioral tests** to assess the model's "off-the-shelf" capabilities 5, 12\. These tests measure:

* **Legal Output Checks:** Whether the model returns only valid labels defined in the codebook 13\.  
* **Memorization/Recovery:** Testing if the model can match a provided verbatim definition or example from the prompt to its correct label 13\.  
* **Sensitivity to Order:** Evaluating if changing the **order of categories** in the codebook—through reversing or shuffling—alters the predicted labels 14, 15\.

### Stage 2: Zero-Shot Evaluation with Labels

Once promising models are identified, researchers must hand-label a **small evaluation set** to quantitatively assess accuracy 16, 17\. Performance is typically measured using **weighted F1 scores** to account for class imbalances 18, 19\. This stage provides a realistic picture of whether the model can handle complex constructs without further training 17, 19\.

### Stage 3: Zero-Shot Error Analysis

This stage involves in-depth probing of model failure modes using three methods:

* **Labels-Required Behavioral Tests:** These include checking **Exclusion criteria consistency** (triggering specific negative rules) and **Swapped Label Accuracy** (permuting labels and definitions to see if the model relies on the label name rather than the definition) 20, 21\.  
* **Ablation Studies:** Systematically removing components, such as negative clarifications, to measure their specific impact on performance 22, 23, 3\.  
* **Manual Analysis:** Inspecting model outputs and explanations to identify **lexical overlap heuristics**, where models incorrectly select labels based on word matches rather than semantic meaning 24, 25, 3\.

### Stage 4: Supervised Fine-Tuning

If zero-shot performance is inadequate, the final stage involves **instruction-tuning** the model directly on human-coded examples 26, 27\. Because updating all weights is costly, researchers should use **parameter-efficient techniques**:

* **Quantization:** Reducing the numerical precision of weights to save memory 28, 29\.  
* **Low-Rank Adaptation (LoRA):** Updating only a small fraction of the model's weights 28, 29\.  
* **Data Structure:** Training on tuples of (Instruction \+ Codebook, Document, and the correct Natural-Language Label) 30.This stage can improve performance by up to **55%** relative to zero-shot baselines 31\.

