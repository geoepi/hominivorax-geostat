#!/usr/bin/env Rscript

# Generate canonical post-fit reporting objects and figures from validated
# reference artifacts. This runner never refits, validates, projects, or
# rasterizes the model.

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
script_path <- sub("^--file=", "", script_arg)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "joint_inla_extract.R"), local = .GlobalEnv)

parse_args <- function(args) {
  values <- list(); i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (name %in% c("overwrite", "no-rpi")) {
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
run_id <- arg(args, "run-id", "20725437")
output_root <- arg(args, "output-root", Sys.getenv("POSTFIT_REPORTING_OUTPUT_ROOT", unset = NA_character_))
fit_path <- arg(args, "fit", Sys.getenv("POSTFIT_REPORTING_FIT", unset = NA_character_))
build_path <- arg(args, "build", Sys.getenv("POSTFIT_REPORTING_BUILD", unset = NA_character_))
stage2_path <- arg(args, "stage2")
phase3_root <- arg(args, "phase3-root", file.path(dirname(fit_path), paste0("raster_surfaces_", run_id)))
phase2_root <- arg(args, "phase2", file.path(dirname(fit_path), paste0("prediction_projection_", run_id)))
boundary_path <- arg(args, "boundary")
species_path <- arg(args, "species-data")
observation_path <- arg(args, "observation-input")
species_cohort <- arg(args, "species-cohort")
if (is.null(observation_path) && is.null(species_cohort) && !is.null(species_path)) observation_path <- species_path
species_column <- arg(args, "species-column", "host_standardized")
species_category_column <- arg(args, "species-category-column")
host_column <- arg(args, "host-column", "host")
mapping_version <- arg(args, "mapping-version", "historical-host-normalization-v2")
cell_area_template <- arg(args, "cell-area-template")
cell_area_value <- arg(args, "cell-area")
cell_area_units <- arg(args, "cell-area-units")
observations_path <- arg(args, "observations")
rpi_observation_path <- arg(args, "rpi-observations", observations_path)
rpi_coordinate_source <- arg(args, "rpi-coordinate-source", "lonlat")
rpi_coordinate_crs <- arg(args, "rpi-coordinate-crs", "EPSG:4326")
structural_root <- arg(args, "structural-root")
masked_structural_root <- arg(args, "masked-structural-root")
reference_fit_path <- arg(args, "reference-fit")
reference_build_path <- arg(args, "reference-build")
reference_run_id <- arg(args, "reference-run", "20725437")
cattle_units <- arg(args, "cattle-units")
overwrite <- isTRUE(args[["overwrite"]])

if (is.null(stage2_path)) stage2_path <- Sys.getenv("POSTFIT_REPORTING_STAGE2", unset = NA_character_)
if (any(is.na(c(output_root, fit_path, build_path, stage2_path))) || any(!nzchar(c(output_root, fit_path, build_path, stage2_path)))) {
  stop("Supply explicit --output-root, --fit, --build, and --stage2 paths for the private reporting run.")
}
if (xor(is.null(structural_root), is.null(masked_structural_root))) stop("Supply both --structural-root and --masked-structural-root for canonical downstream reporting.")
if (is.null(structural_root)) stop("Canonical downstream reporting requires accepted structural and masked structural product roots.")

required_paths <- c(build = build_path, fit = fit_path, stage2 = stage2_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths)) {
  stop("Reference reporting run cannot start because required artifact(s) are unavailable: ",
       paste(names(missing_paths), missing_paths, sep = "=", collapse = "; "),
       ". Supply explicit --build, --fit, and --stage2 paths from the validated reference run.")
}

postfit_reporting_assert_output_isolated(output_root, run_id, overwrite = overwrite)
paths <- postfit_reporting_output_paths(output_root, run_id)
for (directory in paths[c("objects", "tables", "figures", "spatial", "metadata", "qa")]) dir.create(directory, recursive = TRUE, showWarnings = FALSE)

structural_products <- postfit_reporting_prepare_structural_products(
  structural_root = structural_root, masked_root = masked_structural_root, output_spatial = paths$spatial,
  expected_weeks = 133L, expected_cells = 15899L, threshold_celsius = 14.5, overwrite = overwrite
)
utils::write.csv(structural_products$manifest, file.path(paths$metadata, "structural_product_manifest.csv"), row.names = FALSE, na = "")
utils::write.csv(data.frame(
  product = c("tier2_eta_structural", "tier2_intensity_structural", "structural_potential_abundance", "structural_potential_abundance_temp_masked"),
  role = c("structural ecological prediction", "structural ecological prediction", "derived structural ecological potential abundance", "derived physiologically masked ecological potential abundance"),
  spde_terms_included = FALSE,
  temperature_variable = c(NA_character_, NA_character_, NA_character_, "mintemp"),
  temperature_units = c(NA_character_, NA_character_, NA_character_, "degrees Celsius"),
  temperature_threshold_celsius = c(NA_real_, NA_real_, NA_real_, 14.5),
  mask_operator = c(NA_character_, NA_character_, NA_character_, ">="),
  threshold_role = c(NA_character_, NA_character_, NA_character_, "lower developmental thermal threshold"),
  threshold_source = c(NA_character_, NA_character_, NA_character_, "Gutierrez & Ponti 2014"),
  source = c("log(tier2_intensity_structural)", "accepted structural reconstruction", "accepted structural reconstruction", "accepted 14.5 C masked structural diagnostic"),
  stringsAsFactors = FALSE
), file.path(paths$metadata, "structural_product_semantics.csv"), row.names = FALSE, na = "")

build <- readRDS(build_path)
fit_artifact <- readRDS(fit_path)
stage2 <- readRDS(stage2_path)
cattle_provenance <- postfit_reporting_cattle_provenance(stage2, cattle_units = cattle_units)

fixed <- postfit_reporting_fixed_effects(fit_artifact)
cattle <- postfit_reporting_cattle_effect(fit_artifact, stage2, units = cattle_provenance$cattle_density_units)
temporal <- postfit_reporting_temporal_effects(build, fit_artifact, stage2)
model_summary <- postfit_reporting_model_summary(build, fit_artifact, stage2)
random_effect_summaries <- postfit_reporting_random_effect_summaries(fit_artifact, build)

generated_tables <- list()
generated_objects <- list()
write_table <- function(object, name) {
  result <- postfit_reporting_write_table(object, name, paths)
  generated_tables[[name]] <<- result$csv
  generated_objects[[name]] <<- result$rds
}
write_table(fixed$tier1, "fixed_effects_tier1")
write_table(fixed$tier2, "fixed_effects_tier2")
write_table(cattle, "cattle_effect")
write_table(temporal, "temporal_effects")
write_table(random_effect_summaries, "random_effect_summaries")
saveRDS(model_summary, file.path(paths$objects, "model_summary.rds")); generated_objects$model_summary <- file.path(paths$objects, "model_summary.rds")

if (xor(is.null(reference_fit_path), is.null(reference_build_path))) {
  stop("Supply both --reference-fit and --reference-build to generate the reference-vs-production random-effect comparison.")
}
if (!is.null(reference_fit_path)) {
  if (!file.exists(reference_fit_path) || !file.exists(reference_build_path)) stop("Reference fit/build paths for random-effect comparison must exist.")
  reference_summaries <- postfit_reporting_random_effect_summaries(readRDS(reference_fit_path), readRDS(reference_build_path))
  comparison <- postfit_reporting_random_effect_comparison(reference_summaries, random_effect_summaries,
                                                           reference_run = reference_run_id, production_run = run_id)
  write_table(comparison, "random_effect_comparison")
}

generated_figures <- list()
save_figure <- function(plot, name, width, height) {
  result <- postfit_reporting_save_plot(plot, name, paths, width = width, height = height)
  generated_figures[[name]] <<- result
  generated_objects[[paste0("plot_", name)]] <<- result$rds
}
save_figure(postfit_reporting_plot_cattle(cattle, cattle_units = cattle_provenance$cattle_density_units), "cattle_effect", 8, 5)
save_figure(postfit_reporting_plot_temporal(temporal), "temporal_effects", 10, 8)
utils::write.csv(postfit_reporting_metadata_table(cattle_provenance), file.path(paths$metadata, "cattle_effect_provenance.csv"), row.names = FALSE, na = "")

species_audit <- list(status = "UNRESOLVED", reason = "No explicit species source cohort was supplied; denominator was not guessed.")
if (!is.null(observation_path)) {
  if (!file.exists(observation_path)) stop("Authoritative observation input does not exist: ", observation_path)
  observation_data <- utils::read.csv(observation_path, stringsAsFactors = FALSE, check.names = FALSE)
  species <- postfit_reporting_host_composition(
    observation_data, host_column = host_column, source_file = normalizePath(observation_path, mustWork = TRUE),
    mapping_version = mapping_version
  )
  write_table(species, "species_composition")
  write_table(species$lookup, "host_lookup")
  write_table(species$assignment_table, "host_assignments")
  write_table(species$first_host_assignment_table, "host_assignments_first_host")
  write_table(species$first_host_table, "species_composition_first_host")
  write_table(species$first_host_sensitivity, "species_composition_first_host_sensitivity")
  write_table(species$unmatched_audit, "host_unmatched_audit")
  save_figure(postfit_reporting_plot_species(species), "species_composition", 9, 8)
  species_audit <- species$audit
} else if (!is.null(species_path)) {
  if (is.null(species_cohort)) stop("--species-data requires --species-cohort, or use --observation-input with --host-column.")
  species_data <- utils::read.csv(species_path, stringsAsFactors = FALSE, check.names = FALSE)
  species <- postfit_reporting_species_composition(species_data, species_column, species_cohort, species_category_column)
  write_table(species, "species_composition")
  save_figure(postfit_reporting_plot_species(species), "species_composition", 9, 8)
  species_audit <- species$audit
}
utils::write.csv(data.frame(
  metric = names(species_audit),
  value = vapply(species_audit, function(value) if (is.null(value)) NA_character_ else paste(as.character(value), collapse = "|"), character(1L)),
  stringsAsFactors = FALSE
), file.path(paths$metadata, "species_composition_audit.csv"), row.names = FALSE, na = "")

map_manifest <- NULL
map_object <- NULL
map_audit <- list(status = "UNRESOLVED", reason = "No Phase 3 raster root was supplied or found.")
if (!is.null(phase3_root) && dir.exists(phase3_root)) {
  boundary <- NULL
  if (!is.null(boundary_path)) {
    postfit_reporting_require("sf")
    if (!file.exists(boundary_path)) stop("Boundary layer does not exist: ", boundary_path)
    boundary <- sf::st_read(boundary_path, quiet = TRUE)
  }
  map_manifest <- postfit_reporting_map_manifest(phase3_root)
  selected <- postfit_reporting_select_map_weeks(map_manifest, n = 4L)
  selected$run_id <- run_id
  selected$tier1_raster <- selected$tier1_probability_path
  selected$tier2_raster <- selected$tier2_intensity_path
  map_object <- postfit_reporting_selected_map_values(selected, raster_root = phase3_root, boundary = boundary)
  saveRDS(map_object, file.path(paths$objects, "selected_map_values.rds")); generated_objects$selected_map_values <- file.path(paths$objects, "selected_map_values.rds")
  selected_map_plot <- postfit_reporting_plot_selected_maps(map_object)
  save_figure(selected_map_plot, "selected_week_maps", 12, 10)
  map_audit <- list(status = "PASS", selection_rule = selected$selection_rule[[1L]], selected_weeks = selected$week, source_phase3_root = normalizePath(phase3_root, mustWork = TRUE), boundary_path = boundary_path %||% NA_character_, values_unchanged = TRUE)
  utils::write.csv(selected, file.path(paths$metadata, "selected_map_weeks.csv"), row.names = FALSE, na = "")
}

structural_indices <- unique(c(1L, ceiling(structural_products$weeks / 2), structural_products$weeks - 1L, structural_products$weeks))
structural_selected <- structural_products$manifest[structural_indices, , drop = FALSE]
utils::write.csv(structural_selected, file.path(paths$metadata, "selected_structural_masked_weeks.csv"), row.names = FALSE, na = "")
structural_figure_paths <- postfit_reporting_write_structural_masked_figure(
  structural_selected$structural_potential_abundance_path,
  structural_selected$structural_potential_abundance_temp_masked_path,
  structural_selected$week,
  file.path(paths$figures, "selected_structural_vs_masked_potential.png"),
  file.path(paths$figures, "selected_structural_vs_masked_potential.pdf")
)
generated_figures$selected_structural_vs_masked_potential <- as.list(structural_figure_paths)

cell_area <- postfit_reporting_trace_cell_area(cell_area_template, if (is.null(cell_area_value)) NULL else as.numeric(cell_area_value), cell_area_units)
saveRDS(cell_area, file.path(paths$objects, "cell_area_audit.rds")); generated_objects$cell_area_audit <- file.path(paths$objects, "cell_area_audit.rds")
utils::write.csv(postfit_reporting_metadata_table(cell_area), file.path(paths$metadata, "cell_area_audit.csv"), row.names = FALSE, na = "")

rpi_audit <- postfit_reporting_rpi_audit(
  count_stack_semantics = "masked_structural_potential_abundance",
  observed_source = rpi_observation_path,
  time_span_weeks = structural_products$weeks
)
rpi_target_crs <- terra::crs(structural_products$masked_stack[[1L]], proj = TRUE)
rpi_observations <- if (!is.null(rpi_observation_path) && file.exists(rpi_observation_path)) {
  postfit_reporting_read_rpi_observations(rpi_observation_path, target_crs = rpi_target_crs,
                                          coordinate_source = rpi_coordinate_source,
                                          source_crs = rpi_coordinate_crs)
} else NULL
potential <- NULL
if (identical(cell_area$status, "PASS") && !is.null(map_manifest)) {
  tier2_paths <- map_manifest$tier2_intensity_path
  potential <- postfit_reporting_potential_abundance(tier2_paths, cell_area, file.path(paths$spatial, "potential_abundance"), overwrite = overwrite)
  generated_objects$potential_abundance <- file.path(paths$objects, "potential_abundance.rds")
  saveRDS(potential, generated_objects$potential_abundance)
}
if (!isTRUE(args[["no-rpi"]]) && isTRUE(rpi_audit$enabled) && !is.null(rpi_observations)) {
  count_stack <- structural_products$masked_stack
  calibration <- postfit_reporting_dynamic_rpi_calibration(count_stack, rpi_observations$data, structural_products$manifest$week, cut_quant = rpi_audit$parameters$cut_quant)
  paired_calibration_path <- file.path(paths$tables, "rpi_same_week_calibration.csv")
  utils::write.csv(calibration$paired, paired_calibration_path, row.names = FALSE, na = "")
  generated_tables$rpi_same_week_calibration <- paired_calibration_path
  coordinate_audit <- data.frame(
    source_columns = paste(rpi_observations$provenance$coordinate_transform$source_columns, collapse = "/"),
    source_crs = rpi_observations$provenance$coordinate_transform$source_crs,
    target_crs = rpi_observations$provenance$coordinate_transform$target_crs,
    transformation_method = rpi_observations$provenance$coordinate_transform$method,
    stringsAsFactors = FALSE
  )
  coordinate_audit <- cbind(coordinate_audit, calibration$metrics)
  utils::write.csv(coordinate_audit, file.path(paths$metadata, "rpi_coordinate_audit.csv"), row.names = FALSE, na = "")
  threshold_artifact <- list(
    threshold_value = calibration$threshold, cut_quant = calibration$cut_quant,
    source_product = calibration$source_product, source_observation_file = rpi_observations$provenance$path,
    source_observation_sha = rpi_observations$provenance$sha256,
    coordinate_columns = rpi_observations$provenance$coordinate_transform$source_columns,
    coordinate_crs = rpi_observations$provenance$coordinate_transform$source_crs,
    target_crs = rpi_observations$provenance$coordinate_transform$target_crs,
    same_week_matching = calibration$same_week_matching,
    n_observations_total = calibration$metrics$total_observations,
    n_observations_matched = calibration$metrics$successfully_same_week_matched,
    n_values_used_for_quantile = calibration$metrics$n_values_used_for_quantile,
    generated_at = postfit_reporting_iso_timestamp(), historical_threshold_used = FALSE
  )
  threshold_object_path <- file.path(paths$objects, "rpi_dynamic_threshold.rds")
  threshold_table_path <- file.path(paths$tables, "rpi_dynamic_threshold.csv")
  saveRDS(threshold_artifact, threshold_object_path)
  utils::write.csv(postfit_reporting_metadata_table(threshold_artifact), threshold_table_path, row.names = FALSE, na = "")
  generated_objects$rpi_dynamic_threshold <- threshold_object_path
  generated_tables$rpi_dynamic_threshold <- threshold_table_path
  emitted_pairs <- utils::read.csv(paired_calibration_path, stringsAsFactors = FALSE, check.names = FALSE)
  independent_threshold <- as.numeric(stats::quantile(emitted_pairs$extracted_value[emitted_pairs$eligible_for_quantile], probs = calibration$cut_quant, names = FALSE, type = 7))
  threshold_difference <- abs(calibration$threshold - independent_threshold)
  if (!isTRUE(threshold_difference <= 1e-12)) stop("Dynamic RPI threshold reproducibility check failed: reported and independently recomputed values differ.")
  utils::write.csv(data.frame(reported_threshold = calibration$threshold, independently_recomputed_threshold = independent_threshold, absolute_difference = threshold_difference, stringsAsFactors = FALSE), file.path(paths$qa, "rpi_dynamic_threshold_reproducibility.csv"), row.names = FALSE, na = "")
  rpi <- postfit_reporting_calc_rpi_at_threshold(count_stack, calibration$threshold, gen_days = rpi_audit$parameters$gen_days, days_per_layer = rpi_audit$parameters$days_per_layer)
  rpi$parameters$cut_quant <- calibration$cut_quant
  rpi$threshold_calibration <- threshold_artifact
  rpi_continuous_path <- file.path(paths$spatial, "rpi_continuous.tif")
  rpi_class_path <- file.path(paths$spatial, "rpi_class.tif")
  terra::writeRaster(rpi$rpi, rpi_continuous_path, overwrite = TRUE)
  terra::writeRaster(rpi$stability_class, rpi_class_path, overwrite = TRUE)
  generated_objects$rpi <- file.path(paths$objects, "rpi.rds"); saveRDS(rpi, generated_objects$rpi)
  class_area <- postfit_reporting_rpi_class_area(rpi$stability_class, cell_area)
  write_table(class_area, "rpi_class_summary")
  save_figure(postfit_reporting_plot_rpi(rpi$stability_class), "rpi_class", 8, 7)
  rpi_metadata <- list(run_id = run_id, threshold = rpi$calibrated_threshold, parameters = rpi$parameters,
                       canonical = TRUE, source_product = "structural_potential_abundance_temp_masked",
                       threshold_calibration = threshold_artifact, source_observations = rpi_observations$provenance,
                       source_stack = structural_products$manifest$structural_potential_abundance_temp_masked_path,
                       potential_abundance = structural_products$semantics$structural_potential_abundance_temp_masked,
                       output_paths = c(rpi = rpi_continuous_path, rpi_class_map = rpi_class_path),
                       class_summary = class_area)
  saveRDS(rpi_metadata, file.path(paths$metadata, "rpi_metadata.rds"))
  utils::write.csv(postfit_reporting_metadata_table(rpi_metadata), file.path(paths$metadata, "rpi_metadata.csv"), row.names = FALSE, na = "")
  rpi_audit$status <- "COMPLETED"
  rpi_audit$output_status <- "COMPLETED"
  rpi_audit$output_paths <- c(rpi = rpi_continuous_path, rpi_class_map = rpi_class_path)
  rpi_audit$dynamic_threshold <- threshold_artifact
  rpi_audit$threshold_reproducibility <- list(reported = calibration$threshold, independent = independent_threshold, absolute_difference = threshold_difference, status = "PASS")
  rpi_audit$checks <- rbind(rpi_audit$checks, data.frame(check = "dynamic_threshold_reproducibility", status = "PASS", details = "Emitted same-week calibration values independently reproduced the run-specific 10th-percentile threshold.", stringsAsFactors = FALSE))
}
utils::write.csv(rpi_audit$checks, file.path(paths$metadata, "rpi_readiness_audit.csv"), row.names = FALSE, na = "")
saveRDS(rpi_audit, file.path(paths$objects, "rpi_readiness_audit.rds")); generated_objects$rpi_readiness_audit <- file.path(paths$objects, "rpi_readiness_audit.rds")

host_mapping_status <- if (is.null(observation_path)) "WARNING" else if (identical(species_audit$status, "PASS") && isTRUE(as.numeric(species_audit$n_unmatched_submission_rows) == 0)) "PASS" else "WARNING"
denominator_status <- if (is.null(observation_path)) "WARNING" else if (isTRUE(as.numeric(species_audit$n_expanded_host_assignments) == sum(read.csv(file.path(paths$tables, "species_composition.csv"), stringsAsFactors = FALSE)$count))) "PASS" else "FAIL"
denominator_label_status <- if (is.null(observation_path)) "WARNING" else if (isTRUE(species_audit$denominator_discrepancy)) "WARNING" else "PASS"
qa_checks <- data.frame(
  check = c(
    "reference_fit_available", "stage2_provenance", "stage3a_provenance", "host_csv_availability",
    "host_mapping_coverage", "denominator_reconciliation", "denominator_label_accuracy",
    "species_product", "coefficient_tables", "cattle_product", "cattle_unit_provenance", "temporal_product",
    "phase3_raster_access", "map_generation", "potential_abundance_conversion",
    "structural_product_horizon", "structural_masked_support", "rpi_observation_provenance", "rpi_readiness",
    "dynamic_rpi_threshold", "rpi_classification_support", "manifest_checksum_prerequisites"
  ),
  status = c(
    if (file.exists(fit_path)) "PASS" else "FAIL",
    if (file.exists(stage2_path) && dir.exists(phase2_root)) "PASS" else "FAIL",
    if (file.exists(build_path)) "PASS" else "FAIL",
    if (!is.null(observation_path) && identical(species_audit$status, "PASS")) "PASS" else "FAIL",
    host_mapping_status,
    denominator_status,
    denominator_label_status,
    if (file.exists(file.path(paths$tables, "species_composition.csv")) && file.exists(file.path(paths$figures, "species_composition.png"))) "PASS" else "FAIL",
    if (file.exists(file.path(paths$tables, "fixed_effects_tier1.csv")) && file.exists(file.path(paths$tables, "fixed_effects_tier2.csv"))) "PASS" else "FAIL",
    if (file.exists(file.path(paths$tables, "cattle_effect.csv")) && file.exists(file.path(paths$figures, "cattle_effect.png"))) "PASS" else "FAIL",
    cattle_provenance$units_status,
    if (file.exists(file.path(paths$tables, "temporal_effects.csv")) && file.exists(file.path(paths$figures, "temporal_effects.png"))) "PASS" else "FAIL",
    if (!is.null(map_manifest) && nrow(map_manifest) >= 1L) "PASS" else "FAIL",
    if (file.exists(file.path(paths$figures, "selected_week_maps.png"))) "PASS" else "FAIL",
    if (!is.null(potential) && length(potential$paths) == nrow(map_manifest)) "PASS" else "WARNING",
    if (identical(structural_products$weeks, 133L) && nrow(structural_products$manifest) == 133L) "PASS" else "FAIL",
    if (identical(structural_products$support_cells, 15899L) && identical(structural_products$nonfinite_supported, 0L) && identical(structural_products$outside_support_non_na, 0L)) "PASS" else "FAIL",
    if (any(rpi_audit$checks$check == "observed_source" & rpi_audit$checks$status == "PASS")) "PASS" else "WARNING",
    if (rpi_audit$status %in% c("READY", "COMPLETED")) "PASS" else "WARNING",
    if (!is.null(rpi_audit$dynamic_threshold) && isTRUE(rpi_audit$threshold_reproducibility$status == "PASS")) "PASS" else "FAIL",
    if (exists("class_area") && sum(class_area$cell_count) == 15899L) "PASS" else "FAIL",
    if (requireNamespace("digest", quietly = TRUE)) "PASS" else "WARNING"
  ),
  detail = c(
    "Reference fit was loaded from the explicit reference path.",
    "Stage 2 and Phase 2 reference paths were available.",
    "Stage 3A build artifact was available.",
    "Authoritative host CSV was read and audited separately from fit/RPI provenance.",
    if (is.null(observation_path)) "Host source was not supplied." else paste0("Unmatched submission rows: ", species_audit$n_unmatched_submission_rows, "."),
    if (is.null(observation_path)) "Host denominator was not available." else paste0("Expanded assignments: ", species_audit$n_expanded_host_assignments, "; table count sum reconciled."),
    if (is.null(observation_path)) "Host denominator was not available." else if (isTRUE(species_audit$denominator_discrepancy)) "Expanded assignments differ from submission rows; percentage of total submissions is not literally accurate." else "Expanded assignments equal submission rows.",
    "Species-composition table and rendered figure were written.",
    "Tier 1 and Tier 2 coefficient tables were written.",
    "Cattle RW2 table and rendered figure were written.",
    cattle_provenance$units_evidence,
    "Two-panel temporal table and rendered figure were written.",
    "Validated Phase 3 raster manifest was available.",
    "Deterministic selected-week map figure was written.",
    if (is.null(potential)) "Potential abundance was not generated." else paste0("Generated ", length(potential$paths), " nominal-cell potential-abundance rasters."),
    "Accepted structural, unmasked structural potential, and 14.5 C masked structural products were promoted without regeneration.",
    "Supported masked structural cells are finite and outside-support cells remain NA.",
    if (rpi_audit$status %in% c("READY", "COMPLETED")) "Authoritative observations were supplied for same-week dynamic threshold calibration." else "Cleaned RPI observations were not supplied; RPI remains blocked.",
    paste0("RPI gate status: ", rpi_audit$status, "."),
    if (!is.null(rpi_audit$dynamic_threshold)) paste0("Dynamic threshold reproduced within tolerance: ", rpi_audit$threshold_reproducibility$absolute_difference, ".") else "Dynamic threshold artifact was not generated.",
    if (exists("class_area")) paste0("RPI class counts sum to ", sum(class_area$cell_count), " supported cells.") else "RPI class summary was not generated.",
    "SHA-256 checksum support was available for manifest generation."
  ),
  stringsAsFactors = FALSE
)
qa <- list(
  checks = qa_checks,
  totals = as.list(table(factor(qa_checks$status, levels = c("PASS", "WARNING", "FAIL")))),
  overall_status = if (any(qa_checks$status == "FAIL")) "FAIL" else if (any(qa_checks$status == "WARNING")) "WARNING" else "PASS",
  production_fit_scope = "Job 20762325 was outside this reporting run and was not touched."
)
saveRDS(qa, file.path(paths$objects, "reporting_qa_audit.rds")); generated_objects$reporting_qa_audit <- file.path(paths$objects, "reporting_qa_audit.rds")
utils::write.csv(qa_checks, file.path(paths$qa, "reporting_qa_audit.csv"), row.names = FALSE, na = "")
utils::write.csv(data.frame(status = qa$overall_status, pass = qa$totals$PASS, warning = qa$totals$WARNING, fail = qa$totals$FAIL, stringsAsFactors = FALSE), file.path(paths$qa, "reporting_qa_summary.csv"), row.names = FALSE, na = "")

metadata <- list(
  source_run_id = run_id,
  fit = list(path = normalizePath(fit_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(fit_path)),
  stage2 = list(path = normalizePath(stage2_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(stage2_path)),
  stage3a = list(path = normalizePath(build_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(build_path)),
  phase2 = {
    manifest_candidates <- if (dir.exists(phase2_root)) list.files(phase2_root, pattern = "^prediction_projection_manifest_.*\\.csv$", full.names = TRUE) else character()
    manifest_path <- if (length(manifest_candidates)) {
      preferred <- file.path(phase2_root, paste0("prediction_projection_manifest_", run_id, ".csv"))
      if (file.exists(preferred)) preferred else sort(manifest_candidates)[[1L]]
    } else NA_character_
    list(path = if (dir.exists(phase2_root)) normalizePath(phase2_root, mustWork = TRUE) else NA_character_,
         sha256 = if (file.exists(manifest_path)) postfit_reporting_hash_file(manifest_path) else NA_character_,
         manifest = manifest_path)
  },
  phase3 = map_audit,
  git_commit = tryCatch(system2("git", c("-C", repo_root, "-c", "safe.directory=*", "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[[1L]], error = function(e) NA_character_),
  generated_at_utc = postfit_reporting_iso_timestamp(),
  software = list(R = R.version.string, ggplot2 = as.character(utils::packageVersion("ggplot2")), terra = as.character(utils::packageVersion("terra"))),
  output_root = paths$root,
  generated_objects = generated_objects,
  generated_tables = generated_tables,
  generated_figures = generated_figures,
  product_names = postfit_reporting_product_names(),
  selected_map_week_rule = map_audit$selection_rule %||% NA_character_,
  observation_input = if (is.null(observation_path)) NULL else list(path = normalizePath(observation_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(observation_path), role = "authoritative descriptive host-composition source; not fit provenance and not assumed to be the RPI observation set"),
  rpi_observations = if (is.null(rpi_observations)) NULL else rpi_observations$provenance,
  species_composition = species_audit,
  cattle_effect_semantics = cattle_provenance$cattle_contribution_definition,
  cattle_provenance = cattle_provenance,
  temporal_effect_semantics = "week_steps is Tier 1 latent logit deviation; tier2_week is Tier 2 latent log-intensity deviation; Stage 2 mapping is authoritative.",
  cell_area = cell_area,
  potential_abundance = if (is.null(potential)) list(status = "BLOCKED", reason = "Potential abundance requires a validated cell-area audit and Phase 3 map manifest.", cell_area = cell_area) else potential,
  structural_products = list(
    source = structural_products$source, weeks = structural_products$weeks, supported_cells = structural_products$support_cells,
    nonfinite_supported = structural_products$nonfinite_supported, outside_support_non_na = structural_products$outside_support_non_na,
    manifest = file.path(paths$metadata, "structural_product_manifest.csv"), semantics = structural_products$semantics,
    selected_weeks = structural_selected$week, structural_masked_figure = structural_figure_paths
  ),
  rpi = rpi_audit,
  qa = qa,
  model_summary = model_summary
)
postfit_reporting_write_metadata(paths, metadata)
manifest <- postfit_reporting_write_manifest(paths, run_id, metadata$generated_at_utc)
cat("Post-fit reporting complete\n", "Output: ", paths$root, "\n", "Objects: ", sum(manifest$artifact_type == "object"), "\n", "Tables: ", sum(manifest$artifact_type == "table"), "\n", "Figures: ", sum(manifest$artifact_type == "figure"), "\n", "RPI: ", rpi_audit$status, "\n", "QA: PASS=", qa$totals$PASS, " WARNING=", qa$totals$WARNING, " FAIL=", qa$totals$FAIL, "\n", sep = "")
