# C2b v0.9 Redesign: A Case Study in Source-Anchored Codebook Design

**Scope.** A specific and thorough account of how C2b — the act-level motivation classifier in this project's R&R + H&K pipeline — was rewritten between iterations 42 and 48 (2026-05-04 to 2026-05-06), what design moves the rewrite combined, and what the measured outcomes were. n = 1 codebook. No claim of generality is made here; what the recipe might look like for C3 and C4 is sketched only at the end.

**Audience.** The document is written densely enough to be cut into shorter products for several downstream uses: (i) an internal record so the team can re-apply the pattern when building C3 and C4; (ii) a methodology section for the Phase 0 paper; (iii) a generalisable contribution to H&K-adjacent LLM-content-analysis work; (iv) a CLAUDE.md "Workflow Conventions" entry. Each subsection has a tight headline followed by enough detail to defend the claim at peer review.

**TL;DR.** After two architectures hit a ceiling, C2b was rewritten by a fresh agent that read only Romer & Romer's primary sources and the YAML shape of a sister codebook (C1 v0.6.0) that had passed gates. Five design moves were combined: (1) a *constrained-optimization* prompt-design heuristic ("adopt source X's language as closely as possible, subject to constraint Z"); (2) deliberate *blocking* of the writer from prior failed versions; (3) reuse of a structural template proven elsewhere in the project (the *C1 recipe*); (4) *embedded-guardrail* placement of edge-case rules inside class definitions rather than as detached rule ladders; (5) an *investigate-before-rewriting* diagnostic discipline that overturned the premise of the rewrite before any code was written. Outcomes (v0.9.1, frozen as the C2 deliverable at iter 48): exogenous precision 0.800 (CI [0.630, 0.957] contains the 0.85 gate; bias-corrected 0.833), sign accuracy on true-exogenous 0.913 → 0.955 (PASS), motivation wF1 0.665, and an interpretive reading that the codebook is calibrating internalized R&R priors rather than teaching R&R from scratch.

---

## 1. The state we were rewriting from

C2b classifies a single fiscal act into one of Romer & Romer's four motivation categories (`SPENDING_DRIVEN`, `COUNTERCYCLICAL`, `DEFICIT_DRIVEN`, `LONG_RUN`); `exogenous` is then derived as `motivation ∈ {DEFICIT_DRIVEN, LONG_RUN}`. The codebook had been through 42 iterations across two architectures before the v0.9 rewrite.

**v0.5 – v0.6.x (dense decision rules).** Reached exogenous precision 0.812 at iter 32 (v0.6.1). But iter 36's evidence-shuffle leakage diagnostic exposed an F–A median-stability gap of **−0.333** under k=3 deterministic permutations of the C2a evidence array on the 33-act F+A clusters from iter-30 manual analysis. F-cluster acts (the ones v0.6.1 misclassified) were order-fragile. The verdict was *overfit to the 39-act test set*, attributable to the dense DR1–DR4 / BCR1–BCR4 decision rules whose specificity had been tuned to fix individual misclassifications.

**v0.7.0 (Das-et-al.-inspired minimal, 2026-05-01, iter 37).** Dropped the entire `classes` block, dropped DR/BCR rule ladders, collapsed output to a binary `exogenous` flag. Stability gap recovered to **0.000**. But exogenous precision collapsed to **0.500** (iter 39 S2). Worse, with no `classes` the H&K behavioral tests V/VI/VII (exclusion criteria, generic labels, swapped labels) became degenerate and skipped automatically — so the codebook could not be ablation-tested.

**v0.8.0 (2026-05-02, iter 41-42).** Added timing extraction (`enacted_quarter[]`) and sign back into C2b alongside the binary exogeneity surface. Sign accuracy on true-exogenous: 0.957 PASS. Exogenous precision: **0.500**, identical to v0.7.0 — the iter 41/42 numbers reproduce v0.7.0's iter 39 numbers digit-for-digit on the same 39-act primary test set.

The state immediately before the rewrite, then, was: a 0.500 exogenous-precision floor that two architectures had failed to break, a known overfit pattern blocking re-entry to the v0.6.x dense-rule design, and a behavioral-test apparatus (H&K Tests V/VI/VII) sitting idle because the codebook had no classes to test.

## 2. The diagnosis that preceded the rewrite (overturned premise)

The user's incoming premise was: "v0.8.0 added a one-liner that should have improved precision but actually broke things — investigate that one-liner." Before any redesign work, a diagnostic agent was tasked with finding that one-liner.

