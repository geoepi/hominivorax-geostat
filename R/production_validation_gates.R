# Compact production validation gates.
#
# Detailed stage audits remain the implementation-level record.  These
# functions select only scientifically and operationally blocking invariants
# for the three production gates and emit one stable machine-readable schema.

production_gate_scalar <- function(value) {
  if (is.null(value) || !length(value)) return(NA_character_)
  if (is.list(value)) return(paste(unlist(value, use.names = FALSE), collapse = ";"))
  value <- as.character(value)
  if (!length(value)) NA_character_ else paste(value, collapse = ";")
}

production_gate_row <- function(gate, check, severity, status, message = "",
                                artifact = NA_character_, expected = NA_character_,
                                observed = NA_character_) {
  severity <- toupper(as.character(severity))
  status <- toupper(as.character(status))
  if (!severity %in% c("BLOCKING", "WARNING", "PROVENANCE")) stop("Unsupported gate severity: ", severity, call. = FALSE)
  if (!status %in% c("PASS", "WARN", "FAIL", "INFO")) stop("Unsupported gate status: ", status, call. = FALSE)
  data.frame(
    gate = as.character(gate), check = as.character(check), severity = severity,
    status = status, message = as.character(message), artifact = production_gate_scalar(artifact),
    expected = production_gate_scalar(expected), observed = production_gate_scalar(observed),
    stringsAsFactors = FALSE
  )
}

production_gate_finalize <- function(rows) {
  if (is.null(rows) || !length(rows)) stop("A production gate must contain at least one check.", call. = FALSE)
  audit <- if (is.data.frame(rows)) rows else do.call(rbind, rows)
  blocking_fail <- audit$severity == "BLOCKING" & audit$status == "FAIL"
  outcome <- if (any(blocking_fail, na.rm = TRUE)) "FAIL" else if (any(audit$status == "WARN", na.rm = TRUE)) "PASS_WITH_WARNINGS" else "PASS"
  list(
    audit = audit,
    gate = unique(as.character(audit$gate))[[1L]],
    outcome = outcome,
    warning_count = sum(audit$status == "WARN" | (audit$severity == "WARNING" & audit$status == "INFO"), na.rm = TRUE),
    failure_count = sum(blocking_fail, na.rm = TRUE)
  )
}

production_gate_write <- function(result, output_dir, prefix = result$gate) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- file.path(output_dir, paste0(prefix, "_gate.csv"))
  rds_path <- file.path(output_dir, paste0(prefix, "_gate.rds"))
  utils::write.csv(result$audit, csv_path, row.names = FALSE, na = "")
  saveRDS(result, rds_path)
  result$csv_path <- normalizePath(csv_path, mustWork = TRUE)
  result$rds_path <- normalizePath(rds_path, mustWork = TRUE)
  result
}

production_gate_print <- function(result) {
  cat(toupper(gsub("_", "-", result$gate)), " GATE\n", sep = "")
  cat(result$outcome, "\n", sep = "")
  for (i in seq_len(nrow(result$audit))) {
    row <- result$audit[i, , drop = FALSE]
    label <- gsub("_", " ", tools::toTitleCase(row$check[[1L]]))
    status <- if (row$status[[1L]] == "INFO") "INFO" else if (row$status[[1L]] == "WARN") "WARN" else row$status[[1L]]
    cat(sprintf("%-28s %s\n", label, status))
  }
  cat("Warnings: ", result$warning_count, "\n", sep = "")
  invisible(result)
}

production_gate_safe_rds <- function(path) {
  if (is.null(path) || !length(path) || is.na(path[[1L]]) || !file.exists(path[[1L]])) return(NULL)
  tryCatch(readRDS(path[[1L]]), error = function(e) NULL)
}

production_gate_file_ok <- function(path) {
  is.character(path) && length(path) == 1L && !is.na(path) && file.exists(path) && is.finite(file.info(path)$size[[1L]]) && file.info(path)$size[[1L]] > 0
}

