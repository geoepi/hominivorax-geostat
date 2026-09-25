repo_root <- normalizePath(".", mustWork = TRUE)
if (!file.exists(file.path(repo_root, "R", "joint_inla_extract.R"))) repo_root <- normalizePath("..", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"))
source(file.path(repo_root, "R", "postfit_reporting.R"))
testthat::local_edition(3)

summary_columns <- function(ids, means) {
  data.frame(ID = ids, mean = means, sd = rep(0.2, length(ids)),
             `0.025quant` = means - 0.4, `0.5quant` = means,
             `0.975quant` = means + 0.4, check.names = FALSE)
}

make_reporting_fixture <- function() {
  terms <- c("intercept1", "north", "road_dens", "night_illum",
             "intercept2", "mintemp", "soilmoist", "leafarea", "rhum",
             "cattle", "horses", "pigs", "goats", "sheep",
             "mintemp:soilmoist", "mintemp:leafarea")
  fixed <- data.frame(mean = seq_along(terms) / 10, sd = rep(.2, length(terms)),
                      `0.025quant` = seq_along(terms) / 10 - .4,
                      `0.5quant` = seq_along(terms) / 10,
                      `0.975quant` = seq_along(terms) / 10 + .4,
                      row.names = terms, check.names = FALSE)
  tier1 <- data.frame(
    admin_f = c(1L, 1L, 2L, 2L), timestep = c(1L, 2L, 3L, 1L),
    response_training = c(1, 0, 1, 0), response_observed = c(1, 0, 1, 0)
  )
  tier2 <- data.frame(
    cattle_q = c(1L, 1L, 2L, 2L, 3L, 3L),
    cattle_mid_log1p = c(.1, .1, .5, .5, 1, 1),
    cattle_mid = c(.1, .1, .5, .5, 2, 2),
    response_training = c(1, 2, NA, NA, 3, 4),
    response_observed = c(1, 2, 0, 0, 3, 4),
    timestep = c(1L, 2L, 3L, 1L, 2L, 3L),
    admin_f = c(1L, 1L, 2L, 2L, 1L, 2L)
  )
  stage2 <- list(
    tier1 = tier1, tier2 = tier2,
    temporal_mapping = data.frame(timestep = 1:3, epiyear = 2024L,
                                  epiweek = 1:3,
                                  week_start = as.Date("2024-01-01") + 7 * 0:2),
    admin_mapping = data.frame(admin_u = c("A", "B"), admin_f = 1:2),
    prediction_grid = data.frame(.row_id = 1:2)
  )
  fit <- list(
    summary.fixed = fixed,
    summary.random = list(
      week_steps = summary_columns(1:3, c(.1, .2, .3)),
      tier2_week = summary_columns(1:3, c(.4, .5, .6)),
      cattle_q = summary_columns(1:3, c(1, 2, 3))
    ),
    summary.hyperpar = data.frame(mean = 1, row.names = "theta"),
    dic = list(dic = 10), waic = list(waic = 12),
    mlik = matrix(-4, nrow = 1, dimnames = list("log marginal-likelihood (integration)", NULL))
  )
  build <- list(
    family = c("binomial", "nbinomial"),
    spde = list(tier1 = list(n.spde = 5L), tier2 = list(n.spde = 6L)),
    fields = list(
      tier1 = list(tier1_field.group = c(1L, 2L)),
      tier2 = list(tier2_field.group = c(1L, 2L))
    )
  )
  list(build = build, fit = fit, stage2 = stage2)
}

testthat::test_that("fixed effects are assigned to tiers and preserve summaries", {
  fixture <- make_reporting_fixture()
  fixed <- postfit_reporting_fixed_effects(fixture$fit)
  testthat::expect_equal(nrow(fixed$tier1), 4L)
  testthat::expect_equal(nrow(fixed$tier2), 12L)
  testthat::expect_equal(fixed$tier1$term, c("intercept1", "north", "road_dens", "night_illum"))
  testthat::expect_equal(fixed$tier2$term[1], "intercept2")
  testthat::expect_equal(fixed$tier2$posterior_mean[3], .7)
  testthat::expect_equal(anyDuplicated(fixed$tier1$term), 0L)
  testthat::expect_equal(anyDuplicated(fixed$tier2$term), 0L)
})

testthat::test_that("cattle contribution is weighted and inactive bins remain", {
  fixture <- make_reporting_fixture()
  cattle <- postfit_reporting_cattle_effect(fixture$fit, fixture$stage2)
  testthat::expect_equal(cattle$cattle_mid, c(.1, .5, 2))
  testthat::expect_equal(cattle$active_count, c(2L, 0L, 2L))
  testthat::expect_equal(cattle$posterior_mean, c(.1, 1, 3))
  testthat::expect_equal(cattle$q025, c(.06, .8, 2.6))
  testthat::expect_false(cattle$fitted_level[2] == FALSE)
})

testthat::test_that("temporal object has one ordered row per component and uses mapping dates", {
  fixture <- make_reporting_fixture()
  temporal <- postfit_reporting_temporal_effects(fixture$build, fixture$fit, fixture$stage2)
  testthat::expect_equal(nrow(temporal), 6L)
  testthat::expect_equal(as.integer(table(temporal$component)), c(3L, 3L))
  testthat::expect_equal(temporal$calendar_date[temporal$component == "week_steps"], as.Date("2024-01-01") + 7 * 0:2)
  testthat::expect_equal(temporal$timestep[temporal$component == "tier2_week"], 1:3)
})

testthat::test_that("species composition requires and preserves an explicit denominator", {
  x <- data.frame(host = c("bovine", "bovine", "equine", "unknown"),
                  group = c("livestock", "livestock", "livestock", "unknown"))
  object <- postfit_reporting_species_composition(x, "host", "analysis-eligible submissions", "group")
  testthat::expect_equal(sum(object$table$count), 4L)
  testthat::expect_equal(sum(object$table$percentage), 1)
  testthat::expect_equal(object$table$major_minor[object$table$host_species == "bovine"], "Major Hosts")
  testthat::expect_equal(object$audit$cohort_definition, "analysis-eligible submissions")
})

testthat::test_that("maps use deterministic weeks and unchanged raster values", {
  testthat::skip_if_not_installed("terra")
  root <- file.path(tempdir(), paste0("postfit-map-", Sys.getpid()))
  dir.create(file.path(root, "tier1_probability"), recursive = TRUE)
  dir.create(file.path(root, "tier2_intensity"), recursive = TRUE)
  dir.create(file.path(root, "qa"), recursive = TRUE)
  manifest <- data.frame(time_index = 1:4, epiyear = 2024L, epiweek = 1:4,
                         tier1_probability = character(4), tier2_intensity = character(4))
  for (i in 1:4) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
                     crs = "+proj=longlat +datum=WGS84")
    terra::values(r) <- c(i, i + 1, i + 2, NA)
    p1 <- file.path(root, "tier1_probability", sprintf("tier1_prob_y2024_w%02d.tif", i))
    p2 <- file.path(root, "tier2_intensity", sprintf("tier2_intensity_y2024_w%02d.tif", i))
    terra::writeRaster(r, p1, overwrite = TRUE)
    terra::writeRaster(r * 10, p2, overwrite = TRUE)
    manifest$tier1_probability[i] <- p1
    manifest$tier2_intensity[i] <- p2
  }
  utils::write.csv(manifest, file.path(root, "qa", "temporal_manifest.csv"), row.names = FALSE)
  read_manifest <- postfit_reporting_map_manifest(root)
  selected <- postfit_reporting_select_map_weeks(read_manifest, 4L)
  object <- postfit_reporting_selected_map_values(selected, root)
  testthat::expect_equal(selected$week, paste(2024, sprintf("W%02d", 1:4), sep = "-"))
  testthat::expect_equal(object$values$value[object$values$layer == "tier1_probability" & object$values$week == "2024-W01"], c(1, 2, 3))
  testthat::expect_equal(object$raster_value_semantics, "Values are direct Phase 3 cell assignments; no resampling or display rescaling was applied.")
})

