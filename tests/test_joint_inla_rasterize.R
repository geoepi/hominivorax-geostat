repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_rasterize.R"))

expect_error <- function(expr, pattern = NULL) {
  error <- tryCatch({ force(expr); NULL }, error = function(e) e)
  stopifnot(inherits(error, "error"))
  if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(error), fixed = TRUE))
  invisible(error)
}

template <- terra::rast(nrows = 3, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 3, crs = "EPSG:4326")
terra::values(template) <- c(NA, 1, 1, NA, 1, 1, NA, 1, 1, NA, 1, 1)
cell_id <- c(2L, 3L, 5L, 6L, 8L, 9L, 11L, 12L)
source_values <- c(0.125, 1.25, -4.5, 9.75, 10.125, 100.5, -0.25, 3.141592653589793)

output <- joint_inla_rasterize_assign_values(template, cell_id, source_values)
output_values <- terra::values(output, mat = FALSE)
stopifnot(all(is.na(output_values[c(1L, 4L, 7L, 10L)])),
          isTRUE(all.equal(output_values[cell_id], source_values)),
          sum(!is.na(output_values)) == length(cell_id))

shuffled <- sample(seq_along(cell_id), length(cell_id))
shuffled_output <- joint_inla_rasterize_assign_values(template, cell_id[shuffled], source_values[shuffled])
stopifnot(isTRUE(all.equal(terra::values(output, mat = FALSE), terra::values(shuffled_output, mat = FALSE))))

roundtrip <- joint_inla_rasterize_roundtrip_metrics(source_values, terra::values(output, mat = FALSE)[cell_id])
stopifnot(isTRUE(roundtrip$pass[[1L]]), roundtrip$maximum_absolute_error[[1L]] == 0)
expect_error(joint_inla_rasterize_assign_values(template, c(cell_id, cell_id[[1L]]), c(source_values, 1)), "duplicate")
expect_error(joint_inla_rasterize_assign_values(template, c(cell_id, 13L), c(source_values, 1)), "outside")
expect_error(joint_inla_rasterize_validate_cell_ids(cell_id[[1L]], template, require_complete = TRUE, expected_cell_ids = cell_id), "cell_id set")

same_geometry <- template[[1L]]
stopifnot(isTRUE(joint_inla_rasterize_geometry_equal(same_geometry, template)))
modified_resolution <- terra::rast(template); terra::res(modified_resolution) <- c(2, 1)
modified_extent <- terra::rast(template); terra::ext(modified_extent) <- terra::ext(0, 4.1, 0, 3)
modified_crs <- terra::rast(template); terra::crs(modified_crs) <- "EPSG:3857"
stopifnot(!isTRUE(joint_inla_rasterize_geometry_equal(modified_resolution, template)),
          !isTRUE(joint_inla_rasterize_geometry_equal(modified_extent, template)),
          !isTRUE(joint_inla_rasterize_geometry_equal(modified_crs, template)))

weekly <- data.frame(
  space_time_id = paste0("cell_", cell_id, "_time_1"), cell_id = cell_id, x = terra::xyFromCell(template, cell_id)[, 1L],
  y = terra::xyFromCell(template, cell_id)[, 2L], epiyear = 2024L, epiweek = 1L,
  eta1_mean = source_values, tier1_probability_plugin = stats::plogis(source_values),
  eta2_mean = source_values / 10, tier2_intensity_plugin = exp(source_values / 10),
  admin_f = 1L, admin_u = "admin_a", admin_effect_source = "fitted_summary_random",
  stringsAsFactors = FALSE
)
stopifnot(isTRUE(joint_inla_rasterize_validate_week(weekly, 2024L, 1L, cell_id, length(cell_id))))
expect_error(joint_inla_rasterize_validate_week(weekly, 2024L, 2L, cell_id, length(cell_id)), "contents")
mixed <- weekly; mixed$epiweek[[1L]] <- 2L
expect_error(joint_inla_rasterize_validate_week(mixed, 2024L, 1L, cell_id, length(cell_id)), "contents")
duplicate_id <- weekly; duplicate_id$space_time_id[[2L]] <- duplicate_id$space_time_id[[1L]]
expect_error(joint_inla_rasterize_validate_week(duplicate_id, 2024L, 1L, cell_id, length(cell_id)), "unique")
missing_field <- weekly; missing_field$eta2_mean <- NULL
expect_error(joint_inla_rasterize_validate_week(missing_field, 2024L, 1L, cell_id, length(cell_id)), "missing")
nonfinite <- weekly; nonfinite$eta1_mean[[1L]] <- Inf
expect_error(joint_inla_rasterize_validate_week(nonfinite, 2024L, 1L, cell_id, length(cell_id)), "non-finite")
expect_error(joint_inla_rasterize_validate_week(weekly, 2024L, 1L, cell_id[-1L], NULL), "cell_id set")

