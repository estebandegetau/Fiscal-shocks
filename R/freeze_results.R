#' Freeze a validated target result to disk
#'
#' Promotes a targets result to `data/validated/<target_name>.qs` so that
#' downstream targets can depend on the file hash instead of the full R
#' function dependency chain. Use after a stage gate passes to decouple
#' validated results from upstream code changes.
#'
#' @param target_name Character name of the target to freeze (e.g., "c2_input_data")
#' @return Invisible file path to the frozen `.qs` file
#' @export
freeze_results <- function(target_name) {
  result <- targets::tar_read_raw(target_name)
  dir.create("data/validated", showWarnings = FALSE, recursive = TRUE)
  path <- file.path("data", "validated", paste0(target_name, ".qs"))
  qs2::qs_save(result, path)

  meta <- list(
    target = target_name,
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE)
  )
  yaml::write_yaml(meta, sub("\\.qs$", "_meta.yml", path))

  message(sprintf("Frozen %s -> %s", target_name, path))
  invisible(path)
}
