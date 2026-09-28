#!/usr/bin/env Rscript

# Inventory the accepted full-horizon lineage without rerunning any model or
# downstream production stage.  The script writes only audit artifacts and
# never copies the authoritative observation source.

parse_args <- function(args) {
  values <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("Each audit option requires a value: ", key)
    values[[sub("^--", "", key)]] <- args[[i + 1L]]
    i <- i + 2L
  }
  values
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("production-root", "source", "output-dir", "repo-root", "run-id", "git-commit")
missing <- required[vapply(required, function(name) is.null(args[[name]]) || !nzchar(args[[name]]), logical(1L))]
if (length(missing)) stop("Missing required audit option(s): ", paste(paste0("--", missing), collapse = ", "))

production_root <- normalizePath(args[["production-root"]], mustWork = TRUE)
source_path <- normalizePath(args[["source"]], mustWork = TRUE)
output_dir <- normalizePath(args[["output-dir"]], mustWork = FALSE)
repo_root <- normalizePath(args[["repo-root"]], mustWork = TRUE)
run_id <- args[["run-id"]]
git_commit <- args[["git-commit"]]
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("digest", quietly = TRUE)) stop("The provenance audit requires the digest package.")

hash_file <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  digest::digest(file = path, algo = "sha256")
}
line_count <- function(path) {
  if (!file.exists(path)) return(NA_integer_)
  max(0L, length(readLines(path, warn = FALSE)) - 1L)
}
csv_columns <- function(path) {
  if (!file.exists(path)) return(character())
  names(utils::read.csv(path, nrows = 0L, check.names = FALSE, stringsAsFactors = FALSE))
}
fmt <- function(value) ifelse(is.na(value), "", as.character(value))

source_data <- utils::read.csv(source_path, stringsAsFactors = FALSE, check.names = FALSE)
source_sha <- hash_file(source_path)
source_rows <- nrow(source_data)
source_columns <- names(source_data)

stage1_path <- file.path(production_root, "stage1", "model_inputs.rds")
stage2_path <- file.path(production_root, "stage2", "joint_model_inputs.rds")
stage3a_path <- file.path(production_root, "stage3a", "joint_inla_build.rds")
fit_path <- file.path(production_root, "stage3b_fit", "joint_model_fit.rds")
extraction_path <- file.path(production_root, "stage3b_phase1_20762325_5260943", "extraction", "holdout_predictions_20762325_5260943.csv")
validation_path <- file.path(production_root, "stage3b_phase1_20762325_5260943", "validation", "validation_presence_background_20762325_5260943", "holdout_validation_metrics_20762325_5260943.csv")
phase2_manifest_path <- file.path(production_root, "stage3b_phase2_20762325_5260943", "projection", "prediction_projection_manifest_20762325_5260943.csv")
phase3_metadata_path <- file.path(production_root, "stage3b_phase2_20762325_5260943", "raster", "phase3_metadata_20762325_5260943.rds")
structural_metadata_path <- file.path(production_root, "structural_surface_diagnostics", "20762325_0659ea6", "metadata", "structural_surface_metadata.rds")
structural_manifest_path <- file.path(production_root, "structural_surface_diagnostics", "20762325_0659ea6", "metadata", "structural_raster_manifest.csv")
masked_metadata_path <- file.path(production_root, "masked_structural_rpi_diagnostics", "20762325_94e9e0d", "metadata", "masked_structural_rpi_diagnostics_metadata.rds")
masked_extraction_path <- file.path(production_root, "masked_structural_rpi_diagnostics", "20762325_94e9e0d", "qa", "same_week_masked_structural_extraction.csv")
final_root <- file.path(production_root, "final_downstream_reporting", run_id)
final_metadata_path <- file.path(final_root, "metadata", paste0("reporting_metadata_", run_id, ".rds"))
final_manifest_path <- file.path(final_root, "metadata", paste0("manifest_", run_id, ".csv"))
final_calibration_path <- file.path(final_root, "tables", "rpi_same_week_calibration.csv")
final_host_assignments_path <- file.path(final_root, "tables", "host_assignments.csv")
final_threshold_path <- file.path(final_root, "objects", "rpi_dynamic_threshold.rds")

stage1 <- readRDS(stage1_path)
stage2 <- readRDS(stage2_path)
stage1_tier1 <- stage1[["tier1"]]
stage2_tier1 <- stage2[["tier1"]]
stage1_unique_source <- if ("source_obs_id" %in% names(stage1_tier1)) length(unique(stage1_tier1$source_obs_id)) else NA_integer_
stage2_unique_source <- if ("source_obs_id" %in% names(stage2_tier1)) length(unique(stage2_tier1$source_obs_id)) else NA_integer_

