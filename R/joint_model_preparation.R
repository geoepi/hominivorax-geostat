iso_week_start <- function(epiyear, epiweek) {
  jan4 <- as.Date(sprintf("%04d-01-04", as.integer(epiyear)))
  monday_offset <- as.integer(format(jan4, "%u")) - 1L
  jan4 - monday_offset + 7L * (as.integer(epiweek) - 1L)
}

derive_temporal_mapping <- function(time_index, cfg) {
  require_columns(time_index, c("epiyear", "epiweek", "time_index"), "Stage 1 time_index")
  mapping <- unique(time_index[c("epiyear", "epiweek", "time_index")])
  if (anyDuplicated(mapping[c("epiyear", "epiweek")])) stop("Stage 1 time_index has duplicated year-week keys.")
  if (anyDuplicated(mapping$time_index)) stop("Stage 1 time_index has duplicated time_index values.")
  mapping <- mapping[order(mapping$time_index), , drop = FALSE]
  mapping$week_start <- iso_week_start(mapping$epiyear, mapping$epiweek)
  mapping$timestep <- mapping$time_index
  mapping$timestep_2wk <- (mapping$timestep + 1L) %/% 2L
  earliest <- min(mapping$week_start)
  month_diff <- (as.integer(format(mapping$week_start, "%Y")) - as.integer(format(earliest, "%Y"))) * 12L + as.integer(format(mapping$week_start, "%m")) - as.integer(format(earliest, "%m"))
  mapping$quarter_index <- floor(month_diff / 3L) + 1L
  mapping$sixmo_index <- floor(month_diff / 6L) + 1L
  years <- sort(unique(as.integer(format(mapping$week_start, "%Y"))))
  mapping$year_index <- match(as.integer(format(mapping$week_start, "%Y")), years)
  mapping
}

apply_temporal_mapping <- function(data, mapping, cfg, scope) {
  require_columns(data, c("epiyear", "epiweek", "time_index"), paste0(scope, " temporal data"))
  key <- paste(data$epiyear, data$epiweek, sep = "|")
  mapping_key <- paste(mapping$epiyear, mapping$epiweek, sep = "|")
  index <- match(key, mapping_key)
  if (anyNA(index)) stop(scope, " contains a year-week absent from the Stage 1 temporal mapping.")
  if (any(data$time_index != mapping$time_index[index])) stop(scope, " time_index disagrees with Stage 1 time_index.")
  out <- data
  out$week_start <- mapping$week_start[index]
  out$timestep <- mapping$timestep[index]
  if (isTRUE(cfg$temporal$derive_two_week_index)) out$timestep_2wk <- mapping$timestep_2wk[index]
  if (isTRUE(cfg$temporal$derive_quarter_index)) out$quarter_index <- mapping$quarter_index[index]
  if (isTRUE(cfg$temporal$derive_six_month_index)) out$sixmo_index <- mapping$sixmo_index[index]
  if (isTRUE(cfg$temporal$derive_year_index)) out$year_index <- mapping$year_index[index]
  out
}

make_admin_mapping <- function(tier1, tier2, prediction_grid) {
  values <- c(as.character(tier1$admin_u), as.character(tier2$admin_u), as.character(prediction_grid$admin_u))
  values[is.na(values) | !nzchar(values)] <- "Unk"
  units <- sort(unique(values))
  if ("Unk" %in% units) units <- c(setdiff(units, "Unk"), "Unk")
  data.frame(admin_u = units, admin_f = seq_along(units), stringsAsFactors = FALSE)
}

apply_admin_mapping <- function(data, mapping, scope) {
  require_columns(data, "admin_u", paste0(scope, " administrative data"))
  out <- data
  out$admin_u <- as.character(out$admin_u)
  out$admin_u[is.na(out$admin_u) | !nzchar(out$admin_u)] <- "Unk"
  out$admin_f <- mapping$admin_f[match(out$admin_u, mapping$admin_u)]
  if (anyNA(out$admin_f)) stop(scope, " contains an administrative unit absent from admin_mapping.")
  out
}