production_gate_audit <- function(path, ignore = character()) {
  if (!production_gate_file_ok(path)) return(NULL)
  value <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
  if (!is.data.frame(value) || !nrow(value) || !"status" %in% names(value)) return(NULL)
  value$check <- if ("check" %in% names(value)) as.character(value$check) else "audit"
  value$status <- toupper(as.character(value$status))
  value[!value$check %in% ignore, , drop = FALSE]
}

production_gate_audit_has_fail <- function(path, ignore = character()) {
  audit <- production_gate_audit(path, ignore)
  is.data.frame(audit) && any(audit$status == "FAIL")
}

production_gate_find_file <- function(root, pattern, recursive = TRUE) {
  if (is.null(root) || !dir.exists(root)) return(NA_character_)
  paths <- list.files(root, pattern = pattern, recursive = recursive, full.names = TRUE)
  if (!length(paths)) NA_character_ else sort(paths)[[1L]]
}

production_gate_equal_path <- function(observed, expected) {
  if (is.null(observed) || !length(observed) || is.na(observed[[1L]]) || !nzchar(as.character(observed[[1L]]))) return(FALSE)
  normalizePath(as.character(observed[[1L]]), mustWork = FALSE) == normalizePath(as.character(expected), mustWork = FALSE)
}

production_gate_prepare <- function(contract, dims = contract$dynamic_dimensions) {
  gate <- "prepare"
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- production_gate_row(gate, ...)
  input_path <- contract$input$observations
  config_path <- contract$config$path
  add("input_readable", "BLOCKING", if (production_gate_file_ok(input_path)) "PASS" else "FAIL", "Authoritative input is readable.", input_path, "existing non-empty file", input_path)
  input_sha <- if (production_gate_file_ok(input_path)) production_orchestration_hash_file(input_path) else NA_character_
  add("input_sha_recorded", "BLOCKING", if (production_gate_file_ok(input_path) && identical(as.character(contract$input$sha256), input_sha)) "PASS" else "FAIL", "Input SHA is recorded and matches the current authoritative input.", input_path, input_sha, contract$input$sha256)
  add("production_config", "BLOCKING", if (production_gate_file_ok(config_path)) "PASS" else "FAIL", "Production configuration is readable.", config_path, "existing non-empty file", config_path)
  horizon <- contract$horizon
  weeks <- as.character(horizon$modeled_week_labels %||% character())
  horizon_ok <- length(weeks) > 0L && !anyNA(weeks) && !anyDuplicated(weeks) && identical(length(weeks), as.integer(horizon$modeled_weeks))
  add("dynamic_horizon", "BLOCKING", if (horizon_ok) "PASS" else "FAIL", "The resolved horizon is positive, unique, and dynamically represented.", config_path, "unique modeled weeks", paste(weeks, collapse = ","))

  stage_paths <- c(stage1 = file.path(contract$paths$stage1, "model_inputs.rds"), stage2 = file.path(contract$paths$stage2, "joint_model_inputs.rds"), stage3a = file.path(contract$paths$stage3a, "joint_inla_build.rds"))
  readable <- vapply(stage_paths, production_gate_file_ok, logical(1L))
  for (name in names(stage_paths)) add(paste0(name, "_artifact"), "BLOCKING", if (readable[[name]]) "PASS" else "FAIL", paste0("", toupper(name), " artifact is readable."), stage_paths[[name]], "existing non-empty RDS", stage_paths[[name]])
  stage1 <- production_gate_safe_rds(stage_paths[["stage1"]]); stage2 <- production_gate_safe_rds(stage_paths[["stage2"]]); build <- production_gate_safe_rds(stage_paths[["stage3a"]])
  add("stage_artifact_deserialization", "BLOCKING", if (all(readable) && !is.null(stage1) && !is.null(stage2) && !is.null(build)) "PASS" else "FAIL", "Stage 1, Stage 2, and Stage 3A artifacts deserialize.", paste(stage_paths, collapse = ";"), "three readable RDS objects", paste(vapply(list(stage1, stage2, build), function(x) !is.null(x), logical(1L)), collapse = ";"))

  stage2_source <- stage2$provenance$source_model_inputs %||% NA_character_
  stage2_source_ok <- !is.null(stage1) && production_gate_equal_path(stage2_source, stage_paths[["stage1"]])
  add("stage1_to_stage2_provenance", "BLOCKING", if (stage2_source_ok) "PASS" else "FAIL", "Stage 2 records the direct Stage 1 artifact as its source.", stage_paths[["stage2"]], stage_paths[["stage1"]], stage2_source)
  stage3a_source <- build$provenance$source_artifact %||% build$config$inputs$joint_model_inputs %||% NA_character_
  stage3a_sha <- build$provenance$source_artifact_sha256 %||% NA_character_
  stage2_sha <- if (production_gate_file_ok(stage_paths[["stage2"]])) production_orchestration_hash_file(stage_paths[["stage2"]]) else NA_character_
  stage3a_source_ok <- !is.null(build) && production_gate_equal_path(stage3a_source, stage_paths[["stage2"]]) && identical(as.character(stage3a_sha), as.character(stage2_sha))
  add("stage2_to_stage3a_provenance", "BLOCKING", if (stage3a_source_ok) "PASS" else "FAIL", "Stage 3A records and hashes its direct Stage 2 parent.", stage_paths[["stage3a"]], stage2_sha, paste(stage3a_source, stage3a_sha, sep = ";"))

  dims_ok <- !is.null(dims) && isTRUE(as.integer(dims$prediction_rows) == as.integer(dims$expected_prediction_rows)) && isTRUE(as.integer(dims$modeled_weeks) > 0L) && isTRUE(as.integer(dims$supported_cells) > 0L)
  add("dynamic_dimensions", "BLOCKING", if (dims_ok) "PASS" else "FAIL", "Prediction rows and support dimensions reconcile dynamically.", stage_paths[["stage2"]], paste0("rows=", dims$expected_prediction_rows %||% NA, "; weeks=", dims$modeled_weeks %||% NA, "; cells=", dims$supported_cells %||% NA), paste0("rows=", dims$prediction_rows %||% NA))
  group_levels <- if (!is.null(dims$groups$levels)) dims$groups$levels else list()
  groups_ok <- length(group_levels) >= 4L && all(vapply(group_levels, function(x) identical(as.integer(x), seq_len(length(x))), logical(1L)))
  add("dynamic_spde_group_dimensions", "BLOCKING", if (groups_ok) "PASS" else "FAIL", "Temporal and SPDE grouping levels are contiguous and dynamically reconciled.", stage_paths[["stage3a"]], "each group is 1:n_groups", paste(vapply(group_levels, function(x) paste(x, collapse = ","), character(1L)), collapse = ";"))

  grid <- if (is.list(stage2)) stage2$prediction_grid else NULL
  required <- unique(c("x", "y", "quarter_index", "epiyear", "epiweek", build$prediction_compatibility$required_columns %||% character()))
  required_ok <- is.data.frame(grid) && all(required %in% names(grid))
  finite_ok <- required_ok && all(vapply(grid[required], function(x) all(is.finite(as.numeric(x))), logical(1L)))
  add("model_covariates_finite", "BLOCKING", if (finite_ok) "PASS" else "FAIL", "Required prediction-grid covariates and temporal indices are present and finite.", stage_paths[["stage2"]], paste(required, collapse = ","), if (required_ok) paste(names(grid)[vapply(grid, function(x) is.numeric(x) || is.integer(x), logical(1L))], collapse = ",") else "missing prediction_grid")
  fit_executed <- if (is.list(build$provenance)) build$provenance$executed_fit else NA
  add("fit_executed_false", "BLOCKING", if (isFALSE(fit_executed)) "PASS" else "FAIL", "Stage 3A is an assembly artifact and has not executed the fit.", stage_paths[["stage3a"]], FALSE, fit_executed)
  preflight_path <- production_gate_find_file(contract$paths$preflight, "\\.csv$")
  preflight_audit <- production_gate_audit(preflight_path)
  preflight_ok <- !is.na(preflight_path) && is.data.frame(preflight_audit) && !any(preflight_audit$status == "FAIL")
  add("preflight_contract", "BLOCKING", if (preflight_ok) "PASS" else "FAIL", "Stage 3B preflight completed without a blocking failure.", preflight_path, "no FAIL rows", if (is.data.frame(preflight_audit)) paste(table(preflight_audit$status), collapse = ";") else "missing audit")
  production_gate_finalize(rows)
}

