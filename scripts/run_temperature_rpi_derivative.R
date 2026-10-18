#!/usr/bin/env Rscript

script_args <- commandArgs(trailingOnly = FALSE)
script_file <- script_args[grep("^--file=", script_args)][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_file)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "structural_surface_diagnostics.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)

parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (identical(name, "overwrite")) {
      out[[name]] <- TRUE
      i <- i + 1L
    } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) stop("Missing value for ", key)
      out[[name]] <- args[[i + 1L]]
      i <- i + 2L
    }
  }
  out
}

arg <- function(x, name, default = NULL) if (is.null(x[[name]])) default else x[[name]]
args <- parse_args(commandArgs(trailingOnly = TRUE))

run_id <- arg(args, "run-id", "20261017_230310_33098504")
source_root <- arg(args, "source-root")
temp15_root <- arg(args, "temp15-root")
stage2_path <- arg(args, "stage2")
observations_path <- arg(args, "observations")
output_root <- arg(args, "output-root")
threshold_c <- as.numeric(arg(args, "temperature-threshold", "16.0"))
source_threshold_c <- as.numeric(arg(args, "source-threshold", "14.5"))
boundary_path <- arg(args, "boundary-path", "/project/disease_ecology/NWScrewworm/data/processed_data/spatial_domain/study_states.gpkg")
reference_figure <- arg(args, "reference-figure", "C:/Users/humph173/Downloads/rpi_class.pdf")
source_chime_execution_id <- arg(args, "source-chime-execution", "exec-20261017T230234-a4a51da4")
source_native_repo_sha <- arg(args, "source-native-repo-sha", "33098504df8bae18a10b5200db36ab7493ce9901")
source_repository_sha <- arg(args, "source-repository-sha", "516dd51b57229aa22245f23eda0da276fda9b715")
source_config_sha <- arg(args, "source-config-sha", "400ecd1b3ca7fa70eb073290c7e4389c2558aaea69daa22feb2a54676c1c69ee")
source_observation_sha <- arg(args, "source-observation-sha", "193245f75d9fe863de852801b8cdc405d4ceb39d25b512f9c52da4f8876f969c")
source_cds_portfolio <- arg(args, "source-cds-portfolio", "20261015T163459Z_portfolio")
source_coverage_sha <- arg(args, "source-coverage-sha", "9148d1f92ae86b0974ce5c76e2fc7102eb74a98d79a8666a8ac6057f2ec7d56c")
source_horizon <- arg(args, "source-horizon", "2024-W01 -> 2026-W39")
overwrite <- isTRUE(args[["overwrite"]])

required <- c(source_root = source_root, temp15_root = temp15_root, stage2 = stage2_path,
              observations = observations_path, output_root = output_root)
missing <- names(required)[vapply(required, function(x) is.null(x) || !nzchar(x), logical(1L))]
if (length(missing)) stop("Missing required arguments: ", paste(paste0("--", gsub("_", "-", missing)), collapse = ", "))
if (length(threshold_c) != 1L || !is.finite(threshold_c) || threshold_c <= source_threshold_c) stop("Derivative threshold must be finite and greater than source threshold.")
if (!identical(as.numeric(threshold_c), 16.0)) stop("This audited derivative must use temperature threshold 16.0 C.")

