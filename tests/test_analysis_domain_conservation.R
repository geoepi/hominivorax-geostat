repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

model_crs <- "EPSG:3857"
boundary <- sf::st_as_sf(
  data.frame(part = c("main", "small"), wkt = c(
    "POLYGON ((0 0, 10000 0, 10000 10000, 0 10000, 0 0))",
    "POLYGON ((20000 0, 21000 0, 21000 1000, 20000 1000, 20000 0))"
  )), wkt = "wkt", crs = model_crs
)
cfg <- list(study = list(projected_crs = model_crs), mesh = list(island_area_threshold_km2 = 2))
analysis <- build_analysis_domain(boundary, cfg)
observations <- data.frame(
  observation_id = 1:4, x = c(1000, 20500, 5000, 5000), y = c(1000, 500, 5000, 5000),
  epiyear = 2025L, epiweek = c(1L, 1L, 2L, 2L), time_index = c(1L, 1L, 2L, 2L)
)
filtered <- filter_observations_to_analysis_domain(observations, analysis$simplified_domain)
stopifnot(filtered$retained == 3L, filtered$excluded_count == 1L, filtered$excluded$exclusion_reason[[1]] == "outside_analysis_domain")
retained_points <- sf::st_as_sf(filtered$data, coords = c("x", "y"), crs = model_crs)
stopifnot(all(lengths(sf::st_covered_by(retained_points, analysis$simplified_domain)) == 1L))

polygon <- sf::st_as_sf(data.frame(poly_id = 1L, full_area_km2 = 100, terrestrial_area_km2 = 100, wkt = "POLYGON ((0 0, 10000 0, 10000 10000, 0 10000, 0 0))"), wkt = "wkt", crs = model_crs)
support <- list(domain = analysis$simplified_domain, tier2_polygons = polygon)
time <- data.frame(epiyear = 2025L, epiweek = 1:2, time_index = 1:2)
tier2 <- build_tier2(filtered$data, support, time)
integration <- data.frame(point_id = 1L, x = 5000, y = 5000, poly_id = 1L, area_km2 = 100, inside_domain = TRUE)
tier1 <- build_tier1(filtered$data, integration, time)
conservation <- validate_detection_conservation(tier1, tier2, nrow(filtered$data), thinning_enabled = FALSE)
stopifnot(sum(tier2$count) == 3L, max(tier2$count) == 2L, all(tier2$count >= 0), is.integer(tier2$count), sum(tier1$Yi == 1L) == sum(tier2$count), conservation$model_eligible_detections == 3L)

bad <- filtered$data
bad$x[[1]] <- 15000
stopifnot(inherits(try(build_tier2(bad, support, time), silent = TRUE), "try-error"))

cat("Analysis-domain and detection-conservation regression tests passed\n")
