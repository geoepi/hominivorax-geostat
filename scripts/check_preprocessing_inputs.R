parse_config_argument <- function(args) {
  inline <- grep("^--config=", args)
  if (length(inline)) return(sub("^--config=", "", args[inline[1]]))
  separate <- which(args == "--config")
  if (length(separate) && length(args) >= separate[1] + 1L) return(args[separate[1] + 1L])
  stop("Usage: Rscript scripts/check_preprocessing_inputs.R --config config/preprocessing.yml")
}

args <- commandArgs(trailingOnly = TRUE)
config_path <- parse_config_argument(args)
repo_root <- normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x[1])) y else x[1]

cat("Atlas preprocessing preflight\n")
cat("-----------------------------\n")
cat("config: ", normalizePath(config_path, mustWork = FALSE), "\n", sep = "")
cat("host: ", Sys.info()[["nodename"]], "\n", sep = "")
cat("working directory: ", getwd(), "\n\n", sep = "")

required_packages <- c("sf", "terra", "yaml", "dplyr", "tidyr", "readr", "stringr", "lubridate", "INLA")
package_available <- vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
cat("Environment:\n")
cat("  R: ", R.version.string, "\n", sep = "")
cat("  required packages: ", sum(package_available), "/", length(package_available), " available\n", sep = "")
if (any(!package_available)) cat("  missing packages: ", paste(names(package_available)[!package_available], collapse = ", "), "\n", sep = "")
if (all(package_available[c("sf", "terra")])) {
  cat("  sf external software:\n")
  print(sf::sf_extSoftVersion())
  cat("  terra GDAL:\n")
  if ("gdal" %in% getNamespaceExports("terra")) print(tryCatch(terra::gdal(), error = function(e) conditionMessage(e))) else cat("    unavailable in this terra version\n")
}
cat("  gdalinfo: ", Sys.which("gdalinfo"), "\n", sep = "")
cat("  projinfo: ", Sys.which("projinfo"), "\n\n", sep = "")

if (!all(package_available[c("yaml", "sf", "terra", "dplyr", "readr", "lubridate")])) {
  cat("Required packages are missing; input checks cannot continue.\n")
  quit(status = 1, save = "no")
}

cfg <- tryCatch(read_preprocessing_config(config_path, repo_root), error = function(e) {
  cat("Configuration ERROR: ", conditionMessage(e), "\n", sep = "")
  quit(status = 1, save = "no")
})
validate_preprocessing_config(cfg, require_inputs = FALSE)
expected_time <- make_week_index(cfg$study$start_date, cfg$study$end_date)
expected_keys <- paste(expected_time$epiyear, expected_time$epiweek, sep = "-")
failures <- character()
note_failure <- function(x) failures <<- c(failures, x)
exists_input <- function(path, directory = FALSE) if (directory) dir.exists(path) else file.exists(path)
fmt_extent <- function(e) paste(format(as.vector(e), trim = TRUE), collapse = ", ")
fmt_range <- function(r) {
  mm <- terra::minmax(r)
  if (!nrow(mm) || all(is.na(mm))) return("NA")
  paste(signif(range(mm, na.rm = TRUE), 7), collapse = " to ")
}
crs_matches <- function(r, target) {
  if (is.na(terra::crs(r)) || !nzchar(terra::crs(r))) return(FALSE)
  isTRUE(tryCatch(sf::st_crs(terra::crs(r)) == sf::st_crs(target), error = function(e) FALSE))
}
template <- NULL

