args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}
flag <- function(name) paste0("--", name) %in% args

repo_root <- normalizePath(option("repo-root", getwd()), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_validate.R"))

fit_path <- option("fit", file.path(repo_root, "outputs", "joint_inla_fit", "joint_model_fit.rds"))
holdout_path <- option("holdout", file.path(dirname(fit_path), "holdout_predictions.csv"))
stage2_path <- option("stage2", file.path(repo_root, "outputs", "joint_model", "joint_model_inputs.rds"))
output_dir <- option("output-dir", dirname(fit_path))
run_id <- option("run-id", format(Sys.time(), "%Y%m%dT%H%M%S"))
overwrite <- flag("overwrite")

required_paths <- c(fit = fit_path, holdout = holdout_path, stage2 = stage2_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths)) stop("Validation input does not exist: ", paste(missing_paths, collapse = ", "))

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
paths <- c(
  metrics = file.path(output_dir, paste0("holdout_validation_metrics_", run_id, ".csv")),
  tier1_calibration = file.path(output_dir, paste0("tier1_calibration_", run_id, ".csv")),
  tier2_calibration = file.path(output_dir, paste0("tier2_calibration_", run_id, ".csv")),
  tier2_intervals = file.path(output_dir, paste0("tier2_predictive_intervals_", run_id, ".csv")),
  audit = file.path(output_dir, paste0("holdout_validation_audit_", run_id, ".csv")),
  details = file.path(output_dir, paste0("holdout_validation_details_", run_id, ".txt")),
  metadata = file.path(output_dir, paste0("holdout_validation_metadata_", run_id, ".rds"))
)
if (!overwrite && any(file.exists(paths))) stop("Refusing to overwrite existing validation outputs; use --overwrite intentionally.")

holdout <- utils::read.csv(holdout_path, stringsAsFactors = FALSE, check.names = FALSE)
stage2 <- readRDS(stage2_path)
fit_artifact <- readRDS(fit_path)
if (!all(c("tier", "response_observed", "fitted_mean") %in% names(holdout))) {
  stop("Holdout CSV must contain tier, response_observed, and fitted_mean.")
}
if (!all(c("tier1", "tier2") %in% names(stage2))) stop("Stage 2 artifact must contain tier1 and tier2 data frames.")

tier1_holdout <- holdout[holdout$tier == "tier1", , drop = FALSE]
tier2_holdout <- holdout[holdout$tier == "tier2", , drop = FALSE]
tier1 <- joint_inla_validate_tier1(tier1_holdout)
tier2 <- joint_inla_validate_tier2(tier2_holdout)
posterior_support <- joint_inla_validate_posterior_support(fit_artifact)
intervals <- joint_inla_validate_unresolved_intervals(tier2_holdout, tier2$predicted, posterior_support)
audit <- joint_inla_validate_audit(holdout, stage2, tier1, tier2, posterior_support)
metrics <- rbind(tier1$metrics, tier2$metrics,
                 joint_inla_validate_metric_row("tier2", "predictive_interval_coverage", NA_real_, posterior_support$status,
                                                nrow(tier2_holdout), posterior_support$details))

utils::write.csv(metrics, paths[["metrics"]], row.names = FALSE, na = "")
utils::write.csv(tier1$calibration, paths[["tier1_calibration"]], row.names = FALSE, na = "")
utils::write.csv(tier2$calibration, paths[["tier2_calibration"]], row.names = FALSE, na = "")
utils::write.csv(intervals, paths[["tier2_intervals"]], row.names = FALSE, na = "")
utils::write.csv(audit, paths[["audit"]], row.names = FALSE, na = "")

git_head <- tryCatch(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
metadata <- list(
  run_id = run_id,
  generated_utc = format(Sys.time(), tz = "UTC"),
  repository = list(root = repo_root, git_head = paste(git_head, collapse = "")),
  inputs = list(fit = normalizePath(fit_path, mustWork = TRUE), holdout = normalizePath(holdout_path, mustWork = TRUE), stage2 = normalizePath(stage2_path, mustWork = TRUE)),
  holdout_counts = table(factor(holdout$tier, levels = c("tier1", "tier2"))),
  tier1 = list(status = tier1$status, rows = tier1$n, positives = tier1$positives, negatives = tier1$negatives, details = tier1$details),
  tier2 = list(status = tier2$status, rows = sum(is.finite(tier2_holdout$response_observed)), zeros = sum(tier2_holdout$response_observed == 0, na.rm = TRUE), scale = tier2$scale, details = tier2$details),
  posterior_support = posterior_support,
  output_paths = paths,
  audit_summary = list(pass = sum(audit$status == "PASS"), warning = sum(audit$status == "WARNING"), fail = sum(audit$status == "FAIL")),
  scope = list(stage3b_refit = FALSE, model_changed = FALSE, prediction_grid_projected = FALSE, surfaces_created = FALSE, biological_interpretation = FALSE)
)
saveRDS(metadata, paths[["metadata"]])
writeLines(joint_inla_validate_details(audit, tier1, tier2, posterior_support, paths), paths[["details"]])

status_counts <- table(audit$status)
cat("Joint-INLA holdout validation complete\n",
    "  metrics: ", paths[["metrics"]], "\n",
    "  tier1 calibration: ", paths[["tier1_calibration"]], "\n",
    "  tier2 calibration: ", paths[["tier2_calibration"]], "\n",
    "  tier2 predictive intervals: ", paths[["tier2_intervals"]], "\n",
    "  audit: ", paths[["audit"]], "\n",
    "  details: ", paths[["details"]], "\n",
    "  metadata: ", paths[["metadata"]], "\n",
    "  audit PASS/WARNING/FAIL: ", paste(names(status_counts), as.integer(status_counts), collapse = "/"), "\n", sep = "")