**It did not exist.** The v0.7 → v0.8 diff added only timing+sign content; every word of v0.7.0's exogeneity reasoning was preserved verbatim in v0.8.0. The iter 41/42 metrics were not a v0.8.0 regression; they were v0.7.0's iter 39 numbers reproduced because the exogeneity surface was unchanged. The real regression was **v0.6.x → v0.7.0** — the precision drop from 0.812 to 0.500 was the cost of dropping the `classes` block entirely, paid all at once at v0.7.0 and inherited intact by v0.8.0.

This finding sharpened the rewrite brief in three concrete ways:

1. The dense rules were not strictly required; the *class structure* and the *4-way labels* might be the load-bearing parts.
2. The rewrite did not need to start from v0.8.0; it needed to undo a decision made at v0.7.0.
3. Two specific failure modes from v0.8.0 inherited from v0.7.0 needed targeted guardrails: a LONG_RUN recall collapse to 1/15 (the model was treating any mention of macro context as evidence of countercyclicality, even when the stated motive was structural), and SPENDING_DRIVEN false-positives at 5/10 (the model was treating "structural" framing of a spending programme as evidence that the financing tax was exogenous).

Without this diagnostic step, the rewrite would have been chasing a phantom one-liner. The discipline matters because the cost of redesigning from a wrong premise is the same as the cost of redesigning from a right one — but the second design ships.

## 3. The composite recipe (five conspiring moves)

The rewrite combined five moves. None alone would have shipped; the v0.9 design works because they reinforce each other.

### 3.1 Constrained-optimization framing

The instruction to the writing agent was, in effect:

> *Perform task Y (write the codebook prompt) adopting language X (R&R's own) as closely as possible, subject to constraint Z (country-agnostic transferability).*

This is not an instruction to *summarise* R&R or to *paraphrase* R&R. It is an instruction to *minimise distance from R&R's own text* under a transferability constraint. Verbatim phrases that exist in R&R's papers — "return growth to normal," "raise growth above normal," "raise potential output," "inherited deficit," "actuarial soundness," "smaller government," "fairness," "improved incentives" — were quoted verbatim where they fit; the constraint shaped *how* US institutional vocabulary ("Ways and Means," "ERP," "Treasury Annual Report") was scrubbed without disturbing the substantive content.

The framing produces two effects that bare paraphrase does not. First, the prompt is auditable: a reviewer can read it and trace each substantive sentence back to a specific R&R passage. Second, the prompt aligns with the model's pretraining: Claude has read R&R, so language that hews to R&R's voice activates the right priors. Both effects fall out of the same property — proximity to a fixed authoritative source.

The *why* of the constraint matters: the project must transfer to Malaysia, Indonesia, Thailand, etc. without retraining. So the constrained-optimization is asymmetric — adopt R&R's *concepts* maximally, scrub R&R's *institutional vocabulary* completely. Country-specific examples are also forbidden in the first cut for the same reason; they would over-anchor on US institutional patterns that do not transfer.

### 3.2 Blocking the writer from prior failed versions

The writing agent (a `general-purpose` Claude Code agent with no memory of the planning conversation) was given an explicit allow-list and an explicit deny-list of files to read.

**Must read:** R&R 2010 §II.C-E; R&R companion paper §I.C, pp. 5-8 (the most authoritative source on motivation classification); `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md` §RR5 (the project's R&R distillation); `docs/literature_review.md` §1.3 (the verbatim-phrase table) and §4.2 (the cross-country mapping).

**Must NOT read:** any prior version of `prompts/c2b_classification.yml` (current or git history); the iteration log `prompts/iterations/c2b.yml`; any v0.5–v0.8 codebook content reproduced elsewhere.

**Reference template (read for shape only):** `prompts/c1_measure_id.yml` (v0.6.0, S3-passed) and the `codebook-yaml` SKILL.

The blocking matters because anchoring is real. Each failed version represents a local optimum in design space. A writer who has read v0.6.x's dense rules will tend to reproduce dense rules with cosmetic variations; a writer who has read v0.7.0's minimal Das-style design will tend to over-trust minimalism and skip the class structure. The fresh agent, by reading only the *primary source* and the *successful sister-codebook structure*, was free to land in a different region of the design space. The agent did, in fact, choose to embed edge-case guidance inside class clarifications rather than as detached rule paragraphs — a choice that v0.6.x had explicitly rejected.

There is a cost to blocking: the agent had to re-derive design knowledge that prior iterations had earned. It chose, for example, to extend `COUNTERCYCLICAL` symmetrically (covering anti-inflationary restraint, not just stimulus) — a judgment call that earlier iterations had also reached but that the agent rederived from R&R's symmetric "return growth to normal" framing. The cost was acceptable because the rederivation traced back to a primary source, not to an earlier codebook's interpretation.

### 3.3 The C1 recipe as a structural precedent

C1 (`prompts/c1_measure_id.yml` v0.6.0) had passed all H&K stages including S3 manual analysis (iter 28: 31A/6B/0E/3F, bias-corrected recall 100%, precision 83.3%). It was the only codebook in the project with a complete success record. Its structural template — `instructions / classes[label, label_definition, clarification[], negative_clarification[]] / extra_output_fields / output_instructions` — was a known-good shape.

The writing agent was instructed to read C1 *for shape only, not content*. C1 is about measure identification (a binary classification on chunks); C2b is about motivation classification (a 4-way classification on consolidated act-level evidence). The tasks share nothing semantically. But the YAML shape, the convention of separating `clarification[]` from `negative_clarification[]`, the use of `extra_output_fields` for derived metadata, and the `output_instructions` block were all directly reusable.

This is a "what worked before, do it again, structurally" move. It is small but consequential: it removed a degree of freedom from the design (no need to invent the YAML shape) and concentrated the agent's attention on the substantive content question (how to encode R&R's four categories in this shape). A useful subskill of codebook design is recognising when structural moves are off-the-table because a sister artifact has already settled them.

### 3.4 Embedded-guardrail design (rules inside class bodies, not detached)

The single largest rule-density innovation in v0.9 is *where* the edge-case rules live, not whether they exist.

Under v0.5 – v0.6.x, edge-case rules lived as detached paragraphs in the prompt: DR1, DR2, DR3 (decision rules) and BCR1, BCR2, BCR3, BCR4 (boundary case rules) were standalone enumerated lists, structurally separate from the class definitions. This made the rules visible and individually ablation-testable, but it also made them brittle: the iter 36 evidence-shuffle diagnostic showed that the F-cluster acts (those v0.6.1 misclassified) were order-fragile under permutation of the C2a evidence array. The interpretation: the detached rules had been over-tuned to fire on specific patterns in specific evidence orderings.

Under v0.9, every edge-case rule lives *inside* the `clarification[]` or `negative_clarification[]` of the class it most affects. There are no DR or BCR ladders. The two specific guardrails targeting v0.8.0's failure modes are embedded:

- **Inside `LONG_RUN`:** the `clarification[]` includes a sentence equivalent to R&R's observation that *an act proposed when the economy was growing normally remains long-run even if the economy weakened by the time of passage*; the `negative_clarification[]` includes the Das clarifier (*mention of contemporaneous macroeconomic conditions is not by itself evidence of a countercyclical motive when the stated rationale is structural*). These two together target the LONG_RUN recall collapse to 1/15 in v0.8.0.

- **Inside `SPENDING_DRIVEN`:** the `clarification[]` includes R&R's 1-year temporal rule (a tax rise within ~1 year of an associated spending increase is spending-driven; >1 year later it shifts to deficit-driven); the `negative_clarification[]` states that "structural" framing of a spending programme does not by itself make the financing tax exogenous. These target the 5/10 SPENDING_DRIVEN false-positives in v0.8.0.

The embedded-guardrail design has two concrete properties. First, the rule and the class it modifies are read together by the model; there is no detached rule paragraph to be parsed in isolation, so the rule's activation is bound to the class context that justifies it. Second, the rule is shorter — it does not need to re-state which class it applies to, because it already lives there. The combined effect is a prompt that is more robust to evidence ordering (because the rule fires on the class context, not on surface features of the evidence) and shorter (the v0.9 prompt is 256 lines vs. v0.6.x's ~600).

### 3.5 Investigate-before-rewriting

This was covered in §2 but is itself a design move worth naming. The discipline is: when something has visibly failed, do not redesign before diagnosing what failed and why. The cost of the diagnosis (one investigative agent run, ~30 minutes) is small compared to the cost of redesigning from a wrong premise (a full rewrite cycle, multiple S0/S1/S2 iterations, sunk API spend).

