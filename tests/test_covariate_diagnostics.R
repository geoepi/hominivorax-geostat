repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

if (!requireNamespace("terra", quietly = TRUE)) stop("terra is required for this regression test")

root <- tempfile("covariate_diagnostics_")
dir.create(file.path(root, "mintemp"), recursive = TRUE)
output_directory <- file.path(root, "output")
raster <- terra::rast(
  nrows = 5, ncols = 5, xmin = 0, xmax = 100000, ymin = 0, ymax = 100000,
  crs = "EPSG:3857"
)
values <- rep(NA_real_, terra::ncell(raster))
values[21] <- 11
terra::values(raster) <- values
raster_path <- file.path(root, "mintemp", "mintemp_y2024_w01.tif")
terra::writeRaster(raster, raster_path, overwrite = TRUE)

target <- data.frame(
  .row_id = c("outside_near", "far"),
  poly_id = c(1L, 2L),
  epiyear = c(2024L, 2024L),
  epiweek = c(1L, 1L),
  x = c(-5000, 90000),
  y = c(10000, 90000)
)
expected_time <- data.frame(epiyear = 2024L, epiweek = 1L, time_index = 1L)

result <- try(extract_dynamic_covariates(
  target, list(mintemp = file.path(root, "mintemp")), "EPSG:3857", expected_time,
  missing_policy = "fail", search_radius_km = 25, scope = "tier2_dynamic",
  diagnostic_output_directory = output_directory
), silent = TRUE)
stopifnot(inherits(result, "try-error"))
stopifnot(file.exists(file.path(output_directory, "covariate_audit_failed.csv")))
stopifnot(file.exists(file.path(output_directory, "tier2_dynamic_missing.csv")))

audit <- read.csv(file.path(output_directory, "covariate_audit_failed.csv"), stringsAsFactors = FALSE)
missing <- read.csv(file.path(output_directory, "tier2_dynamic_missing.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(audit) == 1L, audit$rows[[1]] == 2L)
stopifnot(audit$direct_extractions[[1]] == 0L, audit$nearest_fallbacks[[1]] == 1L)
stopifnot(audit$unresolved_missing[[1]] == 1L)
stopifnot(nrow(missing) == 1L, missing$.row_id[[1]] == "far")
stopifnot(missing$variable[[1]] == "mintemp")
stopifnot(isTRUE(missing$point_inside_raster_extent[[1]]))
stopifnot(missing$nearest_distance_bin[[1]] == ">75 km")
stopifnot(missing$fallback_attempted[[1]])

cat("Covariate diagnostics regression test passed\n")
