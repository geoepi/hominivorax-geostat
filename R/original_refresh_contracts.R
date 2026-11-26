original_refresh_fixed_terms <- function() {
  c("north", "road_dens", "night_illum", "mintemp", "soilmoist", "leafarea", "rhum",
    "mintemp:soilmoist", "mintemp:leafarea", "cattle", "horses", "pigs", "goats", "sheep")
}

original_refresh_fixed_names <- function() {
  c("intercept1", "intercept2", original_refresh_fixed_terms())
}

original_refresh_c1_only_terms <- function() c("clay", "wv0010", "spressure")

original_refresh_assert_identity <- function(identity, joint_model, joint_inla, fit_config) {
  if (!identical(as.character(identity$model$identifier), "ORIGINAL_REFRESH_W44_2026")) {
    stop("Model identifier must be ORIGINAL_REFRESH_W44_2026.")
  }
  if (!identical(as.character(identity$model$specification_revision), "original_joint_inla_v1") ||
      !identical(as.character(identity$model$data_revision), "observations_2026-11-13_through_2026-W44")) {
    stop("Specification and data revision identifiers must remain independently versioned.")
  }
  if (!identical(as.character(identity$model$frozen_specification_reference),
                 "R/joint_inla_spec.R::make_joint_formula with covariate_registry=null") ||
      !identical(as.character(identity$source$original_formula_reference_commit),
                 "4a463bd62727cf33f783a31d9627afdb576a077f")) {
    stop("The refreshed formula must cite the unchanged manifest-free frozen reference.")
  }
  if (!identical(tolower(as.character(identity$source$observation_sha256)),
                 "784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac")) {
    stop("The refreshed model must reference the approved observation release checksum.")
  }
  if (!identical(as.character(identity$source$analysis_end_week), "2026-W44") ||
      !identical(as.character(identity$source$analysis_end_date), "2026-11-01")) {
    stop("The refreshed analysis window must end at 2026-W44 / 2026-11-01.")
  }
  if (!is.null(joint_model$covariate_manifest) || !is.null(joint_inla$covariate_manifest)) {
    stop("The original refresh must use the manifest-free frozen formula, not the C-1 registry.")
  }
  if (!identical(as.character(joint_model$project$output_directory), "outputs/original_refresh_w44_2026/stage2") ||
      !identical(as.character(joint_inla$project$output_directory), "outputs/original_refresh_w44_2026/stage3a") ||
      !identical(as.character(fit_config$project$output_directory), "outputs/original_refresh_w44_2026/stage3b")) {
    stop("All refreshed artifacts must use the isolated ORIGINAL_REFRESH_W44_2026 output tree.")
  }
  if (isTRUE(fit_config$outputs$overwrite)) stop("The refreshed fit configuration must not overwrite existing artifacts.")
  invisible(TRUE)
}

original_refresh_formula_audit <- function(build) {
  expected_fixed <- original_refresh_fixed_names()
  expected_terms <- original_refresh_fixed_terms()
  signature <- build$model_signature
  observed_order <- if (!is.null(signature$fixed_effect_formula_order)) {
    as.character(signature$fixed_effect_formula_order)
  } else character()
  observed_names <- if (!is.null(signature$fixed_effect_names)) as.character(signature$fixed_effect_names) else character()
  checks <- data.frame(
    check = c("fixed_effect_names", "fixed_effect_order", "fixed_effect_count",
              "no_c1_only_terms", "manifest_free_original_formula", "joint_likelihoods",
              "fit_not_executed"),
    status = c(
      if (identical(sort(observed_names), sort(expected_fixed))) "PASS" else "FAIL",
      if (identical(observed_order, expected_fixed)) "PASS" else "FAIL",
      if (length(observed_names) == 16L) "PASS" else "FAIL",
      if (!length(intersect(observed_names, original_refresh_c1_only_terms()))) "PASS" else "FAIL",
      if (is.null(build$covariate_registry) && is.null(build$config$covariate_registry)) "PASS" else "FAIL",
      if (identical(as.character(build$family), c("binomial", "nbinomial"))) "PASS" else "FAIL",
      if (isFALSE(build$provenance$executed_fit)) "PASS" else "FAIL"
    ),
    observed = c(
      paste(observed_names, collapse = ","),
      paste(observed_order, collapse = ","),
      length(observed_names),
      paste(intersect(observed_names, original_refresh_c1_only_terms()), collapse = ","),
      if (is.null(build$covariate_registry) && is.null(build$config$covariate_registry)) "manifest-free" else "registry present",
      paste(as.character(build$family), collapse = ","),
      as.character(build$provenance$executed_fit)
    ),
    expected = c(
      paste(expected_fixed, collapse = ","),
      paste(expected_fixed, collapse = ","),
      "16 including both tier intercepts",
      "none",
      "manifest-free original fixed-effect specification",
      "binomial,nbinomial",
      "FALSE"
    ),
    stringsAsFactors = FALSE
  )
  checks
}

