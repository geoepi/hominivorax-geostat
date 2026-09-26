repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

cfg <- list(
  study = list(projected_crs = "EPSG:3857", start_date = "2024-01-01", end_date = "2024-01-31"),
  tier1 = list(positive_cellweek_thinning = list(enabled = TRUE, seed = 1976L))
)
template <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20, ymin = 0, ymax = 20, crs = "EPSG:3857")
terra::values(template) <- 1
template_path <- tempfile(fileext = ".tif")
terra::writeRaster(template, template_path, overwrite = TRUE)

tier1 <- data.frame(
  x = c(1, 2, 1, 15, 100, 0, 10),
  y = c(1, 2, 1, 15, 100, 0, 10),
  epiyear = c(2024L, 2024L, 2024L, 2024L, 2024L, 2024L, 2024L),
  epiweek = c(1L, 1L, 1L, 1L, 1L, 1L, 1L),
  Yi = c(1L, 1L, 1L, 1L, 1L, 0L, 0L)
)

enabled <- thin_tier1(tier1, cfg, template, template_path)
stopifnot(
  enabled$audit$enabled,
  enabled$audit$seed == 1976L,
  enabled$audit$input_positive_count == 5L,
  enabled$audit$retained_positive_count == 2L,
  enabled$audit$excluded_positive_count == 3L,
  enabled$audit$positive_outside_template_count == 1L,
  enabled$audit$duplicate_positive_cellweek_groups == 1L,
  enabled$audit$duplicate_positive_cellweek_rows == 2L,
  enabled$audit$final_tier1_response_active_count == nrow(enabled$retained),
  nrow(enabled$retained[enabled$retained$Yi == 0L, , drop = FALSE]) == 2L,
  nrow(enabled$excluded) == 3L,
  !is.na(enabled$audit$template_sha256)
)

repeat_enabled <- thin_tier1(tier1, cfg, template, template_path)
stopifnot(identical(enabled$retained$.tier1_row_id, repeat_enabled$retained$.tier1_row_id))

disabled_cfg <- cfg
disabled_cfg$tier1$positive_cellweek_thinning$enabled <- FALSE
disabled <- thin_tier1(tier1, disabled_cfg, template, template_path)
stopifnot(
  !disabled$audit$enabled,
  disabled$audit$retained_positive_count == 5L,
  disabled$audit$excluded_positive_count == 0L,
  nrow(disabled$retained) == nrow(tier1),
  identical(disabled$retained$Yi, tier1$Yi)
)

seed_cfg <- cfg
seed_cfg$tier1$positive_cellweek_thinning$seed <- 1977L
seed_changed <- thin_tier1(tier1, seed_cfg, template, template_path)
stopifnot(
  all(seed_changed$retained$Yi == 0L | !is.na(seed_changed$retained$cell_id)),
  nrow(seed_changed$excluded[seed_changed$excluded$Yi == 1L, , drop = FALSE]) == 3L,
  !identical(seed_changed$retained$.tier1_row_id, enabled$retained$.tier1_row_id)
)

auto_cfg <- list(
  study = list(start_date = "2024-01-01", end_date = "2024-12-31"),
  temporal = list(start_week = NULL, end_week = "auto_last_complete_observation_week")
)
observations <- data.frame(
  date = as.Date(c("2024-01-01", "2024-01-07", "2024-01-15")),
  epiyear = c(2024L, 2024L, 2024L), epiweek = c(1L, 1L, 3L),
  time_index = c(1L, 1L, 3L)
)
prepared_cfg <- preprocessing_prepare_input_temporal_domain(observations, auto_cfg)
resolved <- preprocessing_resolve_cleaned_temporal_domain(observations, prepared_cfg)
stopifnot(
  identical(resolved$provenance$last_complete_epiweek, "2024-W02"),
  identical(resolved$provenance$current_modeled_final_epiweek, "2025-W01"),
  identical(resolved$provenance$initial_input_endpoint, "2024-W03"),
  resolved$provenance$cleaned_maximum_date == "2024-01-15",
  resolved$provenance$eligible_observations_after_current_endpoint == 1L,
  nrow(resolved$time_index) == 2L,
  nrow(resolved$excluded) == 1L,
  resolved$excluded$exclusion_reason == "after_auto_last_complete_observation_week",
  all(resolved$data$time_index == 1L)
)

cat("Temporal-horizon and Tier 1 thinning regression tests passed\n")