The diagnostic agent in this case overturned the user's premise before the rewrite was scoped: there was no v0.8.0 one-liner to fix; the regression was a deeper architectural decision made at v0.7.0. Without this finding, the rewrite would have targeted the wrong layer.

The discipline generalises: ask "why exactly did the prior design fail?" and "do my proposed changes address the actual mechanism?" before drafting. The answers should be specific (which iteration, which metric, which acts, which mechanism), not generic ("the prompt was too dense").

## 4. The agent brief (the concrete artifact)

The brief sent to the writing agent was self-contained (~1,600 words). Its structure:

1. **Goal and context.** What the agent is producing (a single file rewrite of `prompts/c2b_classification.yml` v0.9.0), high-level history (two prior architectures, both failed in known ways), and the headline constraint (a reviewer should recognise every substantive sentence as coming from R&R).

2. **Inputs the agent MUST read.** R&R primary sources (with specific page ranges); the project's R&R distillation; the literature review's verbatim-phrase table and cross-country mapping table.

3. **Inputs the agent MUST NOT read.** Prior C2b versions, the iteration log, any historical YAML via git.

4. **Reference template (shape only).** C1 v0.6.0 and the codebook-yaml SKILL.

5. **Required output schema.** Spelled out exactly: 4-way label, sign enum, enacted boolean, confidence enum, reasoning string. Note that `exogenous` is *not* an output field — it is derived downstream.

6. **Hard guidelines.** Eight numbered constraints: R&R language fidelity; country-agnostic; four classes by R&R's own names; no examples; no dense rule ladders; the two specific guardrails embedded by construction inside the class bodies most affected by v0.8.0's failure modes; reasoning field discipline; length budget (~300-500 lines, soft).

7. **Out of scope.** No worked examples, no timing logic beyond `enacted`, no magnitude reasoning, no edits to C2a or to any R file or to the iteration log, no test runs.

8. **YAML shape template.** A pseudocode skeleton showing the expected top-level layout.

9. **Self-audit checklist.** The agent was required to verify the produced file against an explicit checklist (all four classes present; verbatim R&R phrases appear in each class; no US institutional names; no examples; no standalone rule ladders; both guardrails embedded; output schema matches; ~300-500 lines).

The brief took longer to write than the codebook itself. This is appropriate: the brief is the design specification; the codebook is its execution. A vague brief produces a vague codebook.

## 5. The product (v0.9.0 → v0.9.1)

**v0.9.0 (iter 43, commit 8c092af, 2026-05-05).** The agent produced a 256-line YAML matching all 12 self-audit items. Three judgment calls were flagged in the agent's report: (a) COUNTERCYCLICAL extended symmetrically to cover anti-inflationary restraint (R&R's logic is direction-symmetric); (b) `enacted` defaulted to FALSE when ambiguous (conservative recall bias); (c) length 256 lines vs. the 300-500 budget — the agent argued that padding would dilute per-component ablation interpretability and we accepted the argument.

**v0.9.1 (iter 44, commit f42276d, 2026-05-05).** A reconciliation patch on top of v0.9.0, two coordinated changes with no behavioural redesign:

- *YAML cleanup.* Stripped 13 inline "Romer and Romer" attributions from the prompt body to preserve country-agnostic transferability for Phase 2 (Malaysia) and beyond. Substantive content (one-year temporal rule, return-to-normal vs raise-above-normal, inherited deficit, offsetting-changes convention, timing-of-decision rule, Das clarifier) was retained verbatim; only the citations and US-decade-specific anchoring examples (1950s–70s social-insurance amendments, payroll-tax prototype) were neutralised. Preamble metadata comment retained the R&R citation as provenance. Replaced one misattributed "R&R apportionment guidance" sentence with neutral largest-share language.
- *R schema reconciliation.* The R behavioral-test runners were hard-coded to the v0.8.0 output schema (`{enacted, exogenous, sign, enacted_quarter[], confidence, reasoning}`) and would have produced NA across the board on v0.9.0's new schema (`{label, enacted, sign, confidence, reasoning}`). `R/c2_behavioral_tests.R::validate_c2b_output()` was rewritten; `test_c2b_schema_recovery` was replaced with a restored `test_c2b_definition_recovery` (the canonical 4-class H&K Test II, restored from pre-v0.7.0 lineage); `test_c2b_order_invariance` was updated to compare `{label|sign}` and derive `exogenous` from the label via the `DEFICIT_DRIVEN`/`LONG_RUN` ⇒ TRUE mapping.

