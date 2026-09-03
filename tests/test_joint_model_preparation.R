repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)
source(file.path(repo_root, "R", "preprocessing_transformations.R"))

time <- data.frame(epiyear = c(2025L, 2025L, 2025L, 2025L), epiweek = c(30L, 31L, 32L, 33L), time_index = 1:4)
make_tier <- function(tier, response) {
  if (tier == "tier1") {
    data.frame(.row_id = paste0("t", seq_along(response)), source_obs_id = seq_along(response), point_id = seq_along(response), admin_u = rep(c("A", "B"), each = 2), time_index = 1:4, epiyear = 2025L, epiweek = time$epiweek, Yi = response, road_density = 1:4, night_illumination = 4:1)
  } else {
    data.frame(.row_id = paste0("p", rep(1:2, each = 4), "_", rep(1:4, 2)), poly_id = rep(1:2, each = 4), admin_u = rep(c("A", "B"), each = 4), time_index = rep(1:4, 2), epiyear = 2025L, epiweek = rep(time$epiweek, 2), count = response, cattle = rep(c(0, 1, 2, 3), 2), pigs = rep(c(1, 2, 3, 4), 2), sheep = rep(c(2, 3, 4, 5), 2), goats = rep(c(3, 4, 5, 6), 2), horses = rep(c(4, 5, 6, 7), 2))
  }
}
prediction <- data.frame(.row_id = paste0("g", 1:4), admin_u = rep(c("A", "B"), each = 2), time_index = 1:4, epiyear = 2025L, epiweek = time$epiweek, cattle = 0:3, pigs = 1:4, sheep = 2:5, goats = 3:6, horses = 4:7)
model_inputs <- list(
  tier1 = make_tier("tier1", c(1, 1, 1, 0)),
  tier2 = make_tier("tier2", c(1, 0, 0, 0, 1, 1, 0, 0)),
  prediction_grid = prediction,
  mesh = list(n = 1L), mesh_polygons = data.frame(poly_id = 1L), time_index = time,
  spatial_support = list(), preprocessing_metadata = list(stage = "geostatistical_preprocessing")
)
cfg <- joint_model_defaults()
cfg$reporting_censoring$cutoff_epiyear <- 2025L
cfg$reporting_censoring$cutoff_epiweek <- 32L
cfg$holdout$tier1$positive_fraction <- 0
cfg$holdout$tier2$positive_fraction <- 0
prepared <- prepare_joint_model_inputs(model_inputs, cfg)

transformation_spec <- list(
  dynamic = list(mintemp = c(center = 10, scale = 2)),
  static = list(road_density = c(impute = 0, center = 1, scale = 1), night_illumination = c(impute = 0, center = 1, scale = 1)),
  northing = c(origin = 0, center = 0, scale = 1), temperature_hinge = 12
)
tier1_subset <- apply_transformations(data.frame(y = 1:2, road_density = 1:2, night_illumination = 2:1), transformation_spec, include_hinge = FALSE)
stopifnot(all(c("road_density_log1p", "night_illumination_log1p", "northing_z") %in% names(tier1_subset)), !any(c("mintemp_z", "soilmoist_z", "cattle_log1p") %in% names(tier1_subset)))
stopifnot(
  all(c("response_observed", "response_censored", "response_training", "is_censored", "is_test_point", "admin_f", "timestep", "timestep_2wk", "week_start", "quarter_index", "sixmo_index", "year_index") %in% names(prepared$tier1)),
  all(prepared$tier1$timestep == prepared$tier1$time_index),
  length(unique(prepared$tier1$admin_f[prepared$tier1$admin_u == "A"])) == 1L,
  unique(prepared$tier1$admin_f[prepared$tier1$admin_u == "A"]) == unique(prepared$tier2$admin_f[prepared$tier2$admin_u == "A"]),
  all(c("temporal_mapping", "admin_mapping", "response_metadata", "holdout_metadata", "feature_metadata", "preparation_audit", "joint_model_config") %in% names(prepared)),
  prepared$holdout_metadata$zero_count_policy == "exclude",
  sum(prepared$tier2$response_observed == 0) == 5L,
  sum(prepared$tier2$response_training == 0, na.rm = TRUE) == 0L
)
stopifnot(!any(vapply(prepared, function(x) inherits(x, c("inla.spde", "inla.stack")), logical(1))))

cat("Joint-model preparation regression tests passed\n")
