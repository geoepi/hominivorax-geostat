run_preprocessing <- function(config_path, repo_root = normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE), write_outputs = TRUE) {
  cfg <- read_preprocessing_config(config_path, repo_root)
  validate_preprocessing_config(cfg)
  dir.create(cfg$project$output_directory, recursive = TRUE, showWarnings = FALSE)
  boundary <- sf::st_read(cfg$inputs$study_boundary, quiet = TRUE)
  admin_geometry <- if (identical(cfg$inputs$admin_boundary, cfg$inputs$study_boundary)) {
    boundary
  } else {
    sf::st_read(cfg$inputs$admin_boundary, quiet = TRUE)
  }
  admin_geometry <- sf::st_transform(sf::st_make_valid(admin_geometry), cfg$study$projected_crs)
  analysis_domain <- build_analysis_domain(boundary, cfg)
  observation_identity <- if (!is.null(cfg$covariate_registry)) {
    verify_observation_source_identity(
      path = cfg$inputs$observations,
      expected_sha256 = cfg$covariate_registry$observations$sha256,
      manifest_observation_path = cfg$covariate_registry$observations$path,
      manifest_path = cfg$covariate_registry$manifest_path,
      manifest_identity = covariate_registry_manifest_identity(cfg$covariate_registry)
    )
  } else {
    NULL
  }
  observation_sha256_before <- if (is.null(observation_identity)) NA_character_ else observation_identity$observed_sha256
  observation_expected_sha256 <- if (is.null(observation_identity)) NA_character_ else observation_identity$expected_sha256
  observations <- read_observations(cfg$inputs$observations)
  observation_sha256_after <- if (!is.null(cfg$covariate_registry)) covariate_registry_sha256(cfg$inputs$observations) else NA_character_
  if (!is.na(observation_sha256_before) && !identical(observation_sha256_before, observation_sha256_after)) {
    covariate_registry_observation_gate_error(
      "OBSERVATION_SOURCE_CHANGED_DURING_READ", cfg$inputs$observations,
      observation_expected_sha256,
      paste0(observation_sha256_before, " -> ", observation_sha256_after),
      cfg$covariate_registry$manifest_path,
      covariate_registry_manifest_identity(cfg$covariate_registry),
      "The source checksum changed across the observation read; processing stopped."
    )
  }
  cfg$source_integrity <- list(
    classification = if (is.null(observation_identity)) NA_character_ else observation_identity$classification,
    resolved_source_path = if (is.null(observation_identity)) NA_character_ else observation_identity$resolved_source_path,
    manifest_path = if (is.null(observation_identity)) NA_character_ else observation_identity$manifest_path,
    manifest_identity = if (is.null(observation_identity)) NA_character_ else observation_identity$manifest_identity,
    observation_expected_sha256 = observation_expected_sha256,
    observation_sha256_before_read = observation_sha256_before,
    observation_sha256_after_read = observation_sha256_after,
    observation_checksum_verified = !is.na(observation_expected_sha256) && identical(observation_sha256_before, observation_expected_sha256)
  )
  cfg <- preprocessing_prepare_input_temporal_domain(observations, cfg)
  if (identical(cfg$inputs$observation_mode, "standardized")) {
    cleaned <- preprocess_standardized_observations(observations, boundary, cfg)
  } else {
    host_lookup <- read_host_lookup(file.path(repo_root, "config", "host_lookup.csv"))
    cleaned <- preprocess_observations(observations, boundary, cfg, host_lookup)
  }
  analysis_filter <- filter_observations_to_analysis_domain(cleaned$data, analysis_domain$simplified_domain)
  cleaned$data <- analysis_filter$data
  if (analysis_filter$excluded_count) cleaned$excluded <- dplyr::bind_rows(cleaned$excluded, analysis_filter$excluded)
  cleaned$audit <- dplyr::bind_rows(
    cleaned$audit[cleaned$audit$stage != "retained", , drop = FALSE],
    data.frame(stage = "outside_analysis_domain", count = analysis_filter$excluded_count),
    data.frame(stage = "retained", count = analysis_filter$retained)
  )
  temporal <- preprocessing_resolve_cleaned_temporal_domain(cleaned$data, cfg)
  cfg <- temporal$config
  cleaned$data <- temporal$data
  if (nrow(temporal$excluded)) {
    cleaned$excluded <- dplyr::bind_rows(cleaned$excluded, temporal$excluded)
    cleaned$audit <- dplyr::bind_rows(cleaned$audit, data.frame(
      stage = "after_auto_last_complete_observation_week", count = nrow(temporal$excluded)
    ))
  }
  cleaned$audit <- dplyr::bind_rows(
    cleaned$audit[cleaned$audit$stage != "retained", , drop = FALSE],
    data.frame(stage = "retained", count = nrow(cleaned$data))
  )
  time_index <- temporal$time_index
  support <- build_spatial_support(boundary, cleaned$data, cfg, analysis_domain = analysis_domain)
  tier1_raw <- build_tier1(cleaned$data, support$integration_points, time_index)
  tier2 <- build_tier2(cleaned$data, support, time_index)
  conservation <- validate_detection_conservation(tier1_raw, tier2, nrow(cleaned$data), thinning_enabled = FALSE)
  thinning <- thin_tier1(tier1_raw, cfg, terra::rast(cfg$inputs$template_raster), cfg$inputs$template_raster)
  conservation$tier1_retained_positive <- sum(thinning$retained$Yi == 1L, na.rm = TRUE)
  conservation$excluded_analysis_domain <- analysis_filter$excluded_count
  prediction <- build_prediction_grid(support, time_index, cfg$inputs$template_raster, cfg$study$projected_crs)
  dynamic_specs <- cfg$dynamic_covariates
  dynamic_names <- c(minimum_temperature = "mintemp", soil_moisture = "soilmoist", leaf_area_low = "leafarea", relative_humidity = "rhum", spressure = "spressure")
  mapped_names <- unname(dynamic_names[names(dynamic_specs)])
  mapped_names[is.na(mapped_names)] <- names(dynamic_specs)[is.na(mapped_names)]
  names(dynamic_specs) <- mapped_names
  static_specs <- cfg$static_covariates
  radius_km <- cfg$extraction$search_radius_km
  dynamic_radius_km <- cfg$extraction$dynamic_search_radius_km
  t2_dynamic <- extract_dynamic_covariates(tier2, dynamic_specs, cfg$study$projected_crs, time_index, cfg$transformations$dynamic_missing_policy, dynamic_radius_km, "tier2_dynamic", cfg$project$output_directory)
  pred_dynamic <- extract_dynamic_covariates(prediction, dynamic_specs, cfg$study$projected_crs, time_index, "retain", dynamic_radius_km, "prediction_dynamic")
  t2_static <- extract_static_covariates(t2_dynamic$data, static_specs, cfg$study$projected_crs, radius_km, "tier2_static")
  pred_static <- extract_static_covariates(pred_dynamic$data, static_specs, cfg$study$projected_crs, radius_km, "prediction_static")
  if (!all(c("road_density", "night_illumination") %in% names(static_specs))) {
    stop("Tier 1 requires static covariates named road_density and night_illumination.")
  }
  t1_static <- extract_static_covariates(thinning$retained, static_specs[c("road_density", "night_illumination")], cfg$study$projected_crs, radius_km, "tier1_static")
  tier2 <- join_covariates(t2_dynamic$data, t2_static$data)
  prediction <- join_covariates(pred_dynamic$data, pred_static$data)
  tier1 <- join_covariates(thinning$retained, t1_static$data)
  covariate_audit <- dplyr::bind_rows(t2_dynamic$audit, pred_dynamic$audit, t2_static$audit, pred_static$audit, t1_static$audit)
  covariate_audit <- annotate_covariate_audit(covariate_audit, cfg$covariate_registry)
  tier2 <- apply_missing_policy(tier2, covariate_audit[covariate_audit$scope == "tier2_dynamic" & covariate_audit$variable %in% names(dynamic_specs), ], cfg, required_dynamic = names(dynamic_specs))
  registered_missingness <- covariate_registry_missingness(
    list(tier2 = tier2, prediction_grid = prediction),
    scopes = c("tier2", "prediction_grid"), registry = cfg$covariate_registry
  )
  if (nrow(registered_missingness) && any(registered_missingness$status == "FAIL")) {
    missing_audit_path <- file.path(cfg$project$output_directory, "configuration_c_missingness_audit.csv")
    utils::write.csv(registered_missingness, missing_audit_path, row.names = FALSE)
    failed <- registered_missingness[registered_missingness$status == "FAIL", , drop = FALSE]
    stop("Configuration C required covariates contain missing or non-finite values; audit written to ", missing_audit_path,
         ". Failed scope/variable pairs: ", paste(paste(failed$scope, failed$covariate, sep = "/"), collapse = ", "))
  }
  transformations <- estimate_transformations(tier2, cfg)
  tier1 <- add_legacy_model_fields(apply_transformations(
    tier1, transformations, include_hinge = FALSE, require_registered_covariates = FALSE
  ))
  tier2 <- add_legacy_model_fields(apply_transformations(tier2, transformations, include_hinge = TRUE))
  prediction <- add_legacy_model_fields(apply_transformations(prediction, transformations, include_hinge = TRUE))
  admin_t1 <- annotate_admin_units(tier1, admin_geometry, cfg$inputs$admin_column, "tier1")
  admin_t2 <- annotate_admin_units(tier2, admin_geometry, cfg$inputs$admin_column, "tier2")
  admin_prediction <- annotate_admin_units(prediction, admin_geometry, cfg$inputs$admin_column, "prediction_grid")
  tier1 <- admin_t1$data
  tier2 <- admin_t2$data
  prediction <- admin_prediction$data
  model_inputs <- assemble_model_inputs(tier1, tier2, prediction, support, time_index, transformations, list(observation = cleaned$audit, covariate = covariate_audit, registered_missingness = registered_missingness, thinning = thinning$audit, temporal = temporal$provenance, admin = dplyr::bind_rows(admin_t1$audit, admin_t2$audit, admin_prediction$audit), conservation = conservation), cfg, cleaned$excluded, thinning$excluded)
  if (isTRUE(write_outputs)) {
    saveRDS(model_inputs, file.path(cfg$project$output_directory, cfg$outputs$model_inputs))
    write.csv(cleaned$audit, file.path(cfg$project$output_directory, cfg$outputs$observation_audit), row.names = FALSE)
    write.csv(covariate_audit, file.path(cfg$project$output_directory, cfg$outputs$covariate_audit), row.names = FALSE)
    write.csv(cleaned$excluded, file.path(cfg$project$output_directory, cfg$outputs$excluded_observations), row.names = FALSE)
    write.csv(thinning$excluded, file.path(cfg$project$output_directory, cfg$outputs$excluded_tier1_positives), row.names = FALSE)
  }
  message("Preprocessing complete: ", nrow(tier1), " Tier 1 rows; ", nrow(tier2), " Tier 2 rows; ", nrow(prediction), " prediction rows; ", support$mesh$n, " mesh vertices.")
  model_inputs
}