The cleanup is worth naming separately because it embodies the constrained-optimization logic from §3.1: the substantive content is what should hew to R&R; the citations and US-anchoring examples are the *form* and can be scrubbed without loss. Treating these as separate concerns let v0.9.1 ship country-agnostic without re-engaging the redesign loop.

## 6. Outcomes (S1 → S2 → shuffle diagnostic → manual analysis → automated S3 → FREEZE)

### 6.1 S1 behavioral tests (iter 44)

All tests pass on the restored 4-class structure — first time since v0.6.1 that 4-way definition recovery (Test II) and order invariance over class enumeration (Test IV) are even measurable.

| Test | Result | Notes |
|---|---|---|
| I (legal outputs) | 1.000 (6/6) | Schema parses cleanly under the v0.9.1 R reconciliation. |
| II (definition recovery) | 1.000 (4/4) | All four R&R class definitions correctly recovered. |
| III (in-context examples) | N/A | Codebook ships with zero examples by design; runner skips per commit `51be788`. |
| IV (order invariance) | Fleiss κ = 1.000 | Reversed and shuffled class orderings produce identical labels on all 6 synthetic evidence sets. |

Caveat: the synthetic Test IV evidence is designed to be unambiguous. The real order-invariance test for this codebook is the evidence-shuffle diagnostic on the 39-act primary set, run as iter 46.

### 6.2 S2 zero-shot evaluation (iter 45)

39 acts, 23 true-exogenous, 16 true-endogenous. 39 API calls on the C1-`discusses_motivation==TRUE` filtered evidence (509 chunks). All quality flags clean: 0 c2a failures, 0 NA predictions on label / sign / exogenous.

| Metric | v0.9.1 | Floor (v0.7.0/v0.8.0) | Ceiling (v0.6.1) | Gate | Verdict |
|---|---|---|---|---|---|
| Exogenous Precision | **0.800** [0.630, 0.957] | 0.500 | 0.812 | ≥0.85 | Borderline (point misses by 5pp; CI contains gate) |
| Sign Accuracy on True-Exo | **0.913** [0.783, 1.000] | 0.957 | — | ≥0.90 | PASS |
| Exogenous Recall | 0.696 | — | 0.619 | — | +7.7pp vs ceiling |
| Exogenous F1 | 0.744 | 0.364 (v0.8.0) | 0.703 | — | +4.1pp vs ceiling |
| Motivation Weighted F1 | 0.665 | — | 0.66 | ≥0.70 (secondary) | At ceiling |

Per-class accuracy on the 4-way classification: COUNTERCYCLICAL 0.833, DEFICIT_DRIVEN 0.875, SPENDING_DRIVEN 0.700, LONG_RUN 0.467. The LONG_RUN weakness is driven by 6 LR→COUNTERCYCLICAL false-negatives on tax acts that combine cyclical context with structural rationale — Revenue Act of 1964 (Kennedy-Johnson tax cut), Revenue Act of 1971/1978, Tax Adjustment Act 1966, Tax Reduction and Simplification Act 1977, Public Law 90-26. The model picks COUNTERCYCLICAL on the basis of "close the production gap / achieve full employment / 4-5M unemployed" language; R&R coded these LONG_RUN on the basis of the underlying structural-reform rationale. All 6 LR→CC errors have correct sign — the model reads direction right and disagrees only on motivation classification.

The headline reading: v0.9.1 essentially recovers the v0.6.1 ceiling on exogenous precision (within bootstrap CI) while improving recall by +7.7pp, F1 by +4.1pp, and gaining a passing sign accuracy. The 4-way R&R-anchored architecture delivers the design intent of restoring the v0.6.x performance without re-introducing the dense-rule failure mode.

### 6.3 Evidence-shuffle leakage diagnostic (iter 46)