testthat::test_that("cell area, potential abundance, and RPI semantic gate are explicit", {
  testthat::skip_if_not_installed("terra")
  root <- file.path(tempdir(), paste0("postfit-rpi-", Sys.getpid()))
  dir.create(root, recursive = TRUE)
  template <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 4, ymin = 0, ymax = 6, crs = "+proj=aea +lat_1=10 +lat_2=30 +lat_0=20 +lon_0=-75 +datum=WGS84 +units=km")
  terra::values(template) <- 1
  template_path <- file.path(root, "template.tif")
  terra::writeRaster(template, template_path, overwrite = TRUE)
  area <- postfit_reporting_trace_cell_area(template_path)
  testthat::expect_equal(area$nominal_average_raster_cell_area, 6)
  intensity_path <- file.path(root, "intensity.tif")
  terra::values(template) <- 2
  terra::writeRaster(template, intensity_path, overwrite = TRUE)
  abundance <- postfit_reporting_potential_abundance(intensity_path, area, file.path(root, "abundance"))
  testthat::expect_equal(as.numeric(terra::global(terra::rast(abundance$paths), "mean", na.rm = TRUE)[1, 1]), 12)
  observation_path <- file.path(root, "observations.csv")
  utils::write.csv(data.frame(x = 1, y = 1), observation_path, row.names = FALSE)
  gate <- postfit_reporting_rpi_audit("standardized_potential_abundance", observation_path, 4L)
  testthat::expect_true(gate$enabled)
  testthat::expect_equal(postfit_reporting_rpi_audit("tier2_intensity", observation_path, 4L)$status, "BLOCKED")
})

testthat::test_that("run-specific output roots cannot collide", {
  base <- file.path(tempdir(), paste0("postfit-output-", Sys.getpid()))
  paths_a <- postfit_reporting_output_paths(base, "reference_20725437")
  paths_b <- postfit_reporting_output_paths(base, "production_20742007")
  testthat::expect_false(identical(paths_a$root, paths_b$root))
  dir.create(paths_a$root, recursive = TRUE)
  file.create(file.path(paths_a$root, "sentinel"))
  testthat::expect_error(postfit_reporting_assert_output_isolated(base, "reference_20725437"), "non-empty")
})
cat("Post-fit reporting tests passed\\n")
