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

production_release_read_json_strict <- function(path, label = "JSON document") {
  production_orchestration_require("jsonlite")
  production_orchestration_require("yaml")
  if (!file.exists(path)) stop(label, " does not exist: ", path, call. = FALSE)
  parsed <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(error) {
    stop(label, " is not valid JSON: ", conditionMessage(error), call. = FALSE)
  })
  if (!is.list(parsed) || is.null(names(parsed))) stop(label, " must contain a JSON object.", call. = FALSE)

  # yaml rejects duplicate mapping keys; jsonlite enforces JSON syntax and preserves large integers.
  tryCatch(
    withCallingHandlers(yaml::read_yaml(path), warning = function(warning) {
      if (grepl("NAs introduced by coercion: [0-9]+ is out of integer range", conditionMessage(warning))) {
        invokeRestart("muffleWarning")
      }
    }),
    error = function(error) stop(label, " has duplicate or invalid mapping keys: ", conditionMessage(error), call. = FALSE)
  )
  parsed
}

production_release_read_qualification_manifest <- function(path, repo_root) {
  evidence <- production_release_read_json_strict(path, "Qualification evidence")
  root_fields <- c("evidence_schema_version", "supersedes", "decision_status", "review_date", "candidate_model",
                   "canonical_tests", "historical_model_preservation", "active_production_snapshot",
                   "deployment_manifest_reconciliation", "activation", "integration")
  production_release_assert_fields(evidence, root_fields, root_fields, "qualification evidence")
  if (!identical(as.integer(evidence$evidence_schema_version), 2L)) stop("Unsupported qualification evidence schema version.", call. = FALSE)
  if (length(evidence$decision_status) != 1L || is.na(evidence$decision_status) || !nzchar(evidence$decision_status)) {
    stop("Qualification evidence decision_status is missing.", call. = FALSE)
  }
  production_release_assert_fields(evidence$supersedes, c("path", "sha256"), c("path", "sha256"), "qualification evidence.supersedes")
  if (!production_release_is_sha256(evidence$supersedes$sha256)) stop("Qualification evidence supersedes.sha256 is invalid.", call. = FALSE)
  superseded_path <- production_release_resolve_path(evidence$supersedes$path, repo_root)
  if (!file.exists(superseded_path) || !identical(production_release_sha256(superseded_path), tolower(evidence$supersedes$sha256))) {
    stop("Superseded historical qualification evidence is missing or has changed.", call. = FALSE)
  }

  candidate_fields <- c("model_id", "qualification_status", "proposed_production_id", "active_in_production",
                        "formula_identity", "formula_reference", "data_release", "repository", "runtime", "fit",
                        "stages", "supporting_records", "supporting_record_checksums", "qualification_evidence")
  production_release_assert_fields(evidence$candidate_model, candidate_fields, candidate_fields, "qualification evidence.candidate_model")
  candidate <- evidence$candidate_model
  if (length(candidate$qualification_status) != 1L || is.na(candidate$qualification_status) || !nzchar(candidate$qualification_status)) {
    stop("Qualification evidence candidate_model.qualification_status is missing.", call. = FALSE)
  }
  qualification_fields <- c(
    "fit_health_pass", "fit_health_fail", "extraction_pass", "extraction_fail", "validation_pass",
    "validation_warning", "validation_fail", "tier1_holdouts", "tier2_holdouts", "holdout_identity_match_with_c1",
    "tier1_area_weighted_pb_auc", "tier1_area_weighted_cbi", "tier2_mae", "tier2_rmse", "tier2_pearson",
    "tier2_spearman", "tier2_calibration_mean_ratio", "tier2_mae_difference_refreshed_minus_c1",
    "tier2_mae_difference_interpretation", "limitations", "fit_stderr_inla_experimental_vb_warning_occurrences",
    "fit_stderr_unclassified_warning_lines", "rasters_generated", "posterior_sampling_performed")
  production_release_assert_fields(candidate$qualification_evidence, qualification_fields, qualification_fields,
                                   "qualification evidence.candidate_model.qualification_evidence")
  for (key in setdiff(qualification_fields, c("holdout_identity_match_with_c1", "tier2_mae_difference_interpretation", "limitations", "rasters_generated", "posterior_sampling_performed"))) {
    value <- candidate$qualification_evidence[[key]]
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
      stop("Qualification evidence has an invalid numeric field: ", key, call. = FALSE)
    }
  }
  limitations <- unlist(candidate$qualification_evidence$limitations, use.names = FALSE)
  if (!is.logical(candidate$qualification_evidence$holdout_identity_match_with_c1) ||
      !is.logical(candidate$qualification_evidence$rasters_generated) ||
      !is.logical(candidate$qualification_evidence$posterior_sampling_performed) ||
      !is.character(limitations) || !length(limitations) || any(!nzchar(limitations))) {
    stop("Qualification evidence is missing required logical or limitation records.", call. = FALSE)
  }
  evidence
}


production_release_canonicalize <- function(value) {
  if (!is.list(value)) return(value)
  keys <- names(value)
  if (!is.null(keys) && all(nzchar(keys))) {
    ordered <- order(keys)
    value <- value[ordered]
    names(value) <- keys[ordered]
  }
  lapply(value, production_release_canonicalize)
}

production_release_specification_digest <- function(descriptor) {
  required <- c("likelihood", "fixed_effects", "random_effects", "priors", "spatial_temporal",
                "transformations", "product_semantics")
  production_release_assert_fields(descriptor, required, required, "scientific specification descriptor")
  production_orchestration_require("jsonlite")
  production_orchestration_require("digest")
  canonical <- production_release_canonicalize(descriptor)
  encoded <- as.character(jsonlite::toJSON(canonical, auto_unbox = TRUE, null = "null",
                                           digits = NA, POSIXt = "ISO8601", force = TRUE))
  tolower(digest::digest(encoded, algo = "sha256", serialize = FALSE))
}

