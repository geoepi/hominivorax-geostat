validate_raster <- function(path, expected_crs = NULL, template = NULL) {
  if (!file.exists(path)) stop("Raster input does not exist: ", path)
  r <- terra::rast(path)
  if (is.na(terra::crs(r))) stop("Raster has no CRS: ", path)
  if (!is.null(expected_crs) && !terra::same.crs(r, terra::rast(ext = terra::ext(r), resolution = terra::res(r), crs = expected_crs))) {
    warning("Raster CRS differs from configured target and will be transformed during extraction: ", path)
  }
  if (!is.null(template) && !terra::compareGeom(r, template, stopOnError = FALSE, crs = TRUE, ext = TRUE, rowcol = TRUE, res = TRUE)) {
    warning("Raster geometry differs from the template: ", path)
  }
  r
}

dynamic_file_index <- function(path, expected_time) {
  if (!dir.exists(path)) stop("Dynamic covariate directory does not exist: ", path)
  files <- list.files(path, pattern = "\\.(tif|grd)$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) stop("No dynamic raster layers found in: ", path)
  m <- stringr::str_match(basename(files), "(?:y|year)?(20[0-9]{2})[^0-9]+(?:w|week)?([0-9]{1,2})")
  index <- data.frame(file = files, epiyear = as.integer(m[, 2]), epiweek = as.integer(m[, 3]))
  if (anyNA(index$epiyear) || anyNA(index$epiweek)) stop("Every dynamic raster must encode year and week: ", path)
  if (anyDuplicated(index[c("epiyear", "epiweek")])) stop("Duplicate dynamic raster year-week keys: ", path)
  missing <- dplyr::anti_join(expected_time[c("epiyear", "epiweek")], index, by = c("epiyear", "epiweek"))
  if (nrow(missing)) stop("Dynamic covariate lacks required weeks: ", path)
  index
}

extract_dynamic_covariates <- function(target, specifications, target_crs, expected_time, missing_policy = "fail") {
  require_columns(target, c(".row_id", "x", "y", "epiyear", "epiweek"), "dynamic extraction target")
  assert_unique_keys(target, ".row_id", "dynamic extraction target")
  result <- target
  audit <- data.frame(variable = character(), source_layers = integer(), missing = integer(), rows = integer())
  for (nm in names(specifications)) {
    index <- dynamic_file_index(specifications[[nm]], expected_time)
    values <- rep(NA_real_, nrow(target))
    for (i in seq_len(nrow(index))) {
      which_rows <- which(target$epiyear == index$epiyear[i] & target$epiweek == index$epiweek[i])
      if (!length(which_rows)) next
      raster <- validate_raster(index$file[i])
      points <- terra::vect(target[which_rows, , drop = FALSE], geom = c("x", "y"), crs = target_crs)
      if (!terra::same.crs(points, raster)) points <- terra::project(points, terra::crs(raster))
      values[which_rows] <- terra::extract(raster, points, method = "bilinear")[, 2]
    }
    result[[nm]] <- values
    audit <- rbind(audit, data.frame(variable = nm, source_layers = nrow(index), missing = sum(is.na(values)), rows = length(values)))
  }
  if (missing_policy == "fail" && any(audit$missing > 0)) stop("Dynamic covariate missingness violates configured policy.")
  list(data = result, audit = audit)
}

extract_static_covariates <- function(data, specifications, target_crs) {
  require_columns(data, c(".row_id", "x", "y"), "static extraction target")
  assert_unique_keys(data, ".row_id", "static extraction target")
  points <- terra::vect(data, geom = c("x", "y"), crs = target_crs)
  out <- data.frame(.row_id = data$.row_id)
  audit <- data.frame(variable = character(), missing = integer(), rows = integer())
  for (nm in names(specifications)) {
    raster <- validate_raster(specifications[[nm]])
    extract_points <- points
    if (!terra::same.crs(extract_points, raster)) extract_points <- terra::project(extract_points, terra::crs(raster))
    values <- terra::extract(raster, extract_points, method = "bilinear")[, 2]
    out[[nm]] <- values
    audit <- rbind(audit, data.frame(variable = nm, missing = sum(is.na(values)), rows = length(values)))
  }
  list(data = out, audit = audit)
}

join_covariates <- function(data, extracted, keys = ".row_id") {
  assert_unique_keys(data, keys, "covariate target")
  assert_unique_keys(extracted, keys, "extracted covariates")
  joined <- dplyr::left_join(data, extracted, by = keys, suffix = c("", ".duplicate"))
  if (nrow(joined) != nrow(data)) stop("Covariate join changed the target row count.")
  joined
}