This was the gating overfit check. The diagnostic config is identical to iter 36 (k=3 deterministic shuffles, seed=42, same 33-act F+A clusters from v0.6.1's iter-30 manual analysis). Hard threshold: F–A median-stability gap > −0.10.

**Verdict: fail (F–A gap = −0.333, identical to v0.6.1 at iter 36).**

But the failure is asymmetric in a way that v0.6.1's was not. A-cluster stability is now near-perfect (24 acts, mean 0.972, Fleiss κ 0.964 "almost-perfect agreement"), with only one act unstable (Social Security Amendments of 1983) and that instability a `SPENDING_DRIVEN`↔`DEFICIT_DRIVEN` label flip with the exogenous regime preserved (both endogenous). F-cluster stability is moderate (9 acts, mean 0.556, Fleiss κ 0.497 "moderate agreement"), concentrated on six borderline acts including the LR↔CC drift on Revenue Acts 1964/1978 (the canonical Kennedy-Johnson boundary cases) and CC↔SPENDING_DRIVEN drift on Tax Adjustment Act 1966 and Crude Oil Windfall Profit Tax 1980.

Under v0.6.1 the instability was distributed across both clusters (A mean 0.861, F mean 0.704); under v0.9.1 it is concentrated entirely on the 9 F-cluster acts (which are by construction the cases v0.6.1 misclassified — the borderline / tough-call acts in the corpus). This is the stability profile of a well-calibrated prompt that struggles on genuinely hard cases, not the stability profile of a prompt that has memorised surface features for the in-distribution training acts. The diagnostic alone cannot distinguish "borderline cases" from "overfit anchors" without additional evidence; manual analysis (iter 47) was used as the disambiguation step.

### 6.4 S3 manual error analysis (iter 47)

Bias-corrected exogenous precision **0.833** (1.7pp below the 0.85 gate; CI on n=18 likely contains the gate). Sign accuracy on true-exogenous **0.955** (PASS).

Error distribution under H&K's six categories: 24A / 2B / 0C / 0D / 2E / 11F. Two new B precedents were established for "evaluation-framework gap" (multi-motivation or multi-quarter acts that exceed the single-label / single-sign codebook output schema — distinct from H&K's original B = "incorrect gold-standard label"); these were the EGTRRA-2001-style cases where the gold label reflects a tie-breaking convention rather than an unambiguous truth. The two E errors were traceable to a regression on one explicit one-year-temporal-rule trigger that the v0.9.1 codebook did not catch, and one LR/CC boundary where the codebook's "return to normal" test fired against R&R's underlying structural-reform reading. The 11 F errors were the F-cluster boundary cases — exactly the same acts that drove the iter 46 evidence-shuffle gap, confirming reading (a) of the diagnostic ambiguity: these are R&R-judgment-call cases, not codebook overfit anchors.

### 6.5 Automated S3: Tests V/VI/VII + ablation (iter 48)

These tests were designed under the v0.6.x classes-bearing architecture; they had been degenerate under v0.7.0/v0.8.0 (no `classes`) and were finally runnable on v0.9.1. Two latent infrastructure bugs surfaced and were fixed (commits 3642033, 4e291a4) — both had been masked by the no-classes early-return guard for two architectural cycles.

| Test | Measurement | Reading |
|---|---|---|
| V (exclusion criteria) | Combo 1 (normal/normal) 1.000; combo 2 (modified ev / normal cb) 0.923; combo 3 (normal ev / modified cb) 0.923; combo 4 (modified/modified) **0.308** | Strong robustness to one-sided perturbation (combos 2/3); partial — not absolute — `negative_clarification` enforcement on combo 4 (the model treats exclusion clauses as soft signals). 27/39 acts retain the original label despite an explicit override. |
| VI (generic labels) | Δaccuracy −0.034; change rate 0.079 | Tiny degradation under `LABEL_1..LABEL_4` substitution. The model is *not* anchoring on the semantic R&R label strings; it reasons from definitions/evidence and the labels are largely interchangeable. |
| VII (swapped labels) | follows-names 0.974, follows-definitions 0.026 | Predictions stick with original label slots 97.4% of the time despite definitions being rotated. Combined with VI, this indicates the model classifies via internalized priors (R&R-style fiscal-policy reasoning from pretraining) rather than re-reading the codebook definitions on each call. |

Ablation (4 conditions on the 39-act test set; baseline accuracy 0.667):

| Condition | Accuracy | wF1 | Drop vs full |
|---|---|---|---|
| full | 0.667 | 0.665 | — |
| no_label_def | 0.615 | 0.618 | −5.1pp acc / −4.7pp wF1 |
| no_clarifications | 0.641 | 0.635 | −2.6pp acc / −2.9pp wF1 |
| all_removed | 0.590 | 0.548 | −7.7pp acc / −11.7pp wF1 |

Even all-removed retains 59% accuracy on the 4-way task — well above the 25% chance baseline. The label_definition is the largest single removable component (5.1pp), but no individual section is dominant. The codebook adds calibration on top of strong pretraining priors.

### 6.6 FREEZE decision (iter 48)

