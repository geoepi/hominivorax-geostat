#!/usr/bin/env Rscript

# Structural health gate for a completed Stage 3B artifact.  This script does
# not compute biological performance metrics and must run only after the
# scheduler gate has established that the fit job completed successfully.

args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}
flag <- function(name) paste0("--", name) %in% args

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(option("repo-root", file.path(dirname(sub("^--file=", "", script_arg)), "..")), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"), local = .GlobalEnv)

required <- c("fit", "build", "stage2", "output-dir", "run-id")
missing <- required[vapply(required, function(x) is.null(option(x)), logical(1L))]
if (length(missing)) stop("Fit-health requires explicit arguments: ", paste(paste0("--", missing), collapse = ", "))

fit_path <- normalizePath(option("fit"), mustWork = TRUE)
build_path <- normalizePath(option("build"), mustWork = TRUE)
stage2_path <- normalizePath(option("stage2"), mustWork = TRUE)
output_dir <- normalizePath(option("output-dir"), mustWork = FALSE)
run_id <- option("run-id")
if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, recursive = TRUE, no.. = TRUE)) && !flag("overwrite")) {
  stop("Refusing to write fit-health outputs into a non-empty directory without --overwrite: ", output_dir)
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

sha256_file <- function(path) {
  value <- tryCatch(system2("sha256sum", path, stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) return(NA_character_)
  sub("[[:space:]].*$", "", value[[1L]])
}

checks <- list()
add <- function(check, status, observed = "", expected = "", details = "") {
  checks[[length(checks) + 1L]] <<- data.frame(
    section = "fit_health", check = check, status = toupper(as.character(status)),
    observed = as.character(observed), expected = as.character(expected), details = as.character(details),
    stringsAsFactors = FALSE
  )
}

fit_size <- file.info(fit_path)$size
fit_sha256 <- sha256_file(fit_path)
add("fit_artifact_exists", if (file.exists(fit_path) && is.finite(fit_size) && fit_size > 0) "PASS" else "FAIL",
    fit_path, "existing non-empty file", "The completed fit artifact is present and non-empty.")

build <- readRDS(build_path)
stage2 <- readRDS(stage2_path)
fit_artifact <- readRDS(fit_path)
fit <- joint_inla_extract_fit(fit_artifact)

family_ok <- identical(as.character(build$family), c("binomial", "nbinomial"))
add("likelihood_families", if (family_ok) "PASS" else "FAIL", paste(as.character(build$family), collapse = "/"), "binomial/nbinomial", "The saved Stage 3A model contract retains the two validated likelihood families.")

status_candidates <- character()
for (container in list(fit_artifact, fit_artifact$audit, fit_artifact$provenance)) {
  if (is.list(container) && !is.null(container$fit_status)) status_candidates <- c(status_candidates, as.character(container$fit_status))
}
if (length(status_candidates)) {
  add("fit_completion_status", if (tolower(status_candidates[[1L]]) %in% c("success", "completed", "ok")) "PASS" else "FAIL",
      status_candidates[[1L]], "success/completed", "The fit status recorded by the runner is successful.")
} else {
  add("fit_completion_status", "WARNING", "not recorded in artifact", "recorded success status", "Scheduler completion is the authoritative Gate 0; this artifact did not expose a runner status field.")
}
if (!is.null(fit$ok)) {
  add("fit_internal_ok", if (isTRUE(fit$ok)) "PASS" else "FAIL", fit$ok, TRUE, "Honor an explicit INLA fit ok flag when present.")
} else {
  add("fit_internal_ok", "WARNING", "not recorded", TRUE, "No explicit fit$ok field was exposed; remaining structural gates still apply.")
}

initialization_candidates <- character()
for (container in list(fit_artifact, fit_artifact$audit, fit_artifact$provenance, fit_artifact$metadata)) {
  if (is.list(container) && !is.null(container$initialization_mode)) initialization_candidates <- c(initialization_candidates, as.character(container$initialization_mode))
}
if (length(initialization_candidates)) {
  initialization_ok <- identical(tolower(initialization_candidates[[1L]]), "default")
  add("initialization_mode", if (initialization_ok) "PASS" else "FAIL", initialization_candidates[[1L]], "default", "The fit records the validated default initialization strategy.")
} else {
  add("initialization_mode", "WARNING", "not recorded in fit artifact", "default", "The runner configuration remains the authoritative initialization record.")
}

finite_summary <- function(x, label) {
  if (is.null(x) || !is.data.frame(as.data.frame(x)) || !nrow(as.data.frame(x))) {
    add(paste0(label, "_present"), "FAIL", "missing/empty", "non-empty summary table", paste(label, "is unavailable."))
    return(FALSE)
  }
  table <- as.data.frame(x, stringsAsFactors = FALSE)
  required_columns <- "mean"
  if (!all(required_columns %in% names(table))) {
    add(paste0(label, "_columns"), "FAIL", paste(names(table), collapse = ","), "mean", paste(label, "does not expose posterior means."))
    return(FALSE)
  }
  columns <- intersect(c("mean", "sd", "0.025quant", "0.975quant"), names(table))
  finite <- all(vapply(table[columns], function(column) all(is.finite(as.numeric(column))), logical(1L)))
  add(paste0(label, "_finite"), if (finite) "PASS" else "FAIL", paste(columns, collapse = ","), "all finite", paste(label, "numeric summaries are finite."))
  finite
}

finite_summary(fit$summary.fixed, "summary_fixed")
finite_summary(fit$summary.hyperpar, "summary_hyperpar")

required_random <- c("tier1_field", "tier2_field", "tier2_copy_field", "week_steps", "tier2_week", "admin_f", "cattle_q")
random_names <- names(fit$summary.random)
missing_random <- setdiff(required_random, random_names)
add("required_random_components", if (!length(missing_random)) "PASS" else "FAIL", paste(random_names, collapse = ","), paste(required_random, collapse = ","),
    if (!length(missing_random)) "All required random-effect summaries are present." else paste("Missing:", paste(missing_random, collapse = ", ")))
for (component in intersect(required_random, random_names)) finite_summary(fit$summary.random[[component]], paste0("summary_random_", component))

stack_info <- tryCatch(joint_inla_extract_stack_info(build), error = function(e) e)
if (inherits(stack_info, "error")) {
  add("joint_stack_structure", "FAIL", conditionMessage(stack_info), "valid named exhaustive stack indices", "Stage 3A stack structure could not be recovered.")
  stack_rows <- c(tier1 = NA_integer_, tier2 = NA_integer_)
} else {
  stack_rows <- vapply(stack_info$indices, length, integer(1L))
  add("joint_stack_structure", "PASS", paste(names(stack_rows), stack_rows, sep = "=", collapse = ";"), "named disjoint exhaustive indices", "The Stage 3A response stack is structurally valid.")
}

layout <- tryCatch(joint_inla_extract_predictor_layout(build, fit_artifact), error = function(e) e)
if (inherits(layout, "error")) {
  add("predictor_layout", "FAIL", conditionMessage(layout), "observed plus latent predictor blocks reconcile", "Fitted-value dimensions are unsafe for downstream extraction.")
  predictor_dimensions <- list(n_observed = NA_integer_, n_latent = NA_integer_, n_total = NA_integer_)
} else {
  predictor_dimensions <- layout[c("n_observed", "n_latent", "n_total")]
  add("predictor_layout", "PASS", paste(unlist(predictor_dimensions), collapse = "/"), "n_observed/n_latent/n_total reconcile", "summary.linear.predictor and summary.fitted.values match the recorded layout.")
}

compute <- build$fit_reference$control_compute
criteria <- list()
for (metric in c("dic", "waic")) {
  requested <- isTRUE(compute[[metric]])
  value <- if (is.list(fit[[metric]]) && !is.null(fit[[metric]][[metric]])) as.numeric(fit[[metric]][[metric]])[[1L]] else NA_real_
  criteria[[metric]] <- value
  status <- if (!requested) "WARNING" else if (is.finite(value)) "PASS" else "FAIL"
  add(paste0(metric, "_finite"), status, value, if (requested) "finite" else "not requested", if (requested) paste(metric, "was requested and is finite.") else paste(metric, "was not requested by the Stage 3A contract."))
}
mlik <- joint_inla_extract_marginal_log_likelihood(fit_artifact)
integration <- mlik$value[grepl("integration", mlik$method, ignore.case = TRUE)]
if (!length(integration)) integration <- mlik$value
mlik_value <- if (length(integration)) integration[[1L]] else NA_real_
add("marginal_log_likelihood", if (is.finite(mlik_value)) "PASS" else "FAIL", mlik_value, "finite", "The saved marginal log likelihood is available and finite.")

warnings <- character()
if (is.list(fit$misc) && !is.null(fit$misc$warnings)) warnings <- as.character(fit$misc$warnings)
add("fit_warnings_recorded", if (length(warnings)) "WARNING" else "PASS", if (length(warnings)) paste(warnings, collapse = " | ") else "none", "recorded provenance", "Warnings are reported as nonblocking provenance; they do not change the model.")

audit <- do.call(rbind, checks)
summary <- list(
  run_id = run_id, generated_utc = format(Sys.time(), tz = "UTC"), hostname = unname(Sys.info()[["nodename"]]),
  fit_path = fit_path, fit_size_bytes = unname(fit_size), fit_sha256 = fit_sha256,
  build_path = build_path, stage2_path = stage2_path,
  stage2_rows = c(tier1 = nrow(stage2$tier1), tier2 = nrow(stage2$tier2)),
  stack_rows = stack_rows, predictor_dimensions = predictor_dimensions,
  criteria = criteria, marginal_log_likelihood = mlik_value,
  initialization_mode = if (length(initialization_candidates)) initialization_candidates[[1L]] else NA_character_,
  warnings = warnings, audit = audit,
  counts = list(pass = sum(audit$status == "PASS"), warning = sum(audit$status == "WARNING"), fail = sum(audit$status == "FAIL"))
)
audit_path <- file.path(output_dir, paste0("fit_health_", run_id, ".csv"))
metadata_path <- file.path(output_dir, paste0("fit_health_", run_id, "_metadata.rds"))
utils::write.csv(audit, audit_path, row.names = FALSE, na = "")
saveRDS(summary, metadata_path)
cat("Stage 3B fit health: PASS=", sum(audit$status == "PASS"), ", WARNING=", sum(audit$status == "WARNING"), ", FAIL=", sum(audit$status == "FAIL"), "\n", sep = "")
cat("Audit: ", audit_path, "\nMetadata: ", metadata_path, "\n", sep = "")
if (any(audit$status == "FAIL")) stop("Stage 3B fit-health gate failed.")
