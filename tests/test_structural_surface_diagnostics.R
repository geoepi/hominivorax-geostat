repo_root <- normalizePath(".", mustWork = TRUE)
if (!file.exists(file.path(repo_root, "R", "structural_surface_diagnostics.R"))) repo_root <- normalizePath("..", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_project.R"))
source(file.path(repo_root, "R", "preprocessing_temporal.R"))
source(file.path(repo_root, "R", "structural_surface_diagnostics.R"))
testthat::local_edition(3)

testthat::test_that("structural coordinate audit records explicit lon/lat projection provenance", {
  testthat::skip_if_not_installed("sf")
  root <- file.path(tempdir(), paste0("structural-coordinates-", Sys.getpid()))
  dir.create(root, recursive = TRUE)
  path <- file.path(root, "observations.csv")
  utils::write.csv(data.frame(date = "2026-07-25", host = "CANINO", lon = -75, lat = 20), path, row.names = FALSE)
  target <- "+proj=aea +lat_0=20 +lon_0=-75 +lat_1=10 +lat_2=30 +x_0=0 +y_0=0 +datum=WGS84 +units=km +no_defs"
  object <- structural_read_authoritative_observations(path, target, "lonlat", "EPSG:4326")
  audit <- structural_coordinate_audit(object$data, object$provenance)
  testthat::expect_equal(audit$coordinate_source, "lonlat")
  testthat::expect_equal(audit$source_crs, "EPSG:4326")
  testthat::expect_equal(audit$target_crs, target)
  testthat::expect_equal(audit$coordinate_columns_present, c("lon", "lat", "x", "y"))
  testthat::expect_equal(as.numeric(object$data[c("x", "y")][1, ]), c(0, 0), tolerance = 1e-8)
})

testthat::test_that("coordinate source selection fails closed when ambiguous", {
  testthat::skip_if_not_installed("sf")
  root <- file.path(tempdir(), paste0("structural-coordinate-selection-", Sys.getpid()))
  dir.create(root, recursive = TRUE)
  path <- file.path(root, "observations.csv")
  utils::write.csv(data.frame(lon = -75, lat = 20, x = 1, y = 2), path, row.names = FALSE)
  testthat::expect_error(structural_read_authoritative_observations(path, "EPSG:4326", NULL, "EPSG:4326"), "coordinate_source")
  testthat::expect_error(structural_read_authoritative_observations(path, "EPSG:4326", "xy", NULL), "source_crs")
})

testthat::test_that("SPDE-excluded reconstruction is exact and reports nonfinite failures", {
  metrics <- structural_reconstruction_metrics(
    full_eta = c(5, 6, 7), structural_eta = c(1, 2, 3),
    tier2_field = c(2, 2, 2), tier2_copy_field = c(2, 2, 2)
  )
  testthat::expect_true(metrics$pass)
  testthat::expect_equal(metrics$rmse, 0)
  testthat::expect_match(metrics$only_removed, "tier2_field")
  testthat::expect_false(structural_reconstruction_metrics(c(5, NA), c(1, 2), c(2, 2), c(2, 2))$pass)
})

testthat::test_that("temperature mask retains threshold and preserves outside-support NA", {
  result <- structural_apply_temperature_mask(c(1, 2, NA, 4), c(10, 12, 12, NA), 12)
  testthat::expect_equal(result, c(0, 2, NA, NA))
  testthat::expect_error(structural_apply_temperature_mask(1, 1, NULL), "finite temperature threshold")
})

testthat::test_that("same-week extraction pairs observations to their modeled week", {
  testthat::skip_if_not_installed("terra")
  testthat::skip_if_not_installed("lubridate")
  root <- file.path(tempdir(), paste0("structural-same-week-", Sys.getpid()))
  dir.create(root, recursive = TRUE)
  template <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2, crs = "EPSG:4326")
  terra::values(template) <- 1:4
  stack <- c(template, template + 10)
  observations <- data.frame(date = c("2024-01-03", "2024-03-01"), x = c(.5, .5), y = c(1.5, 1.5))
  result <- structural_same_week_extract(observations, stack, c("2024-W01", "2024-W02"))
  testthat::expect_true(result$matched[[1L]])
  testthat::expect_false(result$matched[[2L]])
  testthat::expect_equal(result$extracted_value[[1L]], 1)
})

testthat::test_that("temperature alignment accepts both historical and full-horizon week-group sizes", {
  make_grid <- function(n_groups) data.frame(
    epiyear = rep(2024L, n_groups), epiweek = seq_len(n_groups),
    cell_id = seq_len(n_groups), mintemp = rep(10, n_groups)
  )
  testthat::expect_true(structural_validate_temperature_alignment(make_grid(8), 8, 1)$pass)
  testthat::expect_true(structural_validate_temperature_alignment(make_grid(11), 11, 1)$pass)
  bad <- make_grid(11); bad$mintemp[[3L]] <- NA_real_
  testthat::expect_false(structural_validate_temperature_alignment(bad, 11, 1)$pass)
})
