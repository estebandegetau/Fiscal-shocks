# Verification script for Model A fix
# Run this AFTER tar_make() to verify the JSON examples are correct

library(jsonlite)
library(here)

cat("=" , rep("=", 70), "\n", sep="")
cat("VERIFICATION: Model A Few-Shot Examples JSON Structure\n")
cat("=" , rep("=", 70), "\n\n", sep="")

# Load the regenerated examples
examples_file <- here("prompts", "model_a_examples.json")

if (!file.exists(examples_file)) {
  cat("❌ ERROR: Examples file not found at:", examples_file, "\n")
  cat("   Run tar_make() first to regenerate the file.\n")
  quit(status = 1)
}

examples <- fromJSON(examples_file, simplifyVector = FALSE)

cat("✓ Loaded", length(examples), "examples from JSON file\n\n")

# Check structure of each example
all_valid <- TRUE
issues <- c()

for (i in seq_along(examples)) {
  ex <- examples[[i]]

  # Check if output exists
  if (is.null(ex$output)) {
    issues <- c(issues, sprintf("Example %d: Missing 'output' field", i))
    all_valid <- FALSE
    next
  }

  # Check act_name type
  act_name <- ex$output$act_name

  if (is.list(act_name)) {
    issues <- c(issues, sprintf("Example %d: ❌ act_name is a LIST (should be string or null)", i))
    all_valid <- FALSE
  } else if (is.null(act_name)) {
    # NULL is OK for negative examples
    cat(sprintf("Example %d: ✓ act_name is null (negative example)\n", i))
  } else if (is.character(act_name) && length(act_name) == 1) {
    cat(sprintf("Example %d: ✓ act_name is '%s' (single string)\n", i, act_name))
  } else {
    issues <- c(issues, sprintf("Example %d: ❌ act_name has unexpected type/length", i))
    all_valid <- FALSE
  }
}

cat("\n")
cat("=" , rep("=", 70), "\n", sep="")

if (all_valid) {
  cat("✅ ALL EXAMPLES VALID\n")
  cat("   All act_name fields are properly formatted as single strings or null.\n")
  cat("   The LLM will now return act_name as a string, not an array.\n")
} else {
  cat("❌ VALIDATION FAILED\n\n")
  cat("Issues found:\n")
  for (issue in issues) {
    cat("  -", issue, "\n")
  }
  cat("\nThe examples file may need manual inspection.\n")
}

cat("=" , rep("=", 70), "\n", sep="")