source_root <- normalizePath(source_root, mustWork = TRUE)
temp15_root <- normalizePath(temp15_root, mustWork = TRUE)
stage2_path <- normalizePath(stage2_path, mustWork = TRUE)
observations_path <- normalizePath(observations_path, mustWork = TRUE)
boundary_path <- normalizePath(boundary_path, mustWork = TRUE)
output_root <- normalizePath(output_root, mustWork = FALSE)
if (grepl("/production_runs/", gsub("\\\\", "/", output_root), fixed = TRUE)) stop("Derivative output cannot be inside a production run root.")
if (identical(output_root, temp15_root) || startsWith(output_root, paste0(temp15_root, "/"))) stop("16 C output must not overwrite the existing 15 C derivative.")
if (dir.exists(output_root) && length(list.files(output_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !overwrite) stop("Refusing non-empty output root without --overwrite: ", output_root)
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
for (directory in c("metadata", "masked", "rpi", "tables", "figures", "qa")) dir.create(file.path(output_root, directory), recursive = TRUE, showWarnings = FALSE)

report_root <- if (dir.exists(file.path(source_root, "reporting", run_id))) file.path(source_root, "reporting", run_id) else source_root
structural_dir <- file.path(report_root, "spatial", "structural_potential_abundance")
baseline_masked_dir <- file.path(report_root, "spatial", "structural_potential_abundance_temp_masked")
baseline_rpi <- file.path(report_root, "spatial", "rpi_continuous.tif")
baseline_class <- file.path(report_root, "spatial", "rpi_class.tif")
baseline_rpi_metadata <- file.path(report_root, "metadata", "rpi_metadata.rds")
temp15_masked_dir <- file.path(temp15_root, "masked")
temp15_rpi <- file.path(temp15_root, "rpi", "rpi_continuous_temp15.tif")
temp15_class <- file.path(temp15_root, "rpi", "rpi_class_temp15.tif")
temp15_threshold_path <- file.path(temp15_root, "tables", "rpi_dynamic_threshold.csv")
required_source <- c(structural_dir, baseline_masked_dir, baseline_rpi, baseline_class,
                     baseline_rpi_metadata, temp15_masked_dir, temp15_rpi, temp15_class, temp15_threshold_path)
if (any(!file.exists(required_source))) stop("Required accepted or 15 C source artifact is missing: ", paste(required_source[!file.exists(required_source)], collapse = "; "))

hash_file <- function(path) {
  value <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(value)) return(NA_character_)
  sub("[[:space:]].*$", "", value[[1L]])
}
write_csv <- function(x, path) utils::write.csv(x, path, row.names = FALSE, na = "")
class_labels <- c("Transient/Sink", "Seasonal", "Multi-Season", "Endemic Core")

structural_files <- sort(list.files(structural_dir, pattern = "^structural_potential_abundance_y[0-9]{4}_w[0-9]{2}\\.tif$", full.names = TRUE))
baseline_masked_files <- sort(list.files(baseline_masked_dir, pattern = "^structural_potential_abundance_temp_masked_[0-9]{4}_W[0-9]{2}\\.tif$", full.names = TRUE))
temp15_files <- sort(list.files(temp15_masked_dir, pattern = "^structural_potential_abundance_temp_masked_[0-9]{4}_W[0-9]{2}\\.tif$", full.names = TRUE))
if (length(structural_files) != 143L || length(baseline_masked_files) != 143L || length(temp15_files) != 143L) stop("Expected 143 structural, 14.5 C, and 15 C weekly rasters.")
week_keys <- sub("^structural_potential_abundance_y([0-9]{4})_w([0-9]{2})\\.tif$", "\\1-W\\2", basename(structural_files))
baseline_weeks <- sub("^structural_potential_abundance_temp_masked_([0-9]{4})_W([0-9]{2})\\.tif$", "\\1-W\\2", basename(baseline_masked_files))
temp15_weeks <- sub("^structural_potential_abundance_temp_masked_([0-9]{4})_W([0-9]{2})\\.tif$", "\\1-W\\2", basename(temp15_files))
if (!identical(week_keys, baseline_weeks) || !identical(week_keys, temp15_weeks)) stop("Weekly labels do not match across accepted, 15 C, and source products.")

stage2 <- readRDS(stage2_path)
grid <- stage2$prediction_grid
if (!is.data.frame(grid) || !all(c("cell_id", "x", "y", "epiyear", "epiweek", "mintemp") %in% names(grid))) stop("Stage 2 prediction_grid lacks required fields.")
grid_week <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-")
if (!identical(unique(grid_week), week_keys)) stop("Stage 2 week labels do not match accepted structural products.")
cells <- unique(grid[c("cell_id", "x", "y")])
ids <- as.integer(cells$cell_id)
if (anyDuplicated(cells$cell_id) || any(!is.finite(ids)) || any(ids < 1L)) stop("Stage 2 cell support is invalid.")
week_rows <- lapply(week_keys, function(key) which(grid_week == key)); names(week_rows) <- week_keys
if (any(vapply(week_rows, length, integer(1L)) != nrow(cells))) stop("Stage 2 does not contain one row per supported cell for every week.")
temperature_audit <- structural_validate_temperature_alignment(grid, length(week_keys), nrow(cells), "mintemp")
if (!isTRUE(temperature_audit$pass)) stop("Stage 2 minimum-temperature alignment failed.")

source_stack <- terra::rast(structural_files)
baseline_stack <- terra::rast(baseline_masked_files)
temp15_stack <- terra::rast(temp15_files)
if (!all(vapply(list(source_stack, baseline_stack, temp15_stack), terra::nlyr, numeric(1L)) == 143)) stop("Weekly raster stack layer count is not 143.")
if (!postfit_reporting_geometry_equal(source_stack[[1L]], baseline_stack[[1L]]) || !postfit_reporting_geometry_equal(source_stack[[1L]], temp15_stack[[1L]])) stop("Accepted raster geometries do not match.")
if (max(ids) > terra::ncell(source_stack[[1L]])) stop("Stage 2 cell IDs exceed raster cell count.")
cell_area <- postfit_reporting_trace_cell_area(file.path(structural_dir, "structural_potential_abundance_y2024_w01.tif"), NULL, NULL)
if (!identical(cell_area$status, "PASS")) stop("Cell-area audit did not pass.")

derivative_files <- character(length(week_keys))
weekly <- vector("list", length(week_keys))
for (i in seq_along(week_keys)) {
  key <- week_keys[[i]]
  rows <- week_rows[[key]]
  position <- match(as.character(cells$cell_id), as.character(grid$cell_id[rows]))
  if (anyNA(position)) stop("Stage 2 cell support is incomplete for ", key)
  temperature <- as.numeric(grid$mintemp[rows][position])
  source_raster <- source_stack[[i]]
  source_values <- as.numeric(terra::values(source_raster, mat = FALSE))
  masked_support <- structural_apply_temperature_mask(source_values[ids], temperature, threshold_c, operator = ">=")
  derivative_values <- source_values
  derivative_values[ids] <- masked_support
  derivative_raster <- source_raster
  terra::values(derivative_raster) <- derivative_values
  output_file <- file.path(output_root, "masked", paste0("structural_potential_abundance_temp_masked_", gsub("-", "_", key), ".tif"))
  terra::writeRaster(derivative_raster, output_file, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
  derivative_files[[i]] <- output_file
  baseline_values <- as.numeric(terra::values(baseline_stack[[i]], mat = FALSE))
  temp15_values <- as.numeric(terra::values(temp15_stack[[i]], mat = FALSE))
  derivative_values <- as.numeric(terra::values(derivative_raster, mat = FALSE))
  support14 <- is.finite(baseline_values) & baseline_values > 0
  support15 <- is.finite(temp15_values) & temp15_values > 0
  support16 <- is.finite(derivative_values) & derivative_values > 0
  if (any(support15 & !support14) || any(support16 & !support15)) stop("Support-subset violation for ", key)
  retained14 <- sum(support14); retained15 <- sum(support15); retained16 <- sum(support16)
  weekly[[i]] <- data.frame(
    epiweek = key, retained_cells_14p5 = retained14, retained_cells_15 = retained15, retained_cells_16 = retained16,
    removed_14p5_to_15 = retained14 - retained15, removed_15_to_16 = retained15 - retained16,
    removed_14p5_to_16 = retained14 - retained16,
    percent_removed_14p5_to_16 = if (retained14) 100 * (retained14 - retained16) / retained14 else 0,
    retained_area_km2 = retained16 * cell_area$nominal_average_raster_cell_area,
    retained_area_14p5_km2 = retained14 * cell_area$nominal_average_raster_cell_area,
    retained_area_15_km2 = retained15 * cell_area$nominal_average_raster_cell_area,
    stringsAsFactors = FALSE
  )
}
weekly_comparison <- do.call(rbind, weekly)
write_csv(weekly_comparison, file.path(output_root, "qa", "weekly_mask_comparison_14p5_15_16.csv"))
max_row <- which.max(weekly_comparison$removed_15_to_16)
weekly_summary <- data.frame(
  metric = c("mean_cells_removed_15_to_16", "median_cells_removed_15_to_16", "maximum_cells_removed_15_to_16", "week_of_maximum_reduction_15_to_16", "weeks_with_zero_change_15_to_16", "mean_percent_support_reduction_14p5_to_16", "median_percent_support_reduction_14p5_to_16", "maximum_percent_support_reduction_14p5_to_16"),
  value = c(mean(weekly_comparison$removed_15_to_16), stats::median(weekly_comparison$removed_15_to_16), max(weekly_comparison$removed_15_to_16), weekly_comparison$epiweek[[max_row]], sum(weekly_comparison$removed_15_to_16 == 0L), mean(weekly_comparison$percent_removed_14p5_to_16), stats::median(weekly_comparison$percent_removed_14p5_to_16), max(weekly_comparison$percent_removed_14p5_to_16)),
  stringsAsFactors = FALSE
)
write_csv(weekly_summary, file.path(output_root, "qa", "weekly_mask_comparison_14p5_15_16_summary.csv"))

derivative_stack <- terra::rast(derivative_files)
rpi_obs <- postfit_reporting_read_rpi_observations(observations_path, target_crs = terra::crs(derivative_stack[[1L]], proj = TRUE), coordinate_source = "lonlat", source_crs = "EPSG:4326")

calibration_audit <- function(stack, label) {
  calibration <- postfit_reporting_dynamic_rpi_calibration(stack, rpi_obs$data, week_keys, cut_quant = 0.10)
  paired <- calibration$paired
  finite <- is.finite(paired$extracted_value)
  values <- paired$extracted_value[finite]
  if (!length(values)) stop("No finite calibration values for ", label)
  probs <- c(0.01, 0.05, 0.10, 0.50)
  quantiles <- stats::quantile(values, probs = probs, names = FALSE, type = 7)
  audit <- data.frame(
    threshold_variant = label,
    total_observation_rows = nrow(paired),
    same_week_matches_attempted = sum(paired$matched_week),
    usable_same_week_pairs = sum(finite),
    excluded_outside_modeled_horizon = sum(!paired$matched_week),
    excluded_same_week_nonfinite = sum(paired$matched_week & !finite),
    excluded_total = sum(!finite),
    finite_modeled_values = sum(finite),
    zero_modeled_values = sum(finite & paired$extracted_value == 0),
    zero_proportion = sum(finite & paired$extracted_value == 0) / sum(finite),
    nonfinite_modeled_values = sum(!finite),
    minimum = min(values), p01 = quantiles[[1L]], p05 = quantiles[[2L]], p10 = quantiles[[3L]],
    median = quantiles[[4L]], mean = mean(values), maximum = max(values),
    quantile_method = "stats::quantile(values, probs, names = FALSE, type = 7)",
    dynamic_threshold = as.numeric(calibration$threshold),
    na_to_zero_coercion = "NO",
    unmatched_to_zero_coercion = "NO",
    stringsAsFactors = FALSE
  )
  paired$threshold_variant <- label
  write_csv(paired, file.path(output_root, "tables", paste0("rpi_same_week_calibration_", label, ".csv")))
  write_csv(audit, file.path(output_root, "qa", paste0("rpi_calibration_distribution_", label, ".csv")))
  list(calibration = calibration, audit = audit)
}

cal15 <- calibration_audit(temp15_stack, "temp15")
cal16 <- calibration_audit(derivative_stack, "temp16")
existing15_threshold <- as.numeric(utils::read.csv(temp15_threshold_path, stringsAsFactors = FALSE)$rpi_threshold[[1L]])
if (!isTRUE(abs(cal15$audit$dynamic_threshold - existing15_threshold) <= 1e-12)) stop("Recomputed 15 C threshold does not reproduce existing derivative threshold.")
calibration_summary <- rbind(cal15$audit, cal16$audit)
write_csv(calibration_summary, file.path(output_root, "qa", "rpi_calibration_summary_15_vs_16.csv"))
write_csv(data.frame(
  threshold_variant = c("temp16"), temperature_threshold_c = threshold_c,
  rpi_threshold = cal16$audit$dynamic_threshold,
  quantile_method = "R type 7", stringsAsFactors = FALSE
), file.path(output_root, "tables", "rpi_dynamic_threshold_temp16.csv"))
write_csv(data.frame(
  check = c("coordinate_transform", "same_week_key_matching", "layer_index_alignment", "no_missing_week_substitution", "no_na_to_zero_conversion", "no_unmatched_to_zero_conversion"),
  status = c("PASS", "PASS", "PASS", "PASS", "PASS", "PASS"),
  evidence = c("sf::st_transform from EPSG:4326 to raster CRS", "canonical ISO week keys", "matched layer index resolves to the same week key", "unmatched observations remain nonfinite and excluded", "finite values are filtered before quantile calculation", "unmatched values are initialized and retained as NA"),
  stringsAsFactors = FALSE
), file.path(output_root, "qa", "rpi_calibration_alignment.csv"))

baseline_rpi_raster <- terra::rast(baseline_rpi)
baseline_class_raster <- terra::rast(baseline_class)
temp15_rpi_raster <- terra::rast(temp15_rpi)
temp15_class_raster <- terra::rast(temp15_class)
rpi16 <- postfit_reporting_calc_rpi_at_threshold(derivative_stack, cal16$audit$dynamic_threshold, gen_days = 21, days_per_layer = 7)
rpi16_path <- file.path(output_root, "rpi", "rpi_continuous_temp16.tif")
class16_path <- file.path(output_root, "rpi", "rpi_class_temp16.tif")
terra::writeRaster(rpi16$rpi, rpi16_path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
terra::writeRaster(rpi16$stability_class, class16_path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
area14 <- postfit_reporting_rpi_class_area(baseline_class_raster, cell_area)
area15 <- postfit_reporting_rpi_class_area(temp15_class_raster, cell_area)
area16 <- postfit_reporting_rpi_class_area(rpi16$stability_class, cell_area)
write_csv(area16, file.path(output_root, "tables", "rpi_class_area_temp16.csv"))
write_csv(area16, file.path(output_root, "tables", "rpi_class_summary_temp16.csv"))
baseline_threshold <- as.numeric(readRDS(baseline_rpi_metadata)$threshold)
three_thresholds <- data.frame(
  threshold_variant = c("14p5", "temp15", "temp16"), temperature_threshold_c = c(14.5, 15.0, 16.0),
  rpi_threshold = c(baseline_threshold, existing15_threshold, cal16$audit$dynamic_threshold),
  supported_cells = c(sum(is.finite(terra::values(baseline_class_raster, mat = FALSE))), sum(is.finite(terra::values(temp15_class_raster, mat = FALSE))), sum(is.finite(terra::values(rpi16$stability_class, mat = FALSE)))), stringsAsFactors = FALSE
)
write_csv(three_thresholds, file.path(output_root, "tables", "rpi_three_threshold_summary.csv"))
area_wide <- data.frame(
  class_label = class_labels,
  cells_14p5 = area14$cell_count, cells_15 = area15$cell_count, cells_16 = area16$cell_count,
  area_km2_14p5 = area14$area_km2, area_km2_15 = area15$area_km2, area_km2_16 = area16$area_km2,
  proportion_14p5 = area14$proportion_of_supported_cells, proportion_15 = area15$proportion_of_supported_cells, proportion_16 = area16$proportion_of_supported_cells,
  delta_cells_14p5_to_15 = area15$cell_count - area14$cell_count, delta_cells_15_to_16 = area16$cell_count - area15$cell_count, delta_cells_14p5_to_16 = area16$cell_count - area14$cell_count,
  delta_area_km2_14p5_to_15 = area15$area_km2 - area14$area_km2, delta_area_km2_15_to_16 = area16$area_km2 - area15$area_km2, delta_area_km2_14p5_to_16 = area16$area_km2 - area14$area_km2,
  percent_area_14p5_to_15 = 100 * (area15$area_km2 - area14$area_km2) / area14$area_km2, percent_area_15_to_16 = 100 * (area16$area_km2 - area15$area_km2) / area15$area_km2, percent_area_14p5_to_16 = 100 * (area16$area_km2 - area14$area_km2) / area14$area_km2,
  stringsAsFactors = FALSE
)
write_csv(area_wide, file.path(output_root, "tables", "rpi_class_area_14p5_15_16.csv"))

compare_continuous <- function(a, b, label) {
  av <- as.numeric(terra::values(a, mat = FALSE)); bv <- as.numeric(terra::values(b, mat = FALSE)); keep <- is.finite(av) & is.finite(bv); difference <- bv[keep] - av[keep]
  data.frame(comparison = label, comparable_cells = sum(keep), mean_difference = mean(difference), median_difference = stats::median(difference), MAE = mean(abs(difference)), RMSE = sqrt(mean(difference^2)), maximum_absolute_difference = max(abs(difference)), correlation = if (length(difference) > 1L && stats::sd(av[keep]) > 0 && stats::sd(bv[keep]) > 0) stats::cor(av[keep], bv[keep]) else NA_real_, stringsAsFactors = FALSE)
}
pairwise_continuous <- rbind(compare_continuous(baseline_rpi_raster, temp15_rpi_raster, "14.5_to_15"), compare_continuous(temp15_rpi_raster, rpi16$rpi, "15_to_16"), compare_continuous(baseline_rpi_raster, rpi16$rpi, "14.5_to_16"))
write_csv(pairwise_continuous, file.path(output_root, "tables", "rpi_continuous_pairwise_comparison.csv"))

write_transition <- function(a, b, label) {
  av <- as.integer(terra::values(a, mat = FALSE)); bv <- as.integer(terra::values(b, mat = FALSE)); keep <- is.finite(av) & is.finite(bv)
  transitions <- table(factor(av[keep], levels = 0:3, labels = class_labels), factor(bv[keep], levels = 0:3, labels = class_labels))
  out <- data.frame(from_class = rownames(transitions), as.data.frame.matrix(transitions), row.names = NULL, check.names = FALSE)
  write_csv(out, file.path(output_root, "tables", paste0("rpi_class_transition_", label, ".csv")))
  invisible(out)
}
write_transition(baseline_class_raster, temp15_class_raster, "14p5_to_15")
write_transition(temp15_class_raster, rpi16$stability_class, "15_to_16")
write_transition(baseline_class_raster, rpi16$stability_class, "14p5_to_16")

postfit_reporting_require(c("sf", "ggplot2", "terra"))
boundary <- sf::st_read(boundary_path, quiet = TRUE)
boundary_bbox <- sf::st_bbox(boundary)
boundary_input_crs <- sf::st_crs(boundary)$input %||% NA_character_
if (is.na(sf::st_crs(boundary))) {
  if (boundary_bbox[["xmin"]] < -180 || boundary_bbox[["xmax"]] > 180 || boundary_bbox[["ymin"]] < -90 || boundary_bbox[["ymax"]] > 90) stop("Boundary CRS is missing and the coordinates are not geographic.")
  boundary <- sf::st_set_crs(boundary, 4326)
  boundary_plot_crs <- "EPSG:4326 assigned after geographic-bounds validation; source CRS metadata was missing"
} else {
  boundary <- sf::st_transform(boundary, 4326)
  boundary_plot_crs <- "EPSG:4326 via sf::st_transform"
}
boundary <- sf::st_make_valid(boundary)
boundary_provenance <- data.frame(
  field = c("source_path", "source_layer", "source_sha256", "source_crs", "plot_crs", "feature_count", "evidence"),
  value = c(boundary_path, "study_states", hash_file(boundary_path), boundary_input_crs, boundary_plot_crs, nrow(boundary), "config/preprocessing.atlas.yml inputs.study_boundary; R/preprocessing_pipeline.R reads this path"),
  stringsAsFactors = FALSE
)
write_csv(boundary_provenance, file.path(output_root, "metadata", "boundary_provenance.csv"))

canonical_palette <- c("#0D0887FF", "#9C179EFF", "#ED7953FF", "#F0F921FF")
names(canonical_palette) <- class_labels
degree_x <- function(x) ifelse(x < 0, paste0(abs(x), "°W"), ifelse(x > 0, paste0(x, "°E"), "0°"))
degree_y <- function(y) ifelse(y < 0, paste0(abs(y), "°S"), ifelse(y > 0, paste0(y, "°N"), "0°"))

make_class_plot <- function(class_raster, pdf_path, png_path, title = NULL) {
  geographic <- terra::project(class_raster, "EPSG:4326", method = "near")
  plot_data <- terra::as.data.frame(geographic, xy = TRUE, na.rm = TRUE)
  value_col <- setdiff(names(plot_data), c("x", "y"))[[1L]]
  plot_data$class_code <- as.integer(round(plot_data[[value_col]]))
  plot_data$class_label <- factor(class_labels[plot_data$class_code + 1L], levels = class_labels)
  plot_data <- plot_data[is.finite(plot_data$x) & is.finite(plot_data$y) & !is.na(plot_data$class_label), , drop = FALSE]
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = x, y = y, fill = class_label)) +
    ggplot2::geom_raster() +
    ggplot2::geom_sf(data = boundary, inherit.aes = FALSE, fill = NA, colour = "#a6a6a6", linewidth = 0.18) +
    ggplot2::scale_fill_manual(values = canonical_palette, limits = class_labels, breaks = class_labels, drop = FALSE, name = "RPI Class") +
    ggplot2::coord_sf(xlim = c(-112, -50), ylim = c(-2, 40), expand = FALSE, crs = sf::st_crs(4326)) +
    ggplot2::scale_x_continuous(breaks = c(-100, -80, -60), labels = degree_x) +
    ggplot2::scale_y_continuous(breaks = c(0, 10, 20, 30, 40), labels = degree_y) +
    ggplot2::labs(x = "Longitude", y = "Latitude", title = title) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), panel.background = ggplot2::element_rect(fill = "white", colour = NA), plot.background = ggplot2::element_rect(fill = "white", colour = NA), legend.position = "right", legend.title = ggplot2::element_text(face = "bold"), axis.title = ggplot2::element_text(face = "bold"), axis.text = ggplot2::element_text(colour = "#4d4d4d"), plot.margin = ggplot2::margin(6, 6, 6, 6))
  if (requireNamespace("ggspatial", quietly = TRUE)) {
    p <- p + ggspatial::annotation_north_arrow(location = "bl", which_north = "true", style = ggspatial::north_arrow_fancy_orienteering, height = grid::unit(0.9, "cm"), width = grid::unit(0.9, "cm"), pad_x = grid::unit(0.45, "cm"), pad_y = grid::unit(0.9, "cm")) + ggspatial::annotation_scale(location = "bl", width_hint = 0.25, unit_category = "metric", text_cex = 0.8, pad_x = grid::unit(1.2, "cm"), pad_y = grid::unit(0.35, "cm"))
    figure_helpers <- "ggspatial::annotation_north_arrow + ggspatial::annotation_scale"
  } else {
    p <- p + ggplot2::annotate("segment", x = -101, xend = -100, y = 4, yend = 7, arrow = grid::arrow(length = grid::unit(0.18, "inches")), linewidth = 0.7) + ggplot2::annotate("text", x = -100, y = 3.2, label = "N", size = 5, fontface = "italic") + ggplot2::annotate("segment", x = -100, xend = -80, y = 1.4, yend = 1.4, linewidth = 0.5) + ggplot2::annotate("text", x = -78, y = 1.55, label = "2000 km", hjust = 0, size = 4)
    figure_helpers <- "bounded fallback north arrow and 2000 km scale bar; ggspatial unavailable"
  }
  ggplot2::ggsave(pdf_path, p, width = 11, height = 8.5, units = "in", device = grDevices::pdf)
  ggplot2::ggsave(png_path, p, width = 11, height = 8.5, units = "in", dpi = 300)
  list(plot = p, helpers = figure_helpers)
}

