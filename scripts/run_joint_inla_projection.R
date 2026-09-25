args <- commandArgs(trailingOnly = TRUE)

option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}

flag <- function(name) paste0("--", name) %in% args

repo_root <- normalizePath(option("repo-root", getwd()), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"))
source(file.path(repo_root, "R", "joint_inla_project.R"))

build_path <- option("build", file.path(repo_root, "outputs", "joint_inla", "joint_inla_build.rds"))
fit_path <- option("fit", file.path(repo_root, "outputs", "joint_inla_fit", "joint_model_fit.rds"))
run_id <- option("run-id", "20725437")
output_dir <- option("output-dir", file.path(dirname(fit_path), paste0("prediction_projection_", run_id)))
expected_rows <- as.integer(option("expected-rows", "1669395"))
expected_weeks <- as.integer(option("expected-weeks", "105"))
expected_groups <- as.integer(option("expected-groups", "8"))
subset_target <- as.integer(option("diagnostic-subset", "10000"))
n_worst <- as.integer(option("n-worst", "20"))
overwrite <- flag("overwrite")
allow_unseen_admin_zero <- flag("allow-unseen-admin-zero")

if (!file.exists(build_path)) stop("Stage 3A build artifact does not exist: ", build_path)
if (!file.exists(fit_path)) stop("Stage 3B fit artifact does not exist: ", fit_path)

build <- readRDS(build_path)
fit_artifact <- readRDS(fit_path)

stage2_candidates <- c(
  if (!is.null(option("stage2"))) option("stage2") else character(),
  if (!is.null(build$provenance$source_artifact)) as.character(build$provenance$source_artifact) else character(),
  if (!is.null(build$config$inputs$joint_model_inputs)) as.character(build$config$inputs$joint_model_inputs) else character()
)
stage2_candidates <- unique(stage2_candidates[nzchar(stage2_candidates)])
stage2_path <- stage2_candidates[file.exists(stage2_candidates)][1L]
if (is.na(stage2_path) || !length(stage2_path)) {
  stop("Unable to resolve the Stage 2 artifact from --stage2 or Stage 3A provenance/configuration.")
}
stage2 <- readRDS(stage2_path)

fitted_values <- joint_inla_extract_fitted_values(build, fit_artifact, stage2)
components <- joint_inla_project_prepare_components(build, fit_artifact, stage2)
fitted_counts <- table(fitted_values$tier)
expected_fitted_counts <- c(tier1 = 1478518L, tier2 = 1145865L)
if (!identical(as.integer(fitted_counts[names(expected_fitted_counts)]), unname(expected_fitted_counts))) {
  stop("Response-stack row counts do not match the production contract: ", paste(names(fitted_counts), as.integer(fitted_counts), collapse = "/"))
}
if (!identical(as.integer(components$n_groups), expected_groups)) stop("Fitted SPDE group count is ", components$n_groups, "; expected ", expected_groups, ".")
for (component in c("week_steps", "tier2_week")) {
  support <- sort(unique(as.integer(components$random[[component]]$model_index)))
  if (!identical(support, seq_len(expected_weeks))) stop(component, " support does not exactly cover 1:", expected_weeks, ".")
}

subset_rows <- list(
  tier1 = joint_inla_project_stratified_rows(stage2$tier1, components$grouping_variable, subset_target),
  tier2 = joint_inla_project_stratified_rows(stage2$tier2, components$grouping_variable, subset_target)
)
subset_manual <- joint_inla_project_reconstruct_response(
  build, fit_artifact, stage2, components, fitted_values, subset_rows,
  allow_unseen_admin_zero = allow_unseen_admin_zero
)
subset_comparison <- joint_inla_project_reconstruction_metrics(subset_manual, fitted_values, n_worst)
if (!isTRUE(subset_comparison$pass)) stop("Deterministic reconstruction subset failed; dense projection was not attempted.")

full_manual <- joint_inla_project_reconstruct_response(
  build, fit_artifact, stage2, components, fitted_values,
  allow_unseen_admin_zero = allow_unseen_admin_zero
)
reconstruction <- joint_inla_project_reconstruction_metrics(full_manual, fitted_values, n_worst)
if (!isTRUE(reconstruction$pass)) stop("Full fitted-row reconstruction failed; dense projection was not attempted.")

spatial_validation <- joint_inla_project_validate_spatial_projector(build, stage2, components)
if (!isTRUE(spatial_validation$pass)) stop("Response-row spatial projection validation failed; dense projection was not attempted.")

prediction <- joint_inla_project_prediction(
  stage2, build, components, spatial_validation,
  allow_unseen_admin_zero = allow_unseen_admin_zero,
  expected_rows = expected_rows, expected_weeks = expected_weeks
)

prediction_admin_audit <- joint_inla_project_admin_audit(
  prediction$predictions, components$random$admin_f, "admin_f", prediction$contract$id_column, components$admin_mapping
)
prediction_admin_audit$status[prediction_admin_audit$check == "prediction_only_levels" & prediction_admin_audit$observed == "0"] <- "PASS"

response_scale <- joint_inla_project_response_scale_diagnostic(full_manual, fitted_values)
paths <- joint_inla_project_write_outputs(
  reconstruction, prediction, spatial_validation, components, output_dir,
  run_id = run_id, overwrite = overwrite,
  input_paths = list(build = build_path, fit = fit_path, stage2 = stage2_path),
  response_scale = response_scale
)

admin_audit_path <- file.path(output_dir, paste0("prediction_admin_support_audit_", run_id, ".csv"))
utils::write.csv(prediction_admin_audit, admin_audit_path, row.names = FALSE, na = "")
response_scale_path <- file.path(output_dir, paste0("response_scale_fitted_row_diagnostic_", run_id, ".csv"))
utils::write.csv(response_scale, response_scale_path, row.names = FALSE, na = "")
metadata <- readRDS(paths$paths[["metadata"]])
metadata$administrative_support <- prediction_admin_audit
metadata$administrative_support_handling <- if (allow_unseen_admin_zero) {
  "Prediction-only admin_f levels use explicit zero posterior-mean contributions and are flagged as unseen_level_zero_mean."
} else {
  "No unseen admin_f levels were authorized; projection would stop if any were present."
}
metadata$output_paths$admin_audit <- admin_audit_path
metadata$output_paths$response_scale_diagnostic <- response_scale_path
saveRDS(metadata, paths$paths[["metadata"]])

cat(
  "Joint-INLA Phase 2 projection complete\n",
  "  reconstruction audit: ", paths$paths[["reconstruction_audit"]], "\n",
  "  prediction output: ", output_dir, "\n",
  "  Stage 2 rows: ", prediction$contract$n_rows, "\n",
  "  unique spatial cells: ", prediction$contract$n_cells, "\n",
  "  weeks: ", prediction$contract$n_weeks, "\n",
  "  spatial groups: ", paste(prediction$contract$spatial_groups, collapse = ","), "\n",
  "  expected count generated: ", prediction$expected_count_generated, "\n",
  "  no INLA refit, raster surface, or biological interpretation was performed\n",
  sep = ""
)
