args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}
flag <- function(name) paste0("--", name) %in% args

repo_root <- normalizePath(option("repo-root", getwd()), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"))
source(file.path(repo_root, "R", "joint_inla_validate.R"))

acceptance_mode <- tolower(option("acceptance-mode", option("mode", "reference")))
if (!acceptance_mode %in% c("reference", "production")) stop("acceptance mode must be 'reference' or 'production'.")
build_arg <- option("build")
fit_arg <- option("fit")
holdout_arg <- option("holdout")
stage2_arg <- option("stage2")
output_arg <- option("output-dir")
run_id_arg <- option("run-id")
if (identical(acceptance_mode, "production") && any(vapply(list(build_arg, fit_arg, holdout_arg, stage2_arg, output_arg, run_id_arg), is.null, logical(1L)))) {
  stop("Production validation requires explicit --build, --fit, --holdout, --stage2, --output-dir, and --run-id arguments.")
}
build_path <- build_arg %||% file.path(repo_root, "outputs", "joint_inla", "joint_inla_build.rds")
fit_path <- fit_arg %||% file.path(repo_root, "outputs", "joint_inla_fit", "joint_model_fit.rds")
holdout_path <- holdout_arg %||% file.path(dirname(fit_path), "holdout_predictions.csv")
stage2_path <- stage2_arg %||% file.path(repo_root, "outputs", "joint_model", "joint_model_inputs.rds")
output_root <- output_arg %||% dirname(fit_path)
run_id <- run_id_arg %||% "20725437"
source_fit_job <- option("source-fit-job", if (identical(acceptance_mode, "reference")) "20725437" else NA_character_)
prior_validation_job <- option("prior-validation-job", if (identical(acceptance_mode, "reference")) "20740207" else NA_character_)
output_dir <- file.path(output_root, paste0("validation_presence_background_", run_id))
overwrite <- flag("overwrite")

required_paths <- c(build = build_path, fit = fit_path, holdout = holdout_path, stage2 = stage2_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths)) stop("Validation input does not exist: ", paste(missing_paths, collapse = ", "))
if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE, recursive = TRUE)) && !overwrite) {
  stop("Refusing to write into a non-empty validation output directory without overwrite=TRUE: ", output_dir)
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

paths <- c(
  metrics = file.path(output_dir, paste0("holdout_validation_metrics_", run_id, ".csv")),
  tier1_metrics = file.path(output_dir, paste0("tier1_presence_background_metrics_", run_id, ".csv")),
  tier1_boyce_curve = file.path(output_dir, paste0("tier1_boyce_curve_", run_id, ".csv")),
  tier1_percentiles = file.path(output_dir, paste0("tier1_presence_percentiles_", run_id, ".csv")),
  tier1_weekly = file.path(output_dir, paste0("tier1_weekly_rank_summary_", run_id, ".csv")),
  tier2_calibration = file.path(output_dir, paste0("tier2_calibration_", run_id, ".csv")),
  tier2_intervals = file.path(output_dir, paste0("tier2_predictive_intervals_", run_id, ".csv")),
  audit = file.path(output_dir, paste0("holdout_validation_audit_", run_id, ".csv")),
  details = file.path(output_dir, paste0("holdout_validation_details_", run_id, ".txt")),
  metadata = file.path(output_dir, paste0("holdout_validation_metadata_", run_id, ".rds"))
)
if (!overwrite && any(file.exists(paths))) stop("Refusing to overwrite revised validation outputs; use --overwrite intentionally.")

sha256_file <- function(path) {
  value <- tryCatch(system2("sha256sum", path, stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) return(NA_character_)
  sub("[[:space:]].*$", "", value[[1L]])
}

holdout_checksum_before <- sha256_file(holdout_path)
build <- readRDS(build_path)
fit_artifact <- readRDS(fit_path)
stage2 <- readRDS(stage2_path)
holdout <- utils::read.csv(holdout_path, stringsAsFactors = FALSE, check.names = FALSE)
fitted <- joint_inla_extract_fitted_values(build, fit_artifact, stage2)

if (!all(c("tier", "output_id", "source_is_test_point") %in% names(fitted))) stop("Aligned extraction lacks the established holdout row fields.")
extracted_holdout <- fitted[fitted$source_is_test_point %in% TRUE, , drop = FALSE]
if (!setequal(as.character(extracted_holdout$output_id), as.character(holdout$output_id))) stop("Existing holdout CSV does not reconcile exactly to the established extraction/indexing contract.")

derive_stage2_holdout_count <- function(stage2, tier) {
  if (is.list(stage2$holdout_metadata) && is.list(stage2$holdout_metadata[[tier]]) && !is.null(stage2$holdout_metadata[[tier]]$selected_count)) {
    return(as.integer(stage2$holdout_metadata[[tier]]$selected_count))
  }
  if (!is.data.frame(stage2[[tier]]) || !"is_test_point" %in% names(stage2[[tier]])) stop("Stage 2 does not expose an is_test_point contract for ", tier, ".")
  sum(stage2[[tier]]$is_test_point %in% TRUE, na.rm = TRUE)
}
expected_tier1_holdouts <- if (identical(acceptance_mode, "reference")) 6638L else derive_stage2_holdout_count(stage2, "tier1")
expected_tier2_holdouts <- derive_stage2_holdout_count(stage2, "tier2")
reference_background <- joint_inla_validate_reference_background(stage2, fitted, expected_holdouts = expected_tier1_holdouts)
tier1_presence <- joint_inla_validate_tier1_presence_background(reference_background)
tier2_holdout <- holdout[holdout$tier == "tier2", , drop = FALSE]
if (nrow(tier2_holdout) != expected_tier2_holdouts) stop("Tier 2 holdout count is ", nrow(tier2_holdout), "; expected Stage 2 count ", expected_tier2_holdouts, ".")
tier2 <- joint_inla_validate_tier2(tier2_holdout)
posterior_support <- joint_inla_validate_posterior_support(fit_artifact)
intervals <- joint_inla_validate_unresolved_intervals(tier2_holdout, tier2$predicted, posterior_support)

expected_tier2 <- NULL
tier2_differences <- NULL
if (identical(acceptance_mode, "reference")) {
  expected_tier2 <- c(mae = 0.778332244713918, rmse = 1.02158254118904, pearson = 0.392991140775537,
                      spearman = 0.377338853270058, calibration_mean_ratio = 0.982325679980395)
  observed_tier2 <- vapply(names(expected_tier2), function(metric) {
    value <- tier2$metrics$value[tier2$metrics$tier == "tier2" & tier2$metrics$metric == metric]
    if (length(value) != 1L) NA_real_ else value
  }, numeric(1L))
  tier2_differences <- observed_tier2 - expected_tier2
  if (any(!is.finite(observed_tier2)) || any(abs(tier2_differences) > 1e-6)) stop("Tier 2 point metrics materially differ from validation job 20740207: ", paste(names(expected_tier2), format(tier2_differences, digits = 8), collapse = "; "))
} else {
  metric_names <- c("mae", "rmse", "pearson", "spearman", "calibration_mean_ratio")
  observed_tier2 <- vapply(metric_names, function(metric) {
    value <- tier2$metrics$value[tier2$metrics$tier == "tier2" & tier2$metrics$metric == metric]
    if (length(value) != 1L) NA_real_ else value
  }, numeric(1L))
  names(observed_tier2) <- metric_names
  if (any(!is.finite(observed_tier2))) stop("Production Tier 2 point metrics are not all finite: ", paste(names(observed_tier2)[!is.finite(observed_tier2)], collapse = ", "))
}

audit <- joint_inla_validate_audit(holdout, stage2, tier1_presence, tier2, posterior_support,
                                   reference_background = reference_background,
                                   expected_tier1_holdouts = expected_tier1_holdouts)
audit <- rbind(
  audit,
  joint_inla_validate_audit_row("inputs", "holdout_extraction_alignment", "PASS", nrow(extracted_holdout), nrow(holdout), "Existing holdout predictions reconcile to the validated response-stack extraction."),
  joint_inla_validate_audit_row("inputs", "source_holdout_checksum_unchanged", "PASS", holdout_checksum_before, holdout_checksum_before, "Source holdout checksum recorded before and after validation artifact generation."),
  if (identical(acceptance_mode, "reference")) joint_inla_validate_audit_row("tier2", "point_metrics_reconcile_validation_20740207", "PASS", paste(format(observed_tier2, digits = 15), collapse = "/"), paste(format(expected_tier2, digits = 15), collapse = "/"), "All required Tier 2 point metrics agree within 1e-6.") else joint_inla_validate_audit_row("tier2", "point_metrics_finite_production", "PASS", paste(format(observed_tier2, digits = 15), collapse = "/"), "all finite; no reference values applied", "Production metrics are reported without comparison to fit 20725437."),
  joint_inla_validate_audit_row("scope", "acceptance_mode", "PASS", acceptance_mode, "reference or production", if (identical(acceptance_mode, "reference")) "Reference numerical regression checks were applied." else "New-production mode did not apply historical reference metric values."),
  joint_inla_validate_audit_row("scope", "separate_output_directory", "PASS", output_dir, "new output root", "Validation outputs are isolated from the reference fit outputs."),
  joint_inla_validate_audit_row("scope", "no_prediction_grid_projection", "PASS", "not run", "not run", "Reference background uses existing Stage 2 integration rows only."),
  joint_inla_validate_audit_row("scope", "no_surface_generation", "PASS", "not run", "not run", "No dense grid or raster output was created."),
  joint_inla_validate_audit_row("scope", "no_biological_interpretation", "PASS", "not run", "not run", "Outputs are computational validation diagnostics only.")
)

metrics <- rbind(tier1_presence$metrics, tier2$metrics,
                 joint_inla_validate_metric_row("tier2", "predictive_interval_coverage", NA_real_, "WARNING",
                                                nrow(tier2_holdout), posterior_support$details))

utils::write.csv(metrics, paths[["metrics"]], row.names = FALSE, na = "")
utils::write.csv(tier1_presence$metrics, paths[["tier1_metrics"]], row.names = FALSE, na = "")
utils::write.csv(tier1_presence$boyce_curve, paths[["tier1_boyce_curve"]], row.names = FALSE, na = "")
utils::write.csv(tier1_presence$percentiles, paths[["tier1_percentiles"]], row.names = FALSE, na = "")
utils::write.csv(tier1_presence$weekly, paths[["tier1_weekly"]], row.names = FALSE, na = "")
utils::write.csv(tier2$calibration, paths[["tier2_calibration"]], row.names = FALSE, na = "")
utils::write.csv(intervals, paths[["tier2_intervals"]], row.names = FALSE, na = "")
utils::write.csv(audit, paths[["audit"]], row.names = FALSE, na = "")

holdout_checksum_after <- sha256_file(holdout_path)
if (!identical(holdout_checksum_before, holdout_checksum_after)) stop("Source holdout checksum changed during validation.")

git_head <- tryCatch(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
fit_checksum <- sha256_file(fit_path)
stage2_checksum <- sha256_file(stage2_path)
metadata <- list(
  phase = "Phase 1 validation completion",
  run_id = run_id,
  acceptance_mode = acceptance_mode,
  acceptance_profile = if (identical(acceptance_mode, "reference")) "reference_20725437" else "new_production",
  historical_metric_regression_applied = identical(acceptance_mode, "reference"),
  source_fit_job = source_fit_job,
  prior_validation_job = prior_validation_job,
  generated_utc = format(Sys.time(), tz = "UTC"),
  repository = list(root = repo_root, git_head = paste(git_head, collapse = "")),
  inputs = list(build = normalizePath(build_path, mustWork = TRUE), fit = normalizePath(fit_path, mustWork = TRUE), holdout = normalizePath(holdout_path, mustWork = TRUE), stage2 = normalizePath(stage2_path, mustWork = TRUE), fit_sha256 = fit_checksum, holdout_sha256_before = holdout_checksum_before, holdout_sha256_after = holdout_checksum_after, stage2_sha256 = stage2_checksum),
  stage3a_provenance = build$provenance,
  tier1_semantics = list(
    positive_population = paste(expected_tier1_holdouts, "Stage 2 withheld Yi=1 occurrence rows"),
    background_population = reference_background$background_rule,
    background_biological_status = "unknown / not treated as absence",
    background_rows = reference_background$background_rows,
    unique_spatial_nodes = reference_background$unique_spatial_nodes,
    represented_weeks = reference_background$represented_weeks,
    total_integration_weight = reference_background$total_weight,
    weight_min = reference_background$weight_min,
    weight_max = reference_background$weight_max,
    weights_vary = reference_background$weights_vary,
    prediction_scale = "production Tier 1 fitted response-scale probability",
    cbi_window_width = "one tenth of joint presence/background prediction range",
    cbi_resolution = 100L,
    cbi_correlation = "Spearman",
    cbi_duplicate_rule = "successive duplicate P/E values removed",
    tie_rule = "half credit for PB-AUC; weighted midrank for same-week percentiles",
    weighting_modes = c("area_weighted", "unweighted")
  ),
  tier1_results = list(weighted_pb_auc = tier1_presence$weighted_auc, unweighted_pb_auc = tier1_presence$unweighted_auc,
                       weighted_cbi = tier1_presence$weighted_cbi, unweighted_cbi = tier1_presence$unweighted_cbi),
  holdout_counts = list(tier1 = expected_tier1_holdouts, tier2 = expected_tier2_holdouts, extracted_tier1 = nrow(extracted_holdout), extracted_tier2 = nrow(tier2_holdout)),
  tier2_reconciliation = list(expected = expected_tier2, observed = observed_tier2, differences = tier2_differences, tolerance = 1e-6, point_validation = "COMPLETE", historical_regression_applied = identical(acceptance_mode, "reference")),
  posterior_predictive_intervals = list(status = "UNAVAILABLE_FROM_CURRENT_RETAINED_FIT_ARTIFACT", method = posterior_support$method, details = posterior_support$details),
  software = list(
    R = R.version.string,
    INLA_fit_provenance = if (!is.null(build$provenance$INLA)) as.character(build$provenance$INLA) else NA_character_,
    INLA_validation_runtime = if (requireNamespace("INLA", quietly = TRUE)) as.character(utils::packageVersion("INLA")) else "not loaded for validation"
  ),
  output_paths = paths,
  audit_summary = list(pass = sum(audit$status == "PASS"), warning = sum(audit$status == "WARNING"), fail = sum(audit$status == "FAIL")),
  scope = list(stage3b_refit = FALSE, model_changed = FALSE, prediction_grid_projected = FALSE, surfaces_created = FALSE, biological_interpretation = FALSE)
)
saveRDS(metadata, paths[["metadata"]])
writeLines(joint_inla_validate_details(audit, tier1_presence, tier2, posterior_support, paths), paths[["details"]])

status_counts <- table(audit$status)
cat("Joint-INLA Phase 1 presence-background validation complete\n",
    "  output_dir: ", output_dir, "\n",
    "  metrics: ", paths[["metrics"]], "\n",
    "  Tier 1 PB metrics: ", paths[["tier1_metrics"]], "\n",
    "  Boyce curve: ", paths[["tier1_boyce_curve"]], "\n",
    "  occurrence percentiles: ", paths[["tier1_percentiles"]], "\n",
    "  weekly rank summary: ", paths[["tier1_weekly"]], "\n",
    "  Tier 2 calibration: ", paths[["tier2_calibration"]], "\n",
    "  audit: ", paths[["audit"]], "\n",
    "  details: ", paths[["details"]], "\n",
    "  metadata: ", paths[["metadata"]], "\n",
    "  audit PASS/WARNING/FAIL: ", paste(names(status_counts), as.integer(status_counts), collapse = "/"), "\n", sep = "")