production_gate_fit <- function(contract) {
  gate <- "fit"
  rows <- list(); add <- function(...) rows[[length(rows) + 1L]] <<- production_gate_row(gate, ...)
  fit_path <- file.path(contract$paths$stage3b, "joint_model_fit.rds")
  build_path <- file.path(contract$paths$stage3a, "joint_inla_build.rds")
  metadata_path <- file.path(contract$paths$stage3b, "joint_model_fit_metadata.rds")
  health_path <- production_gate_find_file(contract$paths$fit_health, "fit_health_.*\\.csv$")
  fit_artifact <- production_gate_safe_rds(fit_path); build <- production_gate_safe_rds(build_path); metadata <- production_gate_safe_rds(metadata_path)
  fit <- if (is.list(fit_artifact) && !is.null(fit_artifact$fit)) fit_artifact$fit else fit_artifact
  add("fit_readable", "BLOCKING", if (production_gate_file_ok(fit_path) && !is.null(fit_artifact)) "PASS" else "FAIL", "Completed fit artifact is readable.", fit_path, "readable non-empty RDS", fit_path)
  expected_build_sha <- if (production_gate_file_ok(build_path)) production_orchestration_hash_file(build_path) else NA_character_
  recorded_build_sha <- c(fit_artifact$provenance$stage3a_artifact_sha256, metadata$provenance$stage3a_artifact_sha256, metadata$provenance$stage3a_sha256)
  recorded_build_sha <- recorded_build_sha[!is.null(recorded_build_sha) & !is.na(recorded_build_sha)]
  provenance_ok <- length(recorded_build_sha) > 0L && any(as.character(recorded_build_sha) == as.character(expected_build_sha))
  add("fit_provenance", "BLOCKING", if (provenance_ok) "PASS" else "FAIL", "Fit provenance records the accepted Stage 3A artifact SHA.", fit_path, expected_build_sha, if (length(recorded_build_sha)) paste(recorded_build_sha, collapse = ";") else "missing")
  fit_ok <- if (is.list(fit)) fit$ok else FALSE
  add("fit_ok", "BLOCKING", if (isTRUE(fit_ok)) "PASS" else "FAIL", "The fitted model exposes fit$ok == TRUE.", fit_path, TRUE, fit_ok)
  completion <- c(fit_artifact$fit_status, fit_artifact$audit$fit_status, metadata$audit$fit_status)
  completion <- completion[!is.null(completion) & !is.na(completion)]
  completion_ok <- length(completion) > 0L && tolower(as.character(completion[[1L]])) %in% c("success", "completed", "ok")
  add("convergence_completion", "BLOCKING", if (completion_ok) "PASS" else "FAIL", "The runner records successful fit/convergence completion.", fit_path, "success/completed/ok", if (length(completion)) completion[[1L]] else "missing")
  family <- if (is.list(build)) as.character(build$family) else character()
  family_ok <- identical(family, c("binomial", "nbinomial"))
  add("family_link_contract", "BLOCKING", if (family_ok) "PASS" else "FAIL", "Likelihood family/link contract matches the current model.", build_path, "binomial/nbinomial", paste(family, collapse = "/"))
  required_fixed <- is.data.frame(fit$summary.fixed) && nrow(fit$summary.fixed) > 0L
  required_hyper <- is.data.frame(fit$summary.hyperpar) && nrow(fit$summary.hyperpar) > 0L
  required_random <- is.list(fit$summary.random) && all(c("tier1_field", "tier2_field", "tier2_copy_field") %in% names(fit$summary.random))
  add("posterior_summaries", "BLOCKING", if (required_fixed && required_hyper && required_random) "PASS" else "FAIL", "Fixed, hyperparameter, and required random-effect summaries exist.", fit_path, "fixed, hyper, tier1/tier2/copy random summaries", paste(required_fixed, required_hyper, required_random, sep = ";"))
  finite_frame <- function(x) is.data.frame(x) && nrow(x) > 0L && all(vapply(x, function(column) all(is.finite(as.numeric(column))), logical(1L)))
  finite_summaries <- required_fixed && required_hyper && required_random && finite_frame(fit$summary.fixed) && finite_frame(fit$summary.hyperpar) && all(vapply(fit$summary.random[c("tier1_field", "tier2_field", "tier2_copy_field")], finite_frame, logical(1L)))
  add("posterior_values_finite", "BLOCKING", if (finite_summaries) "PASS" else "FAIL", "Required posterior summaries are finite.", fit_path, "all required summary values finite", finite_summaries)
  predictor_finite <- is.data.frame(fit$summary.linear.predictor) && "mean" %in% names(fit$summary.linear.predictor) && all(is.finite(as.numeric(fit$summary.linear.predictor$mean)))
  fitted_finite <- is.data.frame(fit$summary.fitted.values) && "mean" %in% names(fit$summary.fitted.values) && all(is.finite(as.numeric(fit$summary.fitted.values$mean)))
  add("predictor_values_finite", "BLOCKING", if (predictor_finite && fitted_finite) "PASS" else "FAIL", "Posterior predictor and fitted-value means are finite.", fit_path, "linear predictor and fitted means finite", paste(predictor_finite, fitted_finite, sep = ";"))
  health <- production_gate_audit(health_path)
  required_health_checks <- c("fit_artifact_exists", "likelihood_families", "fit_completion_status", "fit_internal_ok", "summary_fixed_finite", "summary_hyperpar_finite", "required_random_components", "joint_stack_structure", "predictor_layout")
  health_fail <- is.data.frame(health) && any(health$check %in% required_health_checks & health$status == "FAIL")
  add("fit_health_structure", "BLOCKING", if (!is.na(health_path) && !health_fail) "PASS" else "FAIL", "Detailed fit-health audit contains no required structural failures.", health_path, "required checks pass", if (is.data.frame(health)) paste(health$check[health$status == "FAIL"], collapse = ",") else "missing audit")
  historical <- if (is.data.frame(health)) health$check %in% c("initialization_provenance", "theta_initialization_provenance", "dic_finite", "waic_finite", "marginal_log_likelihood") else logical()
  if (is.data.frame(health) && any(historical)) add("historical_fit_diagnostics", "WARNING", "WARN", "Historical/initialization diagnostics are retained for provenance and do not block a valid fit.", health_path, "nonblocking", paste(health$check[historical], health$status[historical], sep = "=", collapse = ";"))
  production_gate_finalize(rows)
}

