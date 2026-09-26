joint_inla_hash_file <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) digest::digest(file = path, algo = "sha256") else NA_character_
}

validate_joint_inla_input <- function(joint_inputs) {
  required <- c("tier1", "tier2", "prediction_grid", "mesh", "spatial_support")
  missing <- setdiff(required, names(joint_inputs))
  if (length(missing)) stop("Stage 2 artifact is missing required sections: ", paste(missing, collapse = ", "))
  if (!is.data.frame(joint_inputs$tier1) || !is.data.frame(joint_inputs$tier2) || !is.data.frame(joint_inputs$prediction_grid)) stop("Stage 2 tier sections must be data frames.")
  require_columns(joint_inputs$tier1, c("x", "y", "quarter_index", "response_training", "admin_f"), "Stage 2 Tier 1")
  require_columns(joint_inputs$tier2, c("x", "y", "quarter_index", "response_training"), "Stage 2 Tier 2")
  require_columns(joint_inputs$prediction_grid, c("x", "y", "quarter_index"), "Stage 2 prediction grid")
  if (!isTRUE(inherits(joint_inputs$mesh, "inla.mesh"))) stop("Stage 2 mesh is not an INLA mesh object.")
  invisible(TRUE)
}

joint_group_audit <- function(tier1, tier2, grouping_variable) {
  values1 <- as.integer(tier1[[grouping_variable]])
  values2 <- as.integer(tier2[[grouping_variable]])
  all_values <- sort(unique(c(values1, values2)))
  if (anyNA(all_values) || !identical(all_values, seq_len(max(all_values)))) stop("Temporal groups must be positive contiguous integers shared by both tiers.")
  if (!identical(sort(unique(values1)), sort(unique(values2)))) stop("Tier 1 and Tier 2 quarter groups are not compatible.")
  list(n_groups = max(all_values), groups = all_values)
}

joint_prediction_compatibility <- function(prediction_grid, mapping, grouping_variable, expected_groups) {
  required <- c("x", "y", grouping_variable, unname(mapping$tier1), unname(mapping$tier2))
  missing <- setdiff(required, names(prediction_grid))
  if (length(missing)) stop("Prediction grid is missing eventual model predictors: ", paste(missing, collapse = ", "))
  group_values <- as.integer(prediction_grid[[grouping_variable]])
  if (any(!is.na(group_values) & (group_values < 1L | group_values > expected_groups))) stop("Prediction-grid temporal groups are outside the likelihood groups.")
  nonfinite_counts <- vapply(prediction_grid[required], function(x) sum(!is.finite(as.numeric(x))), integer(1L))
  list(
    required_columns = required,
    missing_columns = missing,
    nonfinite_counts = nonfinite_counts,
    groups = sort(unique(group_values[!is.na(group_values)])),
    compatible = !length(missing) && !any(nonfinite_counts > 0L) &&
      identical(sort(unique(group_values[!is.na(group_values)])), seq_len(expected_groups))
  )
}

joint_audit <- function(tier1, tier2, projections, spdes, cfg, predictor_audit, n_groups, exposure, compatibility, priors, nbinomial_default) {
  audit <- data.frame(stage = character(), scope = character(), metric = character(), value = character(), stringsAsFactors = FALSE)
  add <- function(scope, metric, value) data.frame(stage = "Stage 3A assembly", scope = scope, metric = metric, value = as.character(value), stringsAsFactors = FALSE)
  audit <- rbind(audit,
    add("mesh", "vertices", nrow(spdes$tier1$object$mesh$loc)),
    add("temporal", "quarter_groups", n_groups),
    add("tier1", "rows", nrow(tier1)), add("tier1", "active_rows", sum(!is.na(tier1$response_training))),
    add("tier2", "rows", nrow(tier2)), add("tier2", "active_rows", sum(!is.na(tier2$response_training))),
    add("A", "tier1_dimensions", paste(dim(projections$tier1), collapse = " x ")),
    add("A", "tier2_dimensions", paste(dim(projections$tier2), collapse = " x ")),
    add("SPDE", "tier1_n_spde", spdes$tier1$n_spde), add("SPDE", "tier2_n_spde", spdes$tier2$n_spde),
    add("tier1", "admin_unknown_rows", sum(as.character(tier1$admin_u) == "Unk", na.rm = TRUE)),
    add("tier1", "admin_unknown_nodes", length(unique(paste(tier1$x[as.character(tier1$admin_u) == "Unk"], tier1$y[as.character(tier1$admin_u) == "Unk"], sep = "|")))),
    add("tier2", "exposure_min_active", min(exposure[!is.na(tier2$response_training)], na.rm = TRUE)),
    add("tier2", "exposure_median_active", stats::median(exposure[!is.na(tier2$response_training)], na.rm = TRUE)),
    add("tier2", "exposure_max_active", max(exposure[!is.na(tier2$response_training)], na.rm = TRUE)),
    add("likelihood", "family", paste(c("binomial", "nbinomial"), collapse = ",")),
    add("prediction", "prediction_rows", compatibility$rows),
    add("prediction", "prediction_temporal_groups", compatibility$temporal_groups),
    add("prediction", "prediction_compatible", compatibility$compatible),
    add("shared_field", "copy_enabled", cfg$shared_field$enabled),
    add("shared_field", "copy_prior_mean", cfg$shared_field$beta_prior_mean),
    add("shared_field", "copy_prior_precision", cfg$shared_field$beta_prior_precision),
    add("provenance", "R_version", R.version.string),
    add("provenance", "INLA_version", as.character(utils::packageVersion("INLA"))),
    add("likelihood", "nb_default_prior", if (isTRUE(nbinomial_default$available)) nbinomial_default$hyper$theta$prior else NA_character_),
    add("likelihood", "nb_default_initial", if (isTRUE(nbinomial_default$available)) nbinomial_default$hyper$theta$initial else NA_real_),
    add("shared_field", "copy_prior", paste(capture.output(dput(priors$hyper_copy)), collapse = "")),
    add("predictors", "tier1_nonfinite_active", paste(predictor_audit$tier1$active_rows_nonfinite, collapse = ",")),
    add("predictors", "tier2_nonfinite_active", paste(predictor_audit$tier2$active_rows_nonfinite, collapse = ","))
  )
  for (predictor in names(compatibility$nonfinite_counts)) {
    audit <- rbind(audit, add("prediction", paste0("prediction_nonfinite_", predictor), compatibility$nonfinite_counts[[predictor]]))
  }
  audit
}

