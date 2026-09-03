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

nearest_valid_cells <- function(raster, points, missing, search_radius_km, diagnostic = FALSE) {
  out_values <- rep(NA_real_, length(missing))
  out_distance_km <- rep(NA_real_, length(missing))
  out_nearest_distance_km <- rep(NA_real_, length(missing))
  out_nearest_x <- rep(NA_real_, length(missing))
  out_nearest_y <- rep(NA_real_, length(missing))
  xy <- terra::crds(points)[missing, , drop = FALSE]
  rres <- terra::res(raster)
  longlat <- sf::st_is_longlat(sf::st_crs(terra::crs(raster)))
  raster_values <- as.numeric(terra::values(raster, mat = FALSE))
  valid_cells_all <- which(!is.na(raster_values))
  raster_extent <- terra::ext(raster)
  if (longlat) {
    radius_y <- search_radius_km * 1000 / 111320
    unit_to_m <- NA_real_
  } else {
    unit_to_m <- crs_linear_unit_to_m(terra::crs(raster))
    radius_y <- radius_x <- search_radius_km * 1000 / unit_to_m
  }
  point_distance_km <- function(point_xy, candidate_xy) {
    if (longlat) {
      mean_lat <- mean(c(point_xy[2], candidate_xy[, 2]), na.rm = TRUE)
      sqrt((candidate_xy[, 1] - point_xy[1])^2 * (111.32 * cos(mean_lat * pi / 180))^2 +
        (candidate_xy[, 2] - point_xy[2])^2 * 111.32^2)
    } else {
      sqrt((candidate_xy[, 1] - point_xy[1])^2 + (candidate_xy[, 2] - point_xy[2])^2) * unit_to_m / 1000
    }
  }
  cell_index_near_point <- function(point_xy) {
    cell <- terra::cellFromXY(raster, matrix(point_xy, nrow = 1L))
    if (!is.na(cell)) return(terra::rowColFromCell(raster, cell))
    c(
      floor((terra::ymax(raster_extent) - point_xy[2]) / rres[2]) + 1,
      floor((point_xy[1] - terra::xmin(raster_extent)) / rres[1]) + 1
    )
  }
  for (j in seq_along(missing)) {
    point_xy <- xy[j, , drop = TRUE]
    if (isTRUE(diagnostic)) {
      candidate_cells <- valid_cells_all
    } else {
      rc <- cell_index_near_point(point_xy)
      if (longlat) {
        radius_x <- radius_y / max(cos(point_xy[2] * pi / 180), 0.01)
      } else {
        radius_x <- radius_y
      }
      rows <- max(1, rc[1] - ceiling(radius_y / rres[2])):min(terra::nrow(raster), rc[1] + ceiling(radius_y / rres[2]))
      cols <- max(1, rc[2] - ceiling(radius_x / rres[1])):min(terra::ncol(raster), rc[2] + ceiling(radius_x / rres[1]))
      if (rows[1] > rows[length(rows)] || cols[1] > cols[length(cols)]) next
      candidate_cells <- terra::cellFromRowCol(raster, rep(rows, each = length(cols)), rep(cols, length(rows)))
    }
    if (!length(candidate_cells)) next
    candidate_xy <- terra::xyFromCell(raster, candidate_cells)
    candidate_values <- raster_values[candidate_cells]
    distance_km <- point_distance_km(point_xy, candidate_xy)
    if (isTRUE(diagnostic)) {
      valid <- !is.na(candidate_values)
    } else {
      valid <- !is.na(candidate_values) & distance_km <= search_radius_km
    }
    if (!any(valid)) next
    valid_cells <- which(valid)
    selected <- valid_cells[which.min(distance_km[valid_cells])]
    out_nearest_distance_km[j] <- distance_km[selected]
    out_nearest_x[j] <- candidate_xy[selected, 1]
    out_nearest_y[j] <- candidate_xy[selected, 2]
    if (!isTRUE(diagnostic)) {
      out_values[j] <- candidate_values[selected]
      out_distance_km[j] <- distance_km[selected]
    }
  }
  list(
    values = out_values,
    distance_km = out_distance_km,
    nearest_distance_km = out_nearest_distance_km,
    nearest_x = out_nearest_x,
    nearest_y = out_nearest_y
  )
}

extract_raster_points <- function(raster, points, method = "bilinear", search_radius_km = 0, diagnostic = FALSE) {
  direct_result <- terra::extract(raster, points, method = method)
  direct <- direct_result[[2L]]
  values <- direct
  fallback_distance_km <- rep(NA_real_, length(direct))
  fallback <- rep(FALSE, length(direct))
  nearest_distance_km <- rep(NA_real_, length(direct))
  nearest_x <- rep(NA_real_, length(direct))
  nearest_y <- rep(NA_real_, length(direct))
  if (search_radius_km > 0 && anyNA(direct)) {
    missing <- which(is.na(direct))
    nearest <- nearest_valid_cells(raster, points, missing, search_radius_km)
    values[missing] <- nearest$values
    fallback[missing] <- is.na(direct[missing]) & !is.na(nearest$values)
    fallback_distance_km[missing] <- nearest$distance_km
  }
  unresolved <- is.na(values)
  if (isTRUE(diagnostic) && any(unresolved)) {
    missing <- which(unresolved)
    nearest <- nearest_valid_cells(raster, points, missing, search_radius_km, diagnostic = TRUE)
    nearest_distance_km[missing] <- nearest$nearest_distance_km
    nearest_x[missing] <- nearest$nearest_x
    nearest_y[missing] <- nearest$nearest_y
  }
  list(values = values, direct = !is.na(direct), fallback = fallback,
       fallback_distance_km = fallback_distance_km,
       nearest_distance_km = nearest_distance_km, nearest_x = nearest_x,
       nearest_y = nearest_y, unresolved = unresolved)
}

