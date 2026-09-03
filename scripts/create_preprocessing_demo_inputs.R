create_preprocessing_demo_inputs <- function(repo_root, config_path) {
  if (!requireNamespace("terra", quietly = TRUE)) stop("terra is required to create demo fixtures.")
  if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml is required to create demo fixtures.")
  demo_root <- file.path(repo_root, "demo", "preprocessing")
  dir.create(demo_root, recursive = TRUE, showWarnings = FALSE)
  crs <- "EPSG:3857"
  extent <- terra::ext(-5000, 5000, -5000, 5000)
  template <- terra::rast(nrows = 20, ncols = 20, ext = extent, crs = crs)
  terra::values(template) <- 1
  template_path <- file.path(demo_root, "template.tif")
  terra::writeRaster(template, template_path, overwrite = TRUE)
  boundary <- sf::st_as_sf(sf::st_sfc(sf::st_polygon(list(rbind(c(-5000, -5000), c(5000, -5000), c(5000, 5000), c(-5000, 5000), c(-5000, -5000)))), crs = crs))
  boundary_path <- file.path(demo_root, "boundary.gpkg")
  sf::st_write(boundary, boundary_path, quiet = TRUE, delete_dsn = TRUE)
  set.seed(1976)
  projected_points <- data.frame(x = runif(35, -4500, 4500), y = runif(35, -4500, 4500))
  point_sf <- sf::st_as_sf(projected_points, coords = c("x", "y"), crs = crs)
  lonlat <- sf::st_coordinates(sf::st_transform(point_sf, 4326))
  observations <- data.frame(date = as.Date("2022-01-01") + sample(0:80, 35, replace = TRUE), lon = lonlat[, 1], lat = lonlat[, 2], host = sample(c("bovine", "equine", "unknown", "bovino-equino"), 35, replace = TRUE))
  observations <- rbind(observations, observations[1, ], observations[2, ])
  observations$date[nrow(observations)] <- as.Date("2021-01-01")
  observation_path <- file.path(demo_root, "observations.csv")
  readr::write_csv(observations, observation_path)
  static_dir <- file.path(demo_root, "static")
  dir.create(static_dir, showWarnings = FALSE)
  static_names <- c("cattle", "horses", "pigs", "sheep", "goats", "road_density", "night_illumination")
  for (i in seq_along(static_names)) {
    r <- template
    terra::values(r) <- as.numeric(terra::rowColFromCell(r, seq_len(terra::ncell(r)))[, 1]) + i * as.numeric(terra::rowColFromCell(r, seq_len(terra::ncell(r)))[, 2])
    terra::writeRaster(r, file.path(static_dir, paste0(static_names[i], ".tif")), overwrite = TRUE)
  }
  time <- make_week_index("2022-01-01", "2022-03-31")
  dynamic_names <- c("minimum_temperature", "soil_moisture", "leaf_area_low", "relative_humidity")
  dynamic_dirs <- setNames(file.path(demo_root, dynamic_names), dynamic_names)
  for (nm in dynamic_names) {
    dir.create(dynamic_dirs[[nm]], showWarnings = FALSE)
    for (i in seq_len(nrow(time))) {
      r <- template
      xy <- terra::crds(r, df = TRUE)
      terra::values(r) <- i + xy$x / 10000 + xy$y / 10000
      if (i == 1 && nm == "soil_moisture") terra::values(r)[1] <- NA_real_
      terra::writeRaster(r, file.path(dynamic_dirs[[nm]], sprintf("%s_y%04d_w%02d.tif", nm, time$epiyear[i], time$epiweek[i])), overwrite = TRUE)
    }
  }
  cfg <- list(
    project = list(seed = 1976, output_directory = "outputs/preprocessing_demo"),
    study = list(start_date = "2022-01-01", end_date = "2022-03-31", projected_crs = crs),
    inputs = list(observations = "demo/preprocessing/observations.csv", study_boundary = "demo/preprocessing/boundary.gpkg", template_raster = "demo/preprocessing/template.tif"),
    dynamic_covariates = setNames(file.path("demo/preprocessing", dynamic_names), dynamic_names),
    static_covariates = setNames(file.path("demo/preprocessing/static", paste0(static_names, ".tif")), static_names),
    mesh = list(boundary_buffer_km = 1, use_observation_locations = FALSE, cutoff_km = 0.25, max_edge_km = c(0.5, 2), offset_km = c(1, 2), minimum_angle_degrees = 30, island_area_threshold_km2 = 0),
    extraction = list(search_radius_km = 75, dynamic_search_radius_km = 25),
    transformations = list(temperature_hinge = 12, dynamic_missing_policy = "impute", livestock_missing_policy = "impute_zero"),
    tier1_thinning = list(enabled = TRUE, raster_resolution = 500, seed = 1976),
    outputs = list(model_inputs = "model_inputs.rds", observation_audit = "observation_audit.csv", covariate_audit = "covariate_audit.csv", excluded_observations = "excluded_observations.csv", excluded_tier1_positives = "excluded_tier1_positives.csv")
  )
  yaml::write_yaml(cfg, config_path)
  invisible(config_path)
}