build_joint_inla_from_inputs <- function(joint_inputs, cfg) {
  require_joint_inla()
  validate_joint_inla_input(joint_inputs)
  validate_joint_inla_config(cfg, require_inputs = FALSE)
  tier1 <- joint_inputs$tier1
  tier2 <- joint_inputs$tier2
  grouping_variable <- cfg$spatial$grouping_variable
  groups <- joint_group_audit(tier1, tier2, grouping_variable)
  mapping <- joint_effect_mapping(tier1, tier2)
  predictor_audit <- list(
    tier1 = validate_joint_effect_columns(tier1, mapping$tier1, !is.na(tier1$response_training), "Stage 2 Tier 1"),
    tier2 = validate_joint_effect_columns(tier2, mapping$tier2, !is.na(tier2$response_training), "Stage 2 Tier 2")
  )
  compatibility <- joint_prediction_compatibility(joint_inputs$prediction_grid, mapping, grouping_variable, groups$n_groups)
  compatibility$rows <- nrow(joint_inputs$prediction_grid)
  compatibility$temporal_groups <- length(compatibility$groups)
  unit_to_m <- joint_mesh_unit_to_m(joint_inputs)
  spdes <- list(
    tier1 = make_joint_spde(joint_inputs$mesh, cfg$spatial$tier1, unit_to_m, "tier1"),
    tier2 = make_joint_spde(joint_inputs$mesh, cfg$spatial$tier2, unit_to_m, "tier2")
  )
  fields <- make_joint_field_indices(spdes$tier1$object, spdes$tier2$object, groups$n_groups)
  projections <- list(
    tier1 = make_joint_projection(joint_inputs$mesh, tier1, grouping_variable),
    tier2 = make_joint_projection(joint_inputs$mesh, tier2, grouping_variable)
  )
  effects <- list(tier1 = make_tier1_effects(tier1, fields, mapping), tier2 = make_tier2_effects(tier2, fields, mapping))
  priors <- make_joint_priors(cfg)
  formula <- make_joint_formula(spdes$tier1$object, spdes$tier2$object, priors, cfg)
  nbinomial_default <- introspect_nbinomial_default()
  stacks <- build_joint_stacks(tier1, tier2, projections, effects)
  exposure <- if ("terrestrial_area_km2" %in% names(tier2)) tier2$terrestrial_area_km2 else tier2$area_km2
  audit <- joint_audit(tier1, tier2, projections, spdes, cfg, predictor_audit, groups$n_groups, exposure, compatibility, priors, nbinomial_default)
  input_path <- cfg$inputs$joint_model_inputs
  list(
    spde = list(tier1 = spdes$tier1$object, tier2 = spdes$tier2$object),
    spde_metadata = list(tier1 = spdes$tier1$parameters, tier2 = spdes$tier2$parameters),
    A = projections, fields = fields, effects = effects, stacks = stacks,
    formula = formula, family = c("binomial", "nbinomial"), priors = priors,
    fit_reference = make_joint_fit_reference(cfg, nbinomial_default),
    effect_mapping = mapping, prediction_compatibility = compatibility,
    build_audit = audit, config = cfg,
    provenance = list(stage = "joint_inla_assembly", source_artifact = input_path,
                      source_artifact_sha256 = if (file.exists(input_path)) joint_inla_hash_file(input_path) else NA_character_,
                      R = R.version.string, INLA = as.character(utils::packageVersion("INLA")),
                      executed_fit = FALSE)
  )
}

run_joint_inla_build <- function(config_path, repo_root, output_override = NULL, write_outputs = TRUE) {
  cfg <- read_joint_inla_config(config_path, repo_root)
  validate_joint_inla_config(cfg)
  output_path <- NULL
  if (!is.null(output_override) && length(output_override)) {
    override <- resolve_joint_inla_path(output_override, cfg$repo_root)
    if (grepl("\\.rds$", override, ignore.case = TRUE)) {
      output_path <- override
      cfg$project$output_directory <- dirname(override)
    } else {
      cfg$project$output_directory <- override
    }
  }
  joint_inputs <- readRDS(cfg$inputs$joint_model_inputs)
  build <- build_joint_inla_from_inputs(joint_inputs, cfg)
  if (is.null(output_path)) output_path <- resolve_joint_inla_path(cfg$outputs$build, cfg$project$output_directory)
  audit_path <- resolve_joint_inla_path(cfg$outputs$audit, cfg$project$output_directory)
  if (isTRUE(write_outputs)) {
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
    dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(build, output_path)
    write.csv(build$build_audit, audit_path, row.names = FALSE)
  }
  message("Joint-INLA Stage 3A assembly complete:\n", "  Tier 1 rows: ", nrow(joint_inputs$tier1), "\n", "  Tier 2 rows: ", nrow(joint_inputs$tier2), "\n", "  Quarter groups: ", max(joint_inputs$tier1$quarter_index), "\n", "  INLA fit executed: FALSE\n", "  Output: ", output_path)
  build
}