nearest_distance_bin <- function(distance_km) {
  out <- rep("no nearby valid support", length(distance_km))
  ok <- is.finite(distance_km)
  out[ok] <- as.character(cut(
    distance_km[ok], breaks = c(-Inf, 25, 50, 75, Inf),
    labels = c("<=25 km", "25-50 km", "50-75 km", ">75 km"),
    right = TRUE
  ))
  out
}

dynamic_missing_diagnostics <- function(target, variable, scope, raster, points, extracted, row_index) {
  missing <- which(extracted$unresolved)
  if (!length(missing)) return(data.frame())
  raster_values <- as.numeric(terra::values(raster, mat = FALSE))
  raster_extent <- terra::ext(raster)
  raster_xy <- terra::crds(points)
  cell <- terra::cellFromXY(raster, raster_xy[missing, , drop = FALSE])
  target_rows <- target[row_index[missing], , drop = FALSE]
  data.frame(
    .row_id = target_rows$.row_id,
    poly_id = if ("poly_id" %in% names(target_rows)) target_rows$poly_id else NA_integer_,
    epiyear = target_rows$epiyear,
    epiweek = target_rows$epiweek,
    x = target_rows$x,
    y = target_rows$y,
    variable = variable,
    scope = scope,
    fallback_attempted = !extracted$direct[missing],
    fallback_distance_km = extracted$fallback_distance_km[missing],
    nearest_valid_distance_km = extracted$nearest_distance_km[missing],
    nearest_distance_bin = nearest_distance_bin(extracted$nearest_distance_km[missing]),
    nearest_valid_x = extracted$nearest_x[missing],
    nearest_valid_y = extracted$nearest_y[missing],
    raster_x = raster_xy[missing, 1],
    raster_y = raster_xy[missing, 2],
    point_inside_raster_extent = !is.na(cell),
    point_cell_value = ifelse(is.na(cell), NA_real_, raster_values[cell]),
    raster_valid_cells = sum(!is.na(raster_values)),
    raster_nrow = terra::nrow(raster),
    raster_ncol = terra::ncol(raster),
    raster_resolution_x = terra::res(raster)[1],
    raster_resolution_y = terra::res(raster)[2],
    raster_xmin = terra::xmin(raster_extent),
    raster_xmax = terra::xmax(raster_extent),
    raster_ymin = terra::ymin(raster_extent),
    raster_ymax = terra::ymax(raster_extent),
    raster_crs = terra::crs(raster, proj = TRUE),
    stringsAsFactors = FALSE
  )
}

write_dynamic_failure_diagnostics <- function(audit, missing_rows, output_directory) {
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  failed <- audit[audit$unresolved_missing > 0, , drop = FALSE]
  write.csv(failed, file.path(output_directory, "covariate_audit_failed.csv"), row.names = FALSE)
  if (!nrow(missing_rows)) {
    missing_rows <- data.frame(
      .row_id = character(), poly_id = integer(), epiyear = integer(), epiweek = integer(),
      x = numeric(), y = numeric(), variable = character(), fallback_attempted = logical(),
      fallback_distance_km = numeric(), stringsAsFactors = FALSE
    )
  }
  write.csv(missing_rows, file.path(output_directory, "tier2_dynamic_missing.csv"), row.names = FALSE)
  invisible(file.path(output_directory, "covariate_audit_failed.csv"))
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

extract_dynamic_covariates <- function(target, specifications, target_crs, expected_time, missing_policy = "fail", search_radius_km = 0, scope = "dynamic", diagnostic_output_directory = NULL) {
  require_columns(target, c(".row_id", "x", "y", "epiyear", "epiweek"), "dynamic extraction target")
  assert_unique_keys(target, ".row_id", "dynamic extraction target")
  result <- target
  audit <- data.frame()
  missing_diagnostics <- list()
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
      extracted <- extract_raster_points(
        raster, points, method = "bilinear", search_radius_km = search_radius_km,
        diagnostic = !is.null(diagnostic_output_directory) && missing_policy == "fail"
      )
      values[which_rows] <- extracted$values
      direct[which_rows] <- extracted$direct
      fallback[which_rows] <- extracted$fallback
      fallback_distance_km[which_rows] <- extracted$fallback_distance_km
      if (!is.null(diagnostic_output_directory) && missing_policy == "fail" && any(extracted$unresolved)) {
        missing_diagnostics[[length(missing_diagnostics) + 1L]] <- dynamic_missing_diagnostics(
          target, nm, scope, raster, points, extracted, which_rows
        )
      }
    }
    result[[nm]] <- values
    index_keys <- paste(index$epiyear, index$epiweek, sep = "-")
    expected_keys <- paste(expected_time$epiyear, expected_time$epiweek, sep = "-")
    audit <- rbind(audit, make_covariate_audit(nm, scope, sum(index_keys %in% expected_keys), list(values = values, direct = direct, fallback = fallback, fallback_distance_km = fallback_distance_km, unresolved = is.na(values)), length(values)))
  }
  if (missing_policy == "fail" && any(audit$unresolved_missing > 0)) {
    missing_rows <- if (length(missing_diagnostics)) dplyr::bind_rows(missing_diagnostics) else data.frame()
    if (!is.null(diagnostic_output_directory)) {
      write_dynamic_failure_diagnostics(audit, missing_rows, diagnostic_output_directory)
    }
    diagnostic_message <- if (!is.null(diagnostic_output_directory)) paste0(
      " Diagnostics written to ", diagnostic_output_directory, "."
    ) else ""
    stop(paste0("Dynamic covariate missingness violates configured policy.", diagnostic_message))
  }
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
