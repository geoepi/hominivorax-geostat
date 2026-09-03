repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

model_crs <- "+proj=aea +lat_0=20 +lon_0=-75 +lat_1=10 +lat_2=30 +x_0=0 +y_0=0 +datum=WGS84 +units=km +no_defs"
boundary <- sf::st_as_sf(
  data.frame(id = 1, wkt = "POLYGON ((-110 5, -80 5, -80 25, -110 25, -110 5))"),
  wkt = "wkt", crs = "EPSG:4326"
)
boundary <- sf::st_transform(boundary, model_crs)
cfg <- list(
  inputs = list(observation_mode = "standardized", observation_crs = "EPSG:4326"),
  study = list(start_date = "2024-01-01", end_date = "2024-01-07", projected_crs = model_crs)
)
observations <- data.frame(
  year = c(2024L, 2024L), week = c(1L, 1L),
  x = c(-90, -70), y = c(20, 20), source_tag = c("inside", "outside")
)

processed <- preprocess_standardized_observations(observations, boundary, cfg)
stopifnot(nrow(processed$data) == 1L)
stopifnot(all(processed$data$epiyear == 2024L))
stopifnot(all(processed$data$epiweek == 1L))
stopifnot(processed$data$source_x[[1]] == -90, processed$data$source_y[[1]] == 20)
stopifnot(abs(processed$data$x[[1]] - processed$data$source_x[[1]]) > 100)
stopifnot(processed$data$source_tag[[1]] == "inside")
stopifnot(any(processed$excluded$exclusion_reason == "outside_spatial_domain"))

expected_model_xy <- sf::st_coordinates(sf::st_transform(
  sf::st_as_sf(data.frame(source_x = -90, source_y = 20), coords = c("source_x", "source_y"), crs = "EPSG:4326"),
  model_crs
))
stopifnot(all.equal(unname(unlist(processed$data[1, c("x", "y")])), unname(expected_model_xy[1, ]), tolerance = 1e-8) == TRUE)

missing_crs_cfg <- cfg
missing_crs_cfg$inputs$observation_crs <- NULL
missing_crs_result <- try(preprocess_standardized_observations(observations, boundary, missing_crs_cfg), silent = TRUE)
stopifnot(inherits(missing_crs_result, "try-error"))

cat("Standardized observation CRS regression test passed\n")