production_release_specification_descriptor_from_signature <- function(model_signature, transformations,
                                                                          product_semantics,
                                                                          covariate_registry = NULL) {
  fields <- c("formula", "fixed_effect_names", "fixed_effect_formula_order", "fixed_effect_tiers",
              "family", "spde_structure", "shared_field", "hyperparameter_count", "theta_order",
              "effect_structure", "prior_structure")
  missing <- setdiff(fields, names(model_signature))
  if (length(missing)) stop("Effective model signature lacks scientific fields: ", paste(missing, collapse = ", "), call. = FALSE)
  covariate_registry <- covariate_registry %||% model_signature$covariate_registry
  registry_descriptor <- NULL
  if (!is.null(covariate_registry)) {
    registry_descriptor <- lapply(covariate_registry$covariates, function(entry) {
      list(model_term = entry$model_term, tier = entry$tier, input_section = entry$input_section,
           temporal_support = entry$temporal_support, transformation = entry$transformation,
           missing_policy = entry$missing_policy, reporting_label = entry$reporting_label)
    })
  }
  list(
    likelihood = model_signature$family,
    fixed_effects = list(formula = model_signature$formula,
                         names = model_signature$fixed_effect_names,
                         order = model_signature$fixed_effect_formula_order,
                         tiers = model_signature$fixed_effect_tiers),
    random_effects = list(shared_field = model_signature$shared_field,
                          hyperparameter_count = model_signature$hyperparameter_count,
                          theta_order = model_signature$theta_order,
                          effects = model_signature$effect_structure),
    priors = model_signature$prior_structure,
    spatial_temporal = list(spde = model_signature$spde_structure,
                            shared_field = model_signature$shared_field,
                            temporal = model_signature$prior_structure$temporal,
                            administrative = model_signature$prior_structure$administrative),
    transformations = list(preprocessing = transformations, covariates = registry_descriptor),
    product_semantics = product_semantics
  )
}

production_release_classify_specification <- function(descriptor, comparison_sha256) {
  candidate_sha256 <- production_release_specification_digest(descriptor)
  if (!production_release_is_sha256(comparison_sha256)) {
    stop("Comparison scientific specification must have a SHA-256 digest.", call. = FALSE)
  }
  list(release_class = if (identical(candidate_sha256, tolower(as.character(comparison_sha256)))) {
         "ROUTINE_REFRESH"
       } else {
         "MODEL_REVISION"
       },
       specification_sha256 = candidate_sha256,
       comparison_specification_sha256 = tolower(as.character(comparison_sha256)))
}

production_release_canonical_directories <- function(production_runs_root) {
  if (length(production_runs_root) != 1L || is.na(production_runs_root) || !nzchar(as.character(production_runs_root))) {
    stop("Production execution root must be one non-empty path.", call. = FALSE)
  }
  production_runs <- normalizePath(path.expand(as.character(production_runs_root)), mustWork = FALSE)
  if (!identical(basename(production_runs), "production_runs")) {
    stop("Production execution root must use the established production_runs directory.", call. = FALSE)
  }
  parent <- dirname(production_runs)
  list(
    production_runs = production_runs,
    accepted_products = file.path(parent, "postfit_acceptance"),
    model_registry = file.path(production_runs, "model_registry")
  )
}

production_release_path_within <- function(path, root) {
  if (length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) return(FALSE)
  resolved_path <- normalizePath(path, mustWork = TRUE)
  resolved_root <- normalizePath(root, mustWork = TRUE)
  identical(resolved_path, resolved_root) ||
    startsWith(resolved_path, paste0(sub("/+$", "", resolved_root), .Platform$file.sep))
}

production_release_validate_release_metadata <- function(request) {
  release <- request$release
  fields <- c("release_class", "data_release_id", "comparison_specification_id",
              "comparison_specification_sha256", "specification_descriptor", "specification_sha256",
              "analysis_period", "accepted_products_root", "previous_release_id")
  production_release_assert_fields(release, fields, fields, "release")
  if (!as.character(release$release_class) %in% c("ROUTINE_REFRESH", "MODEL_REVISION")) {
    stop("release.release_class must be ROUTINE_REFRESH or MODEL_REVISION.", call. = FALSE)
  }
  if (!identical(as.character(release$data_release_id), as.character(request$data$release_id))) {
    stop("release.data_release_id must match data.release_id.", call. = FALSE)
  }
  if (!production_release_is_sha256(release$comparison_specification_sha256)) {
    stop("release.comparison_specification_sha256 must be a SHA-256 digest.", call. = FALSE)
  }
  observed <- production_release_specification_digest(release$specification_descriptor)
  if (!production_release_is_sha256(release$specification_sha256) ||
      !identical(observed, tolower(as.character(release$specification_sha256)))) {
    stop("Scientific specification digest does not match its descriptor.", call. = FALSE)
  }
  expected_product_semantics <- list(
    temperature_mask_threshold_c = as.numeric(request$reporting$temperature_mask_threshold_c),
    rpi_calibration = as.character(request$reporting$rpi_calibration),
    rpi_quantile = as.numeric(request$reporting$rpi_quantile),
    required_products = as.character(unlist(request$reporting$required_products, use.names = FALSE))
  )
  observed_product_semantics <- release$specification_descriptor$product_semantics
  observed_product_semantics <- list(
    temperature_mask_threshold_c = as.numeric(observed_product_semantics$temperature_mask_threshold_c),
    rpi_calibration = as.character(observed_product_semantics$rpi_calibration),
    rpi_quantile = as.numeric(observed_product_semantics$rpi_quantile),
    required_products = as.character(unlist(observed_product_semantics$required_products, use.names = FALSE))
  )
  if (!identical(production_release_canonicalize(observed_product_semantics),
                 production_release_canonicalize(expected_product_semantics))) {
    stop("Scientific specification product semantics do not match the requested reporting contract.", call. = FALSE)
  }
  classified <- production_release_classify_specification(
    release$specification_descriptor, release$comparison_specification_sha256
  )
  if (!identical(classified$release_class, as.character(release$release_class))) {
    stop("Release class does not agree with verified scientific specification digests.", call. = FALSE)
  }
  same_specification_id <- identical(as.character(request$model$specification_id),
                                     as.character(release$comparison_specification_id))
  if (identical(classified$release_class, "ROUTINE_REFRESH") && !same_specification_id) {
    stop("ROUTINE_REFRESH must retain the compared scientific specification ID.", call. = FALSE)
  }
  if (identical(classified$release_class, "MODEL_REVISION") && same_specification_id) {
    stop("MODEL_REVISION must use a distinct scientific specification ID.", call. = FALSE)
  }
  production_release_assert_fields(release$analysis_period, c("start_epiweek", "end_epiweek"),
                                   c("start_epiweek", "end_epiweek"), "release.analysis_period")
  if (!identical(as.character(release$analysis_period$start_epiweek), as.character(request$analysis$start_epiweek)) ||
      !identical(as.character(release$analysis_period$end_epiweek), as.character(request$analysis$requested_endpoint))) {
    stop("Release analysis_period must match the declared request horizon.", call. = FALSE)
  }
  canonical <- production_release_canonical_directories(request$output$root)
  if (!identical(normalizePath(as.character(release$accepted_products_root), mustWork = FALSE),
                 normalizePath(canonical$accepted_products, mustWork = FALSE))) {
    stop("Accepted products root must resolve to the canonical postfit_acceptance sibling of production_runs.", call. = FALSE)
  }
  list(
    release_class = classified$release_class,
    specification_sha256 = classified$specification_sha256,
    comparison_specification_sha256 = classified$comparison_specification_sha256,
    model_specification_id = as.character(request$model$specification_id),
    comparison_specification_id = as.character(release$comparison_specification_id),
    data_release_id = as.character(release$data_release_id),
    analysis_period = release$analysis_period,
    accepted_products_root = canonical$accepted_products,
    previous_release_id = release$previous_release_id
  )
}

