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
output_root <- arg(args, "output-root", "/project/disease_ecology/nws-geostat-output/postfit_reporting")
fit_path <- arg(args, "fit", "/project/disease_ecology/nws-geostat-output/joint_inla_fit/joint_model_fit.rds")
build_path <- arg(args, "build", "/project/disease_ecology/nws-geostat-output/joint_inla/joint_inla_build.rds")
stage2_path <- arg(args, "stage2")
phase3_root <- arg(args, "phase3-root", file.path(dirname(fit_path), paste0("raster_surfaces_", run_id)))
phase2_root <- arg(args, "phase2", file.path(dirname(fit_path), paste0("prediction_projection_", run_id)))
boundary_path <- arg(args, "boundary")
species_path <- arg(args, "species-data")
species_column <- arg(args, "species-column", "host_standardized")
species_category_column <- arg(args, "species-category-column")
species_cohort <- arg(args, "species-cohort")
cell_area_template <- arg(args, "cell-area-template")
cell_area_value <- arg(args, "cell-area")
cell_area_units <- arg(args, "cell-area-units")
observations_path <- arg(args, "observations")
cattle_units <- arg(args, "cattle-units")
overwrite <- isTRUE(args[["overwrite"]])

if (is.null(stage2_path)) {
  stage2_path <- "/project/disease_ecology/nws-geostat-output/joint_model/joint_model_inputs.rds"
}

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

build <- readRDS(build_path)
fit_artifact <- readRDS(fit_path)
stage2 <- readRDS(stage2_path)

fixed <- postfit_reporting_fixed_effects(fit_artifact)
cattle <- postfit_reporting_cattle_effect(fit_artifact, stage2)
temporal <- postfit_reporting_temporal_effects(build, fit_artifact, stage2)
model_summary <- postfit_reporting_model_summary(build, fit_artifact, stage2)

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
saveRDS(model_summary, file.path(paths$objects, "model_summary.rds")); generated_objects$model_summary <- file.path(paths$objects, "model_summary.rds")

generated_figures <- list()
save_figure <- function(plot, name, width, height) {
  result <- postfit_reporting_save_plot(plot, name, paths, width = width, height = height)
  generated_figures[[name]] <<- result
  generated_objects[[paste0("plot_", name)]] <<- result$rds
}
save_figure(postfit_reporting_plot_cattle(cattle, cattle_units = cattle_units), "cattle_effect", 8, 5)
save_figure(postfit_reporting_plot_temporal(temporal), "temporal_effects", 10, 8)

species_audit <- list(status = "UNRESOLVED", reason = "No explicit species source cohort was supplied; denominator was not guessed.")
if (!is.null(species_path)) {
  if (is.null(species_cohort)) stop("--species-data requires --species-cohort so the denominator is explicit.")
  species_data <- utils::read.csv(species_path, stringsAsFactors = FALSE, check.names = FALSE)
  species <- postfit_reporting_species_composition(species_data, species_column, species_cohort, species_category_column)
  write_table(species, "species_composition")
  save_figure(postfit_reporting_plot_species(species), "species_composition", 9, 8)
  species_audit <- species$audit
}
utils::write.csv(data.frame(status = species_audit$status, reason = species_audit$reason %||% NA_character_, cohort_definition = species_audit$cohort_definition %||% NA_character_, denominator_n = species_audit$denominator_n %||% NA_integer_, stringsAsFactors = FALSE), file.path(paths$metadata, "species_composition_audit.csv"), row.names = FALSE, na = "")

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
  map_object <- postfit_reporting_selected_map_values(selected, raster_root = phase3_root, boundary = boundary)
  saveRDS(map_object, file.path(paths$objects, "selected_map_values.rds")); generated_objects$selected_map_values <- file.path(paths$objects, "selected_map_values.rds")
  selected_map_plot <- postfit_reporting_plot_selected_maps(map_object)
  save_figure(selected_map_plot, "selected_week_maps", 12, 10)
  map_audit <- list(status = "PASS", selection_rule = selected$selection_rule[[1L]], selected_weeks = selected$week, source_phase3_root = normalizePath(phase3_root, mustWork = TRUE), boundary_path = boundary_path %||% NA_character_, values_unchanged = TRUE)
  utils::write.csv(selected, file.path(paths$metadata, "selected_map_weeks.csv"), row.names = FALSE, na = "")
}

cell_area <- postfit_reporting_trace_cell_area(cell_area_template, if (is.null(cell_area_value)) NULL else as.numeric(cell_area_value), cell_area_units)
saveRDS(cell_area, file.path(paths$objects, "cell_area_audit.rds")); generated_objects$cell_area_audit <- file.path(paths$objects, "cell_area_audit.rds")
utils::write.csv(postfit_reporting_metadata_table(cell_area), file.path(paths$metadata, "cell_area_audit.csv"), row.names = FALSE, na = "")

