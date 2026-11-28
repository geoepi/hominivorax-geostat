covariate_registry_sha256 <- function(path) {
  if (!file.exists(path)) stop("Covariate manifest does not exist: ", path)
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }
  executable <- Sys.which("sha256sum")
  if (!nzchar(executable)) stop("A SHA-256 implementation (digest or sha256sum) is required to identify the covariate manifest.")
  output <- system2(executable, args = shQuote(path), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop("Unable to calculate covariate manifest SHA-256: ", paste(output, collapse = " "))
  hash <- strsplit(trimws(output[[1L]]), "\\s+")[[1L]][[1L]]
  if (!grepl("^[[:xdigit:]]{64}$", hash)) stop("sha256sum returned an invalid manifest checksum.")
  tolower(hash)
}

covariate_registry_manifest_identity <- function(registry) {
  value <- function(x) {
    if (is.null(x) || !length(x) || is.na(x[[1L]]) || !nzchar(as.character(x[[1L]]))) return("unknown")
    as.character(x[[1L]])
  }
  paste0(
    "id=", value(registry$configuration$id),
    "; version=", value(registry$configuration$version),
    "; schema=", value(registry$manifest_schema),
    "; manifest_version=", value(registry$manifest_version)
  )
}

covariate_registry_observation_gate_error <- function(classification, resolved_source_path,
                                                      expected_sha256, observed_sha256,
                                                      manifest_path, manifest_identity,
                                                      detail) {
  display <- function(x) {
    if (is.null(x) || !length(x)) return("<unavailable>")
    x <- as.character(x)
    x[is.na(x)] <- "<NA>"
    paste(x, collapse = ",")
  }
  stop(paste0(
    "Observation checksum gate failed [", display(classification), "]: ",
    "resolved source path=", display(resolved_source_path), "; ",
    "expected SHA-256=", display(expected_sha256), "; ",
    "observed SHA-256=", display(observed_sha256), "; ",
    "manifest path=", display(manifest_path), "; ",
    "manifest identity=", display(manifest_identity), "; ",
    display(detail)
  ), call. = FALSE)
}

verify_observation_source_identity <- function(path, expected_sha256,
                                               manifest_observation_path,
                                               manifest_path,
                                               manifest_identity) {
  resolved_path <- if (length(path) == 1L && !is.na(path) && nzchar(as.character(path))) {
    normalizePath(as.character(path), winslash = "/", mustWork = FALSE)
  } else {
    "<missing>"
  }
  registered_path <- if (length(manifest_observation_path) == 1L && !is.na(manifest_observation_path) && nzchar(as.character(manifest_observation_path))) {
    normalizePath(as.character(manifest_observation_path), winslash = "/", mustWork = FALSE)
  } else {
    "<missing>"
  }
  expected_values <- as.character(expected_sha256)
  expected_display <- if (length(expected_values) == 1L) expected_values else paste(expected_values, collapse = ",")
  checksum_is_valid <- length(expected_values) == 1L && !is.na(expected_values) &&
    grepl("^[[:xdigit:]]{64}$", expected_values)
  if (!checksum_is_valid) {
    covariate_registry_observation_gate_error(
      "MALFORMED_MANIFEST_SHA256", resolved_path, expected_display,
      "NOT_COMPUTED", manifest_path, manifest_identity,
      "The manifest observation checksum must be one 64-character hexadecimal SHA-256 value."
    )
  }
  if (!identical(resolved_path, registered_path)) {
    covariate_registry_observation_gate_error(
      "RUNTIME_CONFIGURATION_DEFECT", resolved_path, tolower(expected_values),
      "NOT_COMPUTED", manifest_path, manifest_identity,
      paste0("The resolved observation path differs from the manifest path (manifest source path=", registered_path, ").")
    )
  }
  if (!file.exists(resolved_path) || dir.exists(resolved_path)) {
    covariate_registry_observation_gate_error(
      "MISSING_OBSERVATION_SOURCE", resolved_path, tolower(expected_values),
      "NOT_COMPUTED", manifest_path, manifest_identity,
      "The resolved observation source is not an existing file."
    )
  }
  observed_sha256 <- covariate_registry_sha256(resolved_path)
  expected_sha256 <- tolower(expected_values)
  if (!identical(observed_sha256, expected_sha256)) {
    covariate_registry_observation_gate_error(
      "OBSERVATION_SOURCE_IDENTITY_MISMATCH", resolved_path, expected_sha256,
      observed_sha256, manifest_path, manifest_identity,
      "The source bytes do not match the approved manifest identity; processing stopped."
    )
  }
  list(
    classification = "OBSERVATION_SOURCE_IDENTITY_VERIFIED",
    resolved_source_path = resolved_path,
    expected_sha256 = expected_sha256,
    observed_sha256 = observed_sha256,
    manifest_path = normalizePath(manifest_path, winslash = "/", mustWork = FALSE),
    manifest_identity = manifest_identity
  )
}