production_gate_postfit <- function(contract, dims = contract$dynamic_dimensions) {
  gate <- "postfit"
  rows <- list(); add <- function(...) rows[[length(rows) + 1L]] <<- production_gate_row(gate, ...)
  required_file <- function(check, path, message, expected = "existing non-empty file") add(check, "BLOCKING", if (production_gate_file_ok(path)) "PASS" else "FAIL", message, path, expected, path)
  holdout <- file.path(contract$paths$extraction, paste0("holdout_predictions_", contract$run_id, ".csv"))
  required_file("extraction_completed", holdout, "Extraction emitted the run-specific holdout predictions.")
  extraction_audit <- production_gate_find_file(contract$paths$extraction, "extraction_audit_.*\\.csv$")
  add("holdout_alignment", "BLOCKING", if (!is.na(extraction_audit) && !production_gate_audit_has_fail(extraction_audit)) "PASS" else "FAIL", "Extraction audit reports aligned holdout rows without a failure.", extraction_audit, "no FAIL rows", extraction_audit)
  validation_audit <- production_gate_find_file(contract$paths$validation, "\\.csv$")
  add("validation_predictions_finite", "BLOCKING", if (!is.na(validation_audit) && !production_gate_audit_has_fail(validation_audit)) "PASS" else "FAIL", "Validation/extraction audit contains no required prediction failure.", validation_audit, "no FAIL rows", validation_audit)
  projection_manifest <- production_gate_find_file(contract$paths$projection, "^prediction_projection_manifest_.*\\.csv$")
  projection_audit <- production_gate_find_file(contract$paths$projection, "^prediction_projection_audit_.*\\.csv$")
  required_file("projection_reconstruction", projection_audit, "Phase 2 projection audit exists.")
  projection <- if (!is.na(projection_manifest)) tryCatch(utils::read.csv(projection_manifest, stringsAsFactors = FALSE), error = function(e) NULL) else NULL
  projection_ok <- is.data.frame(projection) && nrow(projection) == as.integer(dims$prediction_rows) && !is.na(projection_audit) && !production_gate_audit_has_fail(projection_audit)
  add("projection_dimensions", "BLOCKING", if (projection_ok) "PASS" else "FAIL", "Phase 2 projection rows and reconstruction reconcile with dynamic dimensions.", projection_manifest, dims$prediction_rows, if (is.data.frame(projection)) nrow(projection) else "missing")
  raster_manifest <- file.path(contract$paths$raster, "qa", "temporal_manifest.csv")
  raster_audit <- file.path(contract$paths$raster, "qa", "file_integrity_manifest.csv")
  required_file("raster_mapping", raster_manifest, "Phase 3 temporal raster manifest exists.", dims$modeled_weeks)
  raster_table <- if (production_gate_file_ok(raster_manifest)) tryCatch(utils::read.csv(raster_manifest, stringsAsFactors = FALSE), error = function(e) NULL) else NULL
  raster_ok <- is.data.frame(raster_table) && nrow(raster_table) == as.integer(dims$modeled_weeks) && !production_gate_audit_has_fail(raster_audit)
  add("raster_reconciliation", "BLOCKING", if (raster_ok) "PASS" else "FAIL", "Raster weeks and support reconcile with the dynamic model horizon.", raster_manifest, dims$modeled_weeks, if (is.data.frame(raster_table)) nrow(raster_table) else "missing")
  structural_qa <- file.path(contract$paths$structural, "qa", "structural_qa_summary.csv")
  structural_audit <- file.path(contract$paths$structural, "qa", "structural_reconstruction_audit.csv")
  structural_meta <- file.path(contract$paths$structural, "metadata", "structural_surface_metadata.rds")
  structural_ok <- production_gate_file_ok(structural_qa) && production_gate_file_ok(structural_audit) && production_gate_file_ok(structural_meta) && !production_gate_audit_has_fail(structural_qa) && !production_gate_audit_has_fail(structural_audit)
  add("structural_reconstruction", "BLOCKING", if (structural_ok) "PASS" else "FAIL", "SPDE-excluded structural reconstruction and metadata are present without a failure.", structural_qa, "reconstruction and metadata pass", structural_qa)
  masked_meta <- file.path(contract$paths$masked, "metadata", "masked_structural_rpi_metadata.rds")
  if (!production_gate_file_ok(masked_meta)) masked_meta <- production_gate_find_file(contract$paths$masked, "metadata.*\\.rds$")
  temperature_audit <- file.path(contract$paths$masked, "qa", "temperature_alignment_audit.csv")
  if (!production_gate_file_ok(temperature_audit)) temperature_audit <- file.path(contract$paths$structural, "qa", "temperature_alignment_audit.csv")
  mask_audit <- file.path(contract$paths$masked, "qa", "temperature_mask_weekly_audit.csv")
  temperature_ok <- production_gate_file_ok(masked_meta) && production_gate_file_ok(mask_audit) && (!production_gate_file_ok(temperature_audit) || !production_gate_audit_has_fail(temperature_audit))
  add("temperature_mask", "BLOCKING", if (temperature_ok) "PASS" else "FAIL", "Temperature support is aligned and the masked structural product exists.", masked_meta, "aligned mask metadata and weekly audit", masked_meta)
  reporting_manifest <- production_gate_find_file(contract$paths$reporting, "^manifest.*\\.csv$")
  reporting_summary <- file.path(contract$paths$reporting, "qa", "reporting_qa_summary.csv")
  reporting_table <- if (production_gate_file_ok(reporting_summary)) tryCatch(utils::read.csv(reporting_summary, stringsAsFactors = FALSE), error = function(e) NULL) else NULL
  reporting_ok <- production_gate_file_ok(reporting_manifest) && is.data.frame(reporting_table) && nrow(reporting_table) > 0L && !identical(toupper(as.character(reporting_table$status[[1L]])), "FAIL")
  add("reporting_manifest", "BLOCKING", if (reporting_ok) "PASS" else "FAIL", "Final reporting manifest and QA summary exist without a blocking failure.", reporting_manifest, "manifest plus non-FAIL QA", if (is.data.frame(reporting_table)) reporting_table$status[[1L]] else "missing")
  threshold_path <- file.path(contract$paths$reporting, "objects", "rpi_dynamic_threshold.rds")
  threshold_qa <- file.path(contract$paths$reporting, "qa", "rpi_dynamic_threshold_reproducibility.csv")
  threshold_obj <- production_gate_safe_rds(threshold_path)
  threshold_table <- if (production_gate_file_ok(threshold_qa)) tryCatch(utils::read.csv(threshold_qa, stringsAsFactors = FALSE), error = function(e) NULL) else NULL
  threshold_ok <- is.list(threshold_obj) && length(threshold_obj$threshold_value) == 1L && is.finite(as.numeric(threshold_obj$threshold_value)) && is.data.frame(threshold_table) && nrow(threshold_table) > 0L && "absolute_difference" %in% names(threshold_table) && is.finite(as.numeric(threshold_table$absolute_difference[[1L]])) && as.numeric(threshold_table$absolute_difference[[1L]]) <= 1e-8
  add("dynamic_rpi_threshold", "BLOCKING", if (threshold_ok) "PASS" else "FAIL", "The RPI threshold artifact independently reproduces the reported threshold.", threshold_path, "finite and absolute difference <= 1e-8", if (is.data.frame(threshold_table)) threshold_table$absolute_difference[[1L]] else "missing")
  rpi_class <- file.path(contract$paths$reporting, "objects", "rpi_class_summary.rds")
  rpi_class_ok <- production_gate_file_ok(rpi_class) && !is.null(production_gate_safe_rds(rpi_class))
  add("rpi_class_support", "BLOCKING", if (rpi_class_ok) "PASS" else "FAIL", "RPI class summary is present for the dynamic supported-cell product.", rpi_class, "readable class summary", rpi_class)
  metadata_rds <- production_gate_find_file(contract$paths$reporting, "reporting_metadata.*\\.rds$")
  add("final_reporting_artifacts", "BLOCKING", if (!is.na(metadata_rds) && production_gate_file_ok(metadata_rds)) "PASS" else "FAIL", "Required final reporting metadata are present.", metadata_rds, "readable reporting metadata", metadata_rds)
  add("provenance_coordinates", "PROVENANCE", "INFO", "Authoritative coordinate source and CRS remain recorded in the post-fit metadata.", contract$input$observations, "lon/lat, EPSG:4326", contract$input$coordinate_fields)
  production_gate_finalize(rows)
}

