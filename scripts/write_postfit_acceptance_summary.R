#!/usr/bin/env Rscript

# Assemble the machine-readable computational acceptance record.  This script
# summarizes gates and provenance; it does not make biological claims.

args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(option("repo-root", file.path(dirname(sub("^--file=", "", script_arg)), "..")), mustWork = TRUE)
source(file.path(repo_root, "R", "postfit_orchestration.R"))

required <- c("fit-job-id", "run-id", "output-root", "fit", "build", "stage2", "holdout")
missing <- required[vapply(required, function(x) is.null(option(x)), logical(1L))]
if (length(missing)) stop("Acceptance summary requires: ", paste(paste0("--", missing), collapse = ", "))

run_id <- option("run-id")
output_root <- normalizePath(option("output-root"), mustWork = TRUE)
fit_path <- normalizePath(option("fit"), mustWork = TRUE)
build_path <- normalizePath(option("build"), mustWork = TRUE)
stage2_path <- normalizePath(option("stage2"), mustWork = TRUE)
holdout_path <- normalizePath(option("holdout"), mustWork = TRUE)
paths <- postfit_acceptance_output_paths(output_root, run_id)

sha256_file <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  value <- tryCatch(system2("sha256sum", path, stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) return(NA_character_)
  sub("[[:space:]].*$", "", value[[1L]])
}
read_audit <- function(path, label) {
  if (!file.exists(path)) stop("Missing ", label, " audit: ", path)
  audit <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"status" %in% names(audit)) stop(label, " audit lacks a status column: ", path)
  audit
}
audit_gate <- function(name, audit, details) {
  statuses <- toupper(as.character(audit$status))
  status <- if (any(statuses == "FAIL")) "FAIL" else if (any(statuses == "WARNING")) "WARNING" else "PASS"
  postfit_acceptance_gate(name, status, details)
}
find_required <- function(directory, pattern, label) postfit_acceptance_find_one(directory, pattern, label)

fit_health_audit_path <- find_required(paths$fit_health, paste0("^fit_health_", run_id, "\\.csv$"), "fit-health audit")
extraction_audit_path <- find_required(paths$extraction, paste0("^extraction_audit_", run_id, "\\.csv$"), "extraction audit")
validation_audit_path <- find_required(paths$validation, paste0("^holdout_validation_audit_", run_id, "\\.csv$"), "validation audit")
projection_audit_path <- file.path(paths$projection, paste0("prediction_projection_audit_", run_id, ".csv"))
raster_audit_path <- file.path(paths$raster_surfaces, "qa", "phase3_audit.csv")
if (!file.exists(projection_audit_path)) stop("Missing projection audit: ", projection_audit_path)
if (!file.exists(raster_audit_path)) stop("Missing rasterization audit: ", raster_audit_path)

fit_health <- read_audit(fit_health_audit_path, "fit-health")
extraction <- read_audit(extraction_audit_path, "extraction")
validation <- read_audit(validation_audit_path, "validation")
projection <- read_audit(projection_audit_path, "projection")
raster <- read_audit(raster_audit_path, "rasterization")

stage2 <- readRDS(stage2_path)
build <- readRDS(build_path)
fit_metadata_path <- find_required(paths$fit_health, paste0("^fit_health_", run_id, "_metadata\\.rds$"), "fit-health metadata")
fit_health_metadata <- readRDS(fit_metadata_path)
validation_metadata_path <- find_required(paths$validation, paste0("^holdout_validation_metadata_", run_id, "\\.rds$"), "validation metadata")
validation_metadata <- readRDS(validation_metadata_path)
projection_metadata <- readRDS(file.path(paths$projection, paste0("prediction_projection_metadata_", run_id, ".rds")))
raster_metadata_path <- find_required(paths$raster_surfaces, paste0("^phase3_metadata_", run_id, "\\.rds$"), "rasterization metadata")
raster_metadata <- readRDS(raster_metadata_path)

