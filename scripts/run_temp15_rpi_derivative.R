#!/usr/bin/env Rscript

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "structural_surface_diagnostics.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)

parse_args <- function(args) {
  out <- list(); i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]; if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (identical(name, "overwrite")) { out[[name]] <- TRUE; i <- i + 1L } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) stop("Missing value for ", key)
      out[[name]] <- args[[i + 1L]]; i <- i + 2L
    }
  }; out
}
arg <- function(x, name, default = NULL) if (is.null(x[[name]])) default else x[[name]]
args <- parse_args(commandArgs(trailingOnly = TRUE))
run_id <- arg(args, "run-id", "20261017_230310_33098504")
source_root <- arg(args, "source-root"); stage2_path <- arg(args, "stage2"); observations_path <- arg(args, "observations"); output_root <- arg(args, "output-root")
threshold_c <- as.numeric(arg(args, "temperature-threshold", "15.0")); source_threshold_c <- as.numeric(arg(args, "source-threshold", "14.5"))
boundary_path <- arg(args, "boundary-path", "/project/disease_ecology/NWScrewworm/data/processed_data/spatial_domain/study_states.gpkg")
source_chime_execution_id <- arg(args, "source-chime-execution", "exec-20261017T230234-a4a51da4")
source_native_repo_sha <- arg(args, "source-native-repo-sha", "33098504df8bae18a10b5200db36ab7493ce9901")
source_repository_sha <- arg(args, "source-repository-sha", "516dd51b57229aa22245f23eda0da276fda9b715")
source_config_sha <- arg(args, "source-config-sha", "400ecd1b3ca7fa70eb073290c7e4389c2558aaea69daa22feb2a54676c1c69ee")
source_observation_sha <- arg(args, "source-observation-sha", "193245f75d9fe863de852801b8cdc405d4ceb39d25b512f9c52da4f8876f969c")
source_cds_portfolio <- arg(args, "source-cds-portfolio", "20261015T163459Z_portfolio")
source_coverage_sha <- arg(args, "source-coverage-sha", "9148d1f92ae86b0974ce5c76e2fc7102eb74a98d79a8666a8ac6057f2ec7d56c")
source_horizon <- arg(args, "source-horizon", "2024-W01 -> 2026-W39")
overwrite <- isTRUE(args[["overwrite"]])
required <- c(source_root = source_root, stage2 = stage2_path, observations = observations_path, output_root = output_root)
missing <- names(required)[vapply(required, function(x) is.null(x) || !nzchar(x), logical(1L))]
if (length(missing)) stop("Missing required arguments: ", paste(paste0("--", gsub("_", "-", missing)), collapse = ", "))
if (length(threshold_c) != 1L || !is.finite(threshold_c) || threshold_c <= source_threshold_c) stop("Derivative threshold must be finite and greater than source threshold.")
source_root <- normalizePath(source_root, mustWork = TRUE); stage2_path <- normalizePath(stage2_path, mustWork = TRUE); observations_path <- normalizePath(observations_path, mustWork = TRUE); boundary_path <- normalizePath(boundary_path, mustWork = TRUE); output_root <- normalizePath(output_root, mustWork = FALSE)
if (grepl("/production_runs/", gsub("\\\\", "/", output_root), fixed = TRUE) || startsWith(output_root, source_root)) stop("Derivative output is inside a protected source root.")
if (dir.exists(output_root) && length(list.files(output_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !overwrite) stop("Refusing non-empty derivative root without --overwrite: ", output_root)

report_root <- if (dir.exists(file.path(source_root, "reporting", run_id))) file.path(source_root, "reporting", run_id) else source_root
structural_dir <- file.path(report_root, "spatial", "structural_potential_abundance"); baseline_masked_dir <- file.path(report_root, "spatial", "structural_potential_abundance_temp_masked")
baseline_rpi <- file.path(report_root, "spatial", "rpi_continuous.tif"); baseline_class <- file.path(report_root, "spatial", "rpi_class.tif"); baseline_rpi_metadata <- file.path(report_root, "metadata", "rpi_metadata.rds")
cell_area_template <- file.path(structural_dir, "structural_potential_abundance_y2024_w01.tif")
required_source <- c(structural_dir, baseline_masked_dir, baseline_rpi, baseline_class, baseline_rpi_metadata, cell_area_template)
if (any(!file.exists(required_source))) stop("Accepted continuation is missing required source artifact(s): ", paste(required_source[!file.exists(required_source)], collapse = "; "))
dir.create(output_root, recursive = TRUE, showWarnings = FALSE); for (d in c("metadata", "masked", "rpi", "tables", "figures", "qa")) dir.create(file.path(output_root, d), recursive = TRUE, showWarnings = FALSE)

structural_files <- sort(list.files(structural_dir, pattern = "^structural_potential_abundance_y[0-9]{4}_w[0-9]{2}\\.tif$", full.names = TRUE)); baseline_masked_files <- sort(list.files(baseline_masked_dir, pattern = "^structural_potential_abundance_temp_masked_[0-9]{4}_W[0-9]{2}\\.tif$", full.names = TRUE))
if (length(structural_files) != 143L || length(baseline_masked_files) != 143L) stop("Expected exactly 143 weekly source and baseline masked rasters.")
week_keys <- sub("^structural_potential_abundance_y([0-9]{4})_w([0-9]{2})\\.tif$", "\\1-W\\2", basename(structural_files)); baseline_weeks <- sub("^structural_potential_abundance_temp_masked_([0-9]{4})_W([0-9]{2})\\.tif$", "\\1-W\\2", basename(baseline_masked_files))
if (!identical(week_keys, baseline_weeks)) stop("Weekly source and baseline labels do not match.")

stage2 <- readRDS(stage2_path); grid <- stage2$prediction_grid
if (!is.data.frame(grid) || !all(c("cell_id", "x", "y", "epiyear", "epiweek", "mintemp") %in% names(grid))) stop("Stage 2 prediction_grid lacks required fields.")
grid_week <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-"); if (!identical(unique(grid_week), week_keys)) stop("Stage 2 week labels do not match accepted structural products.")
cells <- unique(grid[c("cell_id", "x", "y")]); ids <- as.integer(cells$cell_id); if (anyDuplicated(cells$cell_id) || any(!is.finite(ids)) || any(ids < 1L)) stop("Stage 2 cell support is invalid.")
week_rows <- lapply(week_keys, function(key) which(grid_week == key)); names(week_rows) <- week_keys; if (any(vapply(week_rows, length, integer(1L)) != nrow(cells))) stop("Stage 2 does not contain one row per supported cell for every week.")
temperature_audit <- structural_validate_temperature_alignment(grid, length(week_keys), nrow(cells), "mintemp"); if (!isTRUE(temperature_audit$pass)) stop("Stage 2 minimum-temperature alignment failed.")
source_stack <- terra::rast(structural_files); baseline_masked_stack <- terra::rast(baseline_masked_files); if (terra::nlyr(source_stack) != 143L || terra::nlyr(baseline_masked_stack) != 143L) stop("Accepted source stacks do not contain 143 layers.")
if (!postfit_reporting_geometry_equal(source_stack[[1L]], baseline_masked_stack[[1L]])) stop("Source and baseline masked geometry differ.")
cell_area <- postfit_reporting_trace_cell_area(cell_area_template, NULL, NULL); if (!identical(cell_area$status, "PASS")) stop("Cell-area audit did not pass.")

weekly <- vector("list", length(week_keys)); derivative_files <- character(length(week_keys))
for (i in seq_along(week_keys)) {
  key <- week_keys[[i]]; rows <- week_rows[[key]]; position <- match(as.character(cells$cell_id), as.character(grid$cell_id[rows])); if (anyNA(position)) stop("Stage 2 cell support is incomplete for ", key)
  temperature <- as.numeric(grid$mintemp[rows][position]); source_raster <- source_stack[[i]]; source_values <- terra::values(source_raster, mat = FALSE)
  masked_support <- structural_apply_temperature_mask(source_values[ids], temperature, threshold_c, operator = ">="); derivative_values <- source_values; derivative_values[ids] <- masked_support; derivative_raster <- source_raster; terra::values(derivative_raster) <- derivative_values
  output_file <- file.path(output_root, "masked", paste0("structural_potential_abundance_temp_masked_", gsub("-", "_", key), ".tif")); terra::writeRaster(derivative_raster, output_file, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE")); derivative_files[[i]] <- output_file
  baseline_values <- terra::values(baseline_masked_stack[[i]], mat = FALSE); derivative_values <- terra::values(derivative_raster, mat = FALSE); if (!postfit_reporting_geometry_equal(baseline_masked_stack[[i]], derivative_raster)) stop("Mask geometry changed for ", key)
  base_retained <- is.finite(baseline_values) & baseline_values > 0; new_retained <- is.finite(derivative_values) & derivative_values > 0; added <- sum(new_retained & !base_retained); if (added > 0L) stop("15.0 C support is not a subset of 14.5 C support for ", key)
  base_n <- sum(base_retained); new_n <- sum(new_retained); removed <- base_n - new_n; weekly[[i]] <- data.frame(epiweek = key, retained_cells_14p5 = base_n, retained_cells_15 = new_n, cells_removed = removed, percent_removed = if (base_n) 100 * removed / base_n else 0, retained_area_14p5_km2 = base_n * cell_area$nominal_average_raster_cell_area, retained_area_15_km2 = new_n * cell_area$nominal_average_raster_cell_area, area_removed_km2 = removed * cell_area$nominal_average_raster_cell_area, added_cells = added, stringsAsFactors = FALSE)
}
weekly_comparison <- do.call(rbind, weekly); utils::write.csv(weekly_comparison, file.path(output_root, "qa", "weekly_mask_comparison.csv"), row.names = FALSE, na = "")
utils::write.csv(data.frame(metric = c("mean_cells_removed", "median_cells_removed", "maximum_cells_removed", "week_of_maximum_reduction", "weeks_with_zero_change", "mean_percent_removed", "median_percent_removed", "maximum_area_removed_km2"), value = c(mean(weekly_comparison$cells_removed), stats::median(weekly_comparison$cells_removed), max(weekly_comparison$cells_removed), weekly_comparison$epiweek[which.max(weekly_comparison$cells_removed)], sum(weekly_comparison$cells_removed == 0L), mean(weekly_comparison$percent_removed), stats::median(weekly_comparison$percent_removed), max(weekly_comparison$area_removed_km2)), stringsAsFactors = FALSE), file.path(output_root, "qa", "weekly_mask_comparison_summary.csv"), row.names = FALSE, na = "")

derivative_stack <- terra::rast(derivative_files); rpi_obs <- postfit_reporting_read_rpi_observations(observations_path, target_crs = terra::crs(derivative_stack[[1L]], proj = TRUE), coordinate_source = "lonlat", source_crs = "EPSG:4326"); calibration <- postfit_reporting_dynamic_rpi_calibration(derivative_stack, rpi_obs$data, week_keys, cut_quant = 0.10); derivative_threshold <- as.numeric(calibration$threshold)
utils::write.csv(calibration$paired, file.path(output_root, "tables", "rpi_same_week_calibration.csv"), row.names = FALSE, na = ""); utils::write.csv(calibration$metrics, file.path(output_root, "qa", "rpi_observation_metrics.csv"), row.names = FALSE, na = ""); utils::write.csv(data.frame(temperature_threshold_c = threshold_c, rpi_threshold = derivative_threshold), file.path(output_root, "tables", "rpi_dynamic_threshold.csv"), row.names = FALSE, na = "")
rpi <- postfit_reporting_calc_rpi_at_threshold(derivative_stack, derivative_threshold, gen_days = 21, days_per_layer = 7); derivative_rpi_path <- file.path(output_root, "rpi", "rpi_continuous_temp15.tif"); derivative_class_path <- file.path(output_root, "rpi", "rpi_class_temp15.tif"); terra::writeRaster(rpi$rpi, derivative_rpi_path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE")); terra::writeRaster(rpi$stability_class, derivative_class_path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE")); derivative_area <- postfit_reporting_rpi_class_area(rpi$stability_class, cell_area); utils::write.csv(derivative_area, file.path(output_root, "tables", "rpi_class_summary_temp15.csv"), row.names = FALSE, na = "")

baseline_rpi_raster <- terra::rast(baseline_rpi); baseline_class_raster <- terra::rast(baseline_class); if (!postfit_reporting_geometry_equal(baseline_rpi_raster, rpi$rpi) || !postfit_reporting_geometry_equal(baseline_class_raster, rpi$stability_class)) stop("Baseline and derivative RPI geometry differ.")
baseline_threshold <- as.numeric(readRDS(baseline_rpi_metadata)$threshold); utils::write.csv(data.frame(metric = c("rpi_threshold", "absolute_difference", "percent_difference"), baseline_14p5 = c(baseline_threshold, NA_real_, NA_real_), derivative_15 = c(derivative_threshold, abs(derivative_threshold - baseline_threshold), 100 * abs(derivative_threshold - baseline_threshold) / abs(baseline_threshold))), file.path(output_root, "tables", "rpi_threshold_comparison.csv"), row.names = FALSE)
baseline_area <- postfit_reporting_rpi_class_area(baseline_class_raster, cell_area); area_comparison <- merge(baseline_area[, c("class_id", "class_label", "cell_count", "area_km2")], derivative_area[, c("class_id", "class_label", "cell_count", "area_km2")], by = "class_id", suffixes = c("_14p5", "_15"), sort = TRUE); area_comparison$delta_cells <- area_comparison$cell_count_15 - area_comparison$cell_count_14p5; area_comparison$delta_area_km2 <- area_comparison$area_km2_15 - area_comparison$area_km2_14p5; area_comparison$percent_delta_area <- 100 * area_comparison$delta_area_km2 / area_comparison$area_km2_14p5; utils::write.csv(area_comparison, file.path(output_root, "tables", "rpi_class_area_comparison.csv"), row.names = FALSE)

base_values <- as.numeric(terra::values(baseline_rpi_raster, mat = FALSE)); new_values <- as.numeric(terra::values(rpi$rpi, mat = FALSE)); comparable <- is.finite(base_values) & is.finite(new_values); difference <- new_values[comparable] - base_values[comparable]; base_class_values <- as.integer(terra::values(baseline_class_raster, mat = FALSE)[comparable]); new_class_values <- as.integer(terra::values(rpi$stability_class, mat = FALSE)[comparable]); class_labels <- c("Transient/Sink", "Seasonal", "Multi-Season", "Endemic Core"); class_changed <- base_class_values != new_class_values
utils::write.csv(data.frame(comparable_cells = sum(comparable), mean_difference = mean(difference), median_difference = stats::median(difference), maximum_absolute_difference = max(abs(difference)), RMSE = sqrt(mean(difference^2)), class_changes = sum(class_changed), class_change_percent = 100 * mean(class_changed)), file.path(output_root, "tables", "rpi_continuous_comparison.csv"), row.names = FALSE)
transition <- table(factor(base_class_values, levels = 0:3, labels = class_labels), factor(new_class_values, levels = 0:3, labels = class_labels)); utils::write.csv(data.frame(`14.5C_to_15C` = rownames(transition), as.data.frame.matrix(transition), row.names = NULL, check.names = FALSE), file.path(output_root, "tables", "rpi_class_transition_matrix.csv"), row.names = FALSE)

boundary <- sf::st_read(boundary_path, layer = "study_states", quiet = TRUE)
if (is.na(sf::st_crs(boundary))) stop("Canonical boundary must carry CRS metadata; refusing an implicit CRS assignment.")
boundary <- sf::st_make_valid(boundary)
make_class_plot <- function(class_raster, pdf_path, png_path) {
  p <- postfit_reporting_plot_rpi(class_raster, boundary = boundary, title = "15.0°C RPI classes")
  cartography <- attr(p, "postfit_reporting_rpi_cartography")
  ggplot2::ggsave(pdf_path, p, width = cartography$dimensions[["width"]], height = cartography$dimensions[["height"]], units = "in", device = grDevices::pdf)
  ggplot2::ggsave(png_path, p, width = cartography$dimensions[["width"]], height = cartography$dimensions[["height"]], units = "in", dpi = cartography$dimensions[["dpi"]])
  invisible(p)
}
figure_pdf <- file.path(output_root, "figures", "rpi_class_temp15.pdf"); figure_png <- file.path(output_root, "figures", "rpi_class_temp15.png"); make_class_plot(rpi$stability_class, figure_pdf, figure_png)

source_paths <- list(accepted_continuation_root = source_root, accepted_reporting_root = report_root, structural_potential_abundance = structural_dir, canonical_masked_structural = baseline_masked_dir, canonical_rpi = baseline_rpi, canonical_rpi_class = baseline_class, canonical_rpi_metadata = baseline_rpi_metadata, stage2 = stage2_path, observations = observations_path, boundary = boundary_path, reference_figure = "C:/Users/humph173/Downloads/rpi_class.pdf")
manifest <- list(derivative_type = "postfit_temperature_threshold_variant", source_native_run_id = run_id, source_chime_execution_id = source_chime_execution_id, source_postfit_continuation = source_root, source_repository_sha = source_repository_sha, source_native_run_repository_sha = source_native_repo_sha, source_config_sha = source_config_sha, source_observation_sha = source_observation_sha, source_cds_portfolio = source_cds_portfolio, source_coverage_certificate_sha = source_coverage_sha, source_horizon = source_horizon, source_threshold_c = source_threshold_c, derivative_threshold_c = threshold_c, threshold_operator = ">=", rpi_threshold_baseline = baseline_threshold, rpi_threshold_derivative = derivative_threshold, cell_area_audit = cell_area, modeled_weeks = length(week_keys), supported_cells = nrow(cells), created_at = format(Sys.time(), tz = "UTC", usetz = TRUE), implementation_commit = tryCatch(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_), source_paths = source_paths, boundary_source = list(path = boundary_path, layer = "study_states", rendering = "postfit_reporting_plot_rpi"), figure_palette = postfit_reporting_rpi_class_palette(), cartography = postfit_reporting_rpi_cartography(), outputs = list(masked_rasters = derivative_files, rpi_continuous = derivative_rpi_path, rpi_classified = derivative_class_path, figure_pdf = figure_pdf, figure_png = figure_png), qa = list(weekly_mask_subset = TRUE, geometry_matches = TRUE, cell_area_status = cell_area$status, rpi_generated = TRUE, class_area_generated = TRUE, blocking_failures = 0L))
if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to write derivative provenance.")
yaml::write_yaml(manifest, file.path(output_root, "metadata", "derivative_manifest.yml")); saveRDS(manifest, file.path(output_root, "metadata", "derivative_manifest.rds"))
utils::write.csv(data.frame(check = c("masked_raster_count", "modeled_week_coverage", "grid_geometry", "support_subset", "cell_area_audit", "continuous_rpi", "classified_rpi", "class_summaries", "pdf_figure", "png_figure", "provenance", "blocking_failures"), status = c(if (length(derivative_files) == 143L) "PASS" else "FAIL", "PASS", "PASS", "PASS", cell_area$status, "PASS", "PASS", "PASS", if (file.exists(figure_pdf)) "PASS" else "FAIL", if (file.exists(figure_png)) "PASS" else "FAIL", "PASS", "PASS"), stringsAsFactors = FALSE), file.path(output_root, "qa", "derivative_qa_summary.csv"), row.names = FALSE, na = "")
cat("15.0 C derivative complete\nOutput: ", output_root, "\nMasked rasters: ", length(derivative_files), "\nRPI threshold: ", derivative_threshold, "\n", sep = "")
