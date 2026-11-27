# Versioned refresh requests, fit adoption, release registration and activation.

production_release_sha256 <- function(path) {
  if (!file.exists(path) || dir.exists(path)) stop("Artifact is missing or is not a file: ", path, call. = FALSE)
  production_orchestration_hash_file(path)
}

production_release_is_sha256 <- function(value) {
  length(value) == 1L && !is.na(value) && grepl("^[[:xdigit:]]{64}$", as.character(value))
}

production_release_resolve_path <- function(path, repo_root) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NA_character_)
  production_orchestration_resolve_path(as.character(path), repo_root)
}

production_release_assert_fields <- function(value, required, allowed, label) {
  if (!is.list(value) || is.null(names(value))) stop(label, " must be a named mapping.", call. = FALSE)
  missing <- setdiff(required, names(value))
  extra <- setdiff(names(value), allowed)
  if (length(missing)) stop(label, " is missing required fields: ", paste(missing, collapse = ", "), call. = FALSE)
  if (length(extra)) stop(label, " has unsupported fields: ", paste(extra, collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

production_release_validate_request <- function(request) {
  top <- c("schema_version", "request_id", "operation", "configuration", "model", "data",
           "environmental_data", "covariate_registry", "analysis", "output", "qualification",
           "reporting", "resume", "adoption")
  production_release_assert_fields(request, top, top, "refresh request")
  if (!identical(as.integer(request$schema_version), 1L)) stop("Unsupported refresh request schema_version.", call. = FALSE)
  if (length(request$request_id) != 1L || is.na(request$request_id) || !grepl("^[A-Za-z0-9_.-]+$", request$request_id)) {
    stop("request_id must contain only letters, digits, dot, underscore, or hyphen.", call. = FALSE)
  }
  production_release_assert_fields(request$operation, c("mode", "requested_stages", "dispatch_authorized"),
                                   c("mode", "requested_stages", "dispatch_authorized"), "operation")
  mode <- as.character(request$operation$mode)
  if (length(mode) != 1L || !mode %in% c("full", "resume", "adopt")) stop("operation.mode must be full, resume, or adopt.", call. = FALSE)
  stages <- tolower(unlist(request$operation$requested_stages, use.names = FALSE))
  if (anyDuplicated(stages) || any(!stages %in% c("prepare", "fit", "postfit"))) stop("requested_stages contains an invalid or repeated stage.", call. = FALSE)
  if (mode == "full" && !identical(stages, c("prepare", "fit", "postfit"))) stop("Full refresh must request Prepare, Fit, then Post-fit.", call. = FALSE)
  if (mode == "resume" && !identical(stages, c("prepare", "fit", "postfit"))) stop("Resume requests must declare the canonical Prepare, Fit, Post-fit stage set; accepted statuses choose the first incomplete stage.", call. = FALSE)
  if (mode == "adopt" && any(stages %in% c("prepare", "fit"))) stop("Adopt mode may not request Prepare or Fit.", call. = FALSE)
  if (mode == "adopt" && length(stages) && !identical(stages, "postfit")) stop("Adopt mode may request Post-fit only.", call. = FALSE)
  if (!is.logical(request$operation$dispatch_authorized) || length(request$operation$dispatch_authorized) != 1L || is.na(request$operation$dispatch_authorized)) {
    stop("operation.dispatch_authorized must be a single TRUE or FALSE value.", call. = FALSE)
  }

  production_release_assert_fields(request$configuration, c("role", "path", "sha256", "identity_id", "identity_path", "identity_sha256"),
                                   c("role", "path", "sha256", "identity_id", "identity_path", "identity_sha256"), "configuration")
  if (!as.character(request$configuration$role) %in% c("candidate_execution", "active_deployment")) stop("configuration.role must be candidate_execution or active_deployment.", call. = FALSE)
  if (mode %in% c("full", "resume") && !identical(as.character(request$configuration$role), "candidate_execution")) stop("Full and resume requests require a candidate_execution configuration.", call. = FALSE)
  for (key in c("sha256", "identity_sha256")) if (!production_release_is_sha256(request$configuration[[key]])) stop("configuration.", key, " must be a SHA-256 digest.", call. = FALSE)
  production_release_assert_fields(request$model, c("candidate_id", "production_id", "specification_id", "formula_identity"),
                                   c("candidate_id", "production_id", "specification_id", "formula_identity"), "model")
  production_release_assert_fields(request$data, c("release_id", "availability_endpoint", "observations_path", "observations_sha256"),
                                   c("release_id", "availability_endpoint", "observations_path", "observations_sha256"), "data")
  if (!production_release_is_sha256(request$data$observations_sha256)) stop("data.observations_sha256 must be a SHA-256 digest.", call. = FALSE)
  production_release_assert_fields(request$environmental_data, c("availability_endpoint", "identity_path", "identity_sha256"),
                                   c("availability_endpoint", "identity_path", "identity_sha256"), "environmental_data")
  if (!production_release_is_sha256(request$environmental_data$identity_sha256)) stop("environmental_data.identity_sha256 must be a SHA-256 digest.", call. = FALSE)
  production_release_assert_fields(request$covariate_registry, c("identifier", "sha256", "mode"),
                                   c("identifier", "sha256", "mode", "path"), "covariate_registry")
  if (!as.character(request$covariate_registry$mode) %in% c("manifest_free_original", "manifest")) stop("covariate_registry.mode must be manifest_free_original or manifest.", call. = FALSE)
  if (!is.null(request$covariate_registry$sha256) && !production_release_is_sha256(request$covariate_registry$sha256)) stop("covariate_registry.sha256 must be null or a SHA-256 digest.", call. = FALSE)
  if (identical(as.character(request$covariate_registry$mode), "manifest_free_original") &&
      (!is.null(request$covariate_registry$path) || !is.null(request$covariate_registry$sha256))) stop("The original manifest-free covariate specification must not claim a registry file or checksum.", call. = FALSE)
  if (identical(as.character(request$covariate_registry$mode), "manifest") &&
      (is.null(request$covariate_registry$path) || is.null(request$covariate_registry$sha256))) stop("A versioned covariate registry requires both path and SHA-256.", call. = FALSE)
  production_release_assert_fields(request$analysis, c("start_epiweek", "requested_endpoint"),
                                   c("start_epiweek", "requested_endpoint"), "analysis")
  week_fields <- c(request$data$availability_endpoint, request$environmental_data$availability_endpoint,
                   request$analysis$start_epiweek, request$analysis$requested_endpoint)
  if (any(!grepl("^[0-9]{4}-W[0-9]{2}$", as.character(week_fields)))) stop("Availability and analysis endpoints must use YYYY-Www epiweek format.", call. = FALSE)
  start_week <- production_orchestration_parse_week(request$analysis$start_epiweek)
  endpoint_week <- production_orchestration_parse_week(request$analysis$requested_endpoint)
  observation_endpoint <- production_orchestration_parse_week(request$data$availability_endpoint)
  environmental_endpoint <- production_orchestration_parse_week(request$environmental_data$availability_endpoint)
  endpoint_start <- production_orchestration_week_start(endpoint_week$year, endpoint_week$week)
  if (endpoint_start < production_orchestration_week_start(start_week$year, start_week$week)) stop("Requested analysis endpoint precedes analysis start.", call. = FALSE)
  if (endpoint_start > production_orchestration_week_start(observation_endpoint$year, observation_endpoint$week) ||
      endpoint_start > production_orchestration_week_start(environmental_endpoint$year, environmental_endpoint$week)) {
    stop("Requested analysis endpoint exceeds a declared observation or environmental availability endpoint.", call. = FALSE)
  }
  production_release_assert_fields(request$output, c("root"), c("root"), "output")
  if (length(request$output$root) != 1L || is.na(request$output$root) || !nzchar(as.character(request$output$root))) stop("output.root must be one non-empty path.", call. = FALSE)
  production_release_assert_fields(request$qualification, c("status", "required_gates", "evidence_manifest", "evidence_manifest_sha256"),
                                   c("status", "required_gates", "evidence_manifest", "evidence_manifest_sha256"), "qualification")
  if (!production_release_is_sha256(request$qualification$evidence_manifest_sha256)) stop("qualification.evidence_manifest_sha256 must be a SHA-256 digest.", call. = FALSE)
  production_release_assert_fields(request$reporting, c("temperature_mask_threshold_c", "rpi_calibration", "rpi_quantile", "required_products"),
                                   c("temperature_mask_threshold_c", "rpi_calibration", "rpi_quantile", "required_products"), "reporting")
  if (!is.numeric(request$reporting$temperature_mask_threshold_c) || !isTRUE(as.numeric(request$reporting$temperature_mask_threshold_c) == 16.0)) {
    stop("The production temperature-mask threshold must remain 16.0 C.", call. = FALSE)
  }
  if (!is.numeric(request$reporting$rpi_quantile) || length(request$reporting$rpi_quantile) != 1L ||
      !is.finite(request$reporting$rpi_quantile) || request$reporting$rpi_quantile < 0 || request$reporting$rpi_quantile > 1) stop("reporting.rpi_quantile is invalid.", call. = FALSE)
  if (!identical(as.character(request$reporting$rpi_calibration), "same_week_observation_pairs")) stop("The production RPI calibration must retain same-week observation pairing.", call. = FALSE)
  if (!length(unlist(request$reporting$required_products, use.names = FALSE)) || any(!nzchar(as.character(unlist(request$reporting$required_products, use.names = FALSE))))) stop("reporting.required_products must list at least one product.", call. = FALSE)

  if (mode == "resume") {
    if (!is.null(request$adoption)) stop("Resume requests may not contain adoption fields.", call. = FALSE)
    production_release_assert_fields(request$resume, c("run_id", "manifest_path", "manifest_sha256"),
                                     c("run_id", "manifest_path", "manifest_sha256"), "resume")
    if (!production_release_is_sha256(request$resume$manifest_sha256)) stop("resume.manifest_sha256 must be a SHA-256 digest.", call. = FALSE)
  } else if (!is.null(request$resume)) stop("Only resume requests may contain resume fields.", call. = FALSE)

  if (mode == "adopt") {
    if (!is.null(request$resume)) stop("Adopt requests may not contain resume fields.", call. = FALSE)
    production_release_assert_fields(request$adoption,
      c("artifact_manifest", "artifact_manifest_sha256", "source_fit_job_id", "fit_sha256", "fit_source_commit", "report_generation_commit", "lineage"),
      c("artifact_manifest", "artifact_manifest_sha256", "source_fit_job_id", "fit_sha256", "fit_source_commit", "report_generation_commit", "lineage"), "adoption")
    for (key in c("artifact_manifest_sha256", "fit_sha256")) if (!production_release_is_sha256(request$adoption[[key]])) stop("adoption.", key, " must be a SHA-256 digest.", call. = FALSE)
    for (key in c("fit_source_commit", "report_generation_commit")) {
      if (length(request$adoption[[key]]) != 1L || is.na(request$adoption[[key]]) ||
          !grepl("^[[:xdigit:]]{40}$", as.character(request$adoption[[key]]))) stop("adoption.", key, " must be a full Git commit SHA.", call. = FALSE)
    }
    if (length(request$adoption$source_fit_job_id) != 1L || is.na(request$adoption$source_fit_job_id) ||
        !grepl("^[0-9]+$", as.character(request$adoption$source_fit_job_id))) stop("adoption.source_fit_job_id must be a numeric historical Slurm job ID.", call. = FALSE)
    production_release_assert_fields(request$adoption$lineage,
      c("stage1_to_stage2_sha256", "stage2_to_stage3a_sha256", "stage3a_to_fit_sha256"),
      c("stage1_to_stage2_sha256", "stage2_to_stage3a_sha256", "stage3a_to_fit_sha256"), "adoption.lineage")
    for (key in names(request$adoption$lineage)) if (!production_release_is_sha256(request$adoption$lineage[[key]])) stop("adoption.lineage.", key, " must be a SHA-256 digest.", call. = FALSE)
  } else if (!is.null(request$adoption)) stop("Only adopt requests may contain adoption fields.", call. = FALSE)
  invisible(mode)
}

production_release_read_request <- function(path, repo_root) {
  production_orchestration_require("yaml")
  if (!file.exists(path)) stop("Refresh request does not exist: ", path, call. = FALSE)
  request <- yaml::read_yaml(path)
  production_release_validate_request(request)
  attr(request, "request_path") <- normalizePath(path, mustWork = TRUE)
  attr(request, "request_sha256") <- production_release_sha256(path)
  attr(request, "repo_root") <- normalizePath(repo_root, mustWork = TRUE)
  attr(request, "resolved") <- list(
    configuration = production_release_resolve_path(request$configuration$path, repo_root),
    configuration_identity = production_release_resolve_path(request$configuration$identity_path, repo_root),
    observations = production_release_resolve_path(request$data$observations_path, repo_root),
    environmental_identity = production_release_resolve_path(request$environmental_data$identity_path, repo_root),
    covariate_registry = if (identical(as.character(request$covariate_registry$mode), "manifest")) production_release_resolve_path(request$covariate_registry$path, repo_root) else NA_character_,
    output_root = production_release_resolve_path(request$output$root, repo_root),
    qualification_manifest = production_release_resolve_path(request$qualification$evidence_manifest, repo_root)
  )
  if (identical(request$operation$mode, "adopt")) {
    resolved <- attr(request, "resolved")
    resolved$artifact_manifest <- production_release_resolve_path(request$adoption$artifact_manifest, repo_root)
    attr(request, "resolved") <- resolved
  }
  request
}

production_release_request_document <- function(request) {
  document <- request
  attributes(document) <- list(names = names(request))
  document
}

production_release_validate_request_inputs <- function(request) {
  resolved <- attr(request, "resolved")
  if (is.null(resolved)) stop("Refresh request must be loaded with production_release_read_request().", call. = FALSE)
  checks <- list(
    configuration = production_release_verify_file(resolved$configuration, request$configuration$sha256, label = "production configuration"),
    configuration_identity = production_release_verify_file(resolved$configuration_identity, request$configuration$identity_sha256, label = "model configuration identity"),
    observation_release = production_release_verify_file(resolved$observations, request$data$observations_sha256, label = "observation release"),
    environmental_identity = production_release_verify_file(resolved$environmental_identity, request$environmental_data$identity_sha256, label = "environmental availability identity"),
    qualification_manifest = production_release_verify_file(resolved$qualification_manifest, request$qualification$evidence_manifest_sha256, label = "qualification/evidence manifest")
  )
  if (identical(as.character(request$covariate_registry$mode), "manifest")) {
    checks$covariate_registry <- production_release_verify_file(resolved$covariate_registry, request$covariate_registry$sha256, label = "covariate registry")
  }
  checks
}

production_release_configuration_compatibility <- function(request, repo_root) {
  resolved <- attr(request, "resolved")
  production_orchestration_require("yaml")
  cfg <- yaml::read_yaml(resolved$configuration)
  input_path <- production_release_resolve_path(cfg$input$observations, dirname(resolved$configuration))
  configured_output <- production_release_resolve_path(cfg$project$output_root, dirname(resolved$configuration))
  requested_input <- normalizePath(resolved$observations, mustWork = TRUE)
  requested_output <- production_release_resolve_path(request$output$root, repo_root)
  checks <- c(
    observation_path = identical(input_path, requested_input),
    analysis_start = identical(as.character(cfg$temporal$start_epiweek), as.character(request$analysis$start_epiweek)),
    output_root = identical(configured_output, requested_output)
  )
  list(matches = all(checks), checks = as.list(checks), configured_observations = input_path,
       requested_observations = requested_input, configured_start_epiweek = as.character(cfg$temporal$start_epiweek),
       requested_start_epiweek = as.character(request$analysis$start_epiweek), configured_output_root = configured_output,
       requested_output_root = requested_output)
}

production_release_refresh_contract <- function(request, config_path, repo_root, run_root = NULL,
                                                allow_blocked_adoption_plan = FALSE) {
  mode <- production_release_validate_request(request)
  production_release_validate_request_inputs(request)
  resolved <- attr(request, "resolved")
  config_path <- normalizePath(config_path, mustWork = TRUE)
  if (!identical(config_path, resolved$configuration)) stop("--config does not match the configuration path recorded in the refresh request.", call. = FALSE)
  compatibility <- production_release_configuration_compatibility(request, repo_root)
  if (mode == "resume") {
    if (!compatibility$matches) stop("Resume request differs from the existing deployment configuration: ", paste(names(compatibility$checks)[!unlist(compatibility$checks)], collapse = ", "), call. = FALSE)
    manifest_path <- production_release_resolve_path(request$resume$manifest_path, repo_root)
    production_release_verify_file(manifest_path, request$resume$manifest_sha256, label = "resume run manifest")
    source_contract <- production_orchestration_read_manifest(manifest_path)
    if (!identical(as.character(source_contract$run_id), as.character(request$resume$run_id))) stop("Resume request run_id does not match the recorded run manifest.", call. = FALSE)
    if (!identical(as.character(source_contract$config$sha256), tolower(request$configuration$sha256)) ||
        !identical(as.character(source_contract$input$sha256), tolower(request$data$observations_sha256))) stop("Resume request configuration or observation identity differs from the existing run.", call. = FALSE)
    original_request <- source_contract$refresh_request$document
    if (is.null(original_request) || !identical(as.character(original_request$model$specification_id), as.character(request$model$specification_id)) ||
        !identical(as.character(original_request$model$formula_identity), as.character(request$model$formula_identity)) ||
        !identical(as.character(original_request$data$observations_sha256), as.character(request$data$observations_sha256))) {
      stop("Resume model or data identity is absent from or differs from the original request.", call. = FALSE)
    }
    if (!identical(as.character(source_contract$horizon$configured_start_epiweek), as.character(request$analysis$start_epiweek)) ||
        !identical(as.character(source_contract$horizon$resolved_final_complete_epiweek), as.character(request$analysis$requested_endpoint))) stop("Resume analysis window differs from the existing run.", call. = FALSE)
    source_contract$operation_mode <- "resume"
    source_contract$resume_request <- list(path = attr(request, "request_path"), sha256 = attr(request, "request_sha256"), document = production_release_request_document(request))
    source_contract
  } else {
    if (mode == "full" && !compatibility$matches) stop("Full refresh request differs from its execution configuration: ", paste(names(compatibility$checks)[!unlist(compatibility$checks)], collapse = ", "), call. = FALSE)
    if (mode == "adopt" && identical(as.character(request$configuration$role), "candidate_execution") && !compatibility$matches) stop("Adopt request differs from its candidate execution configuration.", call. = FALSE)
    if (mode == "adopt" && identical(as.character(request$configuration$role), "active_deployment") && isTRUE(request$operation$dispatch_authorized)) stop("An active deployment configuration may be used only for a no-dispatch adoption plan.", call. = FALSE)
    overrides <- list(observations = request$data$observations_path, start_epiweek = request$analysis$start_epiweek,
      end_epiweek = request$analysis$requested_endpoint, output_root = request$output$root)
    run_id <- if (mode == "adopt") paste0("adopt-", request$request_id) else request$request_id
    expected_run_root <- file.path(resolved$output_root, run_id)
    if (!is.null(run_root) && !identical(normalizePath(run_root, mustWork = FALSE), normalizePath(expected_run_root, mustWork = FALSE))) stop("--run-root may not override the versioned output location in a refresh request.", call. = FALSE)
    run_root <- expected_run_root
    contract <- production_orchestration_contract(config_path, repo_root, run_id = run_id, run_root = run_root, config_overrides = overrides)
    if (!identical(as.character(contract$horizon$resolved_final_complete_epiweek), as.character(request$analysis$requested_endpoint))) stop("Requested analysis endpoint does not match the last complete epiweek in the observation release.", call. = FALSE)
    if (dir.exists(contract$run_root) || file.exists(contract$run_root)) stop("Refresh run output already exists; historical outputs are never overwritten: ", contract$run_root, call. = FALSE)
    contract$operation_mode <- mode
    contract$configuration_compatibility <- compatibility
    contract$refresh_request <- list(path = attr(request, "request_path"), sha256 = attr(request, "request_sha256"),
                                     request_id = request$request_id, mode = mode, document = production_release_request_document(request))
    if (mode == "adopt") {
      adoption <- tryCatch(production_release_validate_adoption(request, repo_root, verify_files = TRUE), error = identity)
      if (inherits(adoption, "error")) {
        if (!isTRUE(allow_blocked_adoption_plan)) stop(adoption)
        declared <- tryCatch({
          inventory <- utils::read.csv(resolved$artifact_manifest, stringsAsFactors = FALSE, check.names = FALSE)
          if (!all(c("role", "path", "sha256", "bytes") %in% names(inventory))) stop("Artifact inventory lacks required columns.")
          rows <- lapply(seq_len(nrow(inventory)), function(i) list(
            path = production_release_resolve_path(inventory$path[[i]], repo_root),
            sha256 = as.character(inventory$sha256[[i]]), bytes = as.numeric(inventory$bytes[[i]]),
            identity_status = "NOT_ACCEPTED"))
          names(rows) <- as.character(inventory$role)
          rows
        }, error = function(error) list())
        contract$adoption_validation <- list(outcome = "BLOCKED", request_id = request$request_id,
          reason = conditionMessage(adoption), artifact_inputs = declared,
          deployment_configuration_compatibility = compatibility,
          limitation = "Declared artifacts are listed for review but are not accepted for reuse.")
        contract$artifact_inputs <- declared
        contract$execution_state <- "ADOPTION_VALIDATION_BLOCKED"
      } else {
        contract$adoption_validation <- adoption
        contract$artifact_inputs <- adoption$artifact_inputs
      }
      fit_provenance <- if (inherits(adoption, "error")) list() else adoption$fit_provenance
      contract$refresh_request$source_execution <- list(type = "independent_fit_adoption", fit_source_commit = request$adoption$fit_source_commit,
        report_generation_commit = request$adoption$report_generation_commit, source_fit_job_id = as.character(request$adoption$source_fit_job_id),
        metadata_runtime_commit = fit_provenance$metadata_runtime_commit %||% NA_character_,
        stage1_metadata_reference_recorded = fit_provenance$stage1_metadata_reference_recorded %||% FALSE,
        provenance_completeness = if (inherits(adoption, "error")) "blocked_validation" else if (isTRUE(fit_provenance$stage1_metadata_reference_recorded)) "complete" else "legacy_partial_stage1_resolved_by_config")
    }
    contract
  }
}

production_release_verify_file <- function(path, expected_sha256, expected_bytes = NULL, label = "artifact") {
  if (!file.exists(path) || dir.exists(path)) stop(label, " is missing or not a file: ", path, call. = FALSE)
  observed_bytes <- unname(file.info(path)$size)
  if (!is.null(expected_bytes) && is.finite(as.numeric(expected_bytes)) && observed_bytes != as.numeric(expected_bytes)) {
    stop(label, " byte count mismatch for ", path, ": expected ", expected_bytes, ", observed ", observed_bytes, call. = FALSE)
  }
  observed_sha <- production_release_sha256(path)
  if (!identical(tolower(observed_sha), tolower(as.character(expected_sha256)))) stop(label, " SHA-256 mismatch for ", path, call. = FALSE)
  list(path = normalizePath(path, mustWork = TRUE), bytes = observed_bytes, sha256 = observed_sha)
}

production_release_role <- function(inventory, role, required = TRUE) {
  hit <- which(inventory$role == role)
  if (length(hit) != 1L) {
    if (!required && !length(hit)) return(NULL)
    stop("Artifact inventory must contain exactly one '", role, "' row.", call. = FALSE)
  }
  inventory[hit, , drop = FALSE]
}

production_release_validate_audit <- function(inventory, role, allow_warnings = FALSE) {
  row <- production_release_role(inventory, role)
  audit <- utils::read.csv(row$resolved_path[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
  if (!"status" %in% names(audit)) stop("Qualification audit has no status column: ", role, call. = FALSE)
  status <- toupper(trimws(as.character(audit$status)))
  blocking <- if ("blocking" %in% names(audit)) {
    tolower(trimws(as.character(audit$blocking))) %in% c("true", "t", "1", "yes")
  } else rep(FALSE, length(status))
  accepted <- if (allow_warnings) c("PASS", "WARNING", "PASS_WITH_WARNINGS", "WARN") else "PASS"
  if (any(is.na(status) | !nzchar(status))) stop("Qualification audit contains an empty status: ", role, call. = FALSE)
  if (any(blocking & !status %in% "PASS") || any(!blocking & !status %in% accepted)) {
    bad <- unique(status[blocking & !status %in% "PASS" | !blocking & !status %in% accepted])
    stop("Qualification audit has unaccepted status in ", role, ": ", paste(bad, collapse = ", "), call. = FALSE)
  }
  list(path = row$resolved_path[[1L]], rows = nrow(audit), statuses = as.list(table(status)),
       warnings = sum(status %in% c("WARNING", "WARN", "PASS_WITH_WARNINGS")))
}

production_release_require_audit_checks <- function(inventory, role, required_checks) {
  row <- production_release_role(inventory, role)
  audit <- utils::read.csv(row$resolved_path[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
  if (!"check" %in% names(audit)) stop("Qualification audit has no check column: ", role, call. = FALSE)
  missing <- setdiff(required_checks, as.character(audit$check))
  if (length(missing)) stop("Qualification audit ", role, " is missing required checks: ", paste(missing, collapse = ", "), call. = FALSE)
  for (check in required_checks) {
    matches <- which(as.character(audit$check) == check)
    if (length(matches) != 1L) stop("Qualification audit ", role, " must contain exactly one ", check, " row.", call. = FALSE)
    if (!identical(toupper(trimws(as.character(audit$status[[matches]]))), "PASS")) stop("Required qualification check did not pass: ", role, "/", check, call. = FALSE)
  }
  invisible(audit)
}

production_release_validate_fit_metadata <- function(inventory, request) {
  metadata_row <- production_release_role(inventory, "fit_metadata")
  metadata_path <- metadata_row$resolved_path[[1L]]
  metadata_size <- unname(file.info(metadata_path)$size)
  if (!is.finite(metadata_size) || metadata_size > 16 * 1024^2) stop("Fit metadata exceeds the 16 MiB metadata-only safety limit.", call. = FALSE)
  metadata <- tryCatch(readRDS(metadata_path), error = function(error) {
    stop("Unable to read the small fit metadata RDS: ", conditionMessage(error), call. = FALSE)
  })
  if (!is.list(metadata)) stop("Fit metadata RDS is not a named list.", call. = FALSE)
  get_path <- function(value, label) {
    if (is.null(value) || length(value) != 1L || is.na(value) || !nzchar(as.character(value))) stop("Fit metadata is missing ", label, ".", call. = FALSE)
    normalizePath(as.character(value), mustWork = TRUE)
  }
  path_matches <- function(value, role, label) {
    expected <- production_release_role(inventory, role)$resolved_path[[1L]]
    observed <- get_path(value, label)
    if (!identical(observed, expected)) stop("Fit metadata ", label, " does not match the artifact inventory.", call. = FALSE)
    observed
  }
  optional_path_matches <- function(value, role, label) {
    if (is.null(value) || !length(value) || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) return(NA_character_)
    path_matches(value, role, label)
  }
  provenance <- metadata[["provenance"]]
  chain <- provenance[["chain"]]
  audit <- metadata[["audit"]]
  if (!identical(tolower(as.character(audit[["fit_status"]])), "success")) stop("Fit metadata does not record a successful Stage 3B fit.", call. = FALSE)
  stage1_metadata_path <- optional_path_matches(chain[["stage1"]][["artifact_path"]], "stage1", "Stage 1 input path")
  stage2_path <- path_matches(chain[["stage2"]][["artifact_path"]], "stage2", "Stage 2 input path")
  stage3a_path <- path_matches(chain[["stage3a"]][["artifact_path"]], "stage3a", "Stage 3A input path")
  fit_config_path <- path_matches(chain[["stage3b"]][["config_path"]], "config_fit", "Stage 3B config path")
  fit_path <- path_matches(chain[["stage3b"]][["output_fit"]], "fit", "fit output path")
  if (!identical(tolower(as.character(chain[["stage2"]][["artifact_sha256"]])),
                 tolower(production_release_role(inventory, "stage2")$sha256[[1L]]))) stop("Fit metadata Stage 2 checksum does not match the artifact inventory.", call. = FALSE)
  if (!identical(tolower(as.character(chain[["stage3a"]][["artifact_sha256"]])),
                 tolower(production_release_role(inventory, "stage3a")$sha256[[1L]]))) stop("Fit metadata Stage 3A checksum does not match the artifact inventory.", call. = FALSE)
  if (isTRUE(chain[["stage3a"]][["executed_fit"]])) stop("Stage 3A provenance indicates that fitting was executed during build.", call. = FALSE)
  if (!identical(tolower(as.character(audit[["stage2_artifact_sha256"]])),
                 tolower(production_release_role(inventory, "stage2")$sha256[[1L]])) ||
      !identical(tolower(as.character(audit[["stage3a_artifact_sha256"]])),
                 tolower(production_release_role(inventory, "stage3a")$sha256[[1L]]))) stop("Fit audit lineage checksums do not match the declared upstream artifacts.", call. = FALSE)
  stage1_audit_path <- optional_path_matches(audit[["stage1_artifact_path"]], "stage1", "fit audit Stage 1 input path")
  path_matches(audit[["stage2_artifact_path"]], "stage2", "fit audit Stage 2 input path")
  path_matches(audit[["stage3a_artifact_path"]], "stage3a", "fit audit Stage 3A input path")
  path_matches(audit[["stage3b_config_path"]], "config_fit", "fit audit Stage 3B config path")

  stdout_row <- production_release_role(inventory, "fit_stdout")
  stdout_lines <- readLines(stdout_row$resolved_path[[1L]], warn = FALSE)
  commit_line <- grep("^Repository:[[:space:]]+", stdout_lines, value = TRUE)
  job_line <- grep("^Original refresh Stage 3B job:[[:space:]]+", stdout_lines, value = TRUE)
  if (length(commit_line) != 1L || length(job_line) != 1L) stop("Fit Slurm stdout does not contain unique launch-time commit and job identities.", call. = FALSE)
  launch_commit <- sub("^Repository:[[:space:]]+", "", commit_line[[1L]])
  launch_job_id <- sub("^Original refresh Stage 3B job:[[:space:]]+", "", job_line[[1L]])
  if (!identical(launch_commit, as.character(request$adoption$fit_source_commit)) ||
      !identical(launch_job_id, as.character(request$adoption$source_fit_job_id))) stop("Fit Slurm launch identity does not match the adoption request.", call. = FALSE)

  audit_commit <- as.character(audit[["git_commit"]])
  runtime_commit <- as.character(provenance[["runtime"]][["git_commit"]])
  if (length(audit_commit) != 1L || length(runtime_commit) != 1L || is.na(audit_commit) || is.na(runtime_commit) ||
      !identical(audit_commit, runtime_commit)) stop("Fit metadata audit and runtime commits are missing or inconsistent.", call. = FALSE)
  if (!identical(runtime_commit, launch_commit)) {
    audit_start <- as.character(audit[["start_timestamp"]] %||% NA_character_)
    audit_end <- as.character(audit[["end_timestamp"]] %||% NA_character_)
    stop("Fit source commit mismatch: Slurm launch log records ", launch_commit,
         "; fit metadata records ", runtime_commit,
         " (audit window ", audit_start, " to ", audit_end,
         "). A later completion-time checkout cannot be substituted for launch-time source without an approved provenance resolution.", call. = FALSE)
  }
  list(launch_commit = launch_commit, metadata_runtime_commit = runtime_commit,
       source_fit_job_id = launch_job_id, metadata_path = metadata_path,
       stage1_metadata_path = stage1_metadata_path, stage1_audit_path = stage1_audit_path,
       stage1_metadata_reference_recorded = !is.na(stage1_metadata_path),
       stage1_link_source = if (is.na(stage1_metadata_path)) "verified Stage 2 configuration input and Stage 1 audit" else "fit metadata and configuration",
       stage2_path = stage2_path, stage3a_path = stage3a_path,
       fit_config_path = fit_config_path, fit_path = fit_path)
}

production_release_validate_adoption <- function(request, repo_root, verify_files = TRUE) {
  if (!identical(production_release_validate_request(request), "adopt")) stop("An adoption request is required.", call. = FALSE)
  req <- request
  resolved <- attr(req, "resolved")
  if (is.null(resolved)) stop("Adoption request was not loaded with a repository root.", call. = FALSE)
  request_sha <- attr(req, "request_sha256") %||% NA_character_
  if (!file.exists(resolved$configuration)) stop("Production configuration is not readable: ", resolved$configuration, call. = FALSE)
  if (!identical(production_release_sha256(resolved$configuration), tolower(req$configuration$sha256))) stop("Production configuration SHA does not match the refresh request.", call. = FALSE)
  if (!file.exists(resolved$configuration_identity) || !identical(production_release_sha256(resolved$configuration_identity), tolower(req$configuration$identity_sha256))) stop("Model configuration identity is missing or has a different SHA-256.", call. = FALSE)
  if (!file.exists(resolved$observations) || !identical(production_release_sha256(resolved$observations), tolower(req$data$observations_sha256))) stop("Observation release is missing or has a different SHA-256.", call. = FALSE)
  if (!file.exists(resolved$environmental_identity) || !identical(production_release_sha256(resolved$environmental_identity), tolower(req$environmental_data$identity_sha256))) stop("Environmental availability identity is missing or has a different SHA-256.", call. = FALSE)
  if (!file.exists(resolved$qualification_manifest) || !identical(production_release_sha256(resolved$qualification_manifest), tolower(req$qualification$evidence_manifest_sha256))) stop("Qualification manifest is missing or has a different SHA-256.", call. = FALSE)
  if (!file.exists(resolved$artifact_manifest) || !identical(production_release_sha256(resolved$artifact_manifest), tolower(req$adoption$artifact_manifest_sha256))) stop("Artifact inventory is missing or has a different SHA-256.", call. = FALSE)

  production_orchestration_require("yaml")
  qualification <- yaml::read_yaml(resolved$qualification_manifest)
  candidate <- qualification$candidate_model
  if (!identical(as.character(candidate$model_id), as.character(req$model$candidate_id))) stop("Candidate model identifier does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$proposed_production_id), as.character(req$model$production_id))) stop("Production candidate identifier does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$formula_identity), as.character(req$model$formula_identity))) stop("Formula identity does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$data_release$observations_sha256), tolower(req$data$observations_sha256))) stop("Observation identity does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$data_release$analysis_start_epiweek), as.character(req$analysis$start_epiweek)) ||
      !identical(as.character(candidate$data_release$analysis_end_epiweek), as.character(req$analysis$requested_endpoint))) stop("Requested analysis window does not match the qualified fit.", call. = FALSE)
  if (!identical(as.character(candidate$fit$artifact_sha256), tolower(req$adoption$fit_sha256)) ||
      !identical(as.character(candidate$fit$slurm_job_id), as.character(req$adoption$source_fit_job_id))) stop("Fit checksum or historical Slurm job identity does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$repository$fit_source_commit), as.character(req$adoption$fit_source_commit)) ||
      !identical(as.character(candidate$repository$report_generation_commit), as.character(req$adoption$report_generation_commit))) stop("Fit source or report-generation commit does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$data_release$release_id), as.character(req$data$release_id))) stop("Observation release identifier does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(qualification$decision_status), "W44_PRODUCTION_PROMOTION_BLOCKED")) stop("The W44 qualification evidence has an unexpected decision state.", call. = FALSE)

  inventory <- utils::read.csv(resolved$artifact_manifest, stringsAsFactors = FALSE, check.names = FALSE)
  required_roles <- c("config_identity", "config_stage2", "config_stage3a", "config_fit", "stage1", "stage1_audit", "stage2", "stage2_audit", "stage3a", "formula_audit", "fit", "fit_metadata", "fit_stdout", "fit_stderr", "fit_health", "extraction_audit", "validation_metrics", "validation_audit")
  if (!all(c("role", "path", "sha256", "bytes") %in% names(inventory)) || anyDuplicated(inventory$role) || !all(required_roles %in% inventory$role)) stop("Artifact inventory is incomplete or ambiguous.", call. = FALSE)
  inventory$resolved_path <- vapply(inventory$path, production_release_resolve_path, character(1L), repo_root = repo_root)
  for (role in required_roles) {
    item <- production_release_role(inventory, role)
    if (!production_release_is_sha256(item$sha256[[1L]]) || !is.finite(as.numeric(item$bytes[[1L]]))) stop("Artifact inventory has invalid identity for role ", role, call. = FALSE)
  }
  fit_row <- production_release_role(inventory, "fit")
  if (!identical(tolower(fit_row$sha256[[1L]]), tolower(req$adoption$fit_sha256))) stop("Fit SHA in the artifact inventory does not match the request.", call. = FALSE)
  stage_rows <- lapply(c("stage1", "stage2", "stage3a"), function(role) production_release_role(inventory, role))
  names(stage_rows) <- c("stage1", "stage2", "stage3a")
  json_stage_map <- list("1" = "stage1", "2" = "stage2", "3A" = "stage3a")
  for (json_stage in names(json_stage_map)) {
    role <- json_stage_map[[json_stage]]
    indexes <- which(vapply(candidate$stages, function(x) identical(as.character(x$stage), json_stage), logical(1L)))
    record <- if (length(indexes) == 1L) candidate$stages[[indexes[[1L]]]] else NULL
    row <- stage_rows[[role]]
    if (is.null(record) || !identical(tolower(as.character(record$sha256)), tolower(as.character(row$sha256[[1L]]))) ||
        !identical(as.character(record$path), as.character(row$path[[1L]]))) stop("Qualified Stage ", json_stage, " identity does not match the artifact inventory.", call. = FALSE)
  }
  if (!identical(as.character(candidate$fit$artifact_path), as.character(fit_row$path[[1L]])) ||
      !identical(as.numeric(candidate$fit$artifact_bytes), as.numeric(fit_row$bytes[[1L]]))) stop("Qualified fit path or size does not match the artifact inventory.", call. = FALSE)
  identity_row <- production_release_role(inventory, "config_identity")
  if (!identical(as.character(identity_row$path[[1L]]), as.character(req$configuration$identity_path)) ||
      !identical(tolower(as.character(identity_row$sha256[[1L]])), tolower(as.character(req$configuration$identity_sha256)))) stop("W44 configuration identity descriptor does not match the artifact inventory.", call. = FALSE)
  if (!identical(tolower(stage_rows$stage1$sha256[[1L]]), tolower(req$adoption$lineage$stage1_to_stage2_sha256)) ||
      !identical(tolower(stage_rows$stage2$sha256[[1L]]), tolower(req$adoption$lineage$stage2_to_stage3a_sha256)) ||
      !identical(tolower(stage_rows$stage3a$sha256[[1L]]), tolower(req$adoption$lineage$stage3a_to_fit_sha256))) stop("Declared direct stage lineage does not reconcile with artifact checksums.", call. = FALSE)
  config_path_for_role <- function(role) production_release_role(inventory, role)$resolved_path[[1L]]
  identity <- yaml::read_yaml(config_path_for_role("config_identity"))
  stage2_cfg <- yaml::read_yaml(config_path_for_role("config_stage2"))
  stage3a_cfg <- yaml::read_yaml(config_path_for_role("config_stage3a"))
  fit_cfg <- yaml::read_yaml(config_path_for_role("config_fit"))
  if (identical(as.character(req$covariate_registry$mode), "manifest_free_original") && !is.null(stage2_cfg$covariate_manifest)) stop("The requested original model identity conflicts with a configured covariate manifest.", call. = FALSE)
  source_root <- dirname(dirname(dirname(config_path_for_role("config_identity"))))
  resolve_source_config_path <- function(path) {
    resolved_path <- production_release_resolve_path(path, source_root)
    if (is.na(resolved_path) || !file.exists(resolved_path)) stop("Stage configuration lineage source is missing: ", path, call. = FALSE)
    normalizePath(resolved_path, mustWork = TRUE)
  }
  parent1 <- resolve_source_config_path(stage2_cfg$inputs$model_inputs)
  parent2 <- resolve_source_config_path(stage3a_cfg$inputs$joint_model_inputs)
  parent3 <- resolve_source_config_path(fit_cfg$inputs$stage3a_build)
  if (!identical(parent1, stage_rows$stage1$resolved_path[[1L]]) || !identical(parent2, stage_rows$stage2$resolved_path[[1L]]) ||
      !identical(parent3, production_release_role(inventory, "stage3a")$resolved_path[[1L]])) stop("Stage configuration inputs do not form the declared Stage 1 → Stage 2 → Stage 3A → Stage 3B chain.", call. = FALSE)
  if (!identical(as.character(identity$model$identifier), as.character(req$model$candidate_id)) ||
      !identical(as.character(identity$model$specification_revision), as.character(req$model$specification_id)) ||
      !identical(as.character(identity$model$frozen_specification_reference), as.character(qualification$candidate_model$formula_reference$path))) stop("Model specification identity does not match the immutable W44 run identity.", call. = FALSE)
  if (!identical(as.character(identity$source$observation_sha256), tolower(req$data$observations_sha256))) stop("Run identity observation checksum does not match the request.", call. = FALSE)
  inventory_verified <- list()
  if (verify_files) {
    for (i in seq_len(nrow(inventory))) {
      inventory_verified[[inventory$role[[i]]]] <- production_release_verify_file(
        inventory$resolved_path[[i]], inventory$sha256[[i]], inventory$bytes[[i]], inventory$role[[i]])
    }
  }
  supporting_records <- candidate$supporting_records
  supporting_checksums <- candidate$supporting_record_checksums
  if (!identical(tolower(as.character(supporting_checksums$artifact_manifest_sha256)), tolower(req$adoption$artifact_manifest_sha256))) stop("Qualification evidence points to a different artifact inventory checksum.", call. = FALSE)
  evidence_verified <- list()
  for (key in names(supporting_records)) {
    checksum_key <- paste0(key, "_sha256")
    if (is.null(supporting_checksums[[checksum_key]])) next
    evidence_path <- production_release_resolve_path(supporting_records[[key]], repo_root)
    evidence_verified[[key]] <- production_release_verify_file(evidence_path, supporting_checksums[[checksum_key]], label = paste0("qualification evidence ", key))
  }
  qualification_report <- evidence_verified$qualification_report
  if (is.null(qualification_report)) stop("Qualification evidence does not include a checksummed qualification report.", call. = FALSE)
  qualification_lines <- readLines(qualification_report$path, warn = FALSE)
  if (!any(grepl(as.character(req$qualification$status), qualification_lines, fixed = TRUE))) {
    stop("Requested scientific qualification status is not stated in the checksummed qualification report.", call. = FALSE)
  }

  audit_results <- list(
    stage1 = production_release_validate_audit(inventory, "stage1_audit"),
    fit_health = production_release_validate_audit(inventory, "fit_health"),
    formula = production_release_validate_audit(inventory, "formula_audit"),
    extraction = production_release_validate_audit(inventory, "extraction_audit", allow_warnings = TRUE),
    validation = production_release_validate_audit(inventory, "validation_audit", allow_warnings = TRUE)
  )
  production_release_require_audit_checks(inventory, "stage1_audit",
    c("reused_stage1_sha256", "approved_observation_checksum", "temporal_window", "original_predictor_schema"))
  production_release_require_audit_checks(inventory, "fit_health",
    c("fit_artifact_exists", "likelihood_families", "fit_completion_status", "fit_internal_ok"))
  production_release_require_audit_checks(inventory, "formula_audit",
    c("fixed_effect_names", "fixed_effect_order", "fixed_effect_count", "no_c1_only_terms", "manifest_free_original_formula", "joint_likelihoods", "fit_not_executed", "frozen_reference_formula_regeneration"))
  production_release_require_audit_checks(inventory, "extraction_audit",
    c("disjoint_exhaustive_indices", "predictor_layout", "tier_row_counts"))
  production_release_require_audit_checks(inventory, "validation_audit",
    c("stage2_holdout_counts", "holdout_rows_are_test_points", "holdout_response_finite"))
  formula_audit <- utils::read.csv(production_release_role(inventory, "formula_audit")$resolved_path[[1L]], stringsAsFactors = FALSE)
  fixed_effect_record <- formula_audit[formula_audit$check == "fixed_effect_count", , drop = FALSE]
  expected_fixed_effects <- as.integer(candidate$formula_reference$fixed_effect_count_including_intercepts)
  if (nrow(fixed_effect_record) != 1L || !identical(suppressWarnings(as.integer(fixed_effect_record$observed[[1L]])), expected_fixed_effects) ||
      !grepl(as.character(expected_fixed_effects), as.character(fixed_effect_record$expected[[1L]]), fixed = TRUE)) stop("Formula audit fixed-effect count does not match the qualified formula identity.", call. = FALSE)
  canonical_tests_path <- production_release_resolve_path(qualification$canonical_tests$summary_path, repo_root)
  canonical_test_summary <- production_release_verify_file(canonical_tests_path, qualification$canonical_tests$summary_sha256, label = "canonical test summary")
  canonical_tests <- utils::read.delim(canonical_tests_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"status" %in% names(canonical_tests) || any(toupper(canonical_tests$status) %in% c("FAIL", "SKIPPED"))) stop("Canonical qualification test summary contains a failure or skipped test.", call. = FALSE)
  count_status <- function(result, value) as.integer(result$statuses[[value]] %||% 0L)
  qualification_counts <- list(
    fit_health_pass = count_status(audit_results$fit_health, "PASS"),
    fit_health_fail = count_status(audit_results$fit_health, "FAIL"),
    extraction_pass = count_status(audit_results$extraction, "PASS"),
    extraction_fail = count_status(audit_results$extraction, "FAIL"),
    validation_pass = count_status(audit_results$validation, "PASS"),
    validation_warning = count_status(audit_results$validation, "WARNING") + count_status(audit_results$validation, "WARN"),
    validation_fail = count_status(audit_results$validation, "FAIL")
  )
  for (key in names(qualification_counts)) {
    if (!identical(as.integer(qualification_counts[[key]]), as.integer(candidate$qualification[[key]]))) {
      stop("Qualification count ", key, " does not match the supporting audit record.", call. = FALSE)
    }
  }
  if (count_status(audit_results$extraction, "FAIL") != 0L || count_status(audit_results$validation, "FAIL") != 0L ||
      count_status(audit_results$fit_health, "FAIL") != 0L) stop("A fit-health, extraction, or predictive-validation audit records a failure.", call. = FALSE)

  metadata_provenance <- production_release_validate_fit_metadata(inventory, req)
  fit_verified <- inventory_verified$fit %||% production_release_verify_file(fit_row$resolved_path[[1L]], req$adoption$fit_sha256, fit_row$bytes[[1L]], "fit")
  artifact_inputs <- list()
  for (role in inventory$role) {
    row <- production_release_role(inventory, role)
    artifact_inputs[[role]] <- list(path = row$resolved_path[[1L]], sha256 = tolower(row$sha256[[1L]]), bytes = as.numeric(row$bytes[[1L]]))
  }
  config_compatibility <- production_release_configuration_compatibility(req, repo_root)
  list(
    outcome = "PASS_WITH_WARNINGS", request_id = req$request_id, request_sha256 = request_sha,
    mode = "adopt", source_fit_job_id = as.character(req$adoption$source_fit_job_id),
    fit = fit_verified, artifact_inputs = artifact_inputs,
     imported_artifacts = inventory_verified, evidence = evidence_verified, canonical_test_summary = canonical_test_summary,
     audit_results = audit_results, fit_provenance = metadata_provenance,
    lineage = list(stage1 = stage_rows$stage1[1L, c("path", "sha256"), drop = FALSE], stage2 = stage_rows$stage2[1L, c("path", "sha256"), drop = FALSE], stage3a = stage_rows$stage3a[1L, c("path", "sha256"), drop = FALSE], fit = fit_row[1L, c("path", "sha256"), drop = FALSE]),
    qualification_status = as.character(req$qualification$status),
    configuration_role = as.character(req$configuration$role),
    deployment_configuration_compatibility = config_compatibility,
    limitations = c("The historical qualification record is accepted with limitations; post-fit products are not yet generated for the production release.",
      if (isTRUE(metadata_provenance$stage1_metadata_reference_recorded)) character() else "Legacy fit metadata omits the Stage 1 path; the edge is verified through the checksummed Stage 2 configuration and Stage 1 audit.")
  )
}

production_release_plan <- function(request, statuses = list()) {
  mode <- production_release_validate_request(request)
  if (mode == "full") stages <- c("prepare", "fit", "postfit") else if (mode == "resume") {
    first <- production_orchestration_select_resume_stage(statuses)
    stages <- if (is.null(first)) character() else c("prepare", "fit", "postfit")[match(first, c("prepare", "fit", "postfit")):3L]
  } else stages <- tolower(unlist(request$operation$requested_stages, use.names = FALSE))
  if (mode == "adopt" && any(stages %in% c("prepare", "fit"))) stop("Adoption execution plan contains a prohibited Prepare or Fit stage.", call. = FALSE)
  dependencies <- stats::setNames(rep("none", length(stages)), stages)
  if (mode == "full" && length(stages) == 3L) {
    dependencies[["fit"]] <- "afterok:<prepare-job-id>"
    dependencies[["postfit"]] <- "afterok:<fit-job-id>"
  } else if (mode == "resume" && length(stages) > 1L) {
    for (i in 2:length(stages)) dependencies[[stages[[i]]]] <- paste0("afterok:<", stages[[i - 1L]], "-job-id>")
  }
  plan <- list(
    schema_version = 1L, request_id = request$request_id, request_sha256 = attr(request, "request_sha256") %||% NA_character_,
    operation_mode = mode, stage_sequence = if (mode == "adopt") c("adoption_validation", stages) else stages,
    scheduler_stages = stages, dependencies = dependencies,
    dispatch_authorized = isTRUE(request$operation$dispatch_authorized),
    stages_submitted_by_dry_run = character(), created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  if (mode == "adopt") {
    plan$historical_fit_job_id <- as.character(request$adoption$source_fit_job_id)
    plan$historical_fit_is_scheduler_dependency <- FALSE
    plan$prohibited_stages <- c("prepare", "fit")
    plan$artifact_registry_target <- file.path(request$output$root, "model_registry", request$model$production_id)
    plan$artifact_copy_required <- identical(as.character(request$configuration$role), "active_deployment")
    plan$deployment_configuration_compatibility <- production_release_configuration_compatibility(request, attr(request, "repo_root") %||% getwd())
  }
  plan
}

production_release_assert_adoption_plan <- function(plan) {
  if (!identical(as.character(plan$operation_mode), "adopt")) stop("An adoption plan is required.", call. = FALSE)
  if (any(plan$scheduler_stages %in% c("prepare", "fit")) || any(plan$requested_scheduler_stages %in% c("prepare", "fit"))) stop("Adoption execution plan contains prohibited Prepare or Fit stages.", call. = FALSE)
  if (isTRUE(plan$historical_fit_is_scheduler_dependency) || any(grepl(as.character(plan$historical_fit_job_id), unlist(plan$dependencies, use.names = FALSE), fixed = TRUE))) {
    stop("Historical fit job ID must remain provenance only and may not be a scheduler dependency.", call. = FALSE)
  }
  if (length(plan$dependencies) && any(as.character(unlist(plan$dependencies, use.names = FALSE)) != "none")) stop("Adoption scheduler dependencies must be none.", call. = FALSE)
  invisible(TRUE)
}

production_release_validate_resume_artifacts <- function(contract, statuses) {
  accepted <- intersect(names(statuses), c("prepare", "fit", "postfit"))
  for (stage in accepted) {
    status <- statuses[[stage]]
    if (!toupper(as.character(status$status)) %in% c("PASS", "WARNING")) next
    if (is.null(status$output_artifact) || is.na(status$output_artifact) || is.null(status$output_sha) || !production_release_is_sha256(status$output_sha)) {
      stop("Accepted ", stage, " stage is missing its output artifact identity.", call. = FALSE)
    }
    production_release_verify_file(status$output_artifact, status$output_sha, label = paste0("accepted ", stage, " output"))
    expected_input <- switch(stage,
      prepare = contract$input$observations,
      fit = production_orchestration_artifact_path(contract, "stage3a"),
      postfit = production_orchestration_artifact_path(contract, "fit"))
    if (is.null(status$input_artifact) || is.na(status$input_artifact) || !identical(normalizePath(status$input_artifact, mustWork = TRUE), normalizePath(expected_input, mustWork = TRUE))) {
      stop("Accepted ", stage, " stage input path no longer matches the run contract.", call. = FALSE)
    }
    if (is.null(status$input_sha) || !production_release_is_sha256(status$input_sha)) stop("Accepted ", stage, " stage is missing its input checksum.", call. = FALSE)
    production_release_verify_file(expected_input, status$input_sha, label = paste0("accepted ", stage, " input"))
  }
  if ("prepare" %in% accepted) {
    dims <- contract$dynamic_dimensions
    if (is.null(dims$stage2_sha256) || is.null(dims$build_sha256)) stop("Accepted Prepare stage is missing Stage 2 or Stage 3A identity.", call. = FALSE)
    production_release_verify_file(production_orchestration_artifact_path(contract, "stage2"), dims$stage2_sha256, label = "accepted Stage 2")
    production_release_verify_file(production_orchestration_artifact_path(contract, "stage3a"), dims$build_sha256, label = "accepted Stage 3A")
  }
  list(status = "PASS", accepted_stages_rehashed = accepted)
}

production_release_write_plan <- function(plan, path) {
  production_release_atomic_yaml(plan, path, replace = FALSE)
  production_release_sha256(path)
}

production_release_copy_bundle <- function(artifact_paths, registry_dir) {
  production_orchestration_require("yaml")
  parent <- dirname(registry_dir)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  lock_path <- paste0(registry_dir, ".registry.lock")
  if (!dir.create(lock_path, showWarnings = FALSE)) stop("Registry lock exists; refusing concurrent registration: ", lock_path, call. = FALSE)
  on.exit(unlink(lock_path, recursive = TRUE), add = TRUE)
  if (dir.exists(registry_dir) || file.exists(registry_dir)) {
    existing_manifest <- file.path(registry_dir, "registry-manifest.yml")
    if (!file.exists(existing_manifest)) stop("Versioned model registry destination exists without a manifest; refusing to overwrite: ", registry_dir, call. = FALSE)
    existing <- yaml::read_yaml(existing_manifest)
    if (!identical(sort(names(existing$artifacts)), sort(names(artifact_paths)))) stop("Existing model registry has a different artifact set.", call. = FALSE)
    for (name in names(artifact_paths)) {
      record <- existing$artifacts[[name]]
      if (!identical(tolower(as.character(record$sha256)), tolower(as.character(artifact_paths[[name]]$sha256))) ||
          !identical(normalizePath(record$source_path, mustWork = FALSE), normalizePath(artifact_paths[[name]]$path, mustWork = FALSE))) stop("Existing model registry differs for artifact ", name, call. = FALSE)
      production_release_verify_file(record$path, record$sha256, artifact_paths[[name]]$bytes %||% NULL, paste0("registered ", name))
    }
    return(list(path = normalizePath(registry_dir, mustWork = TRUE), manifest = normalizePath(existing_manifest, mustWork = TRUE),
                manifest_sha256 = production_release_sha256(existing_manifest), artifacts = existing$artifacts, reused = TRUE))
  }
  staging <- tempfile(pattern = paste0(".", basename(registry_dir), ".staging-"), tmpdir = parent)
  if (!dir.create(staging, recursive = FALSE, showWarnings = FALSE)) stop("Unable to create registry staging directory.", call. = FALSE)
  committed <- FALSE
  on.exit(if (!committed && dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  copied <- list()
  for (name in names(artifact_paths)) {
    source <- artifact_paths[[name]]$path
    expected <- artifact_paths[[name]]$sha256
    destination <- file.path(staging, name, basename(source))
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(source, destination, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE)) stop("Failed to stage model artifact ", name, call. = FALSE)
    verified <- production_release_verify_file(destination, expected, label = paste0("staged ", name))
    copied[[name]] <- list(path = file.path(registry_dir, name, basename(source)), bytes = verified$bytes,
                           sha256 = verified$sha256, source_path = normalizePath(source, mustWork = TRUE))
  }
  manifest <- list(schema_version = 1L, created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), artifacts = copied)
  production_release_atomic_yaml(manifest, file.path(staging, "registry-manifest.yml"), replace = FALSE)
  if (dir.exists(registry_dir) || file.exists(registry_dir)) stop("Registry destination appeared during staging; refusing to overwrite.", call. = FALSE)
  if (!file.rename(staging, registry_dir)) stop("Atomic registry publication failed; the source artifacts remain unchanged.", call. = FALSE)
  committed <- TRUE
  manifest_path <- file.path(registry_dir, "registry-manifest.yml")
  list(path = normalizePath(registry_dir, mustWork = TRUE), manifest = normalizePath(manifest_path, mustWork = TRUE),
       manifest_sha256 = production_release_sha256(manifest_path), artifacts = copied, reused = FALSE)
}

production_release_register_adoption <- function(contract, request, repo_root) {
  if (!identical(contract$operation_mode, "adopt")) stop("Only adopted fits may be registered with this function.", call. = FALSE)
  if (!isTRUE(request$operation$dispatch_authorized)) stop("This request does not authorize Post-fit dispatch or artifact registration.", call. = FALSE)
  if (!identical(as.character(request$configuration$role), "candidate_execution")) stop("An active-deployment configuration cannot authorize adoption dispatch.", call. = FALSE)
  source_artifacts <- contract$adoption_validation$artifact_inputs
  source_bundle <- source_artifacts
  resolved <- attr(request, "resolved")
  source_bundle$environmental_identity <- list(path = resolved$environmental_identity,
    sha256 = request$environmental_data$identity_sha256, bytes = file.info(resolved$environmental_identity)$size)
  source_bundle$qualification_manifest <- list(path = resolved$qualification_manifest,
    sha256 = request$qualification$evidence_manifest_sha256, bytes = file.info(resolved$qualification_manifest)$size)
  if (identical(as.character(request$covariate_registry$mode), "manifest")) {
    source_bundle$covariate_registry <- list(path = resolved$covariate_registry,
      sha256 = request$covariate_registry$sha256, bytes = file.info(resolved$covariate_registry)$size)
  }
  registry_root <- file.path(request$output$root, "model_registry", request$model$production_id)
  registered <- production_release_copy_bundle(source_bundle, registry_root)
  contract$artifact_storage <- list(policy = "versioned_copy_required_for_development_source", registry_path = registered$path,
                                    registry_manifest = registered$manifest, reused_existing_registry = isTRUE(registered$reused),
                                    registry_manifest_sha256 = registered$manifest_sha256 %||% production_release_sha256(registered$manifest),
                                    source = source_artifacts, registered = registered$artifacts)
  contract$artifact_inputs <- registered$artifacts
  list(contract = contract, registry = registered)
}

production_release_write_model_manifest <- function(contract) {
  request_record <- contract$refresh_request
  if (is.null(request_record$document)) return(NULL)
  request <- request_record$document
  fit_path <- production_orchestration_artifact_path(contract, "fit")
  stage1_path <- production_orchestration_artifact_path(contract, "stage1")
  stage2_path <- production_orchestration_artifact_path(contract, "stage2")
  stage3a_path <- production_orchestration_artifact_path(contract, "stage3a")
  product_path <- production_gate_find_file(contract$paths$reporting, "^manifest.*\\.csv$")
  if (is.na(product_path) || !file.exists(product_path)) stop("Post-fit product manifest is missing; cannot create a release manifest.", call. = FALSE)
  run_manifest <- file.path(contract$paths$metadata, "run_manifest.yml")
  if (!file.exists(run_manifest)) stop("Run manifest is missing; cannot create a release manifest.", call. = FALSE)
  if (identical(contract$operation_mode, "adopt")) {
    if (!is.list(contract$adoption_validation) || !toupper(as.character(contract$adoption_validation$outcome)) %in% c("PASS", "PASS_WITH_WARNINGS")) stop("Adoption validation did not pass; cannot write a release manifest.", call. = FALSE)
    if (!toupper(as.character(contract$postfit_gate_status)) %in% c("PASS", "PASS_WITH_WARNINGS")) stop("Post-fit gate did not pass; cannot write an adopted model release manifest.", call. = FALSE)
    gate_status <- list(prepare = "NOT_EXECUTED_BY_THIS_RUN", fit = "NOT_EXECUTED_BY_THIS_RUN",
                        adoption = contract$adoption_validation$outcome, postfit = contract$postfit_gate_status)
  } else {
    gate_status <- list(prepare = contract$prepare_gate_status, fit = contract$fit_gate_status, postfit = contract$postfit_gate_status)
    if (any(!vapply(gate_status, function(x) !is.null(x) && toupper(as.character(x)) %in% c("PASS", "PASS_WITH_WARNINGS"), logical(1L)))) stop("All three production validation gates must pass before a release manifest is written.", call. = FALSE)
  }
  deployment <- request$configuration
  environmental_release <- request$environmental_data
  identity_path <- production_release_resolve_path(deployment$identity_path, contract$repository$root)
  environmental_identity_path <- production_release_resolve_path(environmental_release$identity_path, contract$repository$root)
  qualification_path <- production_release_resolve_path(request$qualification$evidence_manifest, contract$repository$root)
  if (identical(contract$operation_mode, "adopt")) {
    registered <- contract$artifact_inputs
    identity_path <- registered$config_identity$path %||% identity_path
    environmental_identity_path <- registered$environmental_identity$path %||% environmental_identity_path
    qualification_path <- registered$qualification_manifest$path %||% qualification_path
    if (identical(as.character(covariate_registry$mode), "manifest")) covariate_registry$path <- registered$covariate_registry$path
  }
  environmental_release$identity_path <- environmental_identity_path
  covariate_registry <- request$covariate_registry
  if (!is.null(covariate_registry$path)) covariate_registry$path <- production_release_resolve_path(covariate_registry$path, contract$repository$root)
  manifest <- list(
    schema_version = 1L, status = "READY_FOR_REVIEW", created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    request_id = request_record$request_id, request_sha256 = request_record$sha256,
    request_archive = contract$refresh_request_archive %||% list(path = request_record$path, sha256 = request_record$sha256),
    candidate_id = request$model$candidate_id, production_id = request$model$production_id,
    specification_id = request$model$specification_id, formula_identity = request$model$formula_identity,
    configuration = list(role = deployment$role, path = contract$config$path, sha256 = contract$config$sha256,
                         identity_id = deployment$identity_id,
                         identity_path = identity_path,
                         identity_sha256 = deployment$identity_sha256),
    data = list(release_id = request$data$release_id, availability_endpoint = request$data$availability_endpoint,
                observations_path = contract$input$observations, observations_sha256 = contract$input$sha256,
                start_epiweek = contract$horizon$configured_start_epiweek,
                end_epiweek = contract$horizon$resolved_final_complete_epiweek),
    environmental_data = environmental_release, covariate_registry = covariate_registry,
    gates = gate_status, qualification = list(scientific_status = request$qualification$status,
      required_gates = request$qualification$required_gates,
      evidence_manifest = qualification_path,
      evidence_manifest_sha256 = request$qualification$evidence_manifest_sha256),
    reporting = request$reporting,
    upstream_artifacts = list(
      stage1 = list(path = stage1_path, bytes = unname(file.info(stage1_path)$size), sha256 = production_release_sha256(stage1_path)),
      stage2 = list(path = stage2_path, bytes = unname(file.info(stage2_path)$size), sha256 = production_release_sha256(stage2_path)),
      stage3a = list(path = stage3a_path, bytes = unname(file.info(stage3a_path)$size), sha256 = production_release_sha256(stage3a_path))),
    fit = list(path = fit_path, bytes = unname(file.info(fit_path)$size), sha256 = production_release_sha256(fit_path)),
    run_manifest = list(path = normalizePath(run_manifest, mustWork = TRUE), sha256 = production_release_sha256(run_manifest)),
    products = list(manifest_path = normalizePath(product_path, mustWork = TRUE), manifest_sha256 = production_release_sha256(product_path)),
    source_execution = contract$refresh_request$source_execution %||% list(type = "pipeline_run", code_commit = contract$repository$git_commit),
    output_root = contract$run_root, artifact_storage = contract$artifact_storage %||% list(policy = "run-scoped production output")
  )
  path <- file.path(contract$run_root, "model-release.yml")
  production_release_atomic_yaml(manifest, path, replace = FALSE)
  list(path = normalizePath(path, mustWork = TRUE), sha256 = production_release_sha256(path))
}

production_release_atomic_yaml <- function(object, path, replace = TRUE) {
  production_orchestration_require("yaml")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!replace && (file.exists(path) || dir.exists(path))) stop("Refusing to overwrite immutable file: ", path, call. = FALSE)
  temp <- tempfile(pattern = paste0(".", basename(path), ".tmp-"), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  yaml::write_yaml(object, temp)
  if (!file.exists(temp) || file.info(temp)$size <= 0) stop("Temporary YAML write failed: ", temp, call. = FALSE)
  if (!file.rename(temp, path)) stop("Atomic rename failed for ", path, "; the previous file remains unchanged.", call. = FALSE)
  normalizePath(path, mustWork = TRUE)
}

production_release_validate_product_manifest <- function(path, reporting) {
  products <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required_columns <- c("logical_product_name", "path", "checksum_sha256", "bytes")
  if (!all(required_columns %in% names(products)) || !nrow(products)) stop("Post-fit product manifest is empty or lacks artifact identities.", call. = FALSE)
  if (anyDuplicated(products$path) || any(!vapply(products$checksum_sha256, production_release_is_sha256, logical(1L))) ||
      any(!is.finite(as.numeric(products$bytes)))) stop("Post-fit product manifest contains duplicate or invalid artifact identities.", call. = FALSE)
  root <- normalizePath(dirname(dirname(path)), mustWork = TRUE)
  verified <- vector("list", nrow(products))
  for (i in seq_len(nrow(products))) {
    artifact_path <- production_release_resolve_path(products$path[[i]], root)
    if (!startsWith(artifact_path, paste0(root, .Platform$file.sep))) stop("Post-fit product path escapes its versioned output directory: ", artifact_path, call. = FALSE)
    verified[[i]] <- production_release_verify_file(artifact_path, products$checksum_sha256[[i]], products$bytes[[i]], "post-fit product")
  }
  required <- as.character(unlist(reporting$required_products, use.names = FALSE))
  missing <- setdiff(required, unique(as.character(products$logical_product_name)))
  if (length(missing)) stop("Post-fit manifest is missing required products: ", paste(missing, collapse = ", "), call. = FALSE)
  masked <- products[products$logical_product_name == "structural_potential_abundance_temp_masked", , drop = FALSE]
  threshold <- as.numeric(reporting$temperature_mask_threshold_c)
  if (!nrow(masked) || !"temperature_variable" %in% names(masked) || !"temperature_threshold_celsius" %in% names(masked) ||
      any(as.character(masked$temperature_variable) != "mintemp") || any(as.numeric(masked$temperature_threshold_celsius) != threshold)) {
    stop("Post-fit manifest does not retain the requested mintemp temperature-mask threshold.", call. = FALSE)
  }
  rpi <- products[products$logical_product_name == "rpi", , drop = FALSE]
  if (!nrow(rpi) || !"rpi_threshold_calibration" %in% names(rpi) ||
      any(!grepl("same-week observation-paired dynamic threshold", as.character(rpi$rpi_threshold_calibration), fixed = TRUE))) {
    stop("Post-fit manifest does not retain same-week observation-paired RPI calibration.", call. = FALSE)
  }
  list(root = root, product_count = nrow(products), required_products = required, verified_artifacts = verified)
}

production_release_read_model_manifest <- function(path, expected_sha256 = NULL, verify_artifact = TRUE) {
  production_orchestration_require("yaml")
  if (!file.exists(path)) stop("Model release manifest does not exist: ", path, call. = FALSE)
  manifest_sha <- production_release_sha256(path)
  if (!is.null(expected_sha256) && !identical(tolower(manifest_sha), tolower(as.character(expected_sha256)))) stop("Model release manifest SHA-256 mismatch.", call. = FALSE)
  manifest <- yaml::read_yaml(path)
  if (!identical(as.integer(manifest$schema_version), 1L)) stop("Unsupported model release manifest schema.", call. = FALSE)
  if (!identical(as.character(manifest$status), "READY_FOR_REVIEW")) stop("Model release manifest is not marked READY_FOR_REVIEW.", call. = FALSE)
  if (is.null(manifest$production_id) || is.null(manifest$fit$path) || !production_release_is_sha256(manifest$fit$sha256)) stop("Model release manifest is missing required identity fields.", call. = FALSE)
  if (!identical(as.character(manifest$configuration$role), "candidate_execution") || is.null(manifest$configuration$path) ||
      !production_release_is_sha256(manifest$configuration$sha256)) stop("Model release does not identify an approved candidate execution configuration.", call. = FALSE)
  production_release_verify_file(manifest$configuration$path, manifest$configuration$sha256, label = "release configuration")
  if (is.null(manifest$configuration$identity_path) || !production_release_is_sha256(manifest$configuration$identity_sha256)) stop("Model release is missing its configuration identity checksum.", call. = FALSE)
  production_release_verify_file(manifest$configuration$identity_path, manifest$configuration$identity_sha256, label = "model configuration identity")
  accepted <- c("PASS", "PASS_WITH_WARNINGS")
  adopted <- toupper(as.character(manifest$gates$adoption %||% "")) %in% accepted
  if (adopted) {
    if (!toupper(as.character(manifest$gates$prepare)) %in% "NOT_EXECUTED_BY_THIS_RUN" ||
        !toupper(as.character(manifest$gates$fit)) %in% "NOT_EXECUTED_BY_THIS_RUN" ||
        !toupper(as.character(manifest$gates$postfit)) %in% accepted) stop("Adopted model release lacks explicit upstream import state or a passing Post-fit gate.", call. = FALSE)
  } else if (!toupper(as.character(manifest$gates$prepare)) %in% accepted ||
             !toupper(as.character(manifest$gates$fit)) %in% accepted ||
             !toupper(as.character(manifest$gates$postfit)) %in% accepted) stop("Model release does not have accepted Prepare, Fit, and Post-fit gates.", call. = FALSE)
  if (is.null(manifest$run_manifest$path) || !production_release_is_sha256(manifest$run_manifest$sha256) ||
      is.null(manifest$products$manifest_path) || !production_release_is_sha256(manifest$products$manifest_sha256)) stop("Model release is missing its run or product manifest identity.", call. = FALSE)
  scientific_status <- toupper(as.character(manifest$qualification$scientific_status %||% ""))
  if (!grepl("QUALIFIED|APPROVED", scientific_status)) stop("Scientific acceptance is not complete; model release cannot be activated.", call. = FALSE)
  evidence_path <- manifest$qualification$evidence_manifest
  evidence_sha <- manifest$qualification$evidence_manifest_sha256
  if (is.null(evidence_path) || !production_release_is_sha256(evidence_sha)) stop("Model release lacks qualification evidence identity.", call. = FALSE)
  production_release_verify_file(evidence_path, evidence_sha, label = "qualification evidence manifest")
  request_archive <- manifest$request_archive
  if (is.null(request_archive$path) || !production_release_is_sha256(request_archive$sha256)) stop("Model release is missing its archived refresh request identity.", call. = FALSE)
  production_release_verify_file(request_archive$path, request_archive$sha256, label = "archived refresh request")
  if (is.null(manifest$data$observations_path) || !production_release_is_sha256(manifest$data$observations_sha256)) stop("Model release is missing its observation source identity.", call. = FALSE)
  production_release_verify_file(manifest$data$observations_path, manifest$data$observations_sha256, label = "release observation source")
  if (is.null(manifest$environmental_data$identity_path) || !production_release_is_sha256(manifest$environmental_data$identity_sha256)) stop("Model release is missing its environmental availability identity.", call. = FALSE)
  production_release_verify_file(manifest$environmental_data$identity_path, manifest$environmental_data$identity_sha256, label = "environmental availability identity")
  if (identical(as.character(manifest$covariate_registry$mode), "manifest")) {
    if (is.null(manifest$covariate_registry$path) || !production_release_is_sha256(manifest$covariate_registry$sha256)) stop("Model release is missing its versioned covariate registry identity.", call. = FALSE)
    production_release_verify_file(manifest$covariate_registry$path, manifest$covariate_registry$sha256, label = "covariate registry")
  } else if (!identical(as.character(manifest$covariate_registry$mode), "manifest_free_original") ||
             !is.null(manifest$covariate_registry$path) || !is.null(manifest$covariate_registry$sha256)) {
    stop("Model release has an unsupported or inconsistent covariate registry mode.", call. = FALSE)
  }
  if (verify_artifact) production_release_verify_file(manifest$fit$path, manifest$fit$sha256, manifest$fit$bytes, "release fit")
  for (stage in c("stage1", "stage2", "stage3a")) {
    upstream <- manifest$upstream_artifacts[[stage]]
    if (is.null(upstream$path) || !production_release_is_sha256(upstream$sha256)) stop("Model release is missing its ", stage, " artifact identity.", call. = FALSE)
    if (verify_artifact) production_release_verify_file(upstream$path, upstream$sha256, upstream$bytes, paste0("release ", stage))
  }
  if (!file.exists(manifest$run_manifest$path) || !identical(production_release_sha256(manifest$run_manifest$path), tolower(manifest$run_manifest$sha256))) stop("Run manifest is missing or has a different SHA-256.", call. = FALSE)
  if (!file.exists(manifest$products$manifest_path) || !identical(production_release_sha256(manifest$products$manifest_path), tolower(manifest$products$manifest_sha256))) stop("Post-fit product manifest is missing or has a different SHA-256.", call. = FALSE)
  production_release_validate_product_manifest(manifest$products$manifest_path, manifest$reporting)
  list(manifest = manifest, sha256 = manifest_sha)
}

production_release_active_state <- function(path) {
  production_orchestration_require("yaml")
  if (!file.exists(path)) stop("Active-release pointer does not exist: ", path, call. = FALSE)
  state <- yaml::read_yaml(path)
  if (!identical(as.integer(state$schema_version), 1L) || is.null(state$generation) || is.null(state$production_id) || is.null(state$manifest_path) ||
      !production_release_is_sha256(state$manifest_sha256) || is.null(state$configuration_path) || !production_release_is_sha256(state$configuration_sha256)) {
    stop("Active-release pointer has an invalid schema or identity.", call. = FALSE)
  }
  state
}

production_release_verify_active <- function(active_state_path, verify_artifact = TRUE) {
  state <- production_release_active_state(active_state_path)
  production_release_verify_file(state$configuration_path, state$configuration_sha256, label = "active release configuration")
  model_release <- production_release_read_model_manifest(state$manifest_path, state$manifest_sha256, verify_artifact)
  if (!identical(as.character(model_release$manifest$production_id), as.character(state$production_id))) stop("Active pointer and release manifest production IDs differ.", call. = FALSE)
  if (!identical(normalizePath(state$configuration_path, mustWork = TRUE), normalizePath(model_release$manifest$configuration$path, mustWork = TRUE)) ||
      !identical(tolower(as.character(state$configuration_sha256)), tolower(as.character(model_release$manifest$configuration$sha256)))) stop("Active pointer and release configuration identities differ.", call. = FALSE)
  list(status = "PASS", generation = as.integer(state$generation), production_id = state$production_id,
       candidate_id = model_release$manifest$candidate_id, formula_identity = model_release$manifest$formula_identity,
       artifact_path = model_release$manifest$fit$path, artifact_sha256 = model_release$manifest$fit$sha256,
       observed_artifact_sha256 = if (verify_artifact) production_release_sha256(model_release$manifest$fit$path) else NA_character_,
       manifest_path = state$manifest_path, manifest_sha256 = state$manifest_sha256)
}

production_release_lock <- function(active_state_path) {
  lock_path <- paste0(active_state_path, ".activation.lock")
  if (!dir.create(lock_path, showWarnings = FALSE)) stop("Activation lock exists; refusing concurrent update: ", lock_path, call. = FALSE)
  lock_path
}

production_release_activate <- function(active_state_path, model_manifest_path, expected_generation,
                                        expected_state_sha256, event_root) {
  lock <- production_release_lock(active_state_path)
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  old <- production_release_active_state(active_state_path)
  old_sha <- production_release_sha256(active_state_path)
  if (as.integer(old$generation) != as.integer(expected_generation) || !identical(tolower(old_sha), tolower(expected_state_sha256))) stop("Active release changed since review; compare-and-swap failed.", call. = FALSE)
  validated <- production_release_read_model_manifest(model_manifest_path, verify_artifact = TRUE)
  if (identical(as.character(old$production_id), as.character(validated$manifest$production_id))) stop("Candidate release is already active.", call. = FALSE)
  event_id <- paste0("activate-", as.integer(Sys.time()), "-", substr(validated$sha256, 1L, 12L))
  event_path <- file.path(event_root, paste0(event_id, ".yml"))
  if (file.exists(event_path)) stop("Activation event already exists; refusing to overwrite history.", call. = FALSE)
  next_state <- list(schema_version = 1L, generation = as.integer(old$generation) + 1L,
                     production_id = validated$manifest$production_id,
                     candidate_id = validated$manifest$candidate_id,
                     manifest_path = normalizePath(model_manifest_path, mustWork = TRUE),
                     manifest_sha256 = validated$sha256,
                     configuration_path = validated$manifest$configuration$path,
                     configuration_sha256 = tolower(validated$manifest$configuration$sha256),
                     activated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                     event_id = event_id)
  production_release_atomic_yaml(next_state, active_state_path, replace = TRUE)
  verified <- tryCatch(production_release_verify_active(active_state_path, verify_artifact = TRUE), error = identity)
  if (inherits(verified, "error")) {
    production_release_atomic_yaml(old, active_state_path, replace = TRUE)
    production_release_atomic_yaml(list(event_id = event_id, action = "ACTIVATION_FAILED_ROLLED_BACK", previous_state_sha256 = old_sha,
      requested_manifest_sha256 = validated$sha256, error = conditionMessage(verified), created_at_utc = next_state$activated_at_utc), event_path, replace = FALSE)
    stop("Activation verification failed; prior active release was restored: ", conditionMessage(verified), call. = FALSE)
  }
  event <- list(event_id = event_id, action = "ACTIVATED", previous_state = old, previous_state_sha256 = old_sha,
                active_state = next_state, active_manifest_sha256 = validated$sha256,
                created_at_utc = next_state$activated_at_utc, verifier_status = verified$status)
  event_result <- tryCatch(production_release_atomic_yaml(event, event_path, replace = FALSE), error = identity)
  if (inherits(event_result, "error")) {
    production_release_atomic_yaml(old, active_state_path, replace = TRUE)
    stop("Activation event could not be written; the previous active release was restored: ", conditionMessage(event_result), call. = FALSE)
  }
  verified$event_path <- normalizePath(event_path, mustWork = TRUE)
  verified
}

production_release_rollback <- function(active_state_path, activation_event_path, expected_generation,
                                        expected_state_sha256, event_root) {
  lock <- production_release_lock(active_state_path)
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  current <- production_release_active_state(active_state_path)
  current_sha <- production_release_sha256(active_state_path)
  if (as.integer(current$generation) != as.integer(expected_generation) || !identical(tolower(current_sha), tolower(expected_state_sha256))) stop("Active release changed since review; rollback compare-and-swap failed.", call. = FALSE)
  if (!file.exists(activation_event_path)) stop("Activation event does not exist: ", activation_event_path, call. = FALSE)
  activation <- yaml::read_yaml(activation_event_path)
  if (!identical(as.character(activation$action), "ACTIVATED") || !identical(as.character(current$event_id), as.character(activation$event_id))) stop("Rollback event is not the event that activated the current release.", call. = FALSE)
  previous <- activation$previous_state
  if (is.null(previous$production_id)) stop("Activation event does not record a previous release.", call. = FALSE)
  production_release_read_model_manifest(previous$manifest_path, previous$manifest_sha256, verify_artifact = TRUE)
  event_id <- paste0("rollback-", as.integer(Sys.time()), "-", substr(current_sha, 1L, 12L))
  event_path <- file.path(event_root, paste0(event_id, ".yml"))
  if (file.exists(event_path)) stop("Rollback event already exists; refusing to overwrite history.", call. = FALSE)
  restored <- previous
  restored$generation <- as.integer(current$generation) + 1L
  restored$rolled_back_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  restored$event_id <- event_id
  production_release_atomic_yaml(restored, active_state_path, replace = TRUE)
  verified <- tryCatch(production_release_verify_active(active_state_path, verify_artifact = TRUE), error = identity)
  if (inherits(verified, "error")) {
    production_release_atomic_yaml(current, active_state_path, replace = TRUE)
    production_release_atomic_yaml(list(event_id = event_id, action = "ROLLBACK_FAILED_RESTORED_CURRENT", current_state_sha256 = current_sha,
      error = conditionMessage(verified), created_at_utc = restored$rolled_back_at_utc), event_path, replace = FALSE)
    stop("Rollback verification failed; the release active before rollback was restored: ", conditionMessage(verified), call. = FALSE)
  }
  event <- list(event_id = event_id, action = "ROLLED_BACK", rollback_of_event_id = activation$event_id,
                previous_state = current, restored_state = restored, current_state_sha256 = current_sha,
                created_at_utc = restored$rolled_back_at_utc, verifier_status = verified$status)
  event_result <- tryCatch(production_release_atomic_yaml(event, event_path, replace = FALSE), error = identity)
  if (inherits(event_result, "error")) {
    production_release_atomic_yaml(current, active_state_path, replace = TRUE)
    stop("Rollback event could not be written; the release active before rollback was restored: ", conditionMessage(event_result), call. = FALSE)
  }
  verified$event_path <- normalizePath(event_path, mustWork = TRUE)
  verified
}

production_release_reconcile_deployment <- function(config_path, deployment_manifest_path, repo_root) {
  production_orchestration_require("yaml")
  if (!file.exists(config_path) || !file.exists(deployment_manifest_path)) stop("Configuration or deployment manifest is missing.", call. = FALSE)
  config_sha <- production_release_sha256(config_path)
  config <- yaml::read_yaml(config_path)
  manifest <- yaml::read_yaml(deployment_manifest_path)
  commit <- production_orchestration_git_commit(repo_root)
  recorded_commit <- as.character(manifest$canonical_commit %||% manifest$commit %||% NA_character_)
  recorded_config_sha <- as.character(manifest$production_config_sha256 %||% NA_character_)
  first_value <- function(...) {
    values <- list(...)
    for (value in values) if (!is.null(value) && length(value) == 1L && !is.na(value) && nzchar(as.character(value))) return(as.character(value))
    NA_character_
  }
  config_observation_path <- if (is.null(config$input$observations)) NA_character_ else production_release_resolve_path(config$input$observations, dirname(normalizePath(config_path, mustWork = TRUE)))
  observed_observation_sha <- if (!is.na(config_observation_path) && file.exists(config_observation_path)) production_release_sha256(config_observation_path) else NA_character_
  recorded_observation_sha <- first_value(manifest$observations_sha256, manifest$approved_observation_sha256,
    manifest$data$observations_sha256, manifest$observation_release$sha256)
  actual_model_id <- first_value(config$model$identifier, config$model$id, config$active_model$identifier, config$active_model_id, config$model_id)
  recorded_model_id <- first_value(manifest$model_identifier, manifest$model_id, manifest$active_model$identifier)
  actual_specification_id <- first_value(config$model$specification_id, config$active_model$specification_id, config$specification_id)
  recorded_specification_id <- first_value(manifest$model_specification_id, manifest$specification_id, manifest$active_model$specification_id)
  actual_start <- first_value(config$temporal$start_epiweek)
  actual_endpoint <- first_value(config$temporal$end_epiweek, config$temporal$requested_endpoint, config$temporal$end_rule)
  recorded_start <- first_value(manifest$analysis_start_epiweek, manifest$analysis$start_epiweek)
  recorded_endpoint <- first_value(manifest$analysis_endpoint, manifest$analysis_end_epiweek, manifest$analysis$requested_endpoint)
  actual_output_root <- if (is.null(config$project$output_root)) NA_character_ else production_release_resolve_path(config$project$output_root, dirname(normalizePath(config_path, mustWork = TRUE)))
  recorded_output_root <- first_value(manifest$output_root, manifest$production_output_root)
  list(
    repository_commit = commit, recorded_repository_commit = recorded_commit,
    production_config_path = normalizePath(config_path, mustWork = TRUE), production_config_sha256 = config_sha,
    recorded_production_config_sha256 = recorded_config_sha,
    repository_matches = !is.na(recorded_commit) && identical(commit, recorded_commit),
    configuration_matches = !is.na(recorded_config_sha) && identical(tolower(config_sha), tolower(recorded_config_sha)),
    active_model_identifier = actual_model_id, recorded_model_identifier = recorded_model_id,
    active_model_specification_id = actual_specification_id, recorded_model_specification_id = recorded_specification_id,
    active_observation_path = config_observation_path, active_observation_sha256 = observed_observation_sha,
    recorded_observation_sha256 = recorded_observation_sha,
    active_analysis_start_epiweek = actual_start, recorded_analysis_start_epiweek = recorded_start,
    active_analysis_endpoint_or_rule = actual_endpoint, recorded_analysis_endpoint = recorded_endpoint,
    active_output_root = actual_output_root, recorded_output_root = recorded_output_root,
    observation_identity_matches = !is.na(recorded_observation_sha) && !is.na(observed_observation_sha) && identical(tolower(recorded_observation_sha), tolower(observed_observation_sha)),
    model_identity_declared = !is.na(actual_model_id) && !is.na(actual_specification_id),
    deployment_manifest_path = normalizePath(deployment_manifest_path, mustWork = TRUE),
    deployment_manifest_sha256 = production_release_sha256(deployment_manifest_path),
    overall_status = if (!is.na(recorded_commit) && identical(commit, recorded_commit) && !is.na(recorded_config_sha) && identical(tolower(config_sha), tolower(recorded_config_sha))) "MATCH" else "MISMATCH"
  )
}