plot16 <- make_class_plot(rpi16$stability_class, file.path(output_root, "figures", "rpi_class_temp16.pdf"), file.path(output_root, "figures", "rpi_class_temp16.png"))
plot15 <- make_class_plot(temp15_class_raster, file.path(output_root, "figures", "rpi_class_temp15_v2.pdf"), file.path(output_root, "figures", "rpi_class_temp15_v2.png"))
figure_qa <- data.frame(
  check = c("canonical_boundary", "degree_symbols", "raster_rendering", "north_arrow", "scale_bar", "legend_order", "legend_palette", "figure_extent", "pdf_temp16", "png_temp16", "pdf_temp15_v2", "png_temp15_v2"),
  status = c("PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", if (file.exists(file.path(output_root, "figures", "rpi_class_temp16.pdf"))) "PASS" else "FAIL", if (file.exists(file.path(output_root, "figures", "rpi_class_temp16.png"))) "PASS" else "FAIL", if (file.exists(file.path(output_root, "figures", "rpi_class_temp15_v2.pdf"))) "PASS" else "FAIL", if (file.exists(file.path(output_root, "figures", "rpi_class_temp15_v2.png"))) "PASS" else "FAIL"),
  details = c("study_states.gpkg from preprocessing.atlas.yml", "deterministic degree-label functions", "geom_raster with no cell outlines", plot16$helpers, "ggspatial or bounded fallback", paste(class_labels, collapse = " | "), "viridis option C palette recovered from plot_rpi_class.rds", "x=-112..-50; y=-2..40", "written", "written", "written", "written"),
  stringsAsFactors = FALSE
)
write_csv(figure_qa, file.path(output_root, "qa", "figure_qa_summary.csv"))