target_crs <- "EPSG:4326"
coordinate <- joint_inla_rasterize_coordinate_crosscheck(template, weekly[c("cell_id", "x", "y")], target_crs, tolerance = 1e-10)
stopifnot(isTRUE(coordinate$summary$pass[[1L]]), coordinate$summary$maximum_absolute_x_difference[[1L]] <= 1e-10)
bad_coordinates <- weekly[c("cell_id", "x", "y")]; bad_coordinates$x[[1L]] <- bad_coordinates$x[[1L]] + 1
bad_coordinate_result <- joint_inla_rasterize_coordinate_crosscheck(template, bad_coordinates, target_crs, tolerance = 1e-10)
stopifnot(!isTRUE(bad_coordinate_result$summary$pass[[1L]]))

temp_path <- tempfile(fileext = ".tif")
invisible(joint_inla_rasterize_write(output, temp_path, overwrite = TRUE))
written <- terra::values(terra::rast(temp_path), mat = FALSE)[cell_id]
precision <- joint_inla_rasterize_roundtrip_metrics(source_values, written)
stopifnot(isTRUE(precision$pass[[1L]]), precision$maximum_absolute_error[[1L]] <= 1e-10)
unlink(temp_path)

# Small production-shaped run: provenance recovery, manifest validation,
# four raster families, masks, temporal support, and metadata.
fixture_root <- file.path(tempdir(), "joint-inla-rasterize-fixture")
phase2_root <- file.path(fixture_root, "prediction_projection_20725437")
dir.create(file.path(phase2_root, "weekly"), recursive = TRUE, showWarnings = FALSE)
template_path <- file.path(fixture_root, "template.tif")
terra::writeRaster(template, template_path, overwrite = TRUE)
stage1_path <- file.path(fixture_root, "model_inputs.rds")
saveRDS(list(configuration = list(inputs = list(template_raster = template_path), study = list(projected_crs = "EPSG:4326"))), stage1_path)
stage2_grid <- do.call(rbind, lapply(1:2, function(time_index) {
  data.frame(cell_id = cell_id, x = weekly$x, y = weekly$y, epiyear = 2024L, epiweek = time_index,
             time_index = time_index, space_time_id = paste0("cell_", cell_id, "_time_", time_index), stringsAsFactors = FALSE)
}))
stage2_path <- file.path(fixture_root, "joint_model_inputs.rds")
saveRDS(list(prediction_grid = stage2_grid,
             temporal_mapping = data.frame(epiyear = 2024L, epiweek = 1:2, time_index = 1:2),
             provenance = list(source_model_inputs = stage1_path)), stage2_path)
manifest_fixture <- do.call(rbind, lapply(1:2, function(time_index) {
  data <- weekly
  data$epiweek <- time_index
  data$space_time_id <- paste0("cell_", data$cell_id, "_time_", time_index)
  target <- file.path(phase2_root, "weekly", sprintf("prediction_y2024_w%02d.rds", time_index))
  saveRDS(data, target)
  data.frame(epiyear = 2024L, epiweek = time_index, rows = nrow(data), path = normalizePath(target, mustWork = TRUE),
             sha256 = joint_inla_rasterize_hash_file(target), stringsAsFactors = FALSE)
}))
manifest_path <- file.path(phase2_root, "prediction_projection_manifest_20725437.csv")
utils::write.csv(manifest_fixture, manifest_path, row.names = FALSE)
fixture_run <- joint_inla_rasterize_run(phase2_root, stage2_artifact = stage2_path,
                                        output_dir = file.path(fixture_root, "raster_surfaces_20725437"),
                                        expected_weeks = 2L, expected_rows = 16L, diagnostic = FALSE)
stopifnot(sum(fixture_run$manifest$raster_family %in% c("tier1_eta", "tier1_probability", "tier2_eta", "tier2_intensity")) == 8L,
          sum(fixture_run$manifest$raster_family == "prediction_cell_mask") == 1L,
          sum(fixture_run$manifest$raster_family == "unseen_admin_cells") == 1L,
          all(fixture_run$roundtrip$pass), all(fixture_run$distribution$pass),
          all(fixture_run$audit$status %in% c("PASS", "WARNING")))

cat("Joint-INLA Phase 3 rasterization helper tests passed\n")