validate_covariate_registry <- function(registry, manifest_path = "<unresolved>") {
  if (!is.list(registry) || !identical(registry$manifest_schema, "hominivorax-geostat-configuration-c-input-manifest/v1")) {
    stop("Unsupported Configuration C covariate manifest schema.")
  }
  if (length(registry$manifest_version) != 1L || as.integer(registry$manifest_version) != 1L) {
    stop("Configuration C covariate manifest_version must be 1.")
  }
  if (!identical(registry$configuration$id, "configuration_c")) stop("Covariate manifest must identify configuration_c.")
  if (!identical(registry$configuration$analysis_window$end_epiweek, "2026-W44")) stop("Configuration C analysis endpoint must be 2026-W44.")
  if (!identical(registry$configuration$analysis_window$start_epiweek, "2022-W01")) stop("Configuration C start week must remain 2022-W01.")
  if (!identical(registry$status, "development_specification_not_production_qualified")) stop("Configuration C manifest must remain explicitly unqualified for production.")
  architecture <- registry$configuration$structural_contract
  if (!identical(as.character(architecture$tier1_family), "binomial") || !identical(as.character(architecture$tier2_family), "nbinomial") ||
      !identical(as.character(architecture$tier1_temporal), "rw1") || !identical(as.character(architecture$tier2_temporal), "rw1") ||
      !identical(as.character(architecture$administrative_effect), "iid") || !identical(as.character(architecture$cattle_effect), "rw2")) {
    stop("Configuration C structural contract differs from the approved model architecture.")
  }
  observation <- registry$observations
  manifest_identity <- covariate_registry_manifest_identity(registry)
  if (is.null(observation$path) || length(observation$path) != 1L || is.na(observation$path) || !nzchar(as.character(observation$path))) {
    covariate_registry_observation_gate_error(
      "MALFORMED_MANIFEST_OBSERVATION_PATH", "<missing>", observation$sha256,
      "NOT_COMPUTED", manifest_path, manifest_identity,
      "Configuration C manifest must record one observation source path."
    )
  }
  if (is.null(observation$sha256) || length(observation$sha256) != 1L || is.na(observation$sha256) ||
      !grepl("^[[:xdigit:]]{64}$", as.character(observation$sha256))) {
    covariate_registry_observation_gate_error(
      "MALFORMED_MANIFEST_SHA256", observation$path, observation$sha256,
      "NOT_COMPUTED", manifest_path, manifest_identity,
      "Configuration C manifest must record one 64-character hexadecimal observation SHA-256."
    )
  }
  approved_observation_sha256 <- "784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac"
  superseded_observation_sha256 <- "784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac"
  if (!identical(tolower(as.character(observation$sha256)), approved_observation_sha256)) {
    covariate_registry_observation_gate_error(
      "MANIFEST_SHA256_NOT_APPROVED", observation$path, observation$sha256,
      "NOT_COMPUTED", manifest_path, manifest_identity,
      "Configuration C observation checksum differs from the approved release specification."
    )
  }
  approval <- observation$owner_approval
  approval_valid <- is.list(approval) &&
    identical(as.character(approval$authority), "project_owner") &&
    identical(as.character(approval$approval_date), "2026-11-21") &&
    identical(as.character(approval$configuration), "C-1") &&
    identical(as.character(approval$supersedes_sha256), superseded_observation_sha256) &&
    length(approval$approved_release_identifier) == 1L &&
    nzchar(as.character(approval$approved_release_identifier)) &&
    length(approval$statement) == 1L &&
    grepl("manually inspected and explicitly approved", as.character(approval$statement), fixed = TRUE)
  if (!approval_valid) stop("Configuration C observation release lacks the recorded 2026-11-21 project-owner approval.")
  history <- observation$checksum_history
  history_sha256 <- if (is.list(history)) vapply(history, function(entry) as.character(entry$sha256), character(1L)) else character()
  history_status <- if (is.list(history)) vapply(history, function(entry) as.character(entry$status), character(1L)) else character()
  history_valid <- length(history_sha256) == length(history_status) &&
    any(history_sha256 == superseded_observation_sha256 & history_status == "superseded") &&
    any(history_sha256 == approved_observation_sha256 & history_status == "current_owner_approved")
  if (!history_valid) stop("Configuration C observation checksum history must retain the superseded checksum and current owner-approved checksum.")
  provenance_notes <- observation$provenance_notes
  unverified_duplicate_note <- is.list(provenance_notes) && any(vapply(provenance_notes, function(note) {
    identical(as.character(note$status), "unverified_possible_explanation") &&
      identical(note$verified, FALSE) &&
      grepl("duplicate records", as.character(note$note), ignore.case = TRUE)
  }, logical(1L)))
  if (!unverified_duplicate_note) stop("Configuration C observation provenance must preserve duplicate removal only as an unverified possible explanation.")
  effects <- registry$configuration$fixed_effects
  required_effect_sections <- c("tier1_terms", "tier2_terms", "interaction_terms", "formula_order", "reporting_order", "new_additive_linear_terms")
  if (!all(required_effect_sections %in% names(effects))) stop("Configuration C fixed-effect registry is incomplete.")
  terms <- unlist(effects[c("tier1_terms", "tier2_terms", "interaction_terms")], use.names = FALSE)
  formula_order <- unlist(effects$formula_order, use.names = FALSE)
  if (anyDuplicated(terms) || anyDuplicated(formula_order) || !setequal(terms, formula_order)) {
    stop("Configuration C formula_order must contain each fixed-effect and interaction term exactly once.")
  }
  expected_new <- c("clay", "wv0010", "spressure")
  if (!identical(as.character(unlist(effects$new_additive_linear_terms, use.names = FALSE)), expected_new)) {
    stop("Configuration C must register clay, wv0010, and spressure in the specified order.")
  }
  if (!all(expected_new %in% unlist(effects$tier2_terms, use.names = FALSE))) {
    stop("All Configuration C environmental additions must be Tier 2 fixed effects.")
  }
  report_order <- effects$reporting_order
  expected_tier1 <- c("intercept1", as.character(unlist(effects$tier1_terms, use.names = FALSE)))
  expected_tier2 <- c("intercept2", as.character(unlist(effects$tier2_terms, use.names = FALSE)), as.character(unlist(effects$interaction_terms, use.names = FALSE)))
  if (!setequal(as.character(unlist(report_order$tier1, use.names = FALSE)), expected_tier1) ||
      !setequal(as.character(unlist(report_order$tier2, use.names = FALSE)), expected_tier2) ||
      anyDuplicated(unlist(report_order, use.names = FALSE))) {
    stop("Configuration C reporting order must contain each configured coefficient exactly once in its likelihood tier.")
  }
  covariates <- registry$covariates
  if (!identical(names(covariates), expected_new)) stop("Configuration C covariate registry must contain clay, wv0010, and spressure in order.")
  for (name in expected_new) {
    entry <- covariates[[name]]
    required <- c("model_term", "tier", "input_section", "temporal_support", "source", "transformation", "missing_policy", "reporting_label")
    if (!all(required %in% names(entry))) stop("Covariate registry entry is incomplete: ", name)
    if (!identical(as.character(entry$model_term), name) || !identical(as.character(entry$tier), "tier2")) stop("Invalid model term or tier for registered covariate: ", name)
    if (!identical(as.character(entry$transformation$method), "identity") || !identical(as.character(entry$transformation$output_column), name)) {
      stop("Configuration C environmental covariates must use an identity transformation into their named input column: ", name)
    }
    if (!identical(as.character(entry$missing_policy), "fail")) stop("Configuration C registered covariates must fail on missing required values: ", name)
    if (is.null(entry$source$path) || !nzchar(as.character(entry$source$path))) stop("Source path is missing for registered covariate: ", name)
    if (name != "spressure" && !grepl("^[[:xdigit:]]{64}$", as.character(entry$source$sha256))) stop("Source SHA-256 is invalid for registered covariate: ", name)
    if (!nzchar(as.character(entry$reporting_label))) stop("Reporting label is missing for registered covariate: ", name)
  }
  if (!identical(as.character(covariates$clay$input_section), "static_covariates") ||
      !identical(as.character(covariates$wv0010$input_section), "static_covariates") ||
      !identical(as.character(covariates$spressure$input_section), "dynamic_covariates")) {
    stop("Configuration C source sections do not match the static/weekly environmental schema.")
  }
  pressure <- covariates$spressure$source
  if (!identical(as.character(pressure$source_units), "Pa") || !identical(as.character(pressure$processed_value_units), "kPa") ||
      !identical(as.character(pressure$source_conversion), "divide_by_1000") ||
      !identical(as.character(pressure$coverage$first_week), "2022-W01") || !identical(as.character(pressure$coverage$last_week), "2026-W44") ||
      as.integer(pressure$coverage$missing_weeks) != 0L || as.integer(pressure$coverage$duplicate_weeks) != 0L) {
    stop("Configuration C pressure units or verified weekly coverage do not match the approved manifest.")
  }
  invisible(TRUE)
}

