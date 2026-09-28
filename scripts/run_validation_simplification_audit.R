#!/usr/bin/env Rscript

# Evaluate the compact validation contract against existing artifacts and
# write the one-time machine-readable simplification audit.  This script does
# not run an upstream stage and never submits a scheduler job.

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_validation_gates.R"), local = .GlobalEnv)

args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}

accepted_root <- option("accepted-root")
output_root <- option("output-root")
commit <- option("commit", production_orchestration_git_commit(repo_root))
if (is.null(accepted_root) || is.null(output_root)) stop("Usage: run_validation_simplification_audit.R --accepted-root PATH --output-root PATH [--commit SHA]", call. = FALSE)
accepted_root <- normalizePath(accepted_root, mustWork = TRUE)
output_root <- normalizePath(output_root, mustWork = FALSE)
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

stage1_path <- file.path(accepted_root, "stage1", "model_inputs.rds")
stage2_path <- file.path(accepted_root, "stage2", "joint_model_inputs.rds")
stage3a_path <- file.path(accepted_root, "stage3a", "joint_inla_build.rds")
stage3b_path <- file.path(accepted_root, "stage3b_fit", "joint_model_fit.rds")
observation_path <- "/project/disease_ecology/NWScrewworm/data/processed_data/case_detections/combined_clean_obs_2027-07-31.csv"
if (!file.exists(observation_path)) stop("Accepted-run authoritative input is not available: ", observation_path, call. = FALSE)
stage2 <- readRDS(stage2_path)
grid <- stage2$prediction_grid
week_labels <- unique(paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-"))
week_start <- week_labels[[1L]]; week_end <- week_labels[[length(week_labels)]]
input_sha <- production_orchestration_hash_file(observation_path)
example_config <- file.path(repo_root, "config", "production.example.yml")
paths <- list(
  stage1 = file.path(accepted_root, "stage1"), stage2 = file.path(accepted_root, "stage2"), stage3a = file.path(accepted_root, "stage3a"),
  preflight = file.path(accepted_root, "stage3b_preflight"), stage3b = file.path(accepted_root, "stage3b_fit"),
  fit_health = file.path(accepted_root, "stage3b_fit_health_20762325"),
  extraction = file.path(accepted_root, "stage3b_phase1_20762325_5260943", "extraction"),
  validation = file.path(accepted_root, "stage3b_phase1_20762325_5260943", "validation"),
  projection = file.path(accepted_root, "stage3b_phase2_20762325_5260943", "projection"),
  raster = file.path(accepted_root, "stage3b_phase2_20762325_5260943", "raster"),
  structural = file.path(accepted_root, "structural_surface_diagnostics", "20762325_0659ea6"),
  masked = file.path(accepted_root, "masked_structural_rpi_diagnostics", "20762325_94e9e0d"),
  reporting = file.path(accepted_root, "final_downstream_reporting", "20762325_28e155e"),
  metadata = file.path(accepted_root, "validation_simplification", as.character(commit)), logs = file.path(accepted_root, "logs")
)
contract <- list(
  run_id = "20762325_5260943",
  run_root = accepted_root,
  repository = list(root = repo_root, branch = "release/workflow-consolidation-v1", git_commit = as.character(commit)),
  config = list(path = example_config, sha256 = production_orchestration_hash_file(example_config)),
  input = list(observations = observation_path, sha256 = input_sha, coordinate_fields = c("lon", "lat"), crs = "EPSG:4326"),
  horizon = list(modeled_weeks = length(week_labels), modeled_week_labels = week_labels, configured_start_epiweek = week_start, resolved_final_complete_epiweek = week_end),
  paths = paths, gate_results = list(), warning_count = 0L
)
contract$dynamic_dimensions <- production_orchestration_dimension_contract(stage2_path, stage3a_path)

results <- list(
  prepare = production_gate_prepare(contract),
  fit = production_gate_fit(contract),
  postfit = production_gate_postfit(contract)
)
gate_rows <- do.call(rbind, lapply(results, function(result) {
  cbind(result$audit, gate_outcome = result$outcome, stringsAsFactors = FALSE)
}))
utils::write.csv(production_validation_inventory(), file.path(output_root, "validation_check_inventory.csv"), row.names = FALSE, na = "")
reclassification <- production_validation_inventory()
reclassification <- reclassification[reclassification$proposed_severity != reclassification$current_severity | reclassification$action != "retain", , drop = FALSE]
utils::write.csv(reclassification, file.path(output_root, "validation_reclassification.csv"), row.names = FALSE, na = "")
utils::write.csv(gate_rows, file.path(output_root, "accepted_run_gate_results.csv"), row.names = FALSE, na = "")
summary_lines <- c(
  paste0("Validation simplification audit commit: ", commit),
  paste0("Accepted run: fit job 20762325; downstream commit 28e155e"),
  paste0("Prepare gate: ", results$prepare$outcome),
  paste0("Fit gate: ", results$fit$outcome),
  paste0("Post-fit gate: ", results$postfit$outcome),
  paste0("Overall: ", if (any(vapply(results, function(x) x$outcome == "FAIL", logical(1L)))) "FAIL" else if (any(vapply(results, function(x) x$outcome == "PASS_WITH_WARNINGS", logical(1L)))) "PASS_WITH_WARNINGS" else "PASS"),
  paste0("Warnings: ", sum(vapply(results, function(x) x$warning_count, integer(1L)))),
  paste0("Private config available on Atlas: ", file.exists(file.path(repo_root, "config", "production.yml"))),
  "Historical numerical comparisons are nonblocking diagnostics.",
  "No upstream stage or fit was executed by this audit."
)
writeLines(summary_lines, file.path(output_root, "validation_simplification_summary.txt"))
for (result in results) production_gate_print(result)
if (any(vapply(results, function(x) x$outcome == "FAIL", logical(1L)))) quit(save = "no", status = 1L)