cat("Configuration:\n")
cat("  study interval: ", cfg$study$start_date, " through ", cfg$study$end_date, " (", nrow(expected_time), " ISO weeks)\n", sep = "")
cat("  model CRS: ", cfg$study$projected_crs, "\n", sep = "")
cat("  nearest-valid search radius (static): ", cfg$extraction$search_radius_km, " km\n", sep = "")
cat("  nearest-valid search radius (dynamic): ", cfg$extraction$dynamic_search_radius_km, " km\n\n", sep = "")
output_directory <- cfg$project$output_directory
output_parent <- if (dir.exists(output_directory)) output_directory else dirname(output_directory)
output_writable <- dir.exists(output_parent) && file.access(output_parent, 2) == 0
cat("  output directory: ", output_directory, " (", if (output_writable) "writable" else "not writable or parent missing", ")\n\n", sep = "")
if (!output_writable) note_failure("configured output directory is not writable")

cat("Observations:\n")
observation_path <- cfg$inputs$observations
observation_mode <- cfg$inputs$observation_mode
cat("  mode: ", observation_mode, "\n", sep = "")
cat("  path: ", observation_path, "\n", sep = "")
if (!file.exists(observation_path)) {
  cat("  status: MISSING\n")
  note_failure("observation source is missing")
} else {
  observations <- readr::read_csv(observation_path, show_col_types = FALSE)
  cat("  records: ", nrow(observations), "\n", sep = "")
  cat("  columns: ", paste(names(observations), collapse = ", "), "\n", sep = "")
  if (identical(observation_mode, "standardized")) {
    year_name <- if ("epiyear" %in% names(observations)) "epiyear" else if ("year" %in% names(observations)) "year" else NULL
    week_name <- if ("epiweek" %in% names(observations)) "epiweek" else if ("week" %in% names(observations)) "week" else NULL
    if (is.null(year_name) || is.null(week_name) || !all(c("x", "y") %in% names(observations))) {
      cat("  status: standardized columns missing\n")
      note_failure("standardized observations lack year/week and x/y columns")
    } else {
      year <- suppressWarnings(as.integer(observations[[year_name]]))
      week <- suppressWarnings(as.integer(observations[[week_name]]))
      source_x <- suppressWarnings(as.numeric(observations$x))
      source_y <- suppressWarnings(as.numeric(observations$y))
      valid_time <- is.finite(year) & is.finite(week) & year > 0 & week >= 1 & week <= 53
      valid_xy <- is.finite(source_x) & is.finite(source_y)
      keys <- paste(year, week, sep = "-")
      time_match <- valid_time & keys %in% expected_keys
      duplicate_key <- paste(keys, signif(source_x, 12), signif(source_y, 12), sep = "|")
      duplicate_count <- sum(duplicated(duplicate_key[valid_time & valid_xy]))
      inside <- rep(NA, nrow(observations))
      model_x <- rep(NA_real_, nrow(observations))
      model_y <- rep(NA_real_, nrow(observations))
      source_crs <- get_observation_source_crs(cfg)
      valid_indices <- which(valid_xy)
      if (length(valid_indices)) {
        standardized_points <- sf::st_as_sf(data.frame(source_x = source_x[valid_indices], source_y = source_y[valid_indices]), coords = c("source_x", "source_y"), crs = source_crs)
        model_points <- sf::st_transform(standardized_points, cfg$study$projected_crs)
        model_coordinates <- sf::st_coordinates(model_points)
        model_x[valid_indices] <- model_coordinates[, 1]
        model_y[valid_indices] <- model_coordinates[, 2]
      }
      valid_model_xy <- is.finite(model_x) & is.finite(model_y)
      if (file.exists(cfg$inputs$study_boundary) && any(valid_model_xy)) {
        boundary_for_obs <- sf::st_read(cfg$inputs$study_boundary, quiet = TRUE)
        boundary_for_obs <- sf::st_transform(sf::st_make_valid(boundary_for_obs), cfg$study$projected_crs)
        model_points <- sf::st_as_sf(data.frame(x = model_x[valid_model_xy], y = model_y[valid_model_xy]), coords = c("x", "y"), crs = cfg$study$projected_crs)
        model_indices <- which(valid_model_xy)
        inside[model_indices] <- lengths(sf::st_covered_by(model_points, boundary_for_obs)) > 0
      }
      retained_candidate <- time_match & valid_model_xy
      cat("  canonical year/week columns: ", year_name, " -> epiyear; ", week_name, " -> epiweek\n", sep = "")
      cat("  source CRS: ", source_crs$input, "\n", sep = "")
      cat("  source x range: ", if (any(valid_xy)) paste(signif(range(source_x[valid_xy]), 8), collapse = " to ") else "NA", "\n", sep = "")
      cat("  source y range: ", if (any(valid_xy)) paste(signif(range(source_y[valid_xy]), 8), collapse = " to ") else "NA", "\n", sep = "")
      cat("  transformed model x range: ", if (any(valid_model_xy)) paste(signif(range(model_x[valid_model_xy]), 8), collapse = " to ") else "NA", "\n", sep = "")
      cat("  transformed model y range: ", if (any(valid_model_xy)) paste(signif(range(model_y[valid_model_xy]), 8), collapse = " to ") else "NA", "\n", sep = "")
      cat("  duplicate point-week rows: ", duplicate_count, "\n", sep = "")
      cat("  study-period records: ", sum(time_match), "\n", sep = "")
      cat("  outside-period records: ", sum(valid_time & !time_match), "\n", sep = "")
      cat("  invalid year/week records: ", sum(!valid_time), "\n", sep = "")
      cat("  inside-domain records after transformation: ", if (all(is.na(inside))) "unavailable" else sum(retained_candidate & inside, na.rm = TRUE), "\n", sep = "")
      cat("  outside-domain records after transformation: ", if (all(is.na(inside))) "unavailable" else sum(retained_candidate & !inside, na.rm = TRUE), "\n", sep = "")
      cat("  time-index match: ", sum(time_match), "/", sum(valid_time), "\n", sep = "")
      cat("  host processing: skipped; no host values invented\n")
      if (any(duplicated(duplicate_key[valid_time & valid_xy]))) note_failure("standardized observations contain duplicate point-week rows")
      if (any(!valid_time)) note_failure("standardized observations contain invalid year/week values")
    }
  } else if (!all(c("date", "lon", "lat", "host") %in% names(observations))) {
    cat("  status: required raw columns missing\n")
    note_failure("raw observations lack required columns")
  } else {
    raw_date <- as.character(observations$date)
    dates <- suppressWarnings(as.Date(raw_date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y")))
    valid_date <- !is.na(dates)
    in_period <- valid_date & dates >= as.Date(cfg$study$start_date) & dates <= as.Date(cfg$study$end_date)
    duplicate_key <- paste(raw_date, observations$lon, observations$lat, sep = "|")
    lookup <- read_host_lookup(file.path(repo_root, "config", "host_lookup.csv"))
    cleaned_host <- clean_host_values(observations$host)
    mapped <- cleaned_host %in% lookup$host_cleaned | !is.na(legacy_host_standardization(cleaned_host))
    cat("  date range: ", if (any(valid_date)) paste(min(dates, na.rm = TRUE), " to ", max(dates, na.rm = TRUE)) else "NA", "\n", sep = "")
    cat("  coordinate columns: lon, lat\n")
    cat("  missing coordinates: ", sum(!is.finite(observations$lon) | !is.finite(observations$lat)), "\n", sep = "")
    cat("  duplicate location/date combinations: ", sum(duplicated(duplicate_key)), "\n", sep = "")
    cat("  unique host strings: ", paste(sort(unique(as.character(observations$host))), collapse = ", "), "\n", sep = "")
    cat("  host lookup coverage: ", sprintf("%.1f%%", 100 * mean(mapped)), " (", sum(mapped), "/", length(mapped), ")\n", sep = "")
    cat("  within study period: ", sum(in_period), "\n", sep = "")
    cat("  outside study period or invalid date: ", sum(!in_period), "\n", sep = "")
  }
}
cat("\nStudy boundary:\n")
boundary_path <- cfg$inputs$study_boundary
cat("  path: ", boundary_path, "\n", sep = "")
if (!file.exists(boundary_path)) {
  cat("  status: MISSING\n")
  note_failure("study boundary is missing")
} else {
  layers <- sf::st_layers(boundary_path)$name
  boundary <- sf::st_read(boundary_path, quiet = TRUE, layer = layers[1])
  boundary_valid <- all(sf::st_is_valid(boundary))
  boundary_projected <- sf::st_transform(sf::st_make_valid(boundary), cfg$study$projected_crs)
  boundary_union <- sf::st_union(boundary_projected)
  pieces <- sf::st_cast(boundary_union, "POLYGON", warn = FALSE)
  area_km2 <- as.numeric(sf::st_area(pieces)) * crs_linear_unit_to_m(cfg$study$projected_crs)^2 / 1e6
  cat("  datasource exists: YES\n")
  cat("  layer(s): ", paste(layers, collapse = ", "), "\n", sep = "")
  cat("  feature count: ", nrow(boundary), "\n", sep = "")
  cat("  geometry type(s): ", paste(unique(as.character(sf::st_geometry_type(boundary))), collapse = ", "), "\n", sep = "")
  cat("  CRS: ", sf::st_crs(boundary)$input, "\n", sep = "")
  cat("  CRS units: ", sf::st_crs(boundary)$units_gdal %||% "unknown", "\n", sep = "")
  cat("  CRS equivalent to configured model: ", if (isTRUE(tryCatch(sf::st_crs(boundary) == sf::st_crs(cfg$study$projected_crs), error = function(e) FALSE))) "YES" else "NO", "\n", sep = "")
  cat("  extent: ", fmt_extent(sf::st_bbox(boundary)), "\n", sep = "")
  cat("  geometry valid: ", if (boundary_valid) "YES" else "NO", "\n", sep = "")
  cat("  total area (km2, model CRS): ", signif(sum(area_km2), 8), "\n", sep = "")
  cat("  polygons at/above 500 km2: ", sum(area_km2 >= cfg$mesh$island_area_threshold_km2), " / ", length(area_km2), "\n", sep = "")
  if (!boundary_valid) note_failure("study boundary contains invalid geometry")
}

cat("\nTemplate raster:\n")
template_path <- cfg$inputs$template_raster
cat("  path: ", template_path, "\n", sep = "")
if (!file.exists(template_path)) {
  cat("  status: MISSING\n")
  note_failure("template raster is missing")
} else {
  template <- terra::rast(template_path)
  template_crs_available <- !is.na(terra::crs(template)) && nzchar(terra::crs(template))
  non_na <- terra::global(!is.na(template[[1]]), "sum", na.rm = TRUE)[1, 1]
  cat("  CRS: ", if (template_crs_available) terra::crs(template) else "MISSING", "\n", sep = "")
  cat("  extent: ", fmt_extent(terra::ext(template)), "\n", sep = "")
  cat("  dimensions: ", paste(terra::nrow(template), terra::ncol(template), sep = " x "), "\n", sep = "")
  cat("  resolution: ", paste(terra::res(template), collapse = " x "), "\n", sep = "")
  cat("  cell count: ", terra::ncell(template), "\n", sep = "")
  cat("  non-NA cells: ", non_na, "\n", sep = "")
  cat("  NA fraction: ", sprintf("%.5f", 1 - non_na / terra::ncell(template)), "\n", sep = "")
  cat("  coordinate units: ", if (!template_crs_available) "unknown" else if (sf::st_is_longlat(sf::st_crs(terra::crs(template)))) "longitude/latitude" else sf::st_crs(terra::crs(template))$units_gdal %||% "projected", "\n", sep = "")
  cat("  CRS equivalent to model CRS: ", if (crs_matches(template, cfg$study$projected_crs)) "YES" else "NO", "\n", sep = "")
  if (!template_crs_available) note_failure("template raster has no CRS metadata")
}

cat("\nStatic inputs:\n")
for (nm in names(cfg$static_covariates)) {
  path <- cfg$static_covariates[[nm]]
  if (!file.exists(path)) {
    cat("  ", nm, ": MISSING (", path, ")\n", sep = "")
    note_failure(paste("static raster missing:", nm))
    next
  }
  r <- terra::rast(path)
  if (is.na(terra::crs(r)) || !nzchar(terra::crs(r))) note_failure(paste("static raster has no CRS metadata:", nm))
  geom_match <- !is.null(template) && terra::compareGeom(r, template, stopOnError = FALSE, crs = TRUE, ext = TRUE, rowcol = TRUE, res = TRUE)
  non_na <- terra::global(!is.na(r[[1]]), "sum", na.rm = TRUE)[1, 1]
  cat("  ", nm, ": YES; CRS=", if (crs_matches(r, cfg$study$projected_crs)) "model" else "mismatch", "; dims=", terra::nrow(r), "x", terra::ncol(r), "; res=", paste(terra::res(r), collapse = "x"), "; NA fraction=", sprintf("%.5f", 1 - non_na / terra::ncell(r)), "; range=", fmt_range(r), "; geometry=", if (geom_match) "template" else "requires transformation", "\n", sep = "")
}

cat("\nDynamic coverage:\n")
for (nm in names(cfg$dynamic_covariates)) {
  path <- cfg$dynamic_covariates[[nm]]
  if (!dir.exists(path)) {
    cat("  ", nm, ": directory MISSING (", path, ")\n", sep = "")
    note_failure(paste("dynamic directory missing:", nm))
    next
  }
  files <- list.files(path, pattern = "\\.(tif|grd)$", full.names = TRUE, ignore.case = TRUE)
  parsed <- tryCatch(dynamic_file_index(path, expected_time), error = function(e) e)
  if (inherits(parsed, "error")) {
    cat("  ", nm, ": parser ERROR: ", conditionMessage(parsed), "\n", sep = "")
    note_failure(paste("dynamic filename parser failed:", nm))
    next
  }
  keys <- paste(parsed$epiyear, parsed$epiweek, sep = "-")
  missing <- setdiff(expected_keys, keys)
  representative <- terra::rast(parsed$file[1])
  if (is.na(terra::crs(representative)) || !nzchar(terra::crs(representative))) note_failure(paste("dynamic raster has no CRS metadata:", nm))
  non_na <- terra::global(!is.na(representative[[1]]), "sum", na.rm = TRUE)[1, 1]
  cat("  ", nm, ": ", length(files), " files; ", length(intersect(expected_keys, keys)), "/", length(expected_keys), " expected weeks; range=", min(keys), " to ", max(keys), "; unique keys=", length(unique(keys)), "; duplicate keys=", sum(duplicated(keys)), "; missing=", if (length(missing)) paste(missing, collapse = ",") else "none", "; representative CRS=", if (crs_matches(representative, cfg$study$projected_crs)) "model" else "mismatch", "; dims=", terra::nrow(representative), "x", terra::ncol(representative), "; res=", paste(terra::res(representative), collapse = "x"), "; extent=", fmt_extent(terra::ext(representative)), "; NA fraction=", sprintf("%.5f", 1 - non_na / terra::ncell(representative)), "\n", sep = "")
  if (length(missing)) note_failure(paste("dynamic coverage incomplete:", nm))
}

cat("\nConfiguration concerns:\n")
if (!length(failures)) cat("  none\n") else for (failure in unique(failures)) cat("  - ", failure, "\n", sep = "")
if (length(failures)) {
  cat("\nPreflight FAILED: required inputs or checks are not ready for the pilot.\n")
  quit(status = 1, save = "no")
}
cat("\nPreflight PASSED: configured inputs and dynamic filename/time coverage are ready for the pilot.\n")