read_covariate_registry <- function(path, repo_root = getwd()) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) return(NULL)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to read the covariate manifest.")
  resolved <- if (grepl("^[A-Za-z]:[/\\\\]|^/", as.character(path[[1L]]))) {
    normalizePath(path[[1L]], mustWork = FALSE)
  } else {
    file.path(repo_root, as.character(path[[1L]]))
  }
  if (!file.exists(resolved)) stop("Covariate manifest does not exist: ", resolved)
  registry <- yaml::read_yaml(resolved)
  validate_covariate_registry(registry, manifest_path = resolved)
  registry$manifest_path <- normalizePath(resolved, mustWork = TRUE)
  registry$manifest_sha256 <- covariate_registry_sha256(resolved)
  registry
}

covariate_registry_signature <- function(registry) {
  if (is.null(registry)) return(NULL)
  manifest_path <- registry$manifest_path
  manifest_sha256 <- registry$manifest_sha256
  if (is.null(manifest_path)) manifest_path <- NA_character_
  if (is.null(manifest_sha256)) manifest_sha256 <- NA_character_
  list(
    id = registry$configuration$id,
    version = registry$configuration$version,
    manifest_path = manifest_path,
    manifest_sha256 = manifest_sha256,
    analysis_end_epiweek = registry$configuration$analysis_window$end_epiweek
  )
}

