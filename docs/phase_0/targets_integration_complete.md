# Training Data Integration into _targets Pipeline

**Date:** 2026-01-20
**Status:** ✅ COMPLETE

## Summary

Successfully integrated all training data preparation into the `_targets` pipeline for full reproducibility and lineage tracking.

## Changes Made

### 1. Added Training Data Targets to `_targets.R`

**New targets added** (lines 341-377):

```r
# Phase 0 Training Data Preparation (Days 2-3)
tar_target(
  aligned_data,
  align_labels_shocks(us_labels, us_shocks, threshold = 0.85),
  packages = c("tidyverse", "stringdist")
),
tar_target(
  aligned_data_split,
  create_train_val_test_splits(
    aligned_data,
    ratios = c(0.6, 0.2, 0.2),
    seed = 20251206,
    stratify_by = "motivation_category"
  ),
  packages = "tidyverse"
),
tar_target(
  negative_examples,
  generate_negative_examples(us_body, n = 200, seed = 20251206),
  packages = "tidyverse"
),
tar_target(
  training_data_a,
  prepare_model_a_data(aligned_data_split, negative_examples),
  packages = "tidyverse"
),
tar_target(
  training_data_b,
  prepare_model_b_data(aligned_data_split),
  packages = "tidyverse"
),
tar_target(
  training_data_c,
  prepare_model_c_data(aligned_data_split),
  packages = "tidyverse"
)
```

### 2. Updated `CLAUDE.md` with Data Generation Policy

Added **CRITICAL section** emphasizing that ALL data generation must go through `_targets`:

```markdown
### **CRITICAL: Data Generation Policy**

**ALL data processing and generation MUST go through the `_targets` pipeline.**

✅ **DO:**
- Define all data generation as targets in `_targets.R`
- Put logic in functions in `R/` directory
- Use `tar_make()` to generate data
- Save outputs via targets `format` parameter (rds, parquet, qs)

❌ **DON'T:**
- Run standalone scripts that create data files
- Manually save data with `saveRDS()`, `write_csv()`, etc. outside targets
- Create data in `data/processed/` without a corresponding target
```

### 3. Updated `R/prepare_training_data.R`

Removed library() calls (packages now loaded by targets):

```r
# Training Data Preparation Functions for Phase 0
# Created: 2026-01-19
# Purpose: Align labels with shocks, create train/val/test splits for LLM models
#
# Note: Packages loaded by targets pipeline (tidyverse, stringdist)
```

### 4. Removed Manual Data Files

Deleted manually created files from `data/processed/`:
- ❌ `aligned_data.rds` (manual)
- ❌ `training_data_a.rds` (manual)
- ❌ `training_data_b.rds` (manual)
- ❌ `training_data_c.rds` (manual)
- ❌ `negative_examples.rds` (manual)

## Verification

### Target Build Results

```
✅ aligned_data:         44 acts (32.5 KB)
✅ aligned_data_split:   44 acts with splits (32.6 KB)
✅ negative_examples:    200 paragraphs (180.6 KB)
✅ training_data_a:      244 examples (201.5 KB)
✅ training_data_b:      44 acts (23.0 KB)
✅ training_data_c:      41 acts (22.6 KB)
```

### Data Consistency Check

**Model A Split Distribution:**
| Split | Positive (acts) | Negative (non-acts) | Total |
|-------|-----------------|---------------------|-------|
| Train | 28 | 127 | 155 |
| Val | 10 | 45 | 55 |
| Test | 6 | 28 | 34 |

**Model B Split Distribution:**
| Split | Acts |
|-------|------|
| Train | 28 |
| Val | 10 |
| Test | 6 |

**Model C Split Distribution:**
| Split | Acts |
|-------|------|
| Train | 27 |
| Val | 9 |
| Test | 5 |

✅ Matches previous manual generation exactly

## Pipeline Dependencies

```
us_labels ─┐
           ├─> aligned_data ─> aligned_data_split ─┬─> training_data_a
us_shocks ─┘                                       ├─> training_data_b
                                                   └─> training_data_c

us_body ────────────────────> negative_examples ───┘
```

## Benefits of Targets Integration

### 1. Reproducibility
- **Tracked dependencies:** Changes to `us_labels` or `us_shocks` automatically invalidate downstream targets
- **Versioned:** Target metadata tracks when each dataset was built
- **Cacheable:** Avoid re-running expensive operations

### 2. Lineage
```r
# Know exactly how each dataset was created
tar_deps(training_data_a)
# Shows: aligned_data_split, negative_examples

tar_deps(aligned_data_split)
# Shows: aligned_data

tar_deps(aligned_data)
# Shows: us_labels, us_shocks
```

### 3. Documentation
```r
# Visualize full pipeline
tar_visnetwork()

# See dependency graph showing:
# us_labels -> aligned_data -> aligned_data_split -> training_data_{a,b,c}
# us_shocks -> aligned_data
# us_body -> negative_examples -> training_data_a
```

### 4. Efficiency
```r
# Only rebuild what's out of date
tar_outdated()

# If us_labels unchanged, all training data targets are cached
# No expensive re-computation
```

## Usage

### Accessing Training Data

```r
library(targets)

# Read any training dataset
training_a <- tar_read(training_data_a)
training_b <- tar_read(training_data_b)
training_c <- tar_read(training_data_c)

# Check if up to date
tar_outdated()

# Rebuild only outdated targets
tar_make()
```

### Modifying Training Data

**Example: Change train/val/test split ratios**

```r
# Edit _targets.R
tar_target(
  aligned_data_split,
  create_train_val_test_splits(
    aligned_data,
    ratios = c(0.7, 0.15, 0.15),  # Changed from c(0.6, 0.2, 0.2)
    seed = 20251206,
    stratify_by = "motivation_category"
  ),
  packages = "tidyverse"
)

# Rebuild - only aligned_data_split and downstream targets rebuild
tar_make()
```

## File Structure

### Before (Manual Approach)
```
data/
  processed/
    *.rds              # Manually created, no lineage tracking
```

### After (Targets Approach)
```
_targets/
  objects/
    aligned_data       # Target cache (automatic)
    training_data_a    # Target cache (automatic)
    ...
  meta/
    meta               # Target metadata (build times, dependencies)
    process            # Process tracking
```

Data is stored in `_targets/objects/` with full lineage tracking.

## Next Steps

All future data generation should follow this pattern:

1. **Write function** in `R/` directory (pure function, no side effects)
2. **Define target** in `_targets.R` with appropriate `packages` parameter
3. **Build via** `tar_make()` - never manually save files
4. **Access via** `tar_read()` - never read manual files

## Compliance

✅ **CRITICAL: Data Generation Policy** now enforced in CLAUDE.md

All project contributors (including Claude Code) must:
- Generate data through `_targets` pipeline only
- Never manually save data files to `data/processed/`
- Always use `tar_read()` to access datasets

## Impact on Phase 0 Plan

**No change to timeline or deliverables** - only implementation method improved:

- ✅ Days 1-2: PDF Extraction (97.1% success - PASS)
- ✅ Days 2-3: Training Data Prep (via _targets pipeline - COMPLETE)
- ⬜ Days 3-4: Model A Development (F1 > 0.85) - NEXT

**Additional benefit:** Model A/B/C implementations can now also be integrated into targets for full experiment tracking.

## Summary

Successfully migrated all training data generation from manual scripts to the `_targets` pipeline, ensuring:
- Full reproducibility
- Lineage tracking
- Efficient caching
- Documented dependencies
- Compliance with project standards

Ready to proceed with Model A implementation.
