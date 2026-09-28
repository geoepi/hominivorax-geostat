# Helpers for the post-fit structural-surface diagnostic.  These functions do
# not fit, project, or rasterize the accepted model product; they only operate
# on immutable posterior summaries and already-built Stage 2/Phase 3 grids.

`%||%` <- function(x, y) if (is.null(x)) y else x

structural_require <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Package required for structural diagnostics: ", package)
  invisible(TRUE)
}

structural_read_authoritative_observations <- function(path, target_crs,
                                                       coordinate_source = "lonlat",
                                                       source_crs = "EPSG:4326") {
  if (is.null(path) || length(path) != 1L || !file.exists(path)) stop("Authoritative observation file does not exist: ", path)
  if (is.null(coordinate_source) || length(coordinate_source) != 1L || !tolower(as.character(coordinate_source)) %in% c("lonlat", "xy")) {
    stop("coordinate_source must be explicitly 'lonlat' or 'xy'.")
  }
  if (is.null(source_crs) || length(source_crs) != 1L || is.na(source_crs) || !nzchar(as.character(source_crs))) {
    stop("source_crs must be explicit for the authoritative coordinates.")
  }
  object <- if (tolower(tools::file_ext(path)) == "rds") readRDS(path) else utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  data <- if (is.list(object) && !is.data.frame(object)) object$data %||% object$observations else object
  if (!is.data.frame(data)) stop("Authoritative observations must be a data frame or an RDS object containing one.")
  coordinate_source <- tolower(as.character(coordinate_source))
  columns <- if (identical(coordinate_source, "lonlat")) c("lon", "lat") else c("x", "y")
  if (!all(columns %in% names(data))) stop("Authoritative observations are missing selected coordinate columns: ", paste(columns, collapse = "/"), ".")
  structural_require("sf")
  coordinates <- data[, columns, drop = FALSE]
  coordinates[[1L]] <- as.numeric(coordinates[[1L]])
  coordinates[[2L]] <- as.numeric(coordinates[[2L]])
  if (any(!is.finite(as.matrix(coordinates)))) stop("Authoritative coordinates contain non-finite values.")
  if (identical(coordinate_source, "lonlat") && (any(coordinates[[1L]] < -180 | coordinates[[1L]] > 180) || any(coordinates[[2L]] < -90 | coordinates[[2L]] > 90))) {
    stop("Authoritative lon/lat coordinates are outside valid geographic bounds.")
  }
  points <- sf::st_as_sf(coordinates, coords = columns, crs = source_crs, remove = FALSE)
  transformed <- sf::st_transform(points, target_crs)
  xy <- sf::st_coordinates(transformed)
  data$x <- xy[, 1L]
  data$y <- xy[, 2L]
  list(
    data = data,
    provenance = list(
      path = normalizePath(path, mustWork = TRUE), coordinate_source = coordinate_source,
      source_columns = columns, source_crs = as.character(source_crs),
      target_crs = as.character(target_crs), transform_method = "sf::st_transform",
      coordinate_columns_present = intersect(c("lon", "lat", "x", "y"), names(data))
    )
  )
}

