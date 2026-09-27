# Post-fit structural ecological prediction diagnostic. This script only reads
# immutable artifacts and existing Phase 2/3 products; it never calls INLA().

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "joint_inla_project.R"), local = .GlobalEnv)
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
required_args <- c("fit", "build", "stage2", "phase2", "phase3", "observations", "full-potential-root", "output-root")
missing_args <- required_args[vapply(required_args, function(name) is.null(args[[name]]) || !nzchar(as.character(args[[name]])), logical(1L))]
if (length(missing_args)) stop("Supply explicit arguments: ", paste(paste0("--", missing_args), collapse = ", "))

fit_path <- arg(args, "fit"); build_path <- arg(args, "build"); stage2_path <- arg(args, "stage2")
phase2_root <- arg(args, "phase2"); phase3_root <- arg(args, "phase3")
observation_path <- arg(args, "observations"); full_potential_root <- arg(args, "full-potential-root")
output_root <- arg(args, "output-root"); run_id <- arg(args, "run-id", "20762325_9a1a478")
coordinate_source <- arg(args, "coordinate-source", "lonlat"); source_crs <- arg(args, "source-crs", "EPSG:4326")
temperature_variable <- arg(args, "temperature-variable", "mintemp")
threshold_text <- arg(args, "temperature-threshold", NULL)
temperature_threshold <- if (is.null(threshold_text) || identical(tolower(as.character(threshold_text)), "null")) NULL else as.numeric(threshold_text)
cell_area_km2 <- as.numeric(arg(args, "cell-area-km2", "623.467152902406"))
overwrite <- isTRUE(args[["overwrite"]])
if (length(cell_area_km2) != 1L || !is.finite(cell_area_km2) || cell_area_km2 <= 0) stop("--cell-area-km2 must be one finite positive value.")
all_paths <- c(fit = fit_path, build = build_path, stage2 = stage2_path, phase2 = phase2_root, phase3 = phase3_root, observations = observation_path, full_potential_root = full_potential_root)
missing_paths <- all_paths[!file.exists(all_paths)]
if (length(missing_paths)) stop("Required input path(s) do not exist: ", paste(names(missing_paths), missing_paths, sep = "=", collapse = "; "))
if (dir.exists(output_root) && length(list.files(output_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !overwrite) stop("Refusing to write into non-empty diagnostic output root without --overwrite: ", output_root)

dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
for (directory in c("structural_intensity", "structural_potential_abundance", "metadata", "qa", "figures")) dir.create(file.path(output_root, directory), recursive = TRUE, showWarnings = FALSE)
if (!is.null(temperature_threshold)) dir.create(file.path(output_root, "structural_potential_abundance_temp_masked"), recursive = TRUE, showWarnings = FALSE)

build <- readRDS(build_path); fit_artifact <- readRDS(fit_path); stage2 <- readRDS(stage2_path)
grid <- stage2$prediction_grid
if (!is.data.frame(grid)) stop("Stage 2 artifact does not contain prediction_grid.")
layout <- joint_inla_extract_expected_spde_layout(build)
groups <- sort(unique(as.integer(grid$quarter_index)))
if (!identical(groups, seq_len(layout$n_groups))) stop("Stage 2 quarter_index levels are not exactly contiguous 1:n_groups from Stage 3A.")
components <- joint_inla_project_prepare_components(build, fit_artifact, stage2)
if (!identical(as.integer(components$n_groups), as.integer(layout$n_groups))) stop("Prepared component group count disagrees with Stage 3A.")

template_files <- list.files(phase3_root, pattern = "tier2_intensity.*\\.tif$", recursive = TRUE, full.names = TRUE)
if (!length(template_files)) stop("Could not locate an existing Phase 3 Tier 2 intensity raster.")
template <- terra::rast(template_files[[1L]])
target_crs <- terra::crs(template, proj = TRUE)
observations <- structural_read_authoritative_observations(observation_path, target_crs, coordinate_source, source_crs)
coordinate_audit <- structural_coordinate_audit(observations$data, observations$provenance)
coordinate_table <- do.call(rbind, lapply(names(coordinate_audit$ranges), function(column) {
  values <- coordinate_audit$ranges[[column]]
  data.frame(coordinate = column, minimum = unname(values[["min"]]), maximum = unname(values[["max"]]), stringsAsFactors = FALSE)
}))
utils::write.csv(coordinate_table, file.path(output_root, "qa", "coordinate_ranges_audit.csv"), row.names = FALSE, na = "")
saveRDS(coordinate_audit, file.path(output_root, "metadata", "coordinate_audit.rds"))

potential_files <- sort(list.files(full_potential_root, pattern = "potential_abundance.*\\.tif$", recursive = TRUE, full.names = TRUE))
if (!length(potential_files)) stop("No accepted potential-abundance rasters found under --full-potential-root.")
full_potential <- terra::rast(potential_files)
if (terra::nlyr(full_potential) != 133L) stop("Accepted full potential-abundance stack must contain 133 layers.")
intersection <- structural_observation_intersection_audit(observations$data, template, full_potential)
if (intersection$finite_potential_extraction < 1L) stop("No authoritative observations intersect a finite accepted potential-abundance value.")
utils::write.csv(intersection, file.path(output_root, "qa", "observation_intersection_audit.csv"), row.names = FALSE, na = "")

weekly_files <- sort(list.files(file.path(phase2_root, "weekly"), pattern = "^prediction_y[0-9]{4}_w[0-9]{2}\\.rds$", full.names = TRUE))
if (length(weekly_files) != 133L) stop("Existing Phase 2 weekly output must contain 133 files.")
weeks <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-")
week_keys <- unique(weeks)
if (length(week_keys) != 133L || nrow(grid) != 133L * 15899L) stop("Stage 2 support is not the accepted 133-week, 15,899-cell horizon.")

cells <- unique(grid[c("cell_id", "x", "y")])
if (anyDuplicated(cells$cell_id)) stop("Stage 2 cells map to multiple coordinates.")
if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required for the saved-mesh projection diagnostic.")
mesh <- joint_inla_project_mesh(build)
A_cell <- INLA::inla.spde.make.A(mesh, loc = as.matrix(cells[c("x", "y")]))
field_cells <- list(
  tier2_field = as.matrix(A_cell %*% joint_inla_project_field_matrix(components$fields$tier2_field, components$n_groups, "tier2_field")),
  tier2_copy_field = as.matrix(A_cell %*% joint_inla_project_field_matrix(components$fields$tier2_copy_field, components$n_groups, "tier2_copy_field"))
)
cell_index <- match(as.character(grid$cell_id), as.character(cells$cell_id))
grid_group <- as.integer(grid$quarter_index)
temperature_audit <- structural_validate_temperature_alignment(grid, length(week_keys), nrow(cells), temperature_variable)
if (!isTRUE(temperature_audit$pass)) stop("Stage 2 temperature source is not complete and aligned to every weekly cell.")

reconstruction_rows <- list(); intensity_stats <- list(); written <- list(); masked_written <- list()
for (i in seq_along(weekly_files)) {
  week_data <- readRDS(weekly_files[[i]])
  if (!is.data.frame(week_data) || nrow(week_data) != nrow(cells)) stop("Phase 2 weekly file has unexpected support size: ", weekly_files[[i]])
  key <- paste(as.integer(week_data$epiyear[[1L]]), sprintf("W%02d", as.integer(week_data$epiweek[[1L]])), sep = "-")
  rows <- which(weeks == key)
  if (length(rows) != nrow(cells)) stop("Stage 2 grid does not have one complete week for ", key)
  phase2_position <- match(as.character(grid$cell_id[rows]), as.character(week_data$cell_id))
  if (anyNA(phase2_position)) stop("Phase 2 weekly support does not match Stage 2 cell support for ", key)
  data <- grid[rows, , drop = FALSE]
  nonspde <- structural_tier2_nonspde_components(data, components)
  spatial <- field_cells$tier2_field[cbind(cell_index[rows], grid_group[rows])]
  copy <- field_cells$tier2_copy_field[cbind(cell_index[rows], grid_group[rows])]
  structural_eta <- nonspde$structural_eta2
  full_eta <- as.numeric(week_data$eta2_mean[phase2_position])
  reconstruction <- structural_reconstruction_metrics(full_eta, structural_eta, spatial, copy)
  if (!isTRUE(reconstruction$pass)) stop("SPDE-excluded reconstruction failed for ", key, ": RMSE=", reconstruction$rmse, ", max_abs=", reconstruction$max_abs)
  reconstruction_rows[[i]] <- data.frame(week = key, n = reconstruction$n, rmse = reconstruction$rmse, max_abs = reconstruction$max_abs, nonfinite = reconstruction$nonfinite, pass = reconstruction$pass, stringsAsFactors = FALSE)
  structural_intensity <- exp(structural_eta)
  if (any(!is.finite(structural_intensity))) stop("Structural intensity is non-finite for ", key)
  structural_potential <- structural_intensity * cell_area_km2
  ids <- as.integer(cells$cell_id)
  intensity_raster <- joint_inla_rasterize_assign_values(template, ids, structural_intensity)
  potential_raster <- joint_inla_rasterize_assign_values(template, ids, structural_potential)
  year <- as.integer(week_data$epiyear[[1L]]); week <- as.integer(week_data$epiweek[[1L]])
  intensity_path <- file.path(output_root, "structural_intensity", paste0("tier2_intensity_structural_y", year, "_w", sprintf("%02d", week), ".tif"))
  potential_path <- file.path(output_root, "structural_potential_abundance", paste0("structural_potential_abundance_y", year, "_w", sprintf("%02d", week), ".tif"))
  joint_inla_rasterize_write(intensity_raster, intensity_path, overwrite = TRUE)
  joint_inla_rasterize_write(potential_raster, potential_path, overwrite = TRUE)
  masked_path <- NA_character_
  if (!is.null(temperature_threshold)) {
    masked_values <- structural_apply_temperature_mask(structural_potential, as.numeric(data[[temperature_variable]]), temperature_threshold)
    masked_raster <- joint_inla_rasterize_assign_values(template, ids, masked_values)
    masked_path <- file.path(output_root, "structural_potential_abundance_temp_masked", paste0("structural_potential_abundance_temp_masked_y", year, "_w", sprintf("%02d", week), ".tif"))
    joint_inla_rasterize_write(masked_raster, masked_path, overwrite = TRUE)
    masked_written[[i]] <- masked_path
  }
  written[[i]] <- data.frame(week = key, structural_intensity = intensity_path, structural_potential_abundance = potential_path, temperature_masked = masked_path, stringsAsFactors = FALSE)
  intensity_stats[[i]] <- data.frame(week = key, minimum = min(structural_intensity), median = stats::median(structural_intensity), mean = mean(structural_intensity), q95 = as.numeric(stats::quantile(structural_intensity, .95, names = FALSE)), q99 = as.numeric(stats::quantile(structural_intensity, .99, names = FALSE)), maximum = max(structural_intensity), stringsAsFactors = FALSE)
}

reconstruction_audit <- do.call(rbind, reconstruction_rows)
utils::write.csv(reconstruction_audit, file.path(output_root, "qa", "structural_reconstruction_audit.csv"), row.names = FALSE)
structural_intensity_summary <- do.call(rbind, intensity_stats)
utils::write.csv(structural_intensity_summary, file.path(output_root, "qa", "structural_intensity_summary.csv"), row.names = FALSE)
full_intensity_files <- sort(list.files(phase3_root, pattern = "^tier2_intensity_y[0-9]{4}_w[0-9]{2}\\.tif$", recursive = TRUE, full.names = TRUE))
if (length(full_intensity_files) != 133L) stop("Existing Phase 3 full Tier 2 intensity stack does not contain 133 layers.")
full_intensity <- terra::rast(full_intensity_files)
full_q95 <- terra::global(full_intensity, fun = function(x) stats::quantile(x, .95, na.rm = TRUE))[, 1L]
full_q99 <- terra::global(full_intensity, fun = function(x) stats::quantile(x, .99, na.rm = TRUE))[, 1L]
full_intensity_summary <- data.frame(
  source = c("full_spde_inclusive", "spde_excluded_structural"),
  minimum = c(min(terra::global(full_intensity, "min", na.rm = TRUE)[, 1L]), min(structural_intensity_summary$minimum)),
  median = c(stats::median(terra::global(full_intensity, "mean", na.rm = TRUE)[, 1L]), stats::median(structural_intensity_summary$median)),
  mean = c(mean(terra::global(full_intensity, "mean", na.rm = TRUE)[, 1L]), mean(structural_intensity_summary$mean)),
  q95 = c(stats::median(full_q95), stats::median(structural_intensity_summary$q95)),
  q99 = c(stats::median(full_q99), stats::median(structural_intensity_summary$q99)),
  maximum = c(max(terra::global(full_intensity, "max", na.rm = TRUE)[, 1L]), max(structural_intensity_summary$maximum)),
  stringsAsFactors = FALSE
)
utils::write.csv(full_intensity_summary, file.path(output_root, "qa", "full_vs_structural_intensity_summary.csv"), row.names = FALSE)
utils::write.csv(do.call(rbind, written), file.path(output_root, "metadata", "structural_raster_manifest.csv"), row.names = FALSE, na = "")

full_threshold_values <- as.matrix(terra::extract(full_potential, terra::vect(observations$data, geom = c("x", "y"), crs = terra::crs(full_potential)))[, -1L, drop = FALSE])
canonical_threshold <- as.numeric(stats::quantile(as.numeric(full_threshold_values), .10, na.rm = TRUE, names = FALSE))
canonical_threshold_audit <- data.frame(reproduced_threshold = canonical_threshold, expected_threshold = 0.6834011847, absolute_difference = abs(canonical_threshold - 0.6834011847), pass = abs(canonical_threshold - 0.6834011847) <= 1e-8, source = "accepted unmasked full potential-abundance stack; current RPI extraction semantics", stringsAsFactors = FALSE)
utils::write.csv(canonical_threshold_audit, file.path(output_root, "qa", "canonical_rpi_threshold_audit.csv"), row.names = FALSE, na = "")
if (!isTRUE(canonical_threshold_audit$pass[[1L]])) stop("Canonical RPI threshold reproduction failed.")

grDevices::png(file.path(output_root, "figures", "observation_locations_supported_domain.png"), width = 1600, height = 1200, res = 150)
terra::plot(template, main = "Authoritative observations and accepted raster support", axes = TRUE)
graphics::points(observations$data$x, observations$data$y, pch = 16, cex = .35, col = grDevices::adjustcolor("black", .35))
grDevices::dev.off()

same_week_status <- "BLOCKED_TEMPERATURE_THRESHOLD_REQUIRED"
if (!is.null(temperature_threshold)) {
  masked_stack <- terra::rast(sort(unlist(masked_written)))
  same_week <- structural_same_week_extract(observations$data, masked_stack, week_keys)
  utils::write.csv(same_week, file.path(output_root, "qa", "same_week_structural_masked_extraction.csv"), row.names = FALSE, na = "")
  candidates <- as.numeric(stats::quantile(as.numeric(terra::values(masked_stack, mat = FALSE)), probs = seq(.05, .95, length.out = 9L), na.rm = TRUE, names = FALSE))
  sensitivity <- structural_rpi_threshold_sensitivity(masked_stack, observations$data, unique(c(canonical_threshold, candidates)))
  utils::write.csv(sensitivity, file.path(output_root, "qa", "rpi_threshold_sensitivity.csv"), row.names = FALSE)
  same_week_status <- "COMPLETED"
}

final_status <- if (is.null(temperature_threshold)) "STRUCTURAL SURFACE COMPLETE — TEMPERATURE THRESHOLD REQUIRED" else "STRUCTURAL SURFACE AND RPI DIAGNOSTICS COMPLETE — READY FOR REVIEW"
qa <- data.frame(
  check = c("coordinate_audit", "observation_intersection", "quarter_group_structure", "spde_excluded_reconstruction", "temperature_alignment", "canonical_rpi_threshold", "same_week_masked_rpi"),
  status = c("PASS", if (intersection$supported > 0L) "PASS" else "FAIL", "PASS", if (all(reconstruction_audit$pass)) "PASS" else "FAIL", if (temperature_audit$pass) "PASS" else "FAIL", if (canonical_threshold_audit$pass) "PASS" else "FAIL", same_week_status),
  details = c("Explicit authoritative coordinate source and CRS recorded.", paste(names(intersection), intersection, sep = "=", collapse = "; "), paste0("Stage 3A n_groups=", layout$n_groups, "; exact levels 1:n_groups."), "Full eta2 equals structural eta2 plus Tier 2 field plus Tier 2 copy field within tolerance.", "Stage 2 mintemp is complete for every modeled week/cell.", paste0("Reproduced threshold=", canonical_threshold), "Masked same-week diagnostics remain blocked until an authoritative temperature threshold is supplied."),
  stringsAsFactors = FALSE
)
utils::write.csv(qa, file.path(output_root, "qa", "structural_qa_summary.csv"), row.names = FALSE, na = "")
metadata <- list(
  status = final_status, run_id = run_id, horizon = list(weeks = length(week_keys), cells = nrow(cells), rows = nrow(grid)),
  immutable_inputs = lapply(c(fit = fit_path, build = build_path, stage2 = stage2_path, phase2 = phase2_root, phase3 = phase3_root), normalizePath, mustWork = TRUE),
  coordinate_audit = coordinate_audit, observation_intersection = intersection,
  group_structure = list(authoritative_n_groups = layout$n_groups, levels = groups, grouping_variable = "quarter_index"),
  structural_prediction = list(name = "tier2_eta_structural", intensity_name = "tier2_intensity_structural", potential_name = "structural_potential_abundance", direct_model_output = FALSE, spde_terms_included = FALSE, removed_terms = c("tier2_field", "tier2_copy_field"), retained_terms = c("fixed_effects", "environmental_covariates_and_interactions", "livestock_effects", "tier2_week_RW1", "cattle_RW2"), nominal_cell_area_km2 = cell_area_km2),
  temperature_mask = list(variable = temperature_variable, threshold = temperature_threshold, operator = ">=", source = temperature_audit$source, status = if (is.null(temperature_threshold)) "THRESHOLD_REQUIRED" else "APPLIED"),
  canonical_rpi = canonical_threshold_audit, same_week_status = same_week_status, output_root = normalizePath(output_root, mustWork = TRUE)
)
saveRDS(metadata, file.path(output_root, "metadata", "structural_surface_metadata.rds"))
if (requireNamespace("yaml", quietly = TRUE)) yaml::write_yaml(metadata, file.path(output_root, "metadata", "structural_surface_metadata.yml"))
cat(final_status, "\nOutput: ", output_root, "\n", sep = "")