production_release_cleanup_eligibility <- function(candidates, as_of = Sys.Date()) {
  if (is.character(candidates) && length(candidates) == 1L) {
    candidates <- utils::read.csv(candidates, stringsAsFactors = FALSE, check.names = FALSE)
  }
  required <- c("path", "classification", "bytes", "owner", "known_source_references",
                "downstream_consumers", "retention_start_date", "subsequent_qualified_refreshes",
                "active_job_references", "replacement_path", "replacement_sha256",
                "replacement_verified", "scientific_preservation_required", "duplicate_finding")
  if (!is.data.frame(candidates) || !all(required %in% names(candidates))) {
    stop("Cleanup candidate inventory lacks required read-only review fields.", call. = FALSE)
  }
  if (!inherits(as.Date(as_of), "Date") || length(as.Date(as_of)) != 1L || is.na(as.Date(as_of))) {
    stop("as_of must be one valid calendar date.", call. = FALSE)
  }
  text_values <- function(x) {
    value <- trimws(as.character(x))
    is.na(value) | !nzchar(value) | tolower(value) %in% c("none", "[]", "null", "na")
  }
  bool_value <- function(x) tolower(as.character(x)) %in% c("true", "1", "yes")
  rows <- lapply(seq_len(nrow(candidates)), function(i) {
    item <- candidates[i, , drop = FALSE]
    blocks <- character()
    bytes <- suppressWarnings(as.numeric(item$bytes[[1L]]))
    cycles <- suppressWarnings(as.integer(item$subsequent_qualified_refreshes[[1L]]))
    start <- suppressWarnings(as.Date(as.character(item$retention_start_date[[1L]])))
    classification <- toupper(as.character(item$classification[[1L]]))
    if (!is.finite(bytes) || bytes < 0) blocks <- c(blocks, "artifact size is missing or invalid")
    if (text_values(item$owner[[1L]])) blocks <- c(blocks, "owner is unknown")
    if (!identical(classification, "ROUTINE_REFRESH_SUPERSEDED")) blocks <- c(blocks, "routine-refresh retention does not apply to this classification")
    if (is.na(start) || as.Date(as_of) < start + 90L) blocks <- c(blocks, "90-day retention period has not expired")
    if (is.na(cycles) || cycles < 2L) blocks <- c(blocks, "two subsequent qualified refreshes are not recorded")
    if (!text_values(item$known_source_references[[1L]])) blocks <- c(blocks, "source references remain unresolved")
    if (!text_values(item$downstream_consumers[[1L]])) blocks <- c(blocks, "downstream consumers remain unresolved")
    if (!text_values(item$active_job_references[[1L]])) blocks <- c(blocks, "active or historical job references require review")
    if (text_values(item$replacement_path[[1L]]) || !production_release_is_sha256(item$replacement_sha256[[1L]]) ||
        !bool_value(item$replacement_verified[[1L]])) blocks <- c(blocks, "verified replacement artifact is absent")
    if (bool_value(item$scientific_preservation_required[[1L]])) blocks <- c(blocks, "scientific preservation requirements apply")
    if (bool_value(item$duplicate_finding[[1L]])) blocks <- c(blocks, "confirmed duplicate finding is retained pending consumer resolution")
    eligible <- !length(blocks)
    data.frame(
      path = as.character(item$path[[1L]]),
      classification = classification,
      bytes = bytes,
      owner = as.character(item$owner[[1L]]),
      known_source_references = as.character(item$known_source_references[[1L]]),
      downstream_consumers = as.character(item$downstream_consumers[[1L]]),
      retention_eligible = eligible,
      scientific_preservation_required = bool_value(item$scientific_preservation_required[[1L]]),
      active_job_references = as.character(item$active_job_references[[1L]]),
      verified_replacement = bool_value(item$replacement_verified[[1L]]),
      estimated_recoverable_bytes = if (eligible) bytes else 0,
      blocking_conditions = paste(blocks, collapse = "; "),
      required_approval = "EXPLICIT_OWNER_AND_GOVERNANCE_APPROVAL",
      as_of = as.character(as.Date(as_of)),
      stringsAsFactors = FALSE
    )
  })
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

production_release_discover_active <- function(active_state_path, verify_artifact = FALSE) {
  state <- production_release_active_state(active_state_path)
  production_release_verify_file(state$configuration_path, state$configuration_sha256,
                                 label = "active release configuration")
  validated <- production_release_read_model_manifest(state$manifest_path, state$manifest_sha256,
                                                       verify_artifact = verify_artifact)
  manifest <- validated$manifest
  if (!identical(as.character(manifest$production_id), as.character(state$production_id))) {
    stop("Active pointer and release manifest production IDs differ.", call. = FALSE)
  }
  if (!identical(normalizePath(state$configuration_path, mustWork = TRUE),
                 normalizePath(manifest$configuration$path, mustWork = TRUE)) ||
      !identical(tolower(as.character(state$configuration_sha256)),
                 tolower(as.character(manifest$configuration$sha256)))) {
    stop("Active pointer and release configuration identities differ.", call. = FALSE)
  }
  verified <- list(
    status = "PASS",
    generation = as.integer(state$generation),
    production_id = state$production_id,
    candidate_id = manifest$candidate_id,
    formula_identity = manifest$formula_identity,
    artifact_path = manifest$fit$path,
    artifact_sha256 = manifest$fit$sha256,
    observed_artifact_sha256 = if (verify_artifact) production_release_sha256(manifest$fit$path) else NA_character_,
    manifest_path = state$manifest_path,
    manifest_sha256 = validated$sha256
  )
  list(status = "ACTIVE_RELEASE_VERIFIED", active_state_path = normalizePath(active_state_path, mustWork = TRUE),
       generation = as.integer(state$generation), production_id = state$production_id,
       manifest_path = state$manifest_path, manifest_sha256 = validated$sha256,
       release = manifest, verification = verified)
}

production_release_validate_request <- function(request) {
  top <- c("schema_version", "request_id", "operation", "configuration", "model", "data",
           "environmental_data", "covariate_registry", "analysis", "output", "qualification",
           "reporting", "resume", "adoption")
  production_release_assert_fields(request, top, c(top, "release"), "refresh request")
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
      c("artifact_manifest", "artifact_manifest_sha256", "source_fit_job_id", "fit_sha256", "fit_source_commit", "report_generation_commit", "lineage", "provenance_reconciliation"), "adoption")
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
    if (!is.null(request$adoption$provenance_reconciliation)) {
      production_release_assert_fields(request$adoption$provenance_reconciliation, c("path", "sha256"), c("path", "sha256"), "adoption.provenance_reconciliation")
      if (!production_release_is_sha256(request$adoption$provenance_reconciliation$sha256)) stop("adoption.provenance_reconciliation.sha256 must be a SHA-256 digest.", call. = FALSE)
    }
  } else if (!is.null(request$adoption)) stop("Only adopt requests may contain adoption fields.", call. = FALSE)
  if (!is.null(request$release)) production_release_validate_release_metadata(request)
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
    if (!is.null(request$adoption$provenance_reconciliation)) {
      resolved$provenance_reconciliation <- production_release_resolve_path(request$adoption$provenance_reconciliation$path, repo_root)
    }
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