covariate_registry_missingness <- function(data, scopes, registry) {
  if (is.null(registry)) return(data.frame())
  rows <- list()
  i <- 0L
  for (name in names(registry$covariates)) {
    entry <- registry$covariates[[name]]
    column <- as.character(entry$transformation$output_column)
    for (scope in scopes) {
      frame <- data[[scope]]
      if (!is.data.frame(frame)) stop("Missing covariate validation scope: ", scope)
      if (!column %in% names(frame)) stop(scope, " lacks registered Configuration C covariate column: ", column)
      values <- suppressWarnings(as.numeric(frame[[column]]))
      missing <- sum(!is.finite(values))
      i <- i + 1L
      rows[[i]] <- data.frame(
        scope = scope,
        covariate = name,
        data_column = column,
        rows = nrow(frame),
        missing_or_nonfinite = missing,
        policy = as.character(entry$missing_policy),
        status = if (missing == 0L) "PASS" else if (identical(entry$missing_policy, "fail")) "FAIL" else "WARN",
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

annotate_covariate_audit <- function(audit, registry) {
  if (is.null(registry) || !nrow(audit)) return(audit)
  lookup <- registry$covariates
  audit$registry_version <- registry$configuration$version
  audit$source_units <- NA_character_
  audit$stored_units <- NA_character_
  audit$transformation <- NA_character_
  audit$temporal_support <- NA_character_
  audit$missing_policy <- NA_character_
  audit$source_path <- NA_character_
  audit$source_sha256 <- NA_character_
  for (name in names(lookup)) {
    entry <- lookup[[name]]
    rows <- audit$variable == name
    source_units <- entry$source$physical_units
    if (is.null(source_units)) source_units <- entry$source$source_units
    if (is.null(source_units)) source_units <- NA_character_
    stored_units <- entry$source$stored_mapped_units
    if (is.null(stored_units)) stored_units <- entry$source$processed_value_units
    if (is.null(stored_units)) stored_units <- NA_character_
    source_sha256 <- entry$source$sha256
    if (is.null(source_sha256)) source_sha256 <- NA_character_
    audit$source_units[rows] <- as.character(source_units)
    audit$stored_units[rows] <- as.character(stored_units)
    audit$transformation[rows] <- as.character(entry$transformation$method)
    audit$temporal_support[rows] <- as.character(entry$temporal_support)
    audit$missing_policy[rows] <- as.character(entry$missing_policy)
    audit$source_path[rows] <- as.character(entry$source$path)
    audit$source_sha256[rows] <- as.character(source_sha256)
  }
  audit
}