audit_rows <- function(stage, scope, metric, value) {
  data.frame(stage = stage, scope = scope, metric = metric, value = as.character(value), stringsAsFactors = FALSE)
}

prepare_joint_model_inputs <- function(model_inputs, cfg) {
  validate_joint_model_input_contract(model_inputs)
  temporal_mapping <- derive_temporal_mapping(model_inputs$time_index, cfg)
  tier1 <- apply_temporal_mapping(model_inputs$tier1, temporal_mapping, cfg, "tier1")
  tier2 <- apply_temporal_mapping(model_inputs$tier2, temporal_mapping, cfg, "tier2")
  prediction_grid <- apply_temporal_mapping(model_inputs$prediction_grid, temporal_mapping, cfg, "prediction_grid")

  censored <- apply_reporting_censoring(tier1, tier2, cfg)
  tier1 <- censored$tier1
  tier2 <- censored$tier2
  holdout1 <- select_response_holdouts(tier1, "tier1", cfg$holdout$tier1$enabled, as.numeric(cfg$holdout$tier1$positive_fraction), cfg$holdout$seed)
  holdout2 <- select_response_holdouts(tier2, "tier2", cfg$holdout$tier2$enabled, as.numeric(cfg$holdout$tier2$positive_fraction), cfg$holdout$seed)
  tier1 <- holdout1$data
  tier2 <- holdout2$data
  zero <- apply_zero_count_policy(tier2, cfg$tier2$zero_count_policy)
  tier2 <- zero$data

  admin_mapping <- make_admin_mapping(tier1, tier2, prediction_grid)
  tier1 <- apply_admin_mapping(tier1, admin_mapping, "tier1")
  tier2 <- apply_admin_mapping(tier2, admin_mapping, "tier2")
  prediction_grid <- apply_admin_mapping(prediction_grid, admin_mapping, "prediction_grid")
  features <- add_livestock_rw2_features(tier2, prediction_grid, cfg)
  tier2 <- features$tier2
  prediction_grid <- features$prediction_grid

  audit <- dplyr::bind_rows(
    audit_rows("Stage 1 input", "tier1", "rows", nrow(model_inputs$tier1)),
    audit_rows("Stage 1 input", "tier2", "rows", nrow(model_inputs$tier2)),
    audit_rows("Stage 1 input", "prediction_grid", "rows", nrow(model_inputs$prediction_grid)),
    audit_rows("Stage 1 interface", "tier1", "admin_unknown_rows", sum(tier1$admin_u == "Unk")),
    audit_rows("Stage 1 interface", "tier2", "admin_unknown_rows", sum(tier2$admin_u == "Unk")),
    audit_rows("Stage 1 interface", "prediction_grid", "admin_unknown_rows", sum(prediction_grid$admin_u == "Unk")),
    audit_rows("response", "tier1", "reporting_censored_rows", sum(tier1$is_censored)),
    audit_rows("response", "tier2", "reporting_censored_rows", sum(tier2$is_censored)),
    audit_rows("response", "all", "affected_admin_units", length(censored$metadata$affected_admin_units)),
    audit_rows("holdout", "tier1", "eligible_positive_holdouts", holdout1$metadata$eligible_count),
    audit_rows("holdout", "tier1", "selected_positive_holdouts", holdout1$metadata$selected_count),
    audit_rows("holdout", "tier2", "eligible_positive_holdouts", holdout2$metadata$eligible_count),
    audit_rows("holdout", "tier2", "selected_positive_holdouts", holdout2$metadata$selected_count),
    audit_rows("response", "tier2", "zero_responses", zero$zero_count),
    audit_rows("response", "tier2", "zeros_excluded_from_training", zero$excluded_count),
    audit_rows("temporal", "all", "temporal_steps", nrow(temporal_mapping)),
    audit_rows("temporal", "all", "two_week_steps", length(unique(temporal_mapping$timestep_2wk))),
    audit_rows("temporal", "all", "quarter_steps", length(unique(temporal_mapping$quarter_index))),
    audit_rows("temporal", "all", "six_month_steps", length(unique(temporal_mapping$sixmo_index))),
    audit_rows("temporal", "all", "year_steps", length(unique(temporal_mapping$year_index)))
  )
  if (isTRUE(features$metadata$enabled)) {
    for (variable in names(features$metadata$specifications)) {
      specification <- features$metadata$specifications[[variable]]
      audit <- dplyr::bind_rows(audit,
        audit_rows("livestock_rw2", variable, "requested_bins", specification$requested_bins),
        audit_rows("livestock_rw2", variable, "effective_bins", specification$effective_bins)
      )
    }
  }

  list(
    tier1 = tier1,
    tier2 = tier2,
    prediction_grid = prediction_grid,
    mesh = model_inputs$mesh,
    mesh_polygons = model_inputs$mesh_polygons,
    time_index = model_inputs$time_index,
    transformations = model_inputs$transformations,
    temporal_mapping = temporal_mapping,
    admin_mapping = admin_mapping,
    response_metadata = censored$metadata,
    holdout_metadata = list(tier1 = holdout1$metadata, tier2 = holdout2$metadata, zero_count_policy = cfg$tier2$zero_count_policy),
    feature_metadata = features$metadata,
    spatial_support = model_inputs$spatial_support,
    preprocessing_metadata = model_inputs$preprocessing_metadata %||% list(),
    joint_model_config = cfg,
    preparation_audit = audit,
    provenance = list(stage = "joint_model_preparation", source_model_inputs = cfg$inputs$model_inputs, R = R.version.string)
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

run_joint_model_preparation <- function(config_path, repo_root = normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE), output_override = NULL, write_outputs = TRUE) {
  cfg <- read_joint_model_config(config_path, repo_root)
  validate_joint_model_config(cfg)
  output_path <- NULL
  if (!is.null(output_override) && length(output_override)) {
    override <- resolve_joint_model_path(output_override, repo_root)
    if (grepl("\\.rds$", override, ignore.case = TRUE)) {
      output_path <- override
      cfg$project$output_directory <- dirname(override)
    } else {
      cfg$project$output_directory <- override
    }
  }
  output_path <- output_path %||% resolve_joint_model_path(cfg$outputs$joint_model_inputs, cfg$project$output_directory)
  if (!grepl("^[A-Za-z]:[/\\\\]|^/", output_path)) output_path <- file.path(cfg$project$output_directory, cfg$outputs$joint_model_inputs)
  audit_path <- resolve_joint_model_path(cfg$outputs$preparation_audit, cfg$project$output_directory)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
  model_inputs <- readRDS(cfg$inputs$model_inputs)
  prepared <- prepare_joint_model_inputs(model_inputs, cfg)
  if (isTRUE(write_outputs)) {
    saveRDS(prepared, output_path)
    write.csv(prepared$preparation_audit, audit_path, row.names = FALSE)
  }
  message("Joint model preparation complete:\n", "  Tier 1 rows: ", nrow(prepared$tier1), "\n", "  Tier 2 rows: ", nrow(prepared$tier2), "\n", "  Prediction rows: ", nrow(prepared$prediction_grid), "\n", "  Censored administrations: ", length(prepared$response_metadata$affected_admin_units), "\n", "  Tier 1 holdouts: ", prepared$holdout_metadata$tier1$selected_count, "\n", "  Tier 2 holdouts: ", prepared$holdout_metadata$tier2$selected_count, "\n", "  Tier 2 zero-count policy: ", cfg$tier2$zero_count_policy, "\n", "  Output: ", output_path)
  prepared
}