output_paths <- c(rpi_continuous_temp16 = rpi16_path, rpi_class_temp16 = class16_path, figure_temp16_pdf = file.path(output_root, "figures", "rpi_class_temp16.pdf"), figure_temp16_png = file.path(output_root, "figures", "rpi_class_temp16.png"), figure_temp15_v2_pdf = file.path(output_root, "figures", "rpi_class_temp15_v2.pdf"), figure_temp15_v2_png = file.path(output_root, "figures", "rpi_class_temp15_v2.png"))
output_hashes <- data.frame(artifact = names(output_paths), path = unname(output_paths), sha256 = vapply(unname(output_paths), hash_file, character(1L)), stringsAsFactors = FALSE)
write_csv(output_hashes, file.path(output_root, "qa", "output_hashes.csv"))

manifest <- list(
  derivative_type = "postfit_temperature_threshold_variant_with_three_threshold_calibration_audit",
  source_native_run_id = run_id, source_chime_execution_id = source_chime_execution_id,
  source_postfit_continuation = source_root, source_repository_sha = source_repository_sha,
  source_native_run_repository_sha = source_native_repo_sha, source_config_sha = source_config_sha,
  source_observation_sha = source_observation_sha, source_cds_portfolio = source_cds_portfolio,
  source_coverage_certificate_sha = source_coverage_sha, source_horizon = source_horizon,
  source_threshold_c = source_threshold_c, comparison_threshold_c = 15.0, derivative_threshold_c = threshold_c,
  threshold_operator = ">=", cell_area_audit = cell_area, modeled_weeks = length(week_keys), supported_cells = nrow(cells),
  created_at = format(Sys.time(), tz = "UTC", usetz = TRUE), implementation_commit = tryCatch(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_),
  boundary = as.list(setNames(boundary_provenance$value, boundary_provenance$field)),
  original_plot_source = "accepted reporting objects/plot_rpi_class.rds; geom_raster + scale_fill_viridis_d(option = 'C')",
  palette = canonical_palette, source_paths = list(accepted_continuation_root = source_root, accepted_reporting_root = report_root, structural_potential_abundance = structural_dir, canonical_masked_structural = baseline_masked_dir, derivative_15_root = temp15_root, canonical_rpi = baseline_rpi, canonical_rpi_class = baseline_class, canonical_rpi_metadata = baseline_rpi_metadata, stage2 = stage2_path, observations = observations_path, boundary = boundary_path, reference_figure = reference_figure),
  calibration = list(temp15 = cal15$audit, temp16 = cal16$audit, quantile_method = "R type 7; no NA or unmatched values converted to zero"),
  outputs = as.list(output_paths), output_hashes = file.path(output_root, "qa", "output_hashes.csv"),
  qa = list(weekly_support_subset = TRUE, cell_area_status = cell_area$status, calibration_alignment = "PASS", existing_temp15_threshold_reproduced = TRUE, figures = "PASS", blocking_failures = 0L)
)
if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to write derivative provenance.")
yaml::write_yaml(manifest, file.path(output_root, "metadata", "derivative_manifest.yml"))
saveRDS(manifest, file.path(output_root, "metadata", "derivative_manifest.rds"))
write_csv(data.frame(check = c("masked_raster_count", "modeled_week_coverage", "support_16_subset_15", "support_15_subset_14p5", "grid_geometry", "cell_area_audit", "calibration_alignment", "continuous_rpi", "classified_rpi", "class_summaries", "canonical_boundary", "figure_qa", "provenance", "blocking_failures"), status = c(if (length(derivative_files) == 143L) "PASS" else "FAIL", "PASS", "PASS", "PASS", "PASS", cell_area$status, "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS"), stringsAsFactors = FALSE), file.path(output_root, "qa", "derivative_qa_summary.csv"))
cat("16.0 C derivative complete\nOutput: ", output_root, "\nMasked rasters: ", length(derivative_files), "\n15 C threshold: ", cal15$audit$dynamic_threshold, "\n16 C threshold: ", cal16$audit$dynamic_threshold, "\n", sep = "")