production_release_adoption_run_id <- function(request_id, now = Sys.time()) {
  production_orchestration_require("digest")
  now <- as.POSIXct(now, tz = "UTC")
  nonce <- digest::digest(paste(as.character(request_id),
                                format(now, "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")),
                          algo = "sha256", serialize = FALSE)
  production_orchestration_run_id(nonce, now = now)
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
    run_id <- if (mode == "adopt") production_release_adoption_run_id(request$request_id) else request$request_id
    expected_run_root <- file.path(resolved$output_root, run_id)
    if (!is.null(run_root) && !identical(normalizePath(run_root, mustWork = FALSE), normalizePath(expected_run_root, mustWork = FALSE))) stop("--run-root may not override the versioned output location in a refresh request.", call. = FALSE)
    run_root <- expected_run_root
    contract <- production_orchestration_contract(config_path, repo_root, run_id = run_id, run_root = run_root, config_overrides = overrides)
    if (!identical(as.character(contract$horizon$resolved_final_complete_epiweek), as.character(request$analysis$requested_endpoint))) stop("Requested analysis endpoint does not match the last complete epiweek in the observation release.", call. = FALSE)
    if (dir.exists(contract$run_root) || file.exists(contract$run_root)) stop("Refresh run output already exists; historical outputs are never overwritten: ", contract$run_root, call. = FALSE)
    contract$operation_mode <- mode
    contract$configuration_compatibility <- compatibility
    contract$refresh_request <- list(path = attr(request, "request_path"), sha256 = attr(request, "request_sha256"),
                                     request_id = request$request_id, mode = mode, execution_run_id = run_id,
                                     release_metadata = if (is.null(request$release)) NULL else production_release_validate_release_metadata(request),
                                     document = production_release_request_document(request))
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
        provenance_reconciliation = fit_provenance$provenance_reconciliation %||% NULL,
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

production_release_validate_source_reconciliation <- function(reference, repo_root, source_fit_job_id,
                                                              launch_commit, metadata_runtime_commit,
                                                              audit_start_utc, audit_end_utc) {
  if (is.null(reference)) stop("Fit source commit mismatch: Slurm launch log records ", launch_commit,
    "; fit metadata records ", metadata_runtime_commit,
    ". A checksummed provenance reconciliation is required.", call. = FALSE)
  production_release_assert_fields(reference, c("path", "sha256"), c("path", "sha256"), "adoption.provenance_reconciliation")
  if (!production_release_is_sha256(reference$sha256)) stop("Provenance reconciliation checksum is invalid.", call. = FALSE)
  path <- production_release_resolve_path(reference$path, repo_root)
  production_release_verify_file(path, reference$sha256, label = "fit source provenance reconciliation")
  reconciliation <- production_release_read_json_strict(path, "Fit source provenance reconciliation")
  fields <- c("schema_version", "record_id", "fit", "comparison", "metadata_discrepancy", "decision")
  production_release_assert_fields(reconciliation, fields, fields, "fit source provenance reconciliation")
  if (!identical(as.integer(reconciliation$schema_version), 1L)) stop("Unsupported fit source provenance reconciliation schema version.", call. = FALSE)
  production_release_assert_fields(reconciliation$fit,
    c("job_id", "launch_commit", "metadata_runtime_commit", "metadata_audit_commit", "launch_commit_recorded_at",
      "metadata_commit_recorded_at", "audit_start_utc", "audit_end_utc"),
    c("job_id", "launch_commit", "metadata_runtime_commit", "metadata_audit_commit", "launch_commit_recorded_at",
      "metadata_commit_recorded_at", "audit_start_utc", "audit_end_utc"),
    "fit source provenance reconciliation.fit")
  if (!identical(as.character(reconciliation$fit$job_id), as.character(source_fit_job_id)) ||
      !identical(as.character(reconciliation$fit$launch_commit), launch_commit) ||
      !identical(as.character(reconciliation$fit$metadata_runtime_commit), metadata_runtime_commit) ||
      !identical(as.character(reconciliation$fit$metadata_audit_commit), metadata_runtime_commit)) {
    stop("Fit source provenance reconciliation does not match the observed job and commit identities.", call. = FALSE)
  }
  timestamp_names <- c("launch_commit_recorded_at", "metadata_commit_recorded_at", "audit_start_utc", "audit_end_utc")
  timestamps <- vapply(timestamp_names, function(key) as.character(reconciliation$fit[[key]]), character(1L))
  if (anyNA(timestamps) || any(!nzchar(timestamps))) stop("Fit source provenance reconciliation has incomplete timestamps.", call. = FALSE)
  if (!identical(timestamps[[3L]], as.character(audit_start_utc)) ||
      !identical(timestamps[[4L]], as.character(audit_end_utc))) {
    stop("Fit source provenance reconciliation audit timestamps do not match the fit metadata.", call. = FALSE)
  }
  parsed_timestamps <- as.POSIXct(timestamps, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  if (anyNA(parsed_timestamps) || parsed_timestamps[[1L]] > parsed_timestamps[[3L]] ||
      parsed_timestamps[[2L]] < parsed_timestamps[[3L]] || parsed_timestamps[[2L]] > parsed_timestamps[[4L]] ||
      parsed_timestamps[[3L]] > parsed_timestamps[[4L]]) {
    stop("Fit source provenance reconciliation timestamps do not place the metadata commit within the fit audit window.", call. = FALSE)
  }
  comparison_fields <- c("changed_paths", "documentation_paths", "archived_scientific_evidence_paths", "test_only_paths",
                         "executable_paths", "model_specification_paths", "configuration_paths", "runtime_setting_paths",
                         "launch_tree_ids", "metadata_tree_ids", "fit_relevant_trees_identical", "model_behavior_changed",
                         "executable_source_changes", "test_file_changes", "configuration_file_changes",
                         "model_definition_changes", "likelihood_or_runtime_setting_changes", "classification")
  production_release_assert_fields(reconciliation$comparison, comparison_fields, comparison_fields,
                                   "fit source provenance reconciliation.comparison")
  paths <- unlist(reconciliation$comparison$changed_paths, use.names = FALSE)
  if (!length(paths) || any(!grepl("^docs/archive/configuration-c-1-2026/[^.].*", paths)) || any(grepl("(^|/)\\.\\.(/|$)", paths))) {
    stop("Fit source provenance reconciliation lists an unsupported changed path.", call. = FALSE)
  }
  documentation_paths <- unlist(reconciliation$comparison$documentation_paths, use.names = FALSE)
  evidence_paths <- unlist(reconciliation$comparison$archived_scientific_evidence_paths, use.names = FALSE)
  if (!identical(sort(c(documentation_paths, evidence_paths)), sort(paths)) ||
      length(unlist(reconciliation$comparison$test_only_paths, use.names = FALSE)) != 0L ||
      length(unlist(reconciliation$comparison$executable_paths, use.names = FALSE)) != 0L ||
      length(unlist(reconciliation$comparison$model_specification_paths, use.names = FALSE)) != 0L ||
      length(unlist(reconciliation$comparison$configuration_paths, use.names = FALSE)) != 0L ||
      length(unlist(reconciliation$comparison$runtime_setting_paths, use.names = FALSE)) != 0L) {
    stop("Fit source provenance reconciliation has inconsistent change classifications.", call. = FALSE)
  }
  tree_names <- c("R", "scripts", "config", "tests")
  production_release_assert_fields(reconciliation$comparison$launch_tree_ids, tree_names, tree_names,
                                   "fit source provenance reconciliation.comparison.launch_tree_ids")
  production_release_assert_fields(reconciliation$comparison$metadata_tree_ids, tree_names, tree_names,
                                   "fit source provenance reconciliation.comparison.metadata_tree_ids")
  for (tree in tree_names) {
    launch_tree <- as.character(reconciliation$comparison$launch_tree_ids[[tree]])
    metadata_tree <- as.character(reconciliation$comparison$metadata_tree_ids[[tree]])
    if (!grepl("^[[:xdigit:]]{40}$", launch_tree) || !identical(launch_tree, metadata_tree)) {
      stop("Fit source provenance reconciliation has a non-identical fit-relevant tree: ", tree, call. = FALSE)
    }
  }
  if (!isTRUE(reconciliation$comparison$fit_relevant_trees_identical) ||
      !identical(reconciliation$comparison$model_behavior_changed, FALSE) ||
      !identical(as.integer(reconciliation$comparison$executable_source_changes), 0L) ||
      !identical(as.integer(reconciliation$comparison$test_file_changes), 0L) ||
      !identical(as.integer(reconciliation$comparison$configuration_file_changes), 0L) ||
      !identical(as.integer(reconciliation$comparison$model_definition_changes), 0L) ||
      !identical(as.integer(reconciliation$comparison$likelihood_or_runtime_setting_changes), 0L) ||
      !identical(as.character(reconciliation$comparison$classification), "NON_EXECUTABLE_C1_ARCHIVE_ONLY")) {
    stop("Fit source provenance reconciliation does not establish executable and scientific compatibility.", call. = FALSE)
  }
  if (length(reconciliation$metadata_discrepancy) != 1L || is.na(reconciliation$metadata_discrepancy) ||
      !nzchar(as.character(reconciliation$metadata_discrepancy))) {
    stop("Fit source provenance reconciliation does not explain the metadata discrepancy.", call. = FALSE)
  }
  decision_fields <- c("status", "source_identity", "governance_mode", "authorization_basis", "production_activation_authorized")
  production_release_assert_fields(reconciliation$decision, decision_fields, decision_fields,
                                   "fit source provenance reconciliation.decision")
  if (!identical(as.character(reconciliation$decision$status), "RECONCILED_NON_EXECUTABLE_METADATA_DRIFT") ||
      !identical(as.character(reconciliation$decision$source_identity), "launch_commit") ||
      !identical(as.character(reconciliation$decision$governance_mode), "HGE") ||
      !identical(as.character(reconciliation$decision$authorization_basis), "USER_TASK_CONDITIONAL_PROVENANCE_RECONCILIATION") ||
      !identical(reconciliation$decision$production_activation_authorized, FALSE)) {
    stop("Fit source provenance reconciliation has no applicable authorized governance decision.", call. = FALSE)
  }
  list(path = path, sha256 = tolower(reference$sha256), status = as.character(reconciliation$decision$status),
       source_identity = launch_commit, launch_commit = launch_commit, metadata_runtime_commit = metadata_runtime_commit,
       changed_paths = paths, fit_relevant_trees_identical = TRUE, production_activation_authorized = FALSE)
}

production_release_validate_fit_metadata <- function(inventory, request, repo_root) {
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
  reconciliation <- NULL
  audit_start <- as.character(audit[["start_timestamp"]] %||% NA_character_)
  audit_end <- as.character(audit[["end_timestamp"]] %||% NA_character_)
  if (!identical(runtime_commit, launch_commit)) {
    reconciliation <- production_release_validate_source_reconciliation(request$adoption$provenance_reconciliation,
      repo_root, request$adoption$source_fit_job_id, launch_commit, runtime_commit, audit_start, audit_end)
  } else if (!is.null(request$adoption$provenance_reconciliation)) {
    reconciliation <- production_release_validate_source_reconciliation(request$adoption$provenance_reconciliation,
      repo_root, request$adoption$source_fit_job_id, launch_commit, runtime_commit, audit_start, audit_end)
  }
  if (!identical(runtime_commit, launch_commit) && is.null(reconciliation)) {
    stop("Fit source commit mismatch: Slurm launch log records ", launch_commit,
         "; fit metadata records ", runtime_commit,
         " (audit window ", audit_start, " to ", audit_end,
         "). A later completion-time checkout cannot be substituted for launch-time source without an approved provenance resolution.", call. = FALSE)
  }
  list(launch_commit = launch_commit, metadata_runtime_commit = runtime_commit,
       provenance_reconciliation = reconciliation,
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
  qualification <- production_release_read_qualification_manifest(resolved$qualification_manifest, repo_root)
  candidate <- qualification$candidate_model
  if (!identical(as.character(candidate$model_id), as.character(req$model$candidate_id))) stop("Candidate model identifier does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$proposed_production_id), as.character(req$model$production_id))) stop("Production candidate identifier does not match the qualification evidence.", call. = FALSE)
  if (!identical(as.character(candidate$qualification_status), as.character(req$qualification$status))) stop("Candidate model qualification status does not match the refresh request.", call. = FALSE)
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
  if (!is.null(req$adoption$provenance_reconciliation)) {
    reconciliation_evidence <- evidence_verified$source_provenance_reconciliation
    requested_reconciliation_path <- production_release_resolve_path(req$adoption$provenance_reconciliation$path, repo_root)
    if (is.null(reconciliation_evidence) ||
        !identical(normalizePath(reconciliation_evidence$path, mustWork = TRUE), normalizePath(requested_reconciliation_path, mustWork = TRUE)) ||
        !identical(tolower(reconciliation_evidence$sha256), tolower(req$adoption$provenance_reconciliation$sha256))) {
      stop("Adoption request and qualification evidence reference different source-provenance reconciliation records.", call. = FALSE)
    }
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
    if (!identical(as.integer(qualification_counts[[key]]), as.integer(candidate$qualification_evidence[[key]]))) {
      stop("Qualification count ", key, " does not match the supporting audit record.", call. = FALSE)
    }
  }
  if (count_status(audit_results$extraction, "FAIL") != 0L || count_status(audit_results$validation, "FAIL") != 0L ||
      count_status(audit_results$fit_health, "FAIL") != 0L) stop("A fit-health, extraction, or predictive-validation audit records a failure.", call. = FALSE)

  metadata_provenance <- production_release_validate_fit_metadata(inventory, req, repo_root)
  if (!identical(as.character(candidate$repository$metadata_runtime_commit),
                 as.character(metadata_provenance$metadata_runtime_commit))) {
    stop("Qualification evidence metadata runtime commit does not match fit metadata.", call. = FALSE)
  }
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
    provenance_reconciliation = metadata_provenance$provenance_reconciliation,
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

production_release_copy_bundle <- function(artifact_paths, registry_dir, production_root = NULL) {
  production_orchestration_require("yaml")
  parent <- dirname(registry_dir)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  lock_path <- paste0(registry_dir, ".registry.lock")
  if (!dir.create(lock_path, showWarnings = FALSE)) stop("Registry lock exists; refusing concurrent registration: ", lock_path, call. = FALSE)
  on.exit(unlink(lock_path, recursive = TRUE), add = TRUE)
  policies <- vapply(artifact_paths, function(item) item$storage_policy %||% "copy", character(1L))
  if (any(!policies %in% c("copy", "reference"))) stop("Artifact storage policy must be copy or reference.", call. = FALSE)
  if (dir.exists(registry_dir) || file.exists(registry_dir)) {
    existing_manifest <- file.path(registry_dir, "registry-manifest.yml")
    if (!file.exists(existing_manifest)) stop("Versioned model registry destination exists without a manifest; refusing to overwrite: ", registry_dir, call. = FALSE)
    existing <- yaml::read_yaml(existing_manifest)
    if (!identical(sort(names(existing$artifacts)), sort(names(artifact_paths)))) stop("Existing model registry has a different artifact set.", call. = FALSE)
    for (name in names(artifact_paths)) {
      record <- existing$artifacts[[name]]
      record_policy <- record$storage_type %||% "copy"
      if (!identical(record_policy, policies[[name]]) ||
          !identical(tolower(as.character(record$sha256)), tolower(as.character(artifact_paths[[name]]$sha256))) ||
          !identical(normalizePath(record$source_path, mustWork = FALSE), normalizePath(artifact_paths[[name]]$path, mustWork = FALSE))) {
        stop("Existing model registry differs for artifact ", name, call. = FALSE)
      }
      production_release_verify_file(record$path, record$sha256, artifact_paths[[name]]$bytes %||% NULL, paste0("registered ", name))
    }
    return(list(path = normalizePath(registry_dir, mustWork = TRUE), manifest = normalizePath(existing_manifest, mustWork = TRUE),
                manifest_sha256 = production_release_sha256(existing_manifest), artifacts = existing$artifacts, reused = TRUE,
                storage_policy = existing$storage_policy %||% "copy"))
  }
  staging <- tempfile(pattern = paste0(".", basename(registry_dir), ".staging-"), tmpdir = parent)
  if (!dir.create(staging, recursive = FALSE, showWarnings = FALSE)) stop("Unable to create registry staging directory.", call. = FALSE)
  committed <- FALSE
  on.exit(if (!committed && dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  registered <- list()
  for (name in names(artifact_paths)) {
    source_value <- artifact_paths[[name]]$path
    if (!file.exists(source_value) || dir.exists(source_value)) {
      stop("Failed to stage model artifact ", name, call. = FALSE)
    }
    source <- normalizePath(source_value, mustWork = TRUE)
    expected <- artifact_paths[[name]]$sha256
    if (!production_release_is_sha256(expected)) stop("Artifact ", name, " has an invalid SHA-256 identity.", call. = FALSE)
    verified_source <- production_release_verify_file(source, expected, artifact_paths[[name]]$bytes %||% NULL,
                                                     paste0("source ", name))
    if (identical(policies[[name]], "reference")) {
      if (is.null(production_root) || !dir.exists(production_root) || !production_release_path_within(source, production_root)) {
        stop("Reference registration is restricted to existing artifacts under canonical production_runs; refusing a development-worktree reference.", call. = FALSE)
      }
      destination <- source
      storage_type <- "reference"
    } else {
      destination <- file.path(staging, name, basename(source))
      dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(source, destination, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE)) stop("Failed to stage model artifact ", name, call. = FALSE)
      verified_source <- production_release_verify_file(destination, expected, label = paste0("staged ", name))
      destination <- file.path(registry_dir, name, basename(source))
      storage_type <- "copy"
    }
    registered[[name]] <- list(path = destination, bytes = verified_source$bytes,
                               sha256 = verified_source$sha256, source_path = source,
                               storage_type = storage_type)
  }
  storage_policy <- if (all(policies == "reference")) "reference" else if (all(policies == "copy")) "copy" else "mixed_reference_and_copy"
  manifest <- list(schema_version = 2L, storage_policy = storage_policy,
                   canonical_production_root = if (is.null(production_root)) NULL else normalizePath(production_root, mustWork = FALSE),
                   created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                   artifacts = registered)
  production_release_atomic_yaml(manifest, file.path(staging, "registry-manifest.yml"), replace = FALSE)
  if (dir.exists(registry_dir) || file.exists(registry_dir)) stop("Registry destination appeared during staging; refusing to overwrite.", call. = FALSE)
  if (!file.rename(staging, registry_dir)) stop("Atomic registry publication failed; the source artifacts remain unchanged.", call. = FALSE)
  committed <- TRUE
  manifest_path <- file.path(registry_dir, "registry-manifest.yml")
  list(path = normalizePath(registry_dir, mustWork = TRUE), manifest = normalizePath(manifest_path, mustWork = TRUE),
       manifest_sha256 = production_release_sha256(manifest_path), artifacts = registered, reused = FALSE,
       storage_policy = storage_policy)
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
  canonical <- production_release_canonical_directories(request$output$root)
  core_artifacts <- intersect(c("stage1", "stage2", "stage3a", "fit"), names(source_bundle))
  for (name in core_artifacts) {
    source_bundle[[name]]$storage_policy <- if (production_release_path_within(source_bundle[[name]]$path, canonical$production_runs)) {
      "reference"
    } else {
      "copy"
    }
  }
  registry_root <- file.path(canonical$model_registry, request$model$production_id)
  registered <- production_release_copy_bundle(source_bundle, registry_root, production_root = canonical$production_runs)
  contract$artifact_storage <- list(policy = registered$storage_policy, registry_path = registered$path,
                                    registry_manifest = registered$manifest, reused_existing_registry = isTRUE(registered$reused),
                                    registry_manifest_sha256 = registered$manifest_sha256 %||% production_release_sha256(registered$manifest),
                                    canonical_payload_root = canonical$production_runs,
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
  if (!is.null(request$release)) {
    release_identity <- production_release_validate_release_metadata(request)
    manifest$schema_version <- 2L
    manifest$release <- list(
      release_class = release_identity$release_class,
      model_specification_id = release_identity$model_specification_id,
      specification_sha256 = release_identity$specification_sha256,
      specification_descriptor = request$release$specification_descriptor,
      comparison_specification_id = release_identity$comparison_specification_id,
      comparison_specification_sha256 = release_identity$comparison_specification_sha256,
      data_release_id = release_identity$data_release_id,
      analysis_period = release_identity$analysis_period,
      code_commit = contract$repository$git_commit,
      configuration_sha256 = contract$config$sha256,
      qualification_status = request$qualification$status,
      fit_artifact = manifest$fit,
      product_categories = request$reporting$required_products,
      accepted_products_root = release_identity$accepted_products_root,
      accepted_package = list(status = "AWAITING_ACCEPTANCE_REGISTRATION"),
      current_release_status = "QUALIFIED_NOT_ACTIVE",
      previous_release_id = release_identity$previous_release_id
    )
  }
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


production_release_register_accepted_package <- function(model_manifest_path, package_path,
                                                           acceptance_summary_path, product_manifest_path,
                                                           output_path = NULL) {
  production_orchestration_require("yaml")
  if (!file.exists(model_manifest_path)) stop("Model release manifest does not exist.", call. = FALSE)
  manifest <- production_release_read_model_manifest(model_manifest_path, verify_artifact = FALSE)$manifest
  if (!identical(as.integer(manifest$schema_version), 2L)) stop("Accepted-package registration requires a schema v2 release manifest.", call. = FALSE)
  release <- manifest$release
  if (is.null(release) || !production_release_is_sha256(release$specification_sha256)) stop("Model release scientific identity is incomplete.", call. = FALSE)
  canonical <- production_release_canonical_directories(dirname(manifest$output_root))
  root <- normalizePath(canonical$accepted_products, mustWork = TRUE)
  package <- normalizePath(package_path, mustWork = TRUE)
  summary <- normalizePath(acceptance_summary_path, mustWork = TRUE)
  products <- normalizePath(product_manifest_path, mustWork = TRUE)
  within_dir <- function(path, directory) identical(path, directory) || startsWith(path, paste0(sub("/+$", "", directory), .Platform$file.sep))
  if (!dir.exists(package) || !within_dir(package, root) || !within_dir(summary, package) || !within_dir(products, package)) {
    stop("Accepted package and its metadata must remain inside the canonical postfit_acceptance package.", call. = FALSE)
  }
  acceptance <- yaml::read_yaml(summary)
  acceptance_status <- toupper(as.character(acceptance$status %||% acceptance$disposition %||% ""))
  if (!acceptance_status %in% c("PASS", "PASS_WITH_WARNINGS", "ACCEPTED")) stop("Acceptance summary is not accepted.", call. = FALSE)
  run_manifest <- yaml::read_yaml(manifest$run_manifest$path)
  source_run_id <- as.character(acceptance$source_run_id %||% acceptance$native_run_id %||% "")
  if (!nzchar(source_run_id) || !identical(source_run_id, as.character(run_manifest$run_id))) {
    stop("Accepted package does not identify this release's execution run.", call. = FALSE)
  }
  normalize_job_id <- function(value) {
    if (is.null(value) || !length(value) || is.na(value[[1L]]) || !nzchar(trimws(as.character(value[[1L]])))) return("")
    as.character(value[[1L]])
  }
  expected_job <- normalize_job_id(run_manifest$refresh_request$source_execution$source_fit_job_id)
  if (!nzchar(expected_job)) expected_job <- normalize_job_id(run_manifest$job_ids$fit)
  package_job <- normalize_job_id(acceptance$fit_job_id %||% acceptance$source_fit_job_id)
  if (!nzchar(expected_job) || !nzchar(package_job) || !identical(package_job, expected_job)) {
    stop("Accepted package does not identify the release's historical source Fit job.", call. = FALSE)
  }
  production_release_validate_product_manifest(products, manifest$reporting)
  release$accepted_package <- list(
    status = "ACCEPTED",
    path = package,
    summary_path = summary,
    summary_sha256 = production_release_sha256(summary),
    product_manifest_path = products,
    product_manifest_sha256 = production_release_sha256(products)
  )
  release$current_release_status <- "QUALIFIED_NOT_ACTIVE"
  manifest$release <- release
  run_directory <- normalizePath(dirname(model_manifest_path), mustWork = TRUE)
  output_path <- output_path %||% file.path(run_directory, "model-release-accepted.yml")
  output_path <- normalizePath(path.expand(output_path), mustWork = FALSE)
  if (!within_dir(output_path, run_directory)) stop("Accepted release manifest must remain inside its execution run directory.", call. = FALSE)
  if (file.exists(output_path) || dir.exists(output_path)) stop("Refusing to overwrite an immutable accepted release manifest.", call. = FALSE)
  written <- production_release_atomic_yaml(manifest, output_path, replace = FALSE)
  validated <- production_release_read_model_manifest(written, verify_artifact = FALSE)
  list(path = written, sha256 = validated$sha256, status = release$current_release_status,
       accepted_package = release$accepted_package)
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
  schema_version <- as.integer(manifest$schema_version)
  if (!schema_version %in% c(1L, 2L)) stop("Unsupported model release manifest schema.", call. = FALSE)
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
  if (identical(schema_version, 2L)) {
    release <- manifest$release
    release_fields <- c("release_class", "model_specification_id", "specification_sha256",
                        "specification_descriptor", "comparison_specification_id", "comparison_specification_sha256",
                        "data_release_id", "analysis_period", "code_commit", "configuration_sha256",
                        "qualification_status", "fit_artifact", "product_categories",
                        "accepted_products_root", "accepted_package", "current_release_status",
                        "previous_release_id")
    production_release_assert_fields(release, release_fields, release_fields, "model release")
    if (!identical(as.character(release$model_specification_id), as.character(manifest$specification_id)) ||
        !release$release_class %in% c("ROUTINE_REFRESH", "MODEL_REVISION") ||
        !production_release_is_sha256(release$specification_sha256) ||
        !production_release_is_sha256(release$comparison_specification_sha256) ||
        !production_release_is_sha256(release$configuration_sha256) ||
        !identical(production_release_specification_digest(release$specification_descriptor),
                   tolower(as.character(release$specification_sha256)))) {
      stop("Model release scientific identity is invalid.", call. = FALSE)
    }
    derived_class <- production_release_classify_specification(
      release$specification_descriptor, release$comparison_specification_sha256
    )$release_class
    if (!identical(derived_class, as.character(release$release_class))) {
      stop("Model release class does not match its specification digests.", call. = FALSE)
    }
    if (!identical(as.character(release$fit_artifact$sha256), as.character(manifest$fit$sha256)) ||
        !identical(as.character(release$data_release_id), as.character(manifest$data$release_id))) {
      stop("Model release data or fit identity differs from its top-level artifact records.", call. = FALSE)
    }
    canonical <- production_release_canonical_directories(dirname(manifest$output_root))
    if (!identical(normalizePath(release$accepted_products_root, mustWork = FALSE),
                   normalizePath(canonical$accepted_products, mustWork = FALSE))) {
      stop("Model release accepted-products root is not canonical.", call. = FALSE)
    }
    package <- release$accepted_package
    package_status <- as.character(package$status)
    if (!package_status %in% c("AWAITING_ACCEPTANCE_REGISTRATION", "ACCEPTED")) {
      stop("Model release accepted-package state is invalid.", call. = FALSE)
    }
    if (identical(package_status, "ACCEPTED")) {
      for (record_name in c("path", "summary_path", "summary_sha256", "product_manifest_path", "product_manifest_sha256")) {
        if (is.null(package[[record_name]])) stop("Accepted package identity is incomplete: ", record_name, call. = FALSE)
      }
      if (!production_release_is_sha256(package$summary_sha256) ||
          !production_release_is_sha256(package$product_manifest_sha256)) stop("Accepted package checksums are invalid.", call. = FALSE)
      package_root <- normalizePath(release$accepted_products_root, mustWork = TRUE)
      package_path <- normalizePath(package$path, mustWork = TRUE)
      within_package <- function(path, parent) identical(path, parent) || startsWith(path, paste0(sub("/+$", "", parent), .Platform$file.sep))
      if (!dir.exists(package_path) || !within_package(package_path, package_root) ||
          !within_package(normalizePath(package$summary_path, mustWork = TRUE), package_path) ||
          !within_package(normalizePath(package$product_manifest_path, mustWork = TRUE), package_path) ||
          !identical(production_release_sha256(package$summary_path), tolower(package$summary_sha256)) ||
          !identical(production_release_sha256(package$product_manifest_path), tolower(package$product_manifest_sha256))) {
        stop("Accepted package metadata is missing, outside its canonical package, or has changed.", call. = FALSE)
      }
    }
  }
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
  if (identical(as.integer(validated$manifest$schema_version), 2L) &&
      !identical(as.character(validated$manifest$release$accepted_package$status), "ACCEPTED")) {
    stop("A versioned release must reference an accepted package under postfit_acceptance before activation.", call. = FALSE)
  }
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