original_refresh_stage1_audit <- function(model_inputs, expected_observation_sha256,
                                          expected_manifest_sha256,
                                          expected_start_week = "2022-W01",
                                          expected_end_week = "2026-W44",
                                          expected_end_date = "2026-11-01") {
  checks <- list()
  add <- function(check, pass, observed, expected, details = "") {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = check, status = if (isTRUE(pass)) "PASS" else "FAIL",
      observed = paste(as.character(observed), collapse = ","),
      expected = as.character(expected), details = details, stringsAsFactors = FALSE
    )
  }
  required <- c("tier1", "tier2", "prediction_grid", "mesh", "spatial_support",
                "time_index", "configuration", "provenance", "preprocessing_metadata")
  missing <- setdiff(required, names(model_inputs))
  add("required_stage1_sections", !length(missing), paste(missing, collapse = ","),
      "all Stage 1 contract sections present")
  if (length(missing)) return(do.call(rbind, checks))
  provenance <- model_inputs$provenance
  add("approved_observation_checksum", identical(tolower(as.character(provenance$observation_expected_sha256)),
      tolower(expected_observation_sha256)) &&
      identical(tolower(as.character(provenance$observation_sha256_before_read)), tolower(expected_observation_sha256)) &&
      identical(tolower(as.character(provenance$observation_sha256_after_read)), tolower(expected_observation_sha256)) &&
      isTRUE(provenance$observation_checksum_verified),
      provenance$observation_sha256_after_read, expected_observation_sha256,
      "Expected, before-read, and after-read checksums match the approved release.")
  manifest_sha <- provenance$covariate_manifest$manifest_sha256
  add("source_manifest_identity", identical(tolower(as.character(manifest_sha)), tolower(expected_manifest_sha256)),
      manifest_sha, expected_manifest_sha256,
      "C-1 source manifest supplied the same approved source bundle; its three added fields are excluded downstream.")
  cfg <- model_inputs$configuration
  configured_start <- cfg$temporal$start_week
  configured_end <- cfg$temporal$resolved_end_week
  configured_date <- cfg$study$end_date
  add("temporal_window", identical(as.character(configured_start), expected_start_week) &&
      identical(as.character(configured_end), expected_end_week) &&
      identical(as.character(configured_date), expected_end_date),
      paste(configured_start, configured_end, configured_date, sep = "/"),
      paste(expected_start_week, expected_end_week, expected_end_date, sep = "/"),
      "The reused Stage 1 artifact has the approved explicit analytical window.")
  add("tier_data", is.data.frame(model_inputs$tier1) && is.data.frame(model_inputs$tier2) &&
      is.data.frame(model_inputs$prediction_grid),
      paste(nrow(model_inputs$tier1), nrow(model_inputs$tier2), nrow(model_inputs$prediction_grid), sep = "/"),
      "data frames for Tier 1, Tier 2, and prediction support")
  expected_t1 <- c("road_density", "night_illumination", "x", "y", "Yi", "sc_Exp")
  expected_t2 <- c("road_density", "night_illumination", "mintemp", "soilmoist",
                   "leafarea", "rhum", "cattle", "horses", "pigs", "goats", "sheep",
                   "x", "y", "count", "area_km2", "terrestrial_area_km2", "sc_Exp")
  miss_t1 <- setdiff(expected_t1, names(model_inputs$tier1))
  miss_t2 <- setdiff(expected_t2, names(model_inputs$tier2))
  add("original_predictor_schema", !length(miss_t1) && !length(miss_t2),
      paste(c(if (length(miss_t1)) paste0("tier1:", paste(miss_t1, collapse = ",")),
              if (length(miss_t2)) paste0("tier2:", paste(miss_t2, collapse = ","))), collapse = ";"),
      "raw inputs required to reconstruct all original predictors and model exposures",
      "C-1-only predictors may remain as unused input columns.")
  coordinate_ok <- all(vapply(list(model_inputs$tier1$x, model_inputs$tier1$y,
      model_inputs$tier2$x, model_inputs$tier2$y, model_inputs$prediction_grid$x,
      model_inputs$prediction_grid$y), function(x) is.numeric(x) && all(is.finite(x)), logical(1L)))
  mesh <- model_inputs$mesh
  mesh_ok <- inherits(mesh, "inla.mesh") && is.matrix(mesh$loc) &&
    nrow(mesh$loc) > 0L && ncol(mesh$loc) >= 2L &&
    all(is.finite(mesh$loc[, 1:2, drop = FALSE]))
  add("coordinate_types_and_geometry", coordinate_ok,
      paste(class(model_inputs$mesh), length(model_inputs$mesh$loc), sep = ";"),
      "finite numeric tier and prediction coordinates plus persisted mesh",
      "The reused artifact retains the established geometry and mesh support.")
  add("persisted_mesh_geometry", mesh_ok,
      if (mesh_ok) paste(nrow(mesh$loc), "vertices") else "mesh class or location matrix is invalid",
      "nonempty inla.mesh location matrix with at least two finite coordinate columns",
      "The original spatial mesh is reused and must be structurally valid.")
  exposure_ok <- all(c("area_km2", "terrestrial_area_km2", "sc_Exp") %in% names(model_inputs$tier2)) &&
    all(is.finite(model_inputs$tier2$area_km2)) &&
    isTRUE(all.equal(as.numeric(model_inputs$tier2$area_km2), as.numeric(model_inputs$tier2$terrestrial_area_km2))) &&
    isTRUE(all.equal(as.numeric(model_inputs$tier2$sc_Exp), as.numeric(model_inputs$tier2$area_km2)))
  add("tier2_exposure_representation", exposure_ok,
      if (exposure_ok) "sc_Exp = area_km2 = terrestrial_area_km2" else "exposure columns missing or inconsistent",
      "consistent terrestrial-area exposure",
      "Exposure values remain unchanged from Stage 1 and are revalidated by Stage 2.")
  transformation_ok <- identical(as.numeric(cfg$transformations$temperature_hinge), 12) &&
    identical(as.character(cfg$transformations$dynamic_missing_policy), "fail") &&
    identical(as.character(cfg$transformations$livestock_missing_policy), "impute_zero")
  add("transformation_contract", transformation_ok,
      paste(cfg$transformations$temperature_hinge, cfg$transformations$dynamic_missing_policy,
            cfg$transformations$livestock_missing_policy, sep = "/"),
      "12/fail/impute_zero",
      "The original temperature hinge and missing-data policies are retained.")
  do.call(rbind, checks)
}