git_head <- tryCatch(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
git_head <- paste(git_head, collapse = "")
mesh_vertices <- if (!is.null(build$mesh$n)) as.integer(build$mesh$n) else if (!is.null(stage2$mesh$n)) as.integer(stage2$mesh$n) else NA_integer_
spde_groups <- if (!is.null(build$groups$n_groups)) as.integer(build$groups$n_groups) else if (!is.null(build$spatial_support$n_groups)) as.integer(build$spatial_support$n_groups) else NA_integer_
cattle_support <- sort(unique(as.integer(stage2$tier2$cattle_q[is.finite(stage2$tier2$cattle_q)])))
active_cattle <- if ("response_training" %in% names(stage2$tier2)) sort(unique(as.integer(stage2$tier2$cattle_q[!is.na(stage2$tier2$response_training)]))) else integer()

gates <- rbind(
  postfit_acceptance_gate("Gate0_scheduler_completion", "PASS", paste("Wrapper verified COMPLETED/0:0 for SLURM job", option("fit-job-id"))),
  audit_gate("Gate1_fit_health", fit_health, "Fit-health structural audit."),
  audit_gate("Gate2_extraction", extraction, "Fail-closed stack extraction audit."),
  audit_gate("Gate3_validation", validation, "New-production holdout validation audit; no historical metric regression applied."),
  audit_gate("Gate4_projection", projection, "Reconstruction identity and dense-grid projection audit."),
  audit_gate("Gate5_rasterization", raster, "Rasterization and surface QA audit."),
  postfit_acceptance_gate("Gate6_output_isolation", if (normalizePath(paths$root, mustWork = TRUE) != normalizePath(dirname(fit_path), mustWork = TRUE)) "PASS" else "FAIL", "Post-fit outputs are stored in a run-specific root distinct from the fit directory.")
)
overall <- postfit_acceptance_overall_status(gates)

summary <- list(
  status = overall,
  purpose = "Post-fit computational acceptance; no biological interpretation.",
  acceptance_mode = "production",
  run_id = run_id,
  fit_job_id = option("fit-job-id"),
  generated_utc = format(Sys.time(), tz = "UTC"),
  repository = list(root = repo_root, git_head = git_head),
  inputs = list(
    stage2 = list(path = stage2_path, sha256 = sha256_file(stage2_path), size_bytes = unname(file.info(stage2_path)$size)),
    stage3a = list(path = build_path, sha256 = sha256_file(build_path), size_bytes = unname(file.info(build_path)$size)),
    stage3b = list(path = fit_path, sha256 = sha256_file(fit_path), size_bytes = unname(file.info(fit_path)$size)),
    holdout = list(path = holdout_path, sha256 = sha256_file(holdout_path), size_bytes = unname(file.info(holdout_path)$size))
  ),
  architecture = list(
    tier1_rows = nrow(stage2$tier1), tier2_rows = nrow(stage2$tier2),
    mesh_vertices = mesh_vertices, spde_groups = spde_groups,
    cattle_support = cattle_support, active_cattle_bins = active_cattle
  ),
  runtime = list(R = R.version.string, lib_paths = .libPaths(), INLA = if (requireNamespace("INLA", quietly = TRUE)) as.character(packageVersion("INLA")) else NA_character_, Matrix = if (requireNamespace("Matrix", quietly = TRUE)) as.character(packageVersion("Matrix")) else NA_character_, terra = if (requireNamespace("terra", quietly = TRUE)) as.character(packageVersion("terra")) else NA_character_, sf = if (requireNamespace("sf", quietly = TRUE)) as.character(packageVersion("sf")) else NA_character_),
  model = list(families = as.character(build$family), initialization_mode = fit_health_metadata$initialization_mode, downstream_refit = FALSE),
  gates = gates,
  audit_counts = list(
    fit_health = fit_health_metadata$counts,
    extraction = as.list(table(extraction$status)), validation = as.list(table(validation$status)),
    projection = as.list(table(projection$status)), rasterization = as.list(table(raster$status))
  ),
  phase_outputs = list(
    fit_health = list(audit = fit_health_audit_path, metadata = fit_metadata_path),
    extraction = list(audit = extraction_audit_path),
    validation = list(audit = validation_audit_path, metadata = validation_metadata_path, holdout_counts = validation_metadata$holdout_counts),
    projection = list(directory = paths$projection, metadata = file.path(paths$projection, paste0("prediction_projection_metadata_", run_id, ".rds")), rows = projection_metadata$prediction$rows, weeks = projection_metadata$prediction$weeks, unique_cells = projection_metadata$prediction$unique_cells),
    rasterization = list(directory = paths$raster_surfaces, metadata = raster_metadata_path, weeks = raster_metadata$weeks, total_raster_files = raster_metadata$total_raster_files, roundtrip_maximum_observed_error = raster_metadata$roundtrip_maximum_observed_error)
  ),
  output_root = paths$root,
  summary_paths = list(gates = file.path(paths$acceptance, paste0("postfit_acceptance_gates_", run_id, ".csv")), summary_rds = paths$summary_rds, summary_yaml = paths$summary_yaml)
)

dir.create(paths$acceptance, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(gates, summary$summary_paths$gates, row.names = FALSE, na = "")
saveRDS(summary, paths$summary_rds)
if (requireNamespace("yaml", quietly = TRUE)) yaml::write_yaml(summary, paths$summary_yaml) else writeLines(c(paste0("status: ", overall), paste0("run_id: ", run_id), paste0("fit_job_id: ", option("fit-job-id"))), paths$summary_yaml)
cat("Post-fit acceptance status: ", overall, "\n", "Summary: ", paths$summary_rds, "\n", sep = "")
if (identical(overall, "FAIL")) quit(status = 1L)
