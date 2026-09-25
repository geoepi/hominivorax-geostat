#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"), local = .GlobalEnv)

parse_args <- function(args) {
  values <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
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
phase2_dir <- args[["phase2-output"]] %||% "/project/disease_ecology/nws-geostat-output/joint_inla_fit/prediction_projection_20725437"
run_id <- args[["run-id"]] %||% "20725437"
output_dir <- args[["output"]] %||% file.path(dirname(phase2_dir), paste0("raster_surfaces_", run_id))
expected_weeks <- as.integer(args[["expected-weeks"]] %||% 105L)
expected_rows <- as.integer(args[["expected-rows"]] %||% 1669395L)
source_phase2_commit <- args[["source-phase2-commit"]] %||% "1bcb6deb554c6f9b84013040487fbdb9470a2c0e"
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
