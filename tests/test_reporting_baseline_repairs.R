repo_root <- normalizePath(".", mustWork = TRUE)
if (!file.exists(file.path(repo_root, "R", "postfit_reporting.R"))) repo_root <- normalizePath("..", mustWork = TRUE)
source(file.path(repo_root, "R", "postfit_reporting.R"))
testthat::local_edition(3)

testthat::test_that("random-effect summaries retain canonical hyperparameter semantics", {
  hyper_names <- c(
    "Range for tier1_field", "Stdev for tier1_field", "Precision for week_steps",
    "Precision for admin_f", "Range for tier2_field", "Stdev for tier2_field",
    "Beta for tier2_copy_field", "Precision for tier2_week", "Precision for cattle_q",
    "Size for the nbinomial observations"
  )
  hyper <- data.frame(mean = seq_along(hyper_names), sd = rep(.1, 10),
                      `0.025quant` = seq_along(hyper_names) - .2,
                      `0.5quant` = seq_along(hyper_names),
                      `0.975quant` = seq_along(hyper_names) + .2,
                      check.names = FALSE, row.names = hyper_names)
  fit <- list(summary.hyperpar = hyper)
  build <- list(spde_metadata = list(
    tier1 = list(coordinate_unit_to_m = 1000, prior_range_km = 100),
    tier2 = list(coordinate_unit_to_m = 1000, prior_range_km = 50)
  ))
  object <- postfit_reporting_random_effect_summaries(fit, build)
  testthat::expect_equal(nrow(object), 10L)
  testthat::expect_equal(object$units[object$parameter == "range"], c("km", "km"))
  testthat::expect_true(all(c("Tier 1 weekly RW1", "Tier 1 administrative IID", "Tier 2 copy/shared field", "Negative-binomial likelihood") %in% object$component))
  testthat::expect_true(all(is.na(object$mode)))
  testthat::expect_equal(attr(object, "spde_unit_audit")$status, "PASS")
})

testthat::test_that("random-effect comparison has accepted run-specific schema", {
  reference <- data.frame(component = c("Tier 1 SPDE", "Tier 2 copy/shared field"), parameter = c("range", "copy coefficient"), mean = c(10, .1))
  production <- data.frame(component = reference$component, parameter = reference$parameter, mean = c(12, .2))
  comparison <- postfit_reporting_random_effect_comparison(reference, production, reference_run = "20725437", production_run = "20742007")
  testthat::expect_equal(names(comparison), c("component", "parameter", "reference_20725437", "production_20742007", "absolute_difference", "ratio_or_fold_change"))
  testthat::expect_equal(comparison$ratio_or_fold_change, c(1.2, 2))
})

testthat::test_that("Water Buffalo spellings map once to Livestock", {
  x <- data.frame(host = c("bufal", "buffal", "bufalino", "buffalino", "Buffalino"), stringsAsFactors = FALSE)
  object <- postfit_reporting_host_composition(x)
  buffalo <- object$assignment_table[object$assignment_table$common_name == "Water Buffalo", , drop = FALSE]
  testthat::expect_equal(nrow(buffalo), nrow(x))
  testthat::expect_true(all(buffalo$broad_group == "Livestock"))
  testthat::expect_equal(object$audit$n_unmatched_submission_rows, 0L)
  testthat::expect_equal(anyDuplicated(buffalo$submission_row), 0L)
})

testthat::test_that("RPI run lengths, conversion, and class boundaries are explicit", {
  testthat::expect_equal(postfit_reporting_max_consecutive_suitable(rep(2, 9), 1), 9)
  testthat::expect_equal(postfit_reporting_max_consecutive_suitable(rep(2, 24), 1) * 7 / 21, 8)
  testthat::expect_equal(postfit_reporting_max_consecutive_suitable(rep(2, 45), 1) * 7 / 21, 15)
  testthat::skip_if_not_installed("terra")
  raster <- terra::rast(nrows = 1, ncols = 6)
  terra::values(raster) <- c(2.999, 3, 7.999, 8, 14.999, 15)
  testthat::expect_equal(as.integer(terra::values(postfit_reporting_rpi_classify(raster))), c(0, 1, 1, 2, 2, 3))
})