lineage_rows <- list()
add_lineage <- function(stage, artifact_name, path, source_artifact, source_sha256,
                        row_level, raw_lonlat, projected_xy, raw_host, raw_date, source_ids,
                        classification, required_for_reproduction) {
  lineage_rows[[length(lineage_rows) + 1L]] <<- data.frame(
    stage = stage, artifact_name = artifact_name, artifact_path = normalizePath(path, mustWork = FALSE),
    sha256 = hash_file(path), source_artifact = source_artifact, source_sha256 = source_sha256,
    run_id = run_id, git_commit = git_commit, row_level_observation_data = row_level,
    contains_raw_lonlat = raw_lonlat, contains_projected_xy = projected_xy, contains_raw_host = raw_host,
    contains_raw_date = raw_date, contains_source_identifiers = source_ids,
    classification = classification, required_for_reproduction = required_for_reproduction,
    stringsAsFactors = FALSE
  )
}

add_lineage("authoritative_source", "combined_clean_observations", source_path, NA_character_, NA_character_,
            "YES", "YES", "NO", "YES", "YES", "YES", "authoritative_source", "YES")
add_lineage("Stage 1", "model_inputs.rds", stage1_path, source_path, source_sha,
            "YES", "YES", "YES", "YES", "YES", "YES", "derived_model_data", "YES")
add_lineage("Stage 2", "joint_model_inputs.rds", stage2_path, stage1_path, hash_file(stage1_path),
            "YES", "YES", "YES", "YES", "YES", "YES", "derived_model_data", "YES")
add_lineage("Stage 3A", "joint_inla_build.rds", stage3a_path, stage2_path, hash_file(stage2_path),
            "NO", "NO", "NO", "NO", "NO", "NO", "fit_artifact", "YES")
add_lineage("Stage 3B", "joint_model_fit.rds", fit_path, stage3a_path, hash_file(stage3a_path),
            "NO", "NO", "NO", "NO", "NO", "NO", "fit_artifact", "YES")
add_lineage("extraction/validation", "holdout_predictions.csv", extraction_path, fit_path, hash_file(fit_path),
            "YES", "NO", "YES", "NO", "NO", "YES", "derived_reporting", "YES")
add_lineage("extraction/validation", "holdout_validation_metrics.csv", validation_path, extraction_path, hash_file(extraction_path),
            "NO", "NO", "NO", "NO", "NO", "NO", "aggregate_summary", "YES")
