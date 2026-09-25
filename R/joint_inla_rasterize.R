# Phase 3 rasterization and computational surface QA.
#
# This module serializes validated Phase 2 prediction tables to the exact
# Stage 1 template geometry.  cell_id is the only authoritative placement
# key; coordinates are used only for an independent diagnostic check.

`%||%` <- function(x, y) if (is.null(x)) y else x

joint_inla_rasterize_require <- function(packages = c("terra", "digest", "sf")) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) stop("Phase 3 requires missing packages: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}

joint_inla_rasterize_hash_file <- function(path) {
  if (!file.exists(path)) stop("Cannot hash missing file: ", path)
  digest::digest(file = path, algo = "sha256")
}

joint_inla_rasterize_is_absolute <- function(path) {
  grepl("^(?:[A-Za-z]:[/\\\\]|/)", as.character(path))
}

joint_inla_rasterize_resolve_path <- function(path, bases = character()) {
  if (is.null(path) || !length(path) || is.na(path[[1L]]) || !nzchar(as.character(path[[1L]]))) return(NA_character_)
  path <- as.character(path[[1L]])
  candidates <- if (joint_inla_rasterize_is_absolute(path)) path else file.path(bases, path)
  candidates <- unique(candidates)
  found <- candidates[file.exists(candidates)]
  if (!length(found)) return(normalizePath(candidates[[1L]], mustWork = FALSE))
  normalizePath(found[[1L]], mustWork = TRUE)
}

joint_inla_rasterize_path_values <- function(x) {
  if (is.null(x)) return(character())
  if (is.atomic(x) && is.null(dim(x))) return(as.character(x))
  if (is.list(x)) return(unlist(lapply(x, joint_inla_rasterize_path_values), use.names = FALSE))
  character()
}

joint_inla_rasterize_extract_template_candidate <- function(object) {
  candidates <- character()
  if (!is.list(object)) return(candidates)
  candidates <- c(
    candidates,
    object$configuration$inputs$template_raster,
    object$joint_model_config$inputs$template_raster,
    object$preprocessing_metadata$template_raster,
    object$provenance$template_raster,
    object$provenance$source_template_raster
  )
  unique(joint_inla_rasterize_path_values(candidates))
}

joint_inla_rasterize_resolve_template <- function(stage2_artifact,
                                                   stage2_path = NULL,
                                                   template_path = NULL,
                                                   repo_root = getwd()) {
  if (is.character(stage2_artifact) && length(stage2_artifact) == 1L) {
    if (!file.exists(stage2_artifact)) stop("Stage 2 artifact does not exist: ", stage2_artifact)
    stage2_path <- normalizePath(stage2_artifact, mustWork = TRUE)
    stage2 <- readRDS(stage2_path)
  } else {
    stage2 <- stage2_artifact
    if (!is.null(stage2_path) && file.exists(stage2_path)) stage2_path <- normalizePath(stage2_path, mustWork = TRUE)
  }
  if (!is.list(stage2) || !is.data.frame(stage2$prediction_grid)) {
    stop("Stage 2 artifact must be a list containing prediction_grid.")
  }
  stage2_dir <- if (!is.null(stage2_path)) dirname(stage2_path) else repo_root
  source_model_inputs <- c(
    stage2$provenance$source_model_inputs,
    stage2$provenance$source_artifact,
    stage2$preprocessing_metadata$source_model_inputs
  )
  source_model_inputs <- unique(joint_inla_rasterize_path_values(source_model_inputs))
  source_paths <- vapply(source_model_inputs, joint_inla_rasterize_resolve_path,
                         character(1L), bases = unique(c(stage2_dir, repo_root, getwd())))
  source_paths <- unique(source_paths[file.exists(source_paths)])

  provenance_objects <- list(stage2)
  if (length(source_paths)) {
    provenance_objects <- c(provenance_objects, lapply(source_paths, readRDS))
  }
  direct <- c(template_path, unlist(lapply(provenance_objects, joint_inla_rasterize_extract_template_candidate), use.names = FALSE))
  direct <- unique(joint_inla_rasterize_path_values(direct))
  direct_paths <- vapply(direct, joint_inla_rasterize_resolve_path,
                         character(1L), bases = unique(c(stage2_dir, repo_root, getwd(), dirname(source_paths))))
  direct_paths <- unique(direct_paths[file.exists(direct_paths)])
  if (!length(direct_paths)) {
    stop("Canonical template raster could not be recovered from Stage 2/Stage 1 provenance. Supply --template explicitly.")
  }
  if (length(direct_paths) > 1L) {
    if (is.null(template_path)) {
      stop("Template provenance is ambiguous; candidates are: ", paste(direct_paths, collapse = ", "))
    }
    chosen <- joint_inla_rasterize_resolve_path(template_path, bases = unique(c(stage2_dir, repo_root, getwd())))
    if (!identical(chosen, direct_paths[[1L]]) && !chosen %in% direct_paths) stop("Explicit template does not reconcile with recovered provenance.")
    direct_paths <- chosen
  }
  template <- terra::rast(direct_paths[[1L]])
  if (terra::nlyr(template) != 1L) stop("Canonical template must have exactly one layer.")
  list(stage2 = stage2, stage2_path = stage2_path, stage2_dir = stage2_dir,
       source_model_inputs = source_paths, template_path = direct_paths[[1L]], template = template)
}

joint_inla_rasterize_template_geometry <- function(template) {
  if (!inherits(template, "SpatRaster") || terra::nlyr(template) != 1L) stop("template must be a single-layer SpatRaster.")
  e <- terra::ext(template)
  r <- terra::res(template)
  values <- terra::values(template, mat = FALSE)
  valid <- which(!is.na(values))
  list(
    crs = terra::crs(template, proj = FALSE),
    crs_wkt = terra::crs(template, proj = TRUE),
    extent = c(xmin = e$xmin, xmax = e$xmax, ymin = e$ymin, ymax = e$ymax),
    resolution = c(x = r[[1L]], y = r[[2L]]),
    nrow = terra::nrow(template), ncol = terra::ncol(template),
    ncell = terra::ncell(template),
    non_na_cells = length(valid),
    cell_number_range = if (length(valid)) range(valid) else c(NA_integer_, NA_integer_)
  )
}

joint_inla_rasterize_temporal_support <- function(stage2) {
  grid <- stage2$prediction_grid
  required <- c("epiyear", "epiweek", "cell_id")
  missing <- setdiff(required, names(grid))
  if (length(missing)) stop("Stage 2 prediction_grid is missing: ", paste(missing, collapse = ", "))
  grid$week_key <- paste(as.integer(grid$epiyear), as.integer(grid$epiweek), sep = "-W")
  mapping <- stage2$temporal_mapping
  if (is.data.frame(mapping) && all(c("epiyear", "epiweek") %in% names(mapping))) {
    mapping$week_key <- paste(as.integer(mapping$epiyear), as.integer(mapping$epiweek), sep = "-W")
    if (anyDuplicated(mapping$week_key)) stop("Stage 2 temporal_mapping has duplicate year-week keys.")
    time_index <- if ("time_index" %in% names(mapping)) mapping$time_index else seq_len(nrow(mapping))
    time_map <- stats::setNames(as.integer(time_index), mapping$week_key)
  } else {
    keys <- unique(grid$week_key)
    time_map <- stats::setNames(seq_along(keys), keys)
  }
  keys <- unique(grid$week_key)
  expected_support <- lapply(keys, function(key) sort(unique(as.integer(grid$cell_id[grid$week_key == key]))))
  names(expected_support) <- keys
  if (any(vapply(expected_support, length, integer(1L)) < 1L)) stop("Stage 2 prediction_grid has an empty weekly support.")
  list(weeks = keys[order(as.integer(time_map[keys]))], time_index = time_map,
       expected_support = expected_support)
}

joint_inla_rasterize_read_phase2_metadata <- function(phase2_dir, run_id) {
  candidates <- c(
    file.path(phase2_dir, paste0("prediction_projection_metadata_", run_id, ".rds")),
    file.path(phase2_dir, "prediction_projection_metadata.rds")
  )
  path <- candidates[file.exists(candidates)][1L]
  if (is.na(path)) return(list(path = NA_character_, metadata = list()))
  list(path = normalizePath(path, mustWork = TRUE), metadata = readRDS(path))
}

joint_inla_rasterize_read_manifest <- function(phase2_dir, run_id, expected_weeks = 105L) {
  manifest_path <- file.path(phase2_dir, paste0("prediction_projection_manifest_", run_id, ".csv"))
  if (!file.exists(manifest_path)) stop("Phase 2 manifest does not exist: ", manifest_path)
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("epiyear", "epiweek", "rows", "path", "sha256")
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("Phase 2 manifest is missing: ", paste(missing, collapse = ", "))
  if (nrow(manifest) != as.integer(expected_weeks)) stop("Phase 2 manifest has ", nrow(manifest), " weeks; expected ", expected_weeks, ".")
  if (anyDuplicated(paste(manifest$epiyear, manifest$epiweek, sep = "-W"))) stop("Phase 2 manifest has duplicate year-week keys.")
  if (any(!nzchar(as.character(manifest$sha256))) || any(!grepl("^[0-9a-fA-F]{64}$", manifest$sha256))) stop("Phase 2 manifest has invalid SHA-256 checksums.")
  actual_paths <- vapply(seq_len(nrow(manifest)), function(i) {
    listed <- as.character(manifest$path[[i]])
    candidates <- unique(c(listed, file.path(phase2_dir, "weekly", basename(listed)), file.path(phase2_dir, basename(listed))))
    found <- candidates[file.exists(candidates)]
    if (!length(found)) stop("Manifest weekly file does not exist: ", listed)
    normalizePath(found[[1L]], mustWork = TRUE)
  }, character(1L))
  actual_sha <- vapply(actual_paths, joint_inla_rasterize_hash_file, character(1L))
  if (any(tolower(actual_sha) != tolower(as.character(manifest$sha256)))) {
    bad <- which(tolower(actual_sha) != tolower(as.character(manifest$sha256)))
    stop("Phase 2 weekly checksum mismatch at manifest row(s): ", paste(bad, collapse = ", "))
  }
  filename <- basename(actual_paths)
  parsed <- regexec("^prediction_y([0-9]{4})_w([0-9]{2})\\.rds$", filename, ignore.case = TRUE)
  parsed <- regmatches(filename, parsed)
  if (any(vapply(parsed, length, integer(1L)) != 3L)) stop("Phase 2 weekly files do not follow the canonical filename contract.")
  parsed_year <- as.integer(vapply(parsed, `[[`, character(1L), 2L))
  parsed_week <- as.integer(vapply(parsed, `[[`, character(1L), 3L))
  if (any(parsed_year != as.integer(manifest$epiyear) | parsed_week != as.integer(manifest$epiweek))) stop("Phase 2 manifest year/week disagrees with a weekly filename.")
  manifest$actual_path <- actual_paths
  manifest$manifest_path <- normalizePath(manifest_path, mustWork = TRUE)
  manifest$filename <- filename
  manifest$week_key <- paste(as.integer(manifest$epiyear), as.integer(manifest$epiweek), sep = "-W")
  manifest[order(as.integer(manifest$epiyear), as.integer(manifest$epiweek)), , drop = FALSE]
}

joint_inla_rasterize_validate_cell_ids <- function(cell_id, template, require_complete = FALSE, expected_cell_ids = NULL) {
  if (length(cell_id) == 0L) stop("cell_id is empty.")
  numeric_id <- suppressWarnings(if (is.factor(cell_id)) as.numeric(as.character(cell_id)) else as.numeric(cell_id))
  if (any(!is.finite(numeric_id)) || any(numeric_id != floor(numeric_id))) stop("cell_id must be finite integer-like values.")
  numeric_id <- as.integer(numeric_id)
  if (any(numeric_id < 1L | numeric_id > terra::ncell(template))) stop("cell_id is outside the template cell-number range.")
  if (any(is.na(terra::values(template, mat = FALSE)[numeric_id]))) stop("Phase 2 cell_id maps to an NA template cell.")
  if (anyDuplicated(numeric_id)) stop("Weekly Phase 2 data contain duplicate cell_id values.")
  if (!is.null(expected_cell_ids) && !setequal(numeric_id, as.integer(expected_cell_ids))) stop("Weekly Phase 2 cell_id set does not match Stage 2 prediction support.")
  if (isTRUE(require_complete) && (is.null(expected_cell_ids) || !setequal(numeric_id, as.integer(expected_cell_ids)))) stop("Complete cell support is required but cell_id support is incomplete.")
  numeric_id
}

joint_inla_rasterize_validate_week <- function(data, year, week, expected_cell_ids = NULL, expected_rows = NULL) {
  if (!is.data.frame(data)) stop("Weekly Phase 2 file must contain a data frame.")
  required <- c("cell_id", "x", "y", "epiyear", "epiweek", "eta1_mean", "tier1_probability_plugin", "eta2_mean", "tier2_intensity_plugin")
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("Weekly Phase 2 data are missing: ", paste(missing, collapse = ", "))
  if (nrow(data) < 1L) stop("Weekly Phase 2 data are empty.")
  if (any(as.integer(data$epiyear) != as.integer(year)) || any(as.integer(data$epiweek) != as.integer(week))) stop("Weekly Phase 2 contents disagree with filename year/week.")
  if (length(unique(paste(data$epiyear, data$epiweek, sep = "-W"))) != 1L) stop("Weekly Phase 2 file contains mixed weeks.")
  stable_id <- c("space_time_id", ".row_id")[c("space_time_id", ".row_id") %in% names(data)][1L]
  if (is.na(stable_id) || anyDuplicated(as.character(data[[stable_id]]))) stop("Weekly Phase 2 data must contain a unique stable space-time ID.")
  for (column in c("x", "y", "eta1_mean", "tier1_probability_plugin", "eta2_mean", "tier2_intensity_plugin")) {
    if (any(!is.finite(as.numeric(data[[column]])))) stop("Weekly Phase 2 field contains non-finite values: ", column)
  }
  if (any(data$tier1_probability_plugin < 0 | data$tier1_probability_plugin > 1)) stop("Weekly Tier 1 probability is outside [0, 1].")
  if (any(data$tier2_intensity_plugin <= 0)) stop("Weekly Tier 2 intensity must be strictly positive.")
  if (!is.null(expected_rows) && nrow(data) != as.integer(expected_rows)) stop("Weekly Phase 2 row count does not match Stage 2 support.")
  if (!is.null(expected_cell_ids) && !setequal(as.integer(data$cell_id), as.integer(expected_cell_ids))) stop("Weekly Phase 2 cell_id set does not match Stage 2 support.")
  invisible(TRUE)
}

joint_inla_rasterize_assign_values <- function(template, cell_id, values) {
  joint_inla_rasterize_require(c("terra"))
  if (length(cell_id) != length(values)) stop("cell_id and values must have equal lengths.")
  ids <- joint_inla_rasterize_validate_cell_ids(cell_id, template)
  values <- as.numeric(values)
  if (any(!is.finite(values))) stop("Raster values must be finite.")
  output <- template[[1L]]
  terra::values(output) <- NA_real_
  out_values <- terra::values(output, mat = FALSE)
  out_values[ids] <- values
  terra::values(output) <- out_values
  output
}

joint_inla_rasterize_coordinate_crosscheck <- function(template, cell_coordinates, target_crs, tolerance = 1e-7) {
  joint_inla_rasterize_require(c("terra", "sf"))
  required <- c("cell_id", "x", "y")
  if (!all(required %in% names(cell_coordinates))) stop("Coordinate cross-check requires cell_id, x, and y.")
  ids <- joint_inla_rasterize_validate_cell_ids(cell_coordinates$cell_id, template)
  original <- terra::xyFromCell(template, ids)
  target <- sf::st_crs(target_crs)
  if (is.na(target)) stop("Prediction coordinate CRS is missing or invalid.")
  source <- sf::st_as_sf(data.frame(cell_id = ids, x = original[, 1L], y = original[, 2L]),
                         coords = c("x", "y"), crs = terra::crs(template, proj = TRUE), remove = FALSE)
  transformed <- sf::st_transform(source, target)
  expected <- sf::st_coordinates(transformed)
  observed_x <- as.numeric(cell_coordinates$x)
  observed_y <- as.numeric(cell_coordinates$y)
  dx <- expected[, 1L] - observed_x
  dy <- expected[, 2L] - observed_y
  summary <- data.frame(
    n = length(ids), mean_absolute_x_difference = mean(abs(dx)), mean_absolute_y_difference = mean(abs(dy)),
    maximum_absolute_x_difference = max(abs(dx)), maximum_absolute_y_difference = max(abs(dy)),
    tolerance = tolerance, pass = max(abs(dx)) <= tolerance && max(abs(dy)) <= tolerance,
    stringsAsFactors = FALSE
  )
  details <- data.frame(cell_id = ids, expected_x = expected[, 1L], expected_y = expected[, 2L],
                        observed_x = observed_x, observed_y = observed_y, dx = dx, dy = dy,
                        stringsAsFactors = FALSE)
  list(summary = summary, details = details)
}

joint_inla_rasterize_stats <- function(values) {
  values <- as.numeric(values)
  finite <- is.finite(values)
  observed <- values[finite]
  q <- if (length(observed)) stats::quantile(observed, c(.01, .05, .25, .5, .75, .95, .99), names = FALSE, type = 7) else rep(NA_real_, 7L)
  data.frame(
    n = length(values), minimum = if (length(observed)) min(observed) else NA_real_,
    Q01 = q[[1L]], Q05 = q[[2L]], Q25 = q[[3L]], median = q[[4L]], mean = if (length(observed)) mean(observed) else NA_real_,
    Q75 = q[[5L]], Q95 = q[[6L]], Q99 = q[[7L]], maximum = if (length(observed)) max(observed) else NA_real_,
    nonfinite = sum(!finite), na_count = sum(is.na(values)), stringsAsFactors = FALSE
  )
}

joint_inla_rasterize_roundtrip_metrics <- function(source, raster_values, tolerance = c(rmse = 1e-12, maximum = 1e-10)) {
  source <- as.numeric(source); raster_values <- as.numeric(raster_values)
  if (length(source) != length(raster_values)) stop("Round-trip vectors must have equal lengths.")
  if (any(!is.finite(source)) || any(!is.finite(raster_values))) stop("Round-trip comparison requires finite values.")
  error <- raster_values - source
  absolute <- abs(error)
  out <- data.frame(
    n = length(error), mean_signed_error = mean(error), MAE = mean(absolute), RMSE = sqrt(mean(error^2)),
    median_absolute_error = stats::median(absolute), Q95_absolute_error = as.numeric(stats::quantile(absolute, .95, names = FALSE)),
    Q99_absolute_error = as.numeric(stats::quantile(absolute, .99, names = FALSE)), maximum_absolute_error = max(absolute),
    rmse_tolerance = unname(tolerance[["rmse"]]), maximum_tolerance = unname(tolerance[["maximum"]]),
    pass = sqrt(mean(error^2)) <= tolerance[["rmse"]] && max(absolute) <= tolerance[["maximum"]], stringsAsFactors = FALSE
  )
  out
}

joint_inla_rasterize_geometry_equal <- function(x, y) {
  if (!inherits(x, "SpatRaster") || !inherits(y, "SpatRaster")) return(FALSE)
  same_vector <- function(a, b) isTRUE(all.equal(as.numeric(unclass(a)), as.numeric(unclass(b)), tolerance = 0, check.attributes = FALSE))
  extent_vector <- function(e) c(e$xmin, e$xmax, e$ymin, e$ymax)
  isTRUE(terra::same.crs(x, y)) &&
    identical(terra::nrow(x), terra::nrow(y)) && identical(terra::ncol(x), terra::ncol(y)) &&
    same_vector(terra::res(x), terra::res(y)) && same_vector(extent_vector(terra::ext(x)), extent_vector(terra::ext(y))) &&
    same_vector(terra::origin(x), terra::origin(y)) &&
    identical(terra::is.rotated(x), terra::is.rotated(y))
}

joint_inla_rasterize_write <- function(raster, path, compression = c("COMPRESS=DEFLATE", "PREDICTOR=3"), overwrite = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(raster, path, overwrite = overwrite,
                     wopt = list(datatype = "FLT8S", gdal = compression, NAflag = -9999))
  if (!file.exists(path)) stop("Raster write did not produce a file: ", path)
  normalizePath(path, mustWork = TRUE)
}

joint_inla_rasterize_raster_manifest_row <- function(path, family, year = NA_integer_, week = NA_integer_, time_index = NA_integer_, raster = terra::rast(path)) {
  e <- terra::ext(raster); r <- terra::res(raster); values <- terra::values(raster, mat = FALSE); finite <- values[is.finite(values)]
  data.frame(
    relative_path = NA_character_, path = normalizePath(path, mustWork = TRUE), raster_family = family,
    epiyear = year, epiweek = week, time_index = time_index, sha256 = joint_inla_rasterize_hash_file(path),
    file_size = file.info(path)$size, nrow = terra::nrow(raster), ncol = terra::ncol(raster),
    resolution_x = r[[1L]], resolution_y = r[[2L]], xmin = e$xmin, xmax = e$xmax, ymin = e$ymin, ymax = e$ymax,
    crs = terra::crs(raster, proj = TRUE), datatype = terra::datatype(raster)[[1L]], non_na_cells = sum(!is.na(values)),
    minimum = if (length(finite)) min(finite) else NA_real_, maximum = if (length(finite)) max(finite) else NA_real_,
    stringsAsFactors = FALSE
  )
}

joint_inla_rasterize_make_diagnostic <- function(raster_path, output_path, title) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::png(output_path, width = 1400, height = 1100, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  terra::plot(terra::rast(raster_path), main = title, axes = TRUE)
  invisible(output_path)
}

joint_inla_rasterize_run <- function(phase2_dir,
                                     stage2_artifact = NULL,
                                     template_path = NULL,
                                     output_dir = NULL,
                                     run_id = "20725437",
                                     expected_weeks = 105L,
                                     expected_rows = 1669395L,
                                     coordinate_tolerance = 1e-7,
                                     roundtrip_tolerances = c(rmse = 1e-12, maximum = 1e-10),
                                     source_phase2_commit = "1bcb6deb554c6f9b84013040487fbdb9470a2c0e",
                                     diagnostic = TRUE,
                                     overwrite = FALSE,
                                     repo_root = getwd()) {
  joint_inla_rasterize_require()
  phase2_dir <- normalizePath(phase2_dir, mustWork = TRUE)
  output_dir <- output_dir %||% file.path(dirname(phase2_dir), paste0("raster_surfaces_", run_id))
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  if (dir.exists(output_dir) && length(list.files(output_dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !isTRUE(overwrite)) {
    stop("Refusing to write into a non-empty Phase 3 output directory without overwrite=TRUE: ", output_dir)
  }
  phase2_metadata <- joint_inla_rasterize_read_phase2_metadata(phase2_dir, run_id)
  if (is.null(stage2_artifact)) {
    input_paths <- phase2_metadata$metadata$input_paths
    candidates <- unique(c(input_paths$stage2_artifact, input_paths$joint_model_inputs, input_paths$model_inputs, input_paths$stage2))
    candidates <- candidates[!is.na(candidates) & nzchar(as.character(candidates))]
    candidates <- candidates[file.exists(candidates)]
    if (length(candidates) != 1L) stop("Stage 2 artifact was not uniquely recoverable from Phase 2 metadata; supply stage2_artifact explicitly.")
    stage2_artifact <- candidates[[1L]]
  }
  provenance <- joint_inla_rasterize_resolve_template(stage2_artifact, template_path = template_path, repo_root = repo_root)
  stage2 <- provenance$stage2
  support <- joint_inla_rasterize_temporal_support(stage2)
  if (length(support$weeks) != as.integer(expected_weeks)) stop("Stage 2 prediction support has ", length(support$weeks), " weeks; expected ", expected_weeks, ".")
  manifest <- joint_inla_rasterize_read_manifest(phase2_dir, run_id, expected_weeks)
  if (!setequal(manifest$week_key, support$weeks)) stop("Phase 2 manifest week support does not match Stage 2 temporal support.")
  if (!is.null(expected_rows) && sum(as.integer(manifest$rows)) != as.integer(expected_rows)) stop("Phase 2 manifest row total does not match expected total.")
  if (nrow(stage2$prediction_grid) != sum(as.integer(manifest$rows))) stop("Stage 2 prediction-grid row count does not match Phase 2 manifest total.")

  template <- provenance$template
  template_geometry <- joint_inla_rasterize_template_geometry(template)
  phase2_cell_coordinates <- NULL
  all_cell_ids <- integer()
  unseen_rows <- list()
  roundtrip <- list(); distribution <- list(); raster_rows <- list(); temporal_rows <- list(); week_rasters <- list()
  output_subdirs <- c(mask = "mask", tier1_eta = "tier1_eta", tier1_probability = "tier1_probability",
                      tier2_eta = "tier2_eta", tier2_intensity = "tier2_intensity", qa = "qa")
  for (d in unname(output_subdirs)) dir.create(file.path(output_dir, d), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(manifest))) {
    record <- manifest[i, , drop = FALSE]
    data <- readRDS(record$actual_path[[1L]])
    key <- record$week_key[[1L]]
    expected_cells <- support$expected_support[[key]]
    joint_inla_rasterize_validate_week(data, record$epiyear[[1L]], record$epiweek[[1L]], expected_cells, length(expected_cells))
    if (!all(c("admin_effect_source", "admin_f", "admin_u") %in% names(data))) stop("Weekly Phase 2 data are missing administrative QA fields: admin_effect_source, admin_f, and admin_u.")
    if (nrow(data) != as.integer(record$rows[[1L]])) stop("Phase 2 manifest row count disagrees with weekly file: ", record$filename[[1L]])
    ids <- joint_inla_rasterize_validate_cell_ids(data$cell_id, template, expected_cell_ids = expected_cells)
    all_cell_ids <- sort(unique(c(all_cell_ids, ids)))
    coords <- unique(data[c("cell_id", "x", "y")])
    if (anyDuplicated(coords$cell_id)) stop("A Phase 2 cell_id maps to multiple coordinates in week ", key, ".")
    if (is.null(phase2_cell_coordinates)) phase2_cell_coordinates <- coords else {
      previous <- match(coords$cell_id, phase2_cell_coordinates$cell_id)
      common <- !is.na(previous)
      if (any(abs(coords$x[common] - phase2_cell_coordinates$x[previous[common]]) > coordinate_tolerance |
              abs(coords$y[common] - phase2_cell_coordinates$y[previous[common]]) > coordinate_tolerance)) {
        stop("Phase 2 coordinates for a cell_id differ across weeks beyond tolerance.")
      }
      phase2_cell_coordinates <- rbind(phase2_cell_coordinates, coords[!common, , drop = FALSE])
    }
    unseen <- which("admin_effect_source" %in% names(data) & data$admin_effect_source == "unseen_level_zero_mean")
    if (length(unseen)) unseen_rows[[length(unseen_rows) + 1L]] <- data[unseen, c("cell_id", "admin_f", "admin_u", "epiyear", "epiweek"), drop = FALSE]
    year <- as.integer(record$epiyear[[1L]]); week <- as.integer(record$epiweek[[1L]]); time_index <- as.integer(support$time_index[[key]])
    specs <- list(
      eta1_mean = list(family = "tier1_eta", dir = "tier1_eta", prefix = "eta1", source = "eta1_mean"),
      tier1_probability_plugin = list(family = "tier1_probability", dir = "tier1_probability", prefix = "tier1_prob", source = "tier1_probability_plugin"),
      eta2_mean = list(family = "tier2_eta", dir = "tier2_eta", prefix = "eta2", source = "eta2_mean"),
      tier2_intensity_plugin = list(family = "tier2_intensity", dir = "tier2_intensity", prefix = "tier2_intensity", source = "tier2_intensity_plugin")
    )
    week_rasters[[key]] <- list()
    for (variable in names(specs)) {
      spec <- specs[[variable]]
      raster <- joint_inla_rasterize_assign_values(template, ids, data[[spec$source]])
      filename <- sprintf("%s_y%04d_w%02d.tif", spec$prefix, year, week)
      path <- file.path(output_dir, spec$dir, filename)
      path <- joint_inla_rasterize_write(raster, path, overwrite = TRUE)
      reread <- terra::rast(path)
      if (!isTRUE(joint_inla_rasterize_geometry_equal(reread, template))) stop("Raster geometry differs from template: ", path)
      values <- terra::values(reread, mat = FALSE)
      roundtrip[[length(roundtrip) + 1L]] <- cbind(data.frame(raster_family = spec$family, variable = variable, week = key, path = path, stringsAsFactors = FALSE), joint_inla_rasterize_roundtrip_metrics(data[[spec$source]], values[ids], roundtrip_tolerances))
      if (!setequal(which(!is.na(values)), ids)) stop("Raster support differs from Phase 2 cell_id support: ", path)
      source_stats <- joint_inla_rasterize_stats(data[[spec$source]])
      raster_stats <- joint_inla_rasterize_stats(values[ids])
      raster_stats$raster_total_n <- length(values)
      raster_stats$raster_total_na_count <- sum(is.na(values))
      distribution[[length(distribution) + 1L]] <- cbind(data.frame(raster_family = spec$family, variable = variable, week = key, path = path, stringsAsFactors = FALSE),
                                                         setNames(source_stats, paste0("table_", names(source_stats))),
                                                         setNames(raster_stats, paste0("raster_", names(raster_stats))))
      raster_rows[[length(raster_rows) + 1L]] <- joint_inla_rasterize_raster_manifest_row(path, spec$family, year, week, time_index, reread)
      week_rasters[[key]][[variable]] <- path
    }
    temporal_rows[[length(temporal_rows) + 1L]] <- data.frame(time_index = time_index, epiyear = year, epiweek = week, week = key,
                                                                 tier1_eta = week_rasters[[key]]$eta1_mean, tier1_probability = week_rasters[[key]]$tier1_probability_plugin,
                                                                 tier2_eta = week_rasters[[key]]$eta2_mean, tier2_intensity = week_rasters[[key]]$tier2_intensity_plugin,
                                                                 stringsAsFactors = FALSE)
  }
  if (is.null(phase2_cell_coordinates) || !length(all_cell_ids)) stop("No Phase 2 cell support was recovered.")
  target_crs <- stage2$joint_model_config$study$projected_crs %||% stage2$configuration$study$projected_crs
  if (is.null(target_crs) && length(provenance$source_model_inputs)) {
    source_object <- readRDS(provenance$source_model_inputs[[1L]])
    target_crs <- source_object$configuration$study$projected_crs %||% source_object$study$projected_crs
  }
  if (is.null(target_crs)) stop("Prediction coordinate CRS could not be recovered from Stage 1/Stage 2 provenance.")
  coordinate <- joint_inla_rasterize_coordinate_crosscheck(template, phase2_cell_coordinates[order(phase2_cell_coordinates$cell_id), , drop = FALSE], target_crs, coordinate_tolerance)
  if (!isTRUE(coordinate$summary$pass[[1L]])) stop("Coordinate cross-check found material cell-location discrepancies.")

  mask <- template[[1L]]; terra::values(mask) <- NA_real_; mask_values <- terra::values(mask, mat = FALSE); mask_values[all_cell_ids] <- 1; terra::values(mask) <- mask_values
  mask_path <- joint_inla_rasterize_write(mask, file.path(output_dir, "mask", "prediction_cell_mask.tif"), overwrite = TRUE)
  if (!setequal(which(!is.na(terra::values(terra::rast(mask_path), mat = FALSE))), all_cell_ids)) stop("Canonical prediction mask support mismatch.")
  raster_rows[[length(raster_rows) + 1L]] <- joint_inla_rasterize_raster_manifest_row(mask_path, "prediction_cell_mask", NA_integer_, NA_integer_, NA_integer_, terra::rast(mask_path))

  unseen <- if (length(unseen_rows)) do.call(rbind, unseen_rows) else data.frame(cell_id = integer(), admin_f = integer(), admin_u = character(), epiyear = integer(), epiweek = integer(), stringsAsFactors = FALSE)
  unseen_key <- if (nrow(unseen)) paste(unseen$cell_id, unseen$admin_f, unseen$admin_u, sep = "|") else character()
  unseen_summary <- if (nrow(unseen)) {
    unique(unseen[c("cell_id", "admin_f", "admin_u")])
  } else unseen[c("cell_id", "admin_f", "admin_u")]
  if (nrow(unseen_summary)) {
    unseen_summary$row_count <- vapply(seq_len(nrow(unseen_summary)), function(i) sum(unseen_key == paste(unseen_summary$cell_id[[i]], unseen_summary$admin_f[[i]], unseen_summary$admin_u[[i]], sep = "|")), integer(1L))
    unseen_summary$weeks_affected <- vapply(seq_len(nrow(unseen_summary)), function(i) length(unique(paste(unseen$epiyear[unseen$cell_id == unseen_summary$cell_id[[i]] & unseen$admin_f == unseen_summary$admin_f[[i]] & unseen$admin_u == unseen_summary$admin_u[[i]]], unseen$epiweek[unseen$cell_id == unseen_summary$cell_id[[i]] & unseen$admin_f == unseen_summary$admin_f[[i]] & unseen$admin_u == unseen_summary$admin_u[[i]]], sep = "-W"))), integer(1L))
  }
  unseen_mask <- template[[1L]]; terra::values(unseen_mask) <- NA_real_; unseen_values <- terra::values(unseen_mask, mat = FALSE)
  unseen_ids <- sort(unique(as.integer(unseen$cell_id))); if (length(unseen_ids)) unseen_values[unseen_ids] <- 1; terra::values(unseen_mask) <- unseen_values
  unseen_mask_path <- joint_inla_rasterize_write(unseen_mask, file.path(output_dir, "qa", "unseen_admin_cells.tif"), overwrite = TRUE)
  raster_rows[[length(raster_rows) + 1L]] <- joint_inla_rasterize_raster_manifest_row(unseen_mask_path, "unseen_admin_cells", NA_integer_, NA_integer_, NA_integer_, terra::rast(unseen_mask_path))

  raster_manifest <- do.call(rbind, raster_rows)
  raster_manifest$relative_path <- gsub("\\\\", "/", substring(raster_manifest$path, nchar(output_dir) + 2L))
  temporal_manifest <- do.call(rbind, temporal_rows)
  temporal_manifest <- temporal_manifest[order(temporal_manifest$time_index), , drop = FALSE]
  for (column in c("tier1_eta", "tier1_probability", "tier2_eta", "tier2_intensity")) {
    information <- raster_manifest[match(temporal_manifest[[column]], raster_manifest$path), , drop = FALSE]
    temporal_manifest[[paste0(column, "_file_size")]] <- information$file_size
    temporal_manifest[[paste0(column, "_sha256")]] <- information$sha256
    temporal_manifest[[paste0(column, "_non_na_cells")]] <- information$non_na_cells
    temporal_manifest[[paste0(column, "_minimum")]] <- information$minimum
    temporal_manifest[[paste0(column, "_maximum")]] <- information$maximum
  }
  distribution <- do.call(rbind, distribution)
  distribution$pass <- apply(distribution, 1L, function(row) {
    metrics <- paste0("table_", c("n", "minimum", "Q01", "Q05", "Q25", "median", "mean", "Q75", "Q95", "Q99", "maximum", "nonfinite"))
    all(vapply(metrics, function(metric) {
      a <- suppressWarnings(as.numeric(row[[metric]])); b <- suppressWarnings(as.numeric(row[[sub("^table_", "raster_", metric)]]))
      if (is.na(a) && is.na(b)) TRUE else is.finite(a) && is.finite(b) && abs(a - b) <= roundtrip_tolerances[["maximum"]]
    }, logical(1L)))
  })
  roundtrip <- do.call(rbind, roundtrip)
  support_counts <- data.frame(
    week = support$weeks,
    time_index = as.integer(support$time_index[support$weeks]),
    phase2_cells = vapply(support$weeks, function(key) length(support$expected_support[[key]]), integer(1L)),
    stringsAsFactors = FALSE
  )
  support_constant <- length(unique(support_counts$phase2_cells)) == 1L &&
    all(vapply(support$weeks, function(key) identical(support$expected_support[[key]], support$expected_support[[support$weeks[[1L]]]]), logical(1L)))
  audit <- rbind(
    data.frame(section = "source/provenance", check = "phase2_manifest_checksum", status = "PASS", observed = joint_inla_rasterize_hash_file(manifest$manifest_path[[1L]]), expected = "recorded", details = manifest$manifest_path[[1L]], stringsAsFactors = FALSE),
    data.frame(section = "template_geometry", check = "canonical_template_recovered", status = "PASS", observed = provenance$template_path, expected = "recovered from provenance", details = joint_inla_rasterize_hash_file(provenance$template_path), stringsAsFactors = FALSE),
    data.frame(section = "cell_id_mapping", check = "template_cell_support", status = "PASS", observed = length(all_cell_ids), expected = length(all_cell_ids), details = "All Phase 2 cell_id values map to unique non-NA template cells.", stringsAsFactors = FALSE),
    data.frame(section = "coordinate_crosscheck", check = "cell_center_coordinates", status = "PASS", observed = coordinate$summary$maximum_absolute_x_difference + coordinate$summary$maximum_absolute_y_difference, expected = paste0("each axis <= ", coordinate_tolerance), details = "Diagnostic coordinate comparison passed.", stringsAsFactors = FALSE),
    data.frame(section = "weekly_inputs", check = "phase2_weekly_contract", status = "PASS", observed = nrow(manifest), expected = expected_weeks, details = "Manifest checksums and weekly contracts passed.", stringsAsFactors = FALSE),
    data.frame(section = "raster_geometry", check = "all_output_geometry", status = "PASS", observed = nrow(raster_manifest), expected = nrow(raster_manifest), details = "Every output was compared with the canonical template geometry.", stringsAsFactors = FALSE),
    data.frame(section = "raster_support", check = "cell_id_roundtrip_support", status = "PASS", observed = nrow(roundtrip), expected = nrow(roundtrip), details = "Non-NA raster cells equal weekly Phase 2 cell_id sets.", stringsAsFactors = FALSE),
    data.frame(section = "raster_support", check = "canonical_prediction_mask", status = "PASS", observed = length(all_cell_ids), expected = length(all_cell_ids), details = if (support_constant) "Support is constant across all weeks; canonical mask equals every weekly support." else "Support varies by week; canonical mask is the union and weekly support was checked separately.", stringsAsFactors = FALSE),
    data.frame(section = "raster_numerical_roundtrip", check = "table_to_raster_values", status = if (all(roundtrip$pass)) "PASS" else "FAIL", observed = max(roundtrip$maximum_absolute_error), expected = paste(names(roundtrip_tolerances), roundtrip_tolerances, collapse = "; "), details = "Exact cell-ID extraction compared against every Phase 2 weekly value.", stringsAsFactors = FALSE),
    data.frame(section = "temporal_support", check = "week_manifest", status = if (nrow(temporal_manifest) == expected_weeks && !anyDuplicated(temporal_manifest$week)) "PASS" else "FAIL", observed = nrow(temporal_manifest), expected = expected_weeks, details = "All four raster families map uniquely to Stage 2 weeks.", stringsAsFactors = FALSE),
    data.frame(section = "distribution_matching", check = "weekly_summary_identity", status = if (all(distribution$pass)) "PASS" else "FAIL", observed = sum(distribution$pass), expected = nrow(distribution), details = "Table and raster distributions agree within storage tolerance.", stringsAsFactors = FALSE),
    data.frame(section = "administrative_qa_mask", check = "unseen_admin_support", status = if (length(unseen_ids) == 14L || length(unseen_ids) == 0L) "PASS" else "WARNING", observed = length(unseen_ids), expected = "production artifact value or zero", details = "QA-only mask; prediction values are unchanged.", stringsAsFactors = FALSE),
    data.frame(section = "scope_restrictions", check = "no_ecological_transformation", status = "PASS", observed = "none", expected = "none", details = "No refit, interpolation, rescaling, clipping, thresholding, Kcrit, smoothing, or biological interpretation.", stringsAsFactors = FALSE)
  )
  utils::write.csv(coordinate$summary, file.path(output_dir, "qa", "coordinate_cross_check_summary.csv"), row.names = FALSE)
  utils::write.csv(coordinate$details, file.path(output_dir, "qa", "coordinate_cross_check_cells.csv"), row.names = FALSE)
  utils::write.csv(roundtrip, file.path(output_dir, "qa", "round_trip_metrics.csv"), row.names = FALSE)
  utils::write.csv(distribution, file.path(output_dir, "qa", "distribution_comparison.csv"), row.names = FALSE)
  utils::write.csv(temporal_manifest, file.path(output_dir, "qa", "temporal_manifest.csv"), row.names = FALSE)
  utils::write.csv(unseen_summary, file.path(output_dir, "qa", "unseen_admin_cells.csv"), row.names = FALSE)
  utils::write.csv(raster_manifest, file.path(output_dir, "qa", "file_integrity_manifest.csv"), row.names = FALSE)
  utils::write.csv(audit, file.path(output_dir, "qa", "phase3_audit.csv"), row.names = FALSE)
  if (isTRUE(diagnostic)) {
    selected <- unique(round(seq(1, nrow(temporal_manifest), length.out = min(5L, nrow(temporal_manifest)))))
    for (i in selected) {
      row <- temporal_manifest[i, , drop = FALSE]
      joint_inla_rasterize_make_diagnostic(row$tier1_probability[[1L]], file.path(output_dir, "qa", "diagnostics", paste0("tier1_probability_", row$week[[1L]], ".png")), paste("Tier 1 plug-in probability", row$week[[1L]]))
      joint_inla_rasterize_make_diagnostic(row$tier2_intensity[[1L]], file.path(output_dir, "qa", "diagnostics", paste0("tier2_intensity_", row$week[[1L]], ".png")), paste("Tier 2 plug-in intensity", row$week[[1L]]))
    }
  }
  metadata <- list(
    phase = "Phase 3 rasterization and surface QA", run_id = run_id, generated_utc = format(Sys.time(), tz = "UTC"),
    source_phase2_commit = phase2_metadata$metadata$git_commit %||% phase2_metadata$metadata$source_phase2_commit %||% source_phase2_commit,
    source_phase2_output_directory = phase2_dir, phase2_manifest_path = manifest$manifest_path[[1L]], phase2_manifest_sha256 = joint_inla_rasterize_hash_file(manifest$manifest_path[[1L]]),
    phase2_metadata_path = phase2_metadata$path, phase2_metadata_sha256 = if (is.na(phase2_metadata$path)) NA_character_ else joint_inla_rasterize_hash_file(phase2_metadata$path),
    stage2_artifact_path = provenance$stage2_path, stage2_artifact_sha256 = if (is.null(provenance$stage2_path)) NA_character_ else joint_inla_rasterize_hash_file(provenance$stage2_path),
    template_raster_path = provenance$template_path, template_raster_sha256 = joint_inla_rasterize_hash_file(provenance$template_path), template_geometry = template_geometry,
    rasterization_method = "Create exact single-layer template geometry, initialize all cells to NA, and assign Phase 2 values directly by original raster cell_id.",
    response_scale_semantics = list(tier1_probability_plugin = "plogis(E[eta1 | data])", tier2_intensity_plugin = "exp(E[eta2 | data])"),
    cell_id_authoritative = TRUE, coordinate_crosscheck = coordinate$summary, raster_datatype = "FLT8S", compression = c("COMPRESS=DEFLATE", "PREDICTOR=3"), na_value = -9999,
    raster_families = c("tier1_eta", "tier1_probability", "tier2_eta", "tier2_intensity"), weeks = expected_weeks, total_raster_files = nrow(raster_manifest),
    roundtrip_tolerances = roundtrip_tolerances, roundtrip_maximum_observed_error = tapply(roundtrip$maximum_absolute_error, roundtrip$raster_family, max),
    prediction_cell_count = length(all_cell_ids), support_constant = support_constant, weekly_support_counts = support_counts,
    mask_support_counts = list(prediction_mask = length(all_cell_ids), unseen_admin_cells = length(unseen_ids)),
    administrative_unseen_level_qa = list(mask_path = unseen_mask_path, affected_cell_ids = unseen_ids, table = unseen_summary),
    temporal_support = temporal_manifest, file_integrity_manifest = raster_manifest, audit = audit,
    software_versions = list(R = R.version.string, terra = as.character(utils::packageVersion("terra")), sf = as.character(utils::packageVersion("sf")), digest = as.character(utils::packageVersion("digest"))),
    git_commit = tryCatch(system2("git", c("-C", normalizePath(repo_root, mustWork = FALSE), "-c", "safe.directory=*", "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[[1L]], error = function(e) NA_character_),
    scope = list(no_refit = TRUE, no_prediction_recalculation = TRUE, no_interpolation = TRUE, no_rescaling = TRUE, no_clipping = TRUE, no_thresholding = TRUE, no_Kcrit = TRUE, no_biological_interpretation = TRUE),
    output_directory = output_dir
  )
  metadata_path <- file.path(output_dir, paste0("phase3_metadata_", run_id, ".rds")); saveRDS(metadata, metadata_path)
  list(output_dir = output_dir, metadata_path = metadata_path, metadata = metadata, audit = audit, manifest = raster_manifest,
       roundtrip = roundtrip, distribution = distribution, temporal_manifest = temporal_manifest, coordinate = coordinate, unseen = unseen_summary)
}
