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
  m <- stringr::str_match(basename(files), "(?i)(?:^|[^0-9])(20[0-9]{2})[^0-9]+(?:w(?:eek)?[-_ ]*)?([0-9]{1,2})(?=[^0-9]|$)")
  index <- data.frame(file = files, epiyear = as.integer(m[, 2]), epiweek = as.integer(m[, 3]))
  if (anyNA(index$epiyear) || anyNA(index$epiweek)) stop("Every dynamic raster must encode year and week: ", path)
  if (any(index$epiweek < 1 | index$epiweek > 53)) stop("Dynamic raster contains an invalid ISO week: ", path)
  if (anyDuplicated(index[c("epiyear", "epiweek")])) stop("Duplicate dynamic raster year-week keys: ", path)
  missing <- dplyr::anti_join(expected_time[c("epiyear", "epiweek")], index, by = c("epiyear", "epiweek"))
  if (nrow(missing)) stop("Dynamic covariate lacks required weeks: ", path)
  index
}

nearest_valid_cells <- function(raster, points, missing, search_radius_km) {
  out_values <- rep(NA_real_, length(missing))
  out_distance_km <- rep(NA_real_, length(missing))
  xy <- terra::crds(points)[missing, , drop = FALSE]
  rres <- terra::res(raster)
  longlat <- sf::st_is_longlat(sf::st_crs(terra::crs(raster)))
  if (longlat) {
    mean_lat <- mean(xy[, 2], na.rm = TRUE)
    radius_y <- search_radius_km * 1000 / 111320
    radius_x <- radius_y / max(cos(mean_lat * pi / 180), 0.01)
    unit_to_m <- 111320
  } else {
    radius_y <- radius_x <- search_radius_km * 1000 / crs_linear_unit_to_m(terra::crs(raster))
    unit_to_m <- crs_linear_unit_to_m(terra::crs(raster))
  }
  for (j in seq_along(missing)) {
    cell <- terra::cellFromXY(raster, xy[j, , drop = FALSE])
    if (is.na(cell)) next
    rc <- terra::rowColFromCell(raster, cell)
    rows <- max(1, rc[1] - ceiling(radius_y / rres[2])):min(terra::nrow(raster), rc[1] + ceiling(radius_y / rres[2]))
    cols <- max(1, rc[2] - ceiling(radius_x / rres[1])):min(terra::ncol(raster), rc[2] + ceiling(radius_x / rres[1]))
    candidate_cells <- terra::cellFromRowCol(raster, rep(rows, each = length(cols)), rep(cols, length(rows)))
    candidate_xy <- terra::xyFromCell(raster, candidate_cells)
    candidate_values <- terra::extract(raster, candidate_cells)[[1L]]
    original_xy <- candidate_xy[which(candidate_cells == cell)[1], , drop = FALSE]
    dx <- candidate_xy[, 1] - original_xy[1, 1]
    dy <- candidate_xy[, 2] - original_xy[1, 2]
    if (longlat) {
      distance_km <- sqrt((dx * 111.32 * cos(mean_lat * pi / 180))^2 + (dy * 111.32)^2)
      valid <- !is.na(candidate_values) & distance_km <= search_radius_km
    } else {
      distance <- sqrt(dx^2 + dy^2)
      valid <- !is.na(candidate_values) & distance <= radius_x
      distance_km <- distance * unit_to_m / 1000
    }
    if (!any(valid)) next
    valid_cells <- which(valid)
    selected <- valid_cells[which.min(distance_km[valid_cells])]
    out_values[j] <- candidate_values[selected]
    out_distance_km[j] <- distance_km[selected]
  }
  list(values = out_values, distance_km = out_distance_km)
}

extract_raster_points <- function(raster, points, method = "bilinear", search_radius_km = 0) {
  direct_result <- terra::extract(raster, points, method = method)
  direct <- direct_result[[2L]]
  values <- direct
  fallback_distance_km <- rep(NA_real_, length(direct))
  fallback <- rep(FALSE, length(direct))
  if (search_radius_km > 0 && anyNA(direct)) {
    missing <- which(is.na(direct))
    nearest <- nearest_valid_cells(raster, points, missing, search_radius_km)
    values[missing] <- nearest$values
    fallback[missing] <- is.na(direct[missing]) & !is.na(nearest$values)
    fallback_distance_km[missing] <- nearest$distance_km
  }
  list(values = values, direct = !is.na(direct), fallback = fallback,
       fallback_distance_km = fallback_distance_km, unresolved = is.na(values))
}