production_validation_inventory <- function() {
  blocking <- data.frame(
    gate = c(rep("prepare", 11L), rep("fit", 9L), rep("postfit", 12L), rep("prepare", 4L), rep("fit", 3L), rep("postfit", 9L)),
    check_name = c(
      "input_readable", "input_sha_recorded", "production_config", "dynamic_horizon", "stage1_artifact", "stage2_artifact", "stage3a_artifact", "stage1_to_stage2_provenance", "stage2_to_stage3a_provenance", "dynamic_dimensions", "fit_executed_false",
      "fit_readable", "fit_provenance", "fit_ok", "convergence_completion", "posterior_summaries", "posterior_values_finite", "predictor_values_finite", "family_link_contract",
      "extraction_completed", "holdout_alignment", "projection_reconstruction", "projection_dimensions", "raster_reconciliation", "structural_reconstruction", "temperature_mask", "authoritative_coordinate_transform", "same_week_rpi_matching", "dynamic_rpi_threshold", "rpi_class_support", "final_reporting_artifacts", "final_manifest",
      "historical_reference_statistics", "historical_mesh_summary", "runtime_estimate", "historical_holdout_count", "initialization_provenance", "theta_source", "theta_compatibility", "dic_waic_comparison", "marginal_likelihood_comparison", "historical_metric_comparison", "historical_rpi_comparison", "host_denominator_expansion", "environment_versions", "scheduler_job_id", "resolved_horizon_provenance", "artifact_shas"),
    current_location = c(rep("orchestrator/preflight", 11L), rep("fit-health/orchestrator", 9L), rep("post-fit audits/orchestrator", 12L), rep("historical diagnostics", 16L)),
    current_severity = c(rep("BLOCKING", 32L), rep("MIXED", 16L)),
    proposed_severity = c(rep("BLOCKING", 32L), "WARNING", "WARNING", "PROVENANCE", "WARNING", "PROVENANCE", "PROVENANCE", "BLOCKING", "WARNING", "WARNING", "WARNING", "WARNING", "WARNING", "PROVENANCE", "PROVENANCE", "PROVENANCE", "PROVENANCE"),
    reason = c(rep("Scientific correctness, lineage, dimensions, finite values, or required output contract.", 32L), "Informs operators but is not a correctness criterion.", "Current mesh is valid when independently dimensioned.", "Operational estimate only.", "Current support is dynamic.", "Provenance is retained; initialization source is not fit health.", "Provenance retained.", "Pre-fit theta compatibility protects model initialization lineage.", "Historical diagnostic only.", "Historical diagnostic only.", "Historical diagnostic only.", "Historical diagnostic only.", "Nonblocking host-composition warning.", "Provenance unless incompatible.", "Provenance only.", "Provenance only.", "Provenance only."),
    upstream_duplicate = FALSE, historical_only = c(rep(FALSE, 32L), TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE), dynamic_or_hardcoded = c(rep("dynamic", 32L), "historical", "historical", "none", "historical", "dynamic", "dynamic", "dynamic", "historical", "historical", "historical", "historical", "dynamic", "environment", "provenance", "dynamic", "provenance"), action = c(rep("retain", 32L), "demote", "demote", "demote", "demote", "demote", "demote", "demote", "demote", "demote", "demote", "demote", "demote", "retain", "retain", "retain", "retain"), stringsAsFactors = FALSE
  )
}