User decision: **freeze v0.9.1 as the C2 codebook deliverable; deploy to Malaysia (Phase 2 pilot).**

Rationale: iter 47 (manual S3, bias-corrected exo precision 0.833 borderline; sign 0.955 PASS) and iter 48 (automated S3 plus ablation) converge on a single reading. The model has internalized R&R-style fiscal motivation reasoning from pretraining (Tests VI/VII), and the codebook adds modest calibration on top (≤7.7pp accuracy / ≤11.7pp wF1 drops under ablation). The exogenous precision miss (1.7pp below gate, point 0.833) is borderline, the sign gate passes, and the residual errors (2 E, 11 F) are dominated by R&R-judgment-call boundary cases rather than fixable codebook deficiencies. Three recommendations are carried forward as deferred (not rejected): (i) iter 47's MINOR REVISION proposal to restore v0.6.1's causal-link priority rule analog inside SD and BCR1(b) analog inside LR for suspended-structural-provision cases — revisit if Malaysia pilot reveals analogous E-category cases; (ii) the Test V combo 4 partial-exclusion finding as a known zero-shot limitation — re-evaluate if cross-country deployment requires harder guardrails; (iii) C4 development requirement to include worked sign-mapping examples for credit suspension/restoration cases.

## 7. The interpretive reading

Three pieces of evidence point to one reading.

1. **Tests VI/VII say the model is using priors, not definitions.** Generic labels barely degrade performance (Δaccuracy −0.034); rotated definitions barely shift predictions (follows-definitions rate 0.026). The model is not re-reading the codebook each call — it is classifying from internalized fiscal-policy reasoning learned in pretraining.

2. **Ablation says the codebook adds calibration, not foundation.** The full prompt scores 0.667 on accuracy; stripping every codebook section retains 0.590. The codebook adds 7.7 percentage points on accuracy / 11.7 on wF1. That is real and measurable — but it is calibration on top of a strong prior, not the source of the prior.

3. **The evidence-shuffle gap is genuinely about borderline cases.** A-cluster stability is near-perfect; F-cluster instability is concentrated on the same acts that drove the manual-analysis F errors (Revenue Acts 1964/1978, Tax Adjustment Act 1966, Crude Oil 1980). These are the acts where R&R's coding decisions are themselves judgment calls — not artifacts of overfit prompting.

The combined reading: the v0.9 codebook works because it harnesses pretraining knowledge of R&R, not because it teaches the model R&R from scratch. The constrained-optimization framing succeeds because it maps the prompt onto familiar terrain in the model's prior. The R&R-language-fidelity constraint is, in effect, an *activation* constraint: by quoting R&R's own phrases, the prompt activates the right region of the model's learned distribution; the codebook then narrows the activation with calibration signal (class definitions, clarifications, embedded guardrails).

This reading has a sharp implication. For domains where the model has strong pretraining knowledge of an authoritative source, source-anchored prompts that quote the source verbatim are likely to outperform paraphrased or invented language — *even when the paraphrase says exactly the same thing*. The mechanism is activation, not semantics. Whether this generalises beyond R&R-on-Claude is an open question; this case study cannot answer it.

## 8. Honest scope (n=1)

Everything in this document is one codebook on one model on one corpus. The case is interesting because the design moves are individually familiar but combine into something that worked where two prior architectures did not. It is not strong evidence that the recipe transfers.

What would upgrade the claim:

- **Replication on C3 (timing) and C4 (magnitude)** with the same recipe — same agent setup, same R&R-anchored constraint, same blocked-anchoring discipline, same C1/C2 structural template, same embedded-guardrail design. If C3/C4 also pass their gates on first or second cut, n becomes 3.
- **Replication on Malaysia data (Phase 2 pilot).** The constrained-optimization claim is partially testable: if v0.9.1 transfers to Malaysia with expert agreement ≥70% on motivation classification (the Phase 2 gate), the country-agnostic constraint did its job.
- **An ablation that isolates the constrained-optimization framing from the other moves.** Hard to construct experimentally — but a counterfactual rewrite using paraphrased R&R language (matched semantics, different surface phrases) could test whether *verbatim activation* is doing real work or whether *any clear paraphrase* would suffice.

Two threats to the reading should be noted explicitly.

