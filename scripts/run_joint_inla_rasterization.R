#!/usr/bin/env Rscript

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
script_path <- sub("^--file=", "", script_arg)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"), local = .GlobalEnv)

parse_args <- function(args) {
  values <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (grepl("=", name, fixed = TRUE)) {
      parts <- strsplit(name, "=", fixed = TRUE)[[1L]]
      if (length(parts) != 2L || !nzchar(parts[[1L]])) stop("Malformed inline argument: ", key)
      values[[parts[[1L]]]] <- parts[[2L]]
      i <- i + 1L
      next
    }
    if (identical(name, "overwrite") || identical(name, "no-diagnostics")) {
      values[[name]] <- TRUE
      i <- i + 1L
    } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) stop("Missing value for ", key)
      values[[name]] <- args[[i + 1L]]
      i <- i + 2L
    }
  }
  values
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
phase2_dir <- args[["phase2-output"]] %||% Sys.getenv("PHASE3_PHASE2_OUTPUT", unset = NA_character_)
if (is.na(phase2_dir) || !nzchar(phase2_dir)) stop("Supply --phase2-output or PHASE3_PHASE2_OUTPUT for the private Phase 2 directory.")
run_id <- args[["run-id"]] %||% paste0("raster_", format(Sys.time(), "%Y%m%d_%H%M%S"))
output_dir <- args[["output"]] %||% file.path(dirname(phase2_dir), paste0("raster_surfaces_", run_id))
expected_weeks <- if (is.null(args[["expected-weeks"]])) NULL else as.integer(args[["expected-weeks"]])
expected_rows <- if (is.null(args[["expected-rows"]])) NULL else as.integer(args[["expected-rows"]])
source_phase2_commit <- args[["source-phase2-commit"]] %||% NULL
stage2_artifact <- args[["stage2-artifact"]] %||% NULL
template_path <- args[["template"]] %||% NULL

result <- joint_inla_rasterize_run(
  phase2_dir = phase2_dir,
  stage2_artifact = stage2_artifact,
  template_path = template_path,
  output_dir = output_dir,
  run_id = run_id,
  expected_weeks = expected_weeks,
  expected_rows = expected_rows,
  source_phase2_commit = source_phase2_commit,
  diagnostic = !isTRUE(args[["no-diagnostics"]]),
  overwrite = isTRUE(args[["overwrite"]]),
  repo_root = repo_root
)

audit <- result$audit
cat("Phase 3 rasterization complete\n")
cat("Output: ", result$output_dir, "\n", sep = "")
cat("Weeks: ", nrow(result$temporal_manifest), "\n", sep = "")
cat("Rasters: ", nrow(result$manifest), "\n", sep = "")
cat("Audit PASS/WARNING/FAIL: ", sum(audit$status == "PASS"), "/", sum(audit$status == "WARNING"), "/", sum(audit$status == "FAIL"), "\n", sep = "")
if (any(audit$status == "FAIL")) quit(status = 1L)
