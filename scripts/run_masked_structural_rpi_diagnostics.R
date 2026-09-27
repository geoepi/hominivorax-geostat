# Diagnostic-only physiological mask and structural RPI comparison.
# This script consumes immutable structural products and Stage 2 temperature
# support. It never fits, projects upstream products, or replaces canonical RPI.

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "preprocessing_temporal.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "structural_surface_diagnostics.R"), local = .GlobalEnv)

parse_args <- function(args) {
  values <- list(); i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (identical(name, "overwrite")) {
      values[[name]] <- TRUE; i <- i + 1L
    } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) stop("Missing value for ", key)
      values[[name]] <- args[[i + 1L]]; i <- i + 2L
    }
  }
  values
}
arg <- function(values, name, default = NULL) if (is.null(values[[name]])) default else values[[name]]
args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("stage2", "structural-root", "observations", "canonical-report-root", "output-root")
missing <- required[vapply(required, function(name) is.null(args[[name]]) || !nzchar(as.character(args[[name]])), logical(1L))]
if (length(missing)) stop("Supply explicit arguments: ", paste(paste0("--", missing), collapse = ", "))

stage2_path <- arg(args, "stage2")
structural_root <- arg(args, "structural-root")
observation_path <- arg(args, "observations")
canonical_report_root <- arg(args, "canonical-report-root")
output_root <- arg(args, "output-root")
run_id <- arg(args, "run-id", "20762325_masked")
coordinate_source <- arg(args, "coordinate-source", "lonlat")
source_crs <- arg(args, "source-crs", "EPSG:4326")
threshold_celsius <- 14.5
thermal_cutoffs <- c(13.5, 14.5, 15.5)
overwrite <- isTRUE(args[["overwrite"]])
required_paths <- c(stage2 = stage2_path, structural_root = structural_root, observations = observation_path, canonical_report_root = canonical_report_root)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths)) stop("Required input path(s) do not exist: ", paste(names(missing_paths), missing_paths, sep = "=", collapse = "; "))
if (dir.exists(output_root) && length(list.files(output_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !overwrite) stop("Refusing to write into non-empty output root without --overwrite: ", output_root)
for (directory in c("", "structural_potential_abundance_temp_masked", "rpi", "qa", "metadata", "figures")) dir.create(file.path(output_root, directory), recursive = TRUE, showWarnings = FALSE)

stage2 <- readRDS(stage2_path)
grid <- stage2$prediction_grid
if (!is.data.frame(grid)) stop("Stage 2 artifact does not contain prediction_grid.")
structural_files <- sort(list.files(file.path(structural_root, "structural_potential_abundance"), pattern = "^structural_potential_abundance_y[0-9]{4}_w[0-9]{2}\\.tif$", full.names = TRUE))
if (length(structural_files) != 133L) stop("Existing structural potential stack must contain exactly 133 layers.")
week_keys <- sub("^structural_potential_abundance_y([0-9]{4})_w([0-9]{2})\\.tif$", "\\1-W\\2", basename(structural_files))
if (anyDuplicated(week_keys) || !identical(week_keys[[1L]], "2024-W01") || !identical(week_keys[[length(week_keys)]], "2026-W29")) stop("Structural stack does not cover 2024-W01 through 2026-W29 exactly.")

structural_stack <- terra::rast(structural_files)
template <- structural_stack[[1L]]
target_crs <- terra::crs(template, proj = TRUE)
observations <- structural_read_authoritative_observations(observation_path, target_crs, coordinate_source, source_crs)
if (!identical(observations$provenance$coordinate_source, "lonlat")) stop("This diagnostic requires authoritative lon/lat observations.")

cells <- unique(grid[c("cell_id", "x", "y")])
if (nrow(cells) != 15899L || nrow(grid) != 133L * 15899L) stop("Stage 2 support is not 133 weeks by 15,899 cells.")
ids <- as.integer(cells$cell_id)
if (any(!is.finite(ids)) || any(ids < 1L | ids > terra::ncell(template))) stop("Stage 2 cell IDs do not map to the structural raster template.")
template_xy <- terra::xyFromCell(template, ids)
geometry_error <- max(c(abs(template_xy[, 1L] - as.numeric(cells$x)), abs(template_xy[, 2L] - as.numeric(cells$y))))
stage2_crs <- stage2$joint_model_config$study$projected_crs %||% stage2$configuration$study$projected_crs
crs_compatible <- is.null(stage2_crs) || isTRUE(tryCatch(sf::st_crs(stage2_crs) == sf::st_crs(target_crs), error = function(e) FALSE))
grid_week <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-")
week_rows <- lapply(week_keys, function(key) which(grid_week == key))
names(week_rows) <- week_keys
temperature_variable <- "mintemp"
temperature_audit <- structural_validate_temperature_alignment(grid, length(week_keys), nrow(cells), temperature_variable)
alignment <- list(
  weeks = length(week_keys), expected_weeks = 133L, cells = nrow(cells), expected_cells = 15899L,
  week_labels_match = identical(week_keys, unique(grid_week)), crs_compatible = crs_compatible,
  supported_geometry_compatible = is.finite(geometry_error) && geometry_error <= 1e-7,
  geometry_max_absolute_difference = geometry_error, no_missing_temperature = temperature_audit$missing_values == 0L,
  no_silent_temporal_recycling = !temperature_audit$duplicate_week_cell, pass = length(week_keys) == 133L &&
    nrow(cells) == 15899L && isTRUE(temperature_audit$pass) && isTRUE(crs_compatible) &&
    is.finite(geometry_error) && geometry_error <= 1e-7 && !temperature_audit$duplicate_week_cell
)
if (!isTRUE(alignment$pass)) stop("Temperature/structural support alignment failed.")

structural_matrix <- terra::values(structural_stack, mat = TRUE)
support_structural <- structural_matrix[ids, seq_len(terra::nlyr(structural_stack)), drop = FALSE]
if (any(!is.finite(support_structural))) stop("Existing structural potential stack contains non-finite supported values.")
masked_matrix <- structural_matrix
mask_rows <- vector("list", length(week_keys))
for (i in seq_along(week_keys)) {
  rows <- week_rows[[i]]
  if (length(rows) != nrow(cells)) stop("Week ", week_keys[[i]], " does not have one row per supported cell.")
  position <- match(as.character(cells$cell_id), as.character(grid$cell_id[rows]))
  if (anyNA(position)) stop("Stage 2 cell support is incomplete for ", week_keys[[i]], ".")
  temperature <- as.numeric(grid[[temperature_variable]][rows][position])
  retained <- is.finite(temperature) & temperature >= threshold_celsius
  masked_matrix[ids[!retained], i] <- 0
  mask_rows[[i]] <- data.frame(week = week_keys[[i]], supported_cells = nrow(cells), cells_retained = sum(retained), cells_set_to_zero = sum(!retained), proportion_masked = mean(!retained), stringsAsFactors = FALSE)
}
mask_audit <- do.call(rbind, mask_rows)
masked_stack <- structural_stack
terra::values(masked_stack) <- masked_matrix
masked_files <- character(length(week_keys))
for (i in seq_along(week_keys)) {
  masked_files[[i]] <- file.path(output_root, "structural_potential_abundance_temp_masked", paste0("structural_potential_abundance_temp_masked_", gsub("-", "_", week_keys[[i]]), ".tif"))
  joint_inla_rasterize_write(masked_stack[[i]], masked_files[[i]], overwrite = TRUE)
}

masked_values <- terra::values(masked_stack, mat = TRUE)
finite_masked <- masked_values[is.finite(masked_values)]
native_summary <- data.frame(
  minimum = min(finite_masked), median = stats::median(finite_masked), mean = mean(finite_masked),
  q95 = as.numeric(stats::quantile(finite_masked, .95, names = FALSE)), q99 = as.numeric(stats::quantile(finite_masked, .99, names = FALSE)),
  maximum = max(finite_masked), nonfinite_count = sum(!is.finite(masked_values)), stringsAsFactors = FALSE
)
utils::write.csv(mask_audit, file.path(output_root, "qa", "temperature_mask_weekly_audit.csv"), row.names = FALSE)
utils::write.csv(native_summary, file.path(output_root, "qa", "masked_structural_native_summary.csv"), row.names = FALSE)

same_week <- structural_same_week_extract(observations$data, masked_stack, week_keys)
same_week$masked_to_zero <- same_week$matched & is.finite(same_week$extracted_value) & same_week$extracted_value == 0
same_week$finite_nonzero <- is.finite(same_week$extracted_value) & same_week$extracted_value > 0
same_week_metrics <- data.frame(
  total_observations = nrow(same_week), successfully_matched = sum(same_week$matched),
  outside_supported_raster = sum(same_week$matched & !is.finite(same_week$extracted_value)),
  in_incomplete_final_week = sum(!same_week$matched & same_week$week_key == tail(week_keys, 1L)),
  outside_horizon_week = sum(!same_week$matched & same_week$week_key != tail(week_keys, 1L)),
  masked_to_zero = sum(same_week$masked_to_zero),
  finite_nonzero_paired_predictions = sum(same_week$finite_nonzero), stringsAsFactors = FALSE
)
paired_values <- same_week$extracted_value[is.finite(same_week$extracted_value)]
paired_quantiles <- structural_paired_quantiles(paired_values)
paired_quantile_table <- data.frame(probability = c(.05, .10, .25, .50, .75, .90, .95), value = as.numeric(paired_quantiles), stringsAsFactors = FALSE)
paired_threshold <- as.numeric(paired_quantiles[[2L]])
utils::write.csv(same_week, file.path(output_root, "qa", "same_week_masked_structural_extraction.csv"), row.names = FALSE)
utils::write.csv(same_week_metrics, file.path(output_root, "qa", "same_week_masked_structural_metrics.csv"), row.names = FALSE)
utils::write.csv(paired_quantile_table, file.path(output_root, "qa", "same_week_masked_quantiles.csv"), row.names = FALSE)

count_candidates <- intersect(c("count", "n", "abundance", "cases", "case_count", "Yi"), names(observations$data))
count_column <- if (length(count_candidates)) count_candidates[[1L]] else NA_character_
association <- if (is.na(count_column)) {
  data.frame(status = "UNAVAILABLE", count_column = NA_character_, n = 0L, pearson = NA_real_, spearman = NA_real_, MAE = NA_real_, RMSE = NA_real_, reason = "Authoritative observation file contains date, host, lon, and lat but no valid observed abundance/count variable.", stringsAsFactors = FALSE)
} else {
  count <- as.numeric(observations$data[[count_column]])
  keep <- is.finite(count) & is.finite(same_week$extracted_value)
  if (sum(keep) < 2L) {
    data.frame(status = "UNAVAILABLE", count_column = count_column, n = sum(keep), pearson = NA_real_, spearman = NA_real_, MAE = NA_real_, RMSE = NA_real_, reason = "Fewer than two finite same-week count/prediction pairs.", stringsAsFactors = FALSE)
  } else {
    prediction <- same_week$extracted_value[keep]; observed <- count[keep]
    data.frame(status = "COMPLETED", count_column = count_column, n = sum(keep), pearson = stats::cor(observed, prediction, method = "pearson"), spearman = stats::cor(observed, prediction, method = "spearman"), MAE = mean(abs(observed - prediction)), RMSE = sqrt(mean((observed - prediction)^2)), reason = NA_character_, stringsAsFactors = FALSE)
  }
}
utils::write.csv(association, file.path(output_root, "qa", "same_week_abundance_association.csv"), row.names = FALSE)

structural_rpi_from_threshold <- function(stack, threshold) {
  max_run <- terra::app(stack, fun = function(x) {
    suitable <- is.finite(x) & x > threshold
    if (!any(suitable)) return(0)
    runs <- rle(suitable)
    max(runs$lengths[runs$values])
  })
  max_run <- terra::mask(max_run, stack[[1L]])
  rpi <- (max_run * 7) / 21
  classes <- postfit_reporting_rpi_classify(rpi)
  list(rpi = rpi, classes = classes, threshold = threshold)
}
rpi_summary <- function(classes) {
  values <- as.numeric(terra::values(classes, mat = FALSE))
  counts <- table(factor(as.integer(values[is.finite(values)]), levels = 0:3))
  data.frame(
    Transient_Sink = as.integer(counts[[1L]]),
    Seasonal = as.integer(counts[[2L]]),
    Multi_Season = as.integer(counts[[3L]]),
    Endemic_Core = as.integer(counts[[4L]]),
    sum_classes = sum(counts), supported_cells = sum(counts), stringsAsFactors = FALSE
  )
}
latitude_summary <- function(classes) {
  values <- as.numeric(terra::values(classes, mat = FALSE))
  cells <- which(is.finite(values) & as.integer(values) == 3L)
  if (!length(cells)) return(data.frame(max_latitude = NA_real_, q95_latitude = NA_real_, north_30 = 0L, north_35 = 0L, north_40 = 0L, stringsAsFactors = FALSE))
  xy <- terra::xyFromCell(classes, cells)
  points <- sf::st_as_sf(data.frame(x = xy[, 1L], y = xy[, 2L]), coords = c("x", "y"), crs = terra::crs(classes, proj = TRUE))
  latitude <- sf::st_coordinates(sf::st_transform(points, "EPSG:4326"))[, 2L]
  data.frame(max_latitude = max(latitude), q95_latitude = as.numeric(stats::quantile(latitude, .95, names = FALSE)), north_30 = sum(latitude > 30), north_35 = sum(latitude > 35), north_40 = sum(latitude > 40), stringsAsFactors = FALSE)
}

masked_rpi <- structural_rpi_from_threshold(masked_stack, paired_threshold)
masked_rpi_class_path <- file.path(output_root, "rpi", "masked_structural_rpi_class.tif")
masked_rpi_path <- file.path(output_root, "rpi", "masked_structural_rpi_continuous.tif")
joint_inla_rasterize_write(masked_rpi$rpi, masked_rpi_path, overwrite = TRUE)
joint_inla_rasterize_write(masked_rpi$classes, masked_rpi_class_path, overwrite = TRUE)

canonical_class_path <- file.path(canonical_report_root, "spatial", "rpi_class.tif")
canonical_metadata_path <- file.path(canonical_report_root, "metadata", "rpi_metadata.rds")
if (!file.exists(canonical_class_path) || !file.exists(canonical_metadata_path)) stop("Accepted canonical RPI class/metadata is unavailable.")
canonical_classes <- terra::rast(canonical_class_path)
canonical_metadata <- readRDS(canonical_metadata_path)
if (!isTRUE(joint_inla_rasterize_geometry_equal(canonical_classes, masked_rpi$classes))) stop("Canonical and masked RPI class rasters do not share the required geometry and projection.")
canonical_summary <- cbind(data.frame(version = "canonical_spde_inclusive_unmasked_historical", threshold = as.numeric(canonical_metadata$threshold), stringsAsFactors = FALSE), rpi_summary(canonical_classes), latitude_summary(canonical_classes))
masked_summary <- cbind(data.frame(version = "masked_structural_spde_excluded_14.5C_same_week", threshold = paired_threshold, stringsAsFactors = FALSE), rpi_summary(masked_rpi$classes), latitude_summary(masked_rpi$classes))
comparison <- rbind(canonical_summary, masked_summary)
utils::write.csv(comparison, file.path(output_root, "qa", "rpi_comparison_summary.csv"), row.names = FALSE)
utils::write.csv(data.frame(stored_canonical_threshold = as.numeric(canonical_metadata$threshold), previously_recomputed_threshold = 0.6627025, stringsAsFactors = FALSE), file.path(output_root, "qa", "canonical_rpi_threshold_provenance.csv"), row.names = FALSE)

thermal_sensitivity <- lapply(thermal_cutoffs, function(cutoff) {
  candidate_matrix <- structural_matrix
  for (i in seq_along(week_keys)) {
    rows <- week_rows[[i]]
    position <- match(as.character(cells$cell_id), as.character(grid$cell_id[rows]))
    temperature <- as.numeric(grid[[temperature_variable]][rows][position])
    candidate_matrix[ids[is.finite(temperature) & temperature < cutoff], i] <- 0
  }
  candidate_stack <- structural_stack
  terra::values(candidate_stack) <- candidate_matrix
  candidate_same_week <- structural_same_week_extract(observations$data, candidate_stack, week_keys)
  candidate_threshold <- as.numeric(structural_paired_quantiles(candidate_same_week$extracted_value[is.finite(candidate_same_week$extracted_value)], .10))
  candidate_rpi <- structural_rpi_from_threshold(candidate_stack, candidate_threshold)
  candidate_latitude <- latitude_summary(candidate_rpi$classes)
  candidate_classes <- rpi_summary(candidate_rpi$classes)
  data.frame(temperature_threshold_celsius = cutoff, paired_threshold = candidate_threshold, endemic_core_count = candidate_classes$Endemic_Core, maximum_endemic_core_latitude = candidate_latitude$max_latitude, endemic_core_north_of_35 = candidate_latitude$north_35, stringsAsFactors = FALSE)
})
thermal_sensitivity <- do.call(rbind, thermal_sensitivity)
utils::write.csv(thermal_sensitivity, file.path(output_root, "qa", "thermal_cutoff_sensitivity.csv"), row.names = FALSE)

class_palette <- c("#f0f0f0", "#2c7fb8", "#41ab5d", "#d7301f")
class_breaks <- c(-.5, .5, 1.5, 2.5, 3.5)
grDevices::png(file.path(output_root, "figures", "canonical_vs_masked_structural_rpi_class.png"), width = 1800, height = 900, res = 150)
graphics::par(mfrow = c(1, 2), mar = c(2, 2, 3, 5))
terra::plot(canonical_classes, col = class_palette, breaks = class_breaks, axes = FALSE, legend = FALSE, main = "Canonical RPI")
graphics::legend("right", legend = c("Transient / Sink", "Seasonal", "Multi-Season", "Endemic Core"), fill = class_palette, bty = "n", cex = .8)
terra::plot(masked_rpi$classes, col = class_palette, breaks = class_breaks, axes = FALSE, legend = FALSE, main = "14.5 C masked structural RPI")
graphics::legend("right", legend = c("Transient / Sink", "Seasonal", "Multi-Season", "Endemic Core"), fill = class_palette, bty = "n", cex = .8)
grDevices::dev.off()

selected_weeks <- unique(c(week_keys[[1L]], week_keys[[ceiling(length(week_keys) / 2L)]], week_keys[[length(week_keys) - 1L]], "2026-W29"))
selected_index <- match(selected_weeks, week_keys)
grDevices::png(file.path(output_root, "figures", "selected_week_structural_vs_masked_potential.png"), width = 1800, height = 900 * length(selected_index) / 2, res = 150)
graphics::par(mfrow = c(length(selected_index), 2), mar = c(2, 2, 3, 4))
for (j in seq_along(selected_index)) {
  i <- selected_index[[j]]
  z <- range(c(terra::values(structural_stack[[i]], mat = FALSE), terra::values(masked_stack[[i]], mat = FALSE)), na.rm = TRUE)
  terra::plot(structural_stack[[i]], zlim = z, axes = FALSE, main = paste("Structural", selected_weeks[[j]]))
  terra::plot(masked_stack[[i]], zlim = z, axes = FALSE, main = paste("Masked 14.5 C", selected_weeks[[j]]))
}
grDevices::dev.off()

utils::write.csv(alignment, file.path(output_root, "qa", "temperature_alignment_audit.csv"), row.names = FALSE)
metadata <- list(
  status = "MASKED STRUCTURAL RPI DIAGNOSTICS COMPLETE — READY FOR REVIEW", run_id = run_id,
  provenance = list(
    fit_job = "20762325", fit_sha = "42bb427d9ea2c456bdabcb64d165bd00eb49091a6f93bfd6d1d7ff92d8c85c3e",
    stage2_sha = "13281ea9dabd90724ab9f9eb4f7fee27c9ec948b6102272abbefcb3ae79bddb3",
    stage3a_sha = "34d17b6cb49e114ba0d6b4a7344113b4a6afebb8f735adf36b96a9ec51fbd64d",
    structural_root = normalizePath(structural_root, mustWork = TRUE), canonical_report_root = normalizePath(canonical_report_root, mustWork = TRUE),
    authoritative_observations = observations$provenance
  ),
  threshold_celsius = threshold_celsius, threshold_role = "lower developmental thermal threshold", source = "Gutierrez & Ponti 2014", application = "derived post-fit physiological mask",
  temperature = list(variable = temperature_variable, units = "degrees Celsius", temporal_aggregation = "modeled weekly minimum temperature", spatial_resolution = "production prediction-cell grid", source = "Stage 2 prediction_grid$mintemp"),
  alignment = alignment, mask_summary = mask_audit, native_summary = native_summary,
  same_week = list(metrics = same_week_metrics, quantiles = paired_quantile_table, primary_threshold = paired_threshold),
  abundance_association = association, canonical_rpi = canonical_summary, masked_structural_rpi = masked_summary,
  thermal_sensitivity = thermal_sensitivity, rpi_parameters = list(gen_days = 21, days_per_layer = 7, class_boundaries = c("RPI < 3" = "Transient / Sink", "3 <= RPI < 8" = "Seasonal", "8 <= RPI < 15" = "Multi-Season", "RPI >= 15" = "Endemic Core")),
  outputs = list(masked_stack = masked_files, masked_rpi = masked_rpi_path, masked_rpi_class = masked_rpi_class_path),
  visual_qa = list(class_comparison = file.path(output_root, "figures", "canonical_vs_masked_structural_rpi_class.png"), selected_weeks = selected_weeks, structural_vs_masked = file.path(output_root, "figures", "selected_week_structural_vs_masked_potential.png"), northern_core_contracts = masked_summary$max_latitude[[1L]] <= canonical_summary$max_latitude[[1L]] && masked_summary$north_35[[1L]] <= canonical_summary$north_35[[1L]])
)
saveRDS(metadata, file.path(output_root, "metadata", "masked_structural_rpi_diagnostics_metadata.rds"))
if (requireNamespace("yaml", quietly = TRUE)) yaml::write_yaml(metadata, file.path(output_root, "metadata", "masked_structural_rpi_diagnostics_metadata.yml"))
cat(metadata$status, "\nOutput: ", normalizePath(output_root, mustWork = TRUE), "\n", sep = "")