make_covariate_audit <- function(variable, scope, source_layers, extracted, rows) {
  distances <- extracted$fallback_distance_km[extracted$fallback]
  data.frame(
    variable = variable, scope = scope, source_layers = source_layers, rows = rows,
    direct_extractions = sum(extracted$direct), nearest_fallbacks = sum(extracted$fallback),
    fallback_distance_min = if (length(distances)) min(distances, na.rm = TRUE) else NA_real_,
    fallback_distance_median = if (length(distances)) stats::median(distances, na.rm = TRUE) else NA_real_,
    fallback_distance_max = if (length(distances)) max(distances, na.rm = TRUE) else NA_real_,
    unresolved_missing = sum(extracted$unresolved), missing = sum(extracted$unresolved),
    stringsAsFactors = FALSE
  )
}

extract_dynamic_covariates <- function(target, specifications, target_crs, expected_time, missing_policy = "fail", search_radius_km = 0, scope = "dynamic") {
  require_columns(target, c(".row_id", "x", "y", "epiyear", "epiweek"), "dynamic extraction target")
  assert_unique_keys(target, ".row_id", "dynamic extraction target")
  result <- target
  audit <- data.frame()
  for (nm in names(specifications)) {
    index <- dynamic_file_index(specifications[[nm]], expected_time)
    values <- rep(NA_real_, nrow(target))
    direct <- rep(FALSE, nrow(target)); fallback <- rep(FALSE, nrow(target))
    fallback_distance_km <- rep(NA_real_, nrow(target))
    for (i in seq_len(nrow(index))) {
      which_rows <- which(target$epiyear == index$epiyear[i] & target$epiweek == index$epiweek[i])
      if (!length(which_rows)) next
      raster <- validate_raster(index$file[i])
      points <- terra::vect(target[which_rows, , drop = FALSE], geom = c("x", "y"), crs = target_crs)
      if (!terra::same.crs(points, raster)) points <- terra::project(points, terra::crs(raster))
      extracted <- extract_raster_points(raster, points, method = "bilinear", search_radius_km = search_radius_km)
      values[which_rows] <- extracted$values
      direct[which_rows] <- extracted$direct
      fallback[which_rows] <- extracted$fallback
      fallback_distance_km[which_rows] <- extracted$fallback_distance_km
    }
    result[[nm]] <- values
    index_keys <- paste(index$epiyear, index$epiweek, sep = "-")
    expected_keys <- paste(expected_time$epiyear, expected_time$epiweek, sep = "-")
    audit <- rbind(audit, make_covariate_audit(nm, scope, sum(index_keys %in% expected_keys), list(values = values, direct = direct, fallback = fallback, fallback_distance_km = fallback_distance_km, unresolved = is.na(values)), length(values)))
  }
  if (missing_policy == "fail" && any(audit$unresolved_missing > 0)) stop("Dynamic covariate missingness violates configured policy.")
  list(data = result, audit = audit)
}

extract_static_covariates <- function(data, specifications, target_crs, search_radius_km = 0, scope = "static") {
  require_columns(data, c(".row_id", "x", "y"), "static extraction target")
  assert_unique_keys(data, ".row_id", "static extraction target")
  points <- terra::vect(data, geom = c("x", "y"), crs = target_crs)
  out <- data.frame(.row_id = data$.row_id)
  audit <- data.frame()
  for (nm in names(specifications)) {
    raster <- validate_raster(specifications[[nm]])
    extract_points <- points
    if (!terra::same.crs(extract_points, raster)) extract_points <- terra::project(extract_points, terra::crs(raster))
    extracted <- extract_raster_points(raster, extract_points, method = "bilinear", search_radius_km = search_radius_km)
    out[[nm]] <- extracted$values
    audit <- rbind(audit, make_covariate_audit(nm, scope, 1L, extracted, length(extracted$values)))
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