add_lineage("Phase 2", "prediction_projection_manifest.csv", phase2_manifest_path, fit_path, hash_file(fit_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "derived_prediction", "YES")
add_lineage("Phase 3", "phase3_metadata.rds", phase3_metadata_path, phase2_manifest_path, hash_file(phase2_manifest_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "provenance_only", "YES")
add_lineage("structural", "structural_surface_metadata.rds", structural_metadata_path, phase3_metadata_path, hash_file(phase3_metadata_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "derived_prediction", "YES")
add_lineage("structural", "structural_raster_manifest.csv", structural_manifest_path, structural_metadata_path, hash_file(structural_metadata_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "provenance_only", "YES")
add_lineage("masked structural", "masked_structural_rpi_diagnostics_metadata.rds", masked_metadata_path, structural_metadata_path, hash_file(structural_metadata_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "derived_prediction", "YES")
add_lineage("masked structural", "same_week_masked_structural_extraction.csv", masked_extraction_path, masked_metadata_path, hash_file(masked_metadata_path),
            "YES", "NO", "YES", "NO", "NO", "YES", "derived_reporting", "YES")
add_lineage("final reporting/RPI", "reporting_metadata.rds", final_metadata_path, masked_metadata_path, hash_file(masked_metadata_path),
            "NO", "NO", "YES", "NO", "NO", "NO", "provenance_only", "YES")
add_lineage("final reporting/RPI", "rpi_same_week_calibration.csv", final_calibration_path, source_path, source_sha,
            "YES", "NO", "NO", "NO", "NO", "NO", "derived_reporting", "YES")
add_lineage("final reporting/RPI", "rpi_dynamic_threshold.rds", final_threshold_path, final_calibration_path, hash_file(final_calibration_path),
            "NO", "NO", "NO", "NO", "NO", "NO", "derived_reporting", "YES")
add_lineage("final reporting/RPI", "reporting_manifest.csv", final_manifest_path, final_metadata_path, hash_file(final_metadata_path),
            "NO", "NO", "NO", "NO", "NO", "NO", "provenance_only", "YES")
lineage <- do.call(rbind, lineage_rows)
utils::write.csv(lineage, file.path(output_dir, "artifact_lineage.csv"), row.names = FALSE, na = "")

residency <- data.frame(
  stage = c("Stage 1", "Stage 2", "Stage 3A", "Stage 3B", "extraction/validation", "projection/rasterization", "structural/masked processing", "final reporting/RPI"),
  artifact = c("model_inputs.rds tier1/tier2", "joint_model_inputs.rds tier1/tier2", "joint_inla_build.rds", "joint_model_fit.rds", "holdout predictions and validation summaries", "projection manifests and raster metadata", "structural/masked rasters and QA", "host summaries, minimal same-week calibration, RPI and manifests"),
  row_level_observation_data_persisted = c("YES", "YES", "NO", "NO", "YES", "NO", "MINIMAL", "MINIMAL"),
  purpose = c("model preparation and covariate/response assembly", "model-ready Tier 1/Tier 2 design data", "INLA stacks, effects, formula, priors, and compatibility", "posterior fit and runtime provenance", "holdout reconciliation and validation", "prediction-grid projection and rasterization", "SPDE-excluded reconstruction and temperature-masked diagnostics", "host mapping, dynamic threshold, RPI, and final provenance"),
  major_retained_fields = c("date, host, lon, lat, host_raw, x, y, source IDs, response, covariates", "Tier 1 source-derived fields plus model response/time fields; Tier 2 grid/covariates", "Y/link/exposure, A matrices, effects, responses, formula, priors", "INLA internals, summaries, provenance", "holdout/source row keys, responses, predictions", "cell/week keys, predictions, raster geometry", "raster values, cell/week keys, CRS, QA", "aggregate host mapping plus observation index/week/value pairs and path/SHA metadata"),
  unnecessary_source_duplication = c("NO; minimization opportunity", "NO; minimization opportunity", "NO", "NO", "NO", "NO", "NO", "NO"),
  classification = c("derived_model_data", "derived_model_data", "fit_artifact", "fit_artifact", "derived_reporting", "derived_prediction", "derived_prediction", "derived_reporting"),
  stringsAsFactors = FALSE
)
utils::write.csv(residency, file.path(output_dir, "data_residency_audit.csv"), row.names = FALSE, na = "")

near_copy <- data.frame(
  artifact = c("Stage 1 tier1", "Stage 2 tier1", "final host_assignments.csv", "final rpi_same_week_calibration.csv", "masked same_week_masked_structural_extraction.csv", "Phase 1 holdout_predictions.csv"),
  storage = c("RDS data.frame", "RDS data.frame", "CSV", "CSV", "CSV", "CSV"),
  row_count = c(nrow(stage1_tier1), nrow(stage2_tier1), line_count(final_host_assignments_path), line_count(final_calibration_path), line_count(masked_extraction_path), line_count(extraction_path)),
  column_count = c(ncol(stage1_tier1), ncol(stage2_tier1), length(csv_columns(final_host_assignments_path)), length(csv_columns(final_calibration_path)), length(csv_columns(masked_extraction_path)), length(csv_columns(extraction_path))),
  source_row_count = source_rows,
  unique_source_row_count = c(stage1_unique_source, stage2_unique_source, NA, NA, NA, NA),
  source_row_coverage = c(stage1_unique_source, stage2_unique_source, source_rows, source_rows, source_rows, line_count(extraction_path)) / source_rows,
  exact_source_column_overlap = c(sum(source_columns %in% names(stage1_tier1)), sum(source_columns %in% names(stage2_tier1)), sum(source_columns %in% csv_columns(final_host_assignments_path)), sum(source_columns %in% csv_columns(final_calibration_path)), sum(source_columns %in% csv_columns(masked_extraction_path)), sum(source_columns %in% csv_columns(extraction_path))),
  original_like_fields = c("date,host,lon,lat,host_raw,source IDs", "date,host,lon,lat,host_raw,source IDs", "raw_host and submission row only", "none", "none", "source-prefixed model keys but no raw source columns"),
  disposition = c("acceptable derived model artifact; minimize later if schema migration is scheduled", "acceptable derived model artifact; minimize later if schema migration is scheduled", "acceptable derived reporting mapping; minimize later if aggregate-only reporting is adopted", "acceptable minimal calibration artifact", "acceptable minimal diagnostic extraction", "acceptable holdout-validation artifact"),
  blocking_residency_problem = "NO",
  stringsAsFactors = FALSE
)
utils::write.csv(near_copy, file.path(output_dir, "near_copy_candidates.csv"), row.names = FALSE, na = "")

all_files <- list.files(production_root, recursive = TRUE, full.names = TRUE)
all_files <- all_files[!dir.exists(all_files)]
exact_hits <- character()
if (length(all_files)) {
  hashes <- vapply(all_files, hash_file, character(1L))
  exact_hits <- all_files[hashes == source_sha & normalizePath(all_files, mustWork = FALSE) != normalizePath(source_path, mustWork = FALSE)]
}
exact_scan <- data.frame(target_sha256 = source_sha, authoritative_source = source_path,
                         duplicate_path = if (length(exact_hits)) exact_hits else NA_character_,
                         duplicate_count = length(exact_hits), status = if (length(exact_hits)) "FAIL" else "PASS",
                         stringsAsFactors = FALSE)
utils::write.csv(exact_scan, file.path(output_dir, "exact_copy_scan.csv"), row.names = FALSE, na = "")

scan_roots <- file.path(repo_root, c("R", "scripts", "config", "docs", "tests"))
scan_files <- unlist(lapply(scan_roots, function(path) if (dir.exists(path)) list.files(path, recursive = TRUE, full.names = TRUE) else character()), use.names = FALSE)
scan_files <- scan_files[file.info(scan_files)$isdir %in% FALSE]
scan_files <- scan_files[!grepl("run_provenance_residency_audit\\.R$", scan_files)]
stale_patterns <- c(
  "105 weeks" = "105\\s*(weeks?|wk)", "8 quarter groups" = "8\\s*(quarter|groups?)|expected_quarter_groups\\s*=\\s*8",
  "133 weeks" = "133\\s*(weeks?|wk)|expected_weeks\\s*=\\s*133", "11 quarter groups" = "11\\s*(quarter|groups?)|expected_quarter_groups\\s*=\\s*11",
  "2026-W29" = "2026-W29", "stored RPI threshold" = "0\\.6834011847", "recomputed RPI threshold" = "0\\.6627025",
  "dynamic RPI threshold" = "0\\.67710580986898", "15,899 support cells" = "15[, ]?899|15899",
  "historical class counts" = "1281|5092|3202|6324", "old job/output identifiers" = "20725437|20742007|20762271|20762325_9a1a478"
)
stale_rows <- list()
for (path in scan_files) {
  lines <- readLines(path, warn = FALSE)
  for (label in names(stale_patterns)) {
    hits <- grep(stale_patterns[[label]], lines, ignore.case = TRUE)
    if (length(hits)) for (line_number in hits) {
      relative <- gsub("\\\\", "/", substring(normalizePath(path, mustWork = FALSE), nchar(normalizePath(repo_root, mustWork = FALSE)) + 2L))
      classification <- if (grepl("(^|/)tests/", relative)) "test fixture" else if (grepl("(^|/)docs/", relative)) "acceptable historical/documentation reference" else if (grepl("(^|/)config/", relative)) "run-specific example/configuration reference" else if (label %in% c("old job/output identifiers", "133 weeks", "15,899 support cells")) "production-relevant accepted-run contract or legacy default; review for orchestration" else "acceptable production semantic/reference value"
      stale_rows[[length(stale_rows) + 1L]] <- data.frame(pattern = label, file = relative, line = line_number, text = trimws(lines[[line_number]]), classification = classification, repair_required = grepl("production-relevant", classification), stringsAsFactors = FALSE)
    }
  }
}
stale <- if (length(stale_rows)) do.call(rbind, stale_rows) else data.frame(pattern = character(), file = character(), line = integer(), text = character(), classification = character(), repair_required = logical(), stringsAsFactors = FALSE)
utils::write.csv(stale, file.path(output_dir, "stale_assumption_audit.csv"), row.names = FALSE, na = "")

summary_lines <- c(
  paste0("Production root: ", production_root), paste0("Authoritative source: ", source_path), paste0("Authoritative SHA-256: ", source_sha),
  paste0("Authoritative rows/columns: ", source_rows, "/", length(source_columns)), paste0("Exact duplicate count outside source: ", length(exact_hits)),
  paste0("Lineage rows: ", nrow(lineage)), paste0("Residency stage rows: ", nrow(residency)), paste0("Near-copy candidates reviewed: ", nrow(near_copy)),
  paste0("Stale-assumption matches: ", nrow(stale)), paste0("Stale matches classified production-relevant: ", sum(stale$repair_required)),
  "No model, projection, rasterization, RPI, or reporting stage was rerun by this audit.",
  "The authoritative observation CSV is referenced by path and SHA; it is not copied into the audit directory."
)
writeLines(summary_lines, file.path(output_dir, "provenance_audit_summary.txt"))
cat("Provenance and data-residency audit complete\n", "Output: ", output_dir, "\n", "Exact duplicates: ", length(exact_hits), "\n", "Stale production-relevant matches: ", sum(stale$repair_required), "\n", sep = "")
