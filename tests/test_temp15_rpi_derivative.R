#!/usr/bin/env Rscript

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "structural_surface_diagnostics.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)
script_path <- file.path(repo_root, "scripts", "run_temp15_rpi_derivative.R")
script_text <- paste(readLines(script_path, warn = FALSE), collapse = "\n")
stopifnot(grepl('temperature-threshold", "15.0', script_text, fixed = TRUE))
stopifnot(grepl('source-threshold", "14.5', script_text, fixed = TRUE))
stopifnot(grepl('structural_apply_temperature_mask', script_text, fixed = TRUE))
stopifnot(grepl('rpi_class_temp15.pdf', script_text, fixed = TRUE), grepl('rpi_class_temp15.png', script_text, fixed = TRUE))
stopifnot(grepl('postfit_reporting_plot_rpi', script_text, fixed = TRUE), grepl('postfit_reporting_rpi_class_palette', script_text, fixed = TRUE), grepl('boundary-path', script_text, fixed = TRUE))

values <- c(1, 2, 3, NA_real_)
temperature <- c(14.5, 15.0, 15.1, 15.1)
masked <- structural_apply_temperature_mask(values, temperature, 15.0)
stopifnot(identical(masked[[1L]], 0), identical(masked[[2L]], 2), identical(masked[[3L]], 3), is.na(masked[[4L]]))
baseline_masked <- structural_apply_temperature_mask(values, temperature, 14.5)
baseline_support <- is.finite(baseline_masked) & baseline_masked > 0
derivative_support <- is.finite(masked) & masked > 0
stopifnot(all(!derivative_support | baseline_support))

tmp <- tempfile(fileext = ".tif")
terra::writeRaster(terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2, crs = "EPSG:3857", vals = 1:4), tmp, overwrite = TRUE)
audit <- postfit_reporting_trace_cell_area(tmp, NULL, NULL)
stopifnot(identical(audit$status, "PASS"), isTRUE(audit$nominal_average_raster_cell_area > 0))
unlink(tmp)
cat("TEMP15_DERIVATIVE_TEST_PASS\n")