structural_coordinate_audit <- function(observations, provenance) {
  if (!is.data.frame(observations)) stop("observations must be a data frame.")
  coordinate_columns <- intersect(c("lon", "lat", "x", "y"), names(observations))
  ranges <- lapply(coordinate_columns, function(column) {
    values <- suppressWarnings(as.numeric(observations[[column]]))
    c(min = if (any(is.finite(values))) min(values, na.rm = TRUE) else NA_real_,
      max = if (any(is.finite(values)) ) max(values, na.rm = TRUE) else NA_real_)
  })
  names(ranges) <- coordinate_columns
  discrepancy <- NULL
  if (all(c("lon", "lat", "x", "y") %in% names(observations))) {
    structural_require("sf")
    source_points <- sf::st_as_sf(observations[c("lon", "lat")], coords = c("lon", "lat"), crs = provenance$source_crs, remove = FALSE)
    projected <- sf::st_coordinates(sf::st_transform(source_points, provenance$target_crs))
    dx <- projected[, 1L] - as.numeric(observations$x)
    dy <- projected[, 2L] - as.numeric(observations$y)
    discrepancy <- data.frame(
      median_abs_dx = stats::median(abs(dx), na.rm = TRUE),
      q95_abs_dx = as.numeric(stats::quantile(abs(dx), 0.95, na.rm = TRUE, names = FALSE)),
      max_abs_dx = max(abs(dx), na.rm = TRUE),
      median_abs_dy = stats::median(abs(dy), na.rm = TRUE),
      q95_abs_dy = as.numeric(stats::quantile(abs(dy), 0.95, na.rm = TRUE, names = FALSE)),
      max_abs_dy = max(abs(dy), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  list(
    coordinate_columns_present = coordinate_columns,
    ranges = ranges,
    coordinate_source = provenance$coordinate_source,
    source_crs = provenance$source_crs,
    target_crs = provenance$target_crs,
    transform_method = provenance$transform_method,
    both_coordinate_pairs_present = all(c("lon", "lat", "x", "y") %in% coordinate_columns),
    discrepancy = discrepancy,
    note = if (all(c("x", "y") %in% coordinate_columns)) "Projected x/y retained for audit; selected source is explicit." else "Authoritative input has no x/y pair; projected x/y were derived from the selected lon/lat source."
  )
}

structural_observation_intersection_audit <- function(observations, template, potential_stack = NULL) {
  structural_require("terra")
  if (!inherits(template, "SpatRaster")) template <- terra::rast(template)
  if (!all(c("x", "y") %in% names(observations))) stop("Projected observations must contain x and y columns.")
  xy <- observations[, c("x", "y"), drop = FALSE]
  ext <- terra::ext(template)
  inside_extent <- xy$x >= ext$xmin & xy$x <= ext$xmax & xy$y >= ext$ymin & xy$y <= ext$ymax
  cell <- rep(NA_integer_, nrow(xy)); cell[inside_extent] <- terra::cellFromXY(template, xy[inside_extent, , drop = FALSE])
  supported <- rep(FALSE, nrow(xy))
  supported[inside_extent] <- !is.na(terra::extract(template, xy[inside_extent, , drop = FALSE])[, 2L])
  finite_potential <- rep(NA, nrow(xy))
  if (!is.null(potential_stack)) {
    if (!inherits(potential_stack, "SpatRaster")) potential_stack <- terra::rast(potential_stack)
    extracted <- terra::extract(potential_stack, xy)
    values <- as.matrix(extracted[, -1L, drop = FALSE])
    finite_potential <- apply(values, 1L, function(row) any(is.finite(row)))
  }
  data.frame(
    total = nrow(xy), inside_extent = sum(inside_extent), outside_extent = sum(!inside_extent),
    supported = sum(supported), unsupported = sum(inside_extent & !supported),
    finite_potential_extraction = if (all(is.na(finite_potential))) NA_integer_ else sum(finite_potential, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

structural_tier2_nonspde_components <- function(data, components) {
  mapping <- components$mapping$tier2
  fixed <- joint_inla_project_fixed_contributions(data, components$fixed, mapping, "intercept2", "tier2")
  week <- joint_inla_project_random_lookup(components$random$tier2_week, data[[unname(mapping[["tier2_week"]])]], "tier2_week")
  cattle <- joint_inla_project_cattle_contribution(data, mapping, components$random$cattle_q, components$cattle_support)
  out <- cbind(fixed, data.frame(
    week_contribution = week,
    cattle_q = cattle$cattle_q,
    cattle_mid_log1p = cattle$cattle_mid_log1p,
    cattle_random_mean = cattle$cattle_random_mean,
    cattle_rw2_contribution = cattle$cattle_rw2_contribution,
    stringsAsFactors = FALSE
  ))
  out$structural_eta2 <- out$fixed_total + out$week_contribution + out$cattle_rw2_contribution
  out
}

structural_reconstruction_metrics <- function(full_eta, structural_eta, tier2_field, tier2_copy_field,
                                              tolerance = c(rmse = 1e-8, max_abs = 1e-6)) {
  vectors <- list(full_eta = full_eta, structural_eta = structural_eta, tier2_field = tier2_field, tier2_copy_field = tier2_copy_field)
  if (length(unique(vapply(vectors, length, integer(1L)))) != 1L) stop("Reconstruction vectors have different lengths.")
  reconstructed <- structural_eta + tier2_field + tier2_copy_field
  error <- reconstructed - full_eta
  finite <- is.finite(error) & is.finite(reconstructed)
  rmse <- if (any(finite)) sqrt(mean(error[finite]^2)) else Inf
  maximum <- if (any(finite)) max(abs(error[finite])) else Inf
  list(
    n = length(error), rmse = rmse, max_abs = maximum,
    nonfinite = sum(!finite), pass = all(finite) && rmse <= tolerance[["rmse"]] && maximum <= tolerance[["max_abs"]],
    only_removed = "tier2_field and tier2_copy_field; fixed effects, environmental covariates/interactions, livestock RW2, and Tier 2 RW1 remain in structural_eta2",
    reconstructed = reconstructed, error = error
  )
}

structural_validate_temperature_alignment <- function(grid, expected_weeks, expected_cells, variable = "mintemp") {
  if (!is.data.frame(grid) || !variable %in% names(grid)) stop("Temperature alignment source is missing: ", variable)
  required <- c("epiyear", "epiweek", "cell_id", variable)
  if (!all(required %in% names(grid))) stop("Temperature alignment requires: ", paste(required, collapse = ", "))
  week_key <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-")
  counts <- table(week_key)
  finite <- is.finite(as.numeric(grid[[variable]]))
  list(
    pass = length(counts) == as.integer(expected_weeks) && all(as.integer(counts) == as.integer(expected_cells)) && all(finite),
    variable = variable, weeks = length(counts), cells_per_week = sort(unique(as.integer(counts))),
    missing_values = sum(!finite), duplicate_week_cell = anyDuplicated(paste(week_key, grid$cell_id, sep = "|")) > 0L,
    source = "Stage 2 prediction_grid; model-aligned weekly covariate"
  )
}

structural_apply_temperature_mask <- function(values, temperature, threshold, operator = ">=") {
  if (length(values) != length(temperature)) stop("Temperature and surface vectors must have equal lengths.")
  if (length(threshold) != 1L || !is.finite(threshold)) stop("A finite temperature threshold is required for masking.")
  if (!identical(operator, ">=")) stop("Only the configured >= temperature-mask operator is supported.")
  out <- as.numeric(values)
  retain <- is.finite(temperature) & temperature >= threshold
  out[is.finite(out) & !retain] <- 0
  out[!is.finite(temperature)] <- NA_real_
  out
}

structural_paired_quantiles <- function(values, probabilities = c(.05, .10, .25, .50, .75, .90, .95)) {
  values <- as.numeric(values)
  if (!length(values) || !any(is.finite(values))) stop("Same-week paired values contain no finite predictions.")
  if (any(!is.finite(probabilities)) || any(probabilities < 0 | probabilities > 1)) stop("Quantile probabilities must be finite and between 0 and 1.")
  stats::quantile(values[is.finite(values)], probs = probabilities, names = FALSE, type = 7)
}

structural_same_week_extract <- function(observations, stack, week_keys, target_crs = NULL) {
  structural_require("terra")
  if (!inherits(stack, "SpatRaster")) stack <- terra::rast(stack)
  if (!all(c("x", "y") %in% names(observations))) stop("Observations must contain projected x and y columns.")
  if ("date" %in% names(observations)) {
    structural_require("lubridate")
    date <- as.Date(as.character(observations$date))
    temporal <- data.frame(epiyear = lubridate::isoyear(date), epiweek = lubridate::isoweek(date))
  } else if (all(c("epiyear", "epiweek") %in% names(observations))) {
    temporal <- observations[c("epiyear", "epiweek")]
  } else stop("Same-week extraction requires date or epiyear/epiweek observation fields.")
  keys <- preprocessing_epiweek_label(temporal$epiyear, temporal$epiweek)
  layer <- match(keys, as.character(week_keys))
  matched <- !is.na(layer)
  values <- rep(NA_real_, nrow(observations))
  if (any(matched)) {
    for (index in sort(unique(layer[matched]))) {
      rows <- which(layer == index)
      extracted <- terra::extract(stack[[index]], observations[rows, c("x", "y"), drop = FALSE])
      values[rows] <- as.numeric(extracted[, 2L])
    }
  }
  data.frame(observation_index = seq_len(nrow(observations)), week_key = keys, matched = matched,
             extracted_value = values, stringsAsFactors = FALSE)
}

structural_rpi_threshold_sensitivity <- function(count_stack, observations, thresholds,
                                                 gen_days = 21, days_per_layer = 7) {
  structural_require("terra")
  if (!length(thresholds) || any(!is.finite(thresholds))) stop("Threshold sensitivity requires finite candidate thresholds.")
  if (!all(c("x", "y") %in% names(observations))) stop("RPI sensitivity observations must contain x and y.")
  points <- terra::vect(observations, geom = c("x", "y"), crs = terra::crs(count_stack))
  values <- as.matrix(terra::extract(count_stack, points)[, -1L, drop = FALSE])
  classes <- lapply(thresholds, function(threshold) {
    max_run <- apply(values, 1L, function(x) {
      suitable <- is.finite(x) & x > threshold
      if (!any(suitable)) return(0)
      runs <- rle(suitable)
      max(runs$lengths[runs$values])
    })
    rpi <- (max_run * days_per_layer) / gen_days
    data.frame(threshold = threshold, n_observations = nrow(values), median_rpi = stats::median(rpi), q95_rpi = as.numeric(stats::quantile(rpi, 0.95, names = FALSE)), stringsAsFactors = FALSE)
  })
  do.call(rbind, classes)
}

structural_northing_diagnostic <- function(class_raster, endemic_value = 3, latitude_bands = NULL) {
  structural_require("terra")
  if (!inherits(class_raster, "SpatRaster")) class_raster <- terra::rast(class_raster)
  cells <- which(as.numeric(terra::values(class_raster, mat = FALSE)) == endemic_value)
  if (!length(cells)) return(data.frame(class = "Endemic Core", cells = 0L, median_northing = NA_real_, q95_northing = NA_real_, max_northing = NA_real_, stringsAsFactors = FALSE))
  xy <- terra::xyFromCell(class_raster, cells)
  data.frame(class = "Endemic Core", cells = length(cells), median_northing = stats::median(xy[, 2L]),
             q95_northing = as.numeric(stats::quantile(xy[, 2L], 0.95, names = FALSE)), max_northing = max(xy[, 2L]),
             latitude_bands = if (is.null(latitude_bands)) NA_character_ else paste(latitude_bands, collapse = "|"), stringsAsFactors = FALSE)
}