- **Ground-truth saturation.** The 39-act primary test set is the same set the manual error analysis used. If the v0.9 codebook is over-tuned to the iter-30 F-cluster acts indirectly (via the project's accumulated knowledge of which acts are hard), the apparent gain over v0.7.0/v0.8.0 could be partly an artifact of *which mistakes we already understand*. The ablation results push back on this (the codebook contributes only 7.7pp), but a hold-out test set would settle it. We do not have one.
- **Pretraining contamination.** The model knows R&R from pretraining. This is the *mechanism* the constrained-optimization framing exploits, but it also means the test set acts have been seen in some form during training. The Phase 2 Malaysia pilot is the clean replication: Malaysia fiscal acts are unlikely to have been classified by R&R in pretraining data.

## 9. The recipe sketched for C3 and C4

Speculative; included so the project can re-apply the pattern.

**C3 (Timing).** Source: R&R 2010 §II.D and companion paper §I.D on quarter assignment (midpoint rule, phased changes, retroactive standard-vs-adjusted series). Constraint: country-agnostic timing arithmetic (the midpoint rule is universal; signing-vs-effective-date conventions vary). Structural template: C1 + C2b + the codebook-yaml SKILL. Embedded-guardrail candidates: "if the evidence names both signing and effective date, prefer effective date" inside the relevant class; "retroactive components per the standard series — implementation quarter only" inside the negative_clarification of the wrong handling. Ablation hypothesis: with timing being a more procedural task than motivation, codebook contribution may be larger than C2b's 7.7pp because the model's pretraining priors on the specific R&R midpoint rule are weaker.

**C4 (Magnitude).** Source: R&R 2010 §II.D and companion paper §I.D on revenue estimation (consensus estimate, fallback hierarchy, annual-rate convention, present-value alternative). Constraint: domestic-currency normalisation (the dollar-vs-local-currency dimension breaks pure constrained-optimization on R&R's text; the constraint becomes "adopt R&R's *conventions* in country-local currency"). Carry forward iter 48's deferred recommendation: include worked sign-mapping examples for credit suspension/restoration cases. Honest note: C4 may not be feasible as a country-agnostic codebook at all if the magnitude conventions vary too much; an alternative is to ship C4 as a per-country specialisation rather than a single codebook.

In both cases the same five moves should apply: investigate before rewriting (especially since C3 and C4 are starting from no prior); fresh blocked-anchoring agent; C1/C2b structural template; R&R-anchored constrained optimization; embedded guardrails inside class bodies. The expectation is that the recipe will need adjustment, not replacement.

---

## Appendix: Iteration index for this case study

| Iter | Date | Stage | Codebook | Headline |
|---|---|---|---|---|
| 35 | 2026-04-29 | s3_manual | v0.6.1 | Bias-corrected accuracy 0.714; structural ceiling diagnosed |
| 36 | 2026-04-29 | s3_leakage | v0.6.1 | F–A median-stability gap −0.333 (overfit verdict) |
| 37 | 2026-05-01 | s0 | v0.7.0 | Das-inspired binary minimal redesign |
| 39 | 2026-05-01 | s2 | v0.7.0 | Exogenous precision 0.500 (regression) |
| 40 | 2026-05-01 | s3_leakage | v0.7.0 | F–A gap 0.000 (stability recovered) |
| 41 | 2026-05-04 | s1 | v0.8.0 | Tests pass on extended schema |
| 42 | 2026-05-04 | s2 | v0.8.0 | Exogenous precision 0.500 (v0.7 verbatim); sign 0.957 PASS |
| 43 | 2026-05-05 | s0 | **v0.9.0** | 4-class R&R-anchored rewrite by fresh agent (8c092af) |
| 44 | 2026-05-05 | s1 | v0.9.1 | All tests pass on restored 4-class structure |
| 45 | 2026-05-05 | s2 | v0.9.1 | Exogenous precision 0.800 [0.630, 0.957]; sign 0.913 PASS |
| 46 | 2026-05-06 | s3_leakage | v0.9.1 | F–A gap −0.333 again, but asymmetric (A near-perfect, F moderate) |
| 47 | 2026-05-06 | s3_manual | v0.9.1 | 24A/2B/0C/0D/2E/11F; bias-corrected exo precision 0.833 |
| 48 | 2026-05-06 | s3 | v0.9.1 | Tests V/VI/VII + ablation; **FREEZE decision; Malaysia deployment authorized** |

Codebook YAMLs at any past version are recoverable via `git show <commit>:prompts/c2b_classification.yml` using the `git_commit` field of the corresponding iteration entry in `prompts/iterations/c2b.yml`.