rpi_audit <- postfit_reporting_rpi_audit(
  count_stack_semantics = if (identical(cell_area$status, "PASS") && !is.null(map_manifest)) "standardized_potential_abundance" else "tier2_intensity",
  observed_source = observations_path,
  time_span_weeks = if (is.null(map_manifest)) NULL else nrow(map_manifest)
)
if (!isTRUE(args[["no-rpi"]]) && isTRUE(rpi_audit$enabled) && !is.null(map_manifest)) {
  tier2_paths <- map_manifest$tier2_intensity_path
  potential <- postfit_reporting_potential_abundance(tier2_paths, cell_area, file.path(paths$spatial, "potential_abundance"), overwrite = overwrite)
  generated_objects$potential_abundance <- file.path(paths$objects, "potential_abundance.rds")
  saveRDS(potential, generated_objects$potential_abundance)
  count_stack <- terra::rast(potential$paths)
  observations <- utils::read.csv(observations_path, stringsAsFactors = FALSE, check.names = FALSE)
  rpi <- postfit_reporting_calc_rpi(count_stack, observations, gen_days = rpi_audit$parameters$gen_days, days_per_layer = rpi_audit$parameters$days_per_layer, cut_quant = rpi_audit$parameters$cut_quant)
  terra::writeRaster(rpi$rpi, file.path(paths$spatial, "rpi.tif"), overwrite = TRUE)
  terra::writeRaster(rpi$stability_class, file.path(paths$spatial, "rpi_classes.tif"), overwrite = TRUE)
  class_area <- postfit_reporting_rpi_class_area(rpi$stability_class, cell_area)
  write_table(class_area, "rpi_class_area")
  save_figure(postfit_reporting_plot_rpi(rpi$stability_class), "rpi_classes", 8, 7)
  rpi_audit$output_status <- "GENERATED"
  rpi_audit$output_paths <- c(rpi = file.path(paths$spatial, "rpi.tif"), classes = file.path(paths$spatial, "rpi_classes.tif"))
} else {
  utils::write.csv(rpi_audit$checks, file.path(paths$metadata, "rpi_readiness_audit.csv"), row.names = FALSE, na = "")
}
saveRDS(rpi_audit, file.path(paths$objects, "rpi_readiness_audit.rds")); generated_objects$rpi_readiness_audit <- file.path(paths$objects, "rpi_readiness_audit.rds")

metadata <- list(
  source_run_id = run_id,
  fit = list(path = normalizePath(fit_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(fit_path)),
  stage2 = list(path = normalizePath(stage2_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(stage2_path)),
  stage3a = list(path = normalizePath(build_path, mustWork = TRUE), sha256 = postfit_reporting_hash_file(build_path)),
  phase2 = list(path = if (dir.exists(phase2_root)) normalizePath(phase2_root, mustWork = TRUE) else NA_character_, sha256 = if (dir.exists(phase2_root)) postfit_reporting_hash_file(file.path(phase2_root, paste0("prediction_projection_manifest_", run_id, ".csv"))) else NA_character_, manifest = if (dir.exists(phase2_root)) file.path(phase2_root, paste0("prediction_projection_manifest_", run_id, ".csv")) else NA_character_),
  phase3 = map_audit,
  git_commit = tryCatch(system2("git", c("-C", repo_root, "-c", "safe.directory=*", "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[[1L]], error = function(e) NA_character_),
  generated_at_utc = postfit_reporting_iso_timestamp(),
  software = list(R = R.version.string, ggplot2 = as.character(utils::packageVersion("ggplot2")), terra = as.character(utils::packageVersion("terra"))),
  output_root = paths$root,
  generated_objects = generated_objects,
  generated_tables = generated_tables,
  generated_figures = generated_figures,
  selected_map_week_rule = map_audit$selection_rule %||% NA_character_,
  species_composition = species_audit,
  cattle_effect_semantics = "Weighted cattle_q RW2 posterior summary: latent RW2 summary × cattle_mid_log1p.",
  temporal_effect_semantics = "week_steps is Tier 1 latent logit deviation; tier2_week is Tier 2 latent log-intensity deviation; Stage 2 mapping is authoritative.",
  potential_abundance = cell_area,
  rpi = rpi_audit,
  model_summary = model_summary
)
postfit_reporting_write_metadata(paths, metadata)
manifest <- postfit_reporting_write_manifest(paths, run_id, metadata$generated_at_utc)
cat("Post-fit reporting complete\n", "Output: ", paths$root, "\n", "Objects: ", sum(manifest$artifact_type == "object"), "\n", "Tables: ", sum(manifest$artifact_type == "table"), "\n", "Figures: ", sum(manifest$artifact_type == "figure"), "\n", "RPI: ", rpi_audit$status, "\n", sep = "")
