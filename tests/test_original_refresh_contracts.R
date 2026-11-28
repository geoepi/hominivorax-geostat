repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "original_refresh_contracts.R"))
source(file.path(repo_root, "R", "c1_effect_assessment.R"))
source(file.path(repo_root, "R", "original_refresh_comparison.R"))
source(file.path(repo_root, "R", "covariate_registry.R"))
testthat::local_edition(3)

testthat::test_that("the refreshed identity and stage configs are versioned and isolated", {
  identity <- yaml::read_yaml(file.path(repo_root, "config", "original_refresh_w44_2026", "identity.yml"))
  joint_model <- yaml::read_yaml(file.path(repo_root, "config", "original_refresh_w44_2026", "joint_model.yml"))
  joint_inla <- yaml::read_yaml(file.path(repo_root, "config", "original_refresh_w44_2026", "joint_inla.yml"))
  fit <- yaml::read_yaml(file.path(repo_root, "config", "original_refresh_w44_2026", "joint_inla_fit.yml"))
  testthat::expect_null(joint_model$covariate_manifest)
  testthat::expect_null(joint_inla$covariate_manifest)
  testthat::expect_true(original_refresh_assert_identity(identity, joint_model, joint_inla, fit))
  testthat::expect_equal(identity$source$observation_rows, 164767)
  testthat::expect_equal(identity$source$original_formula_reference_commit,
    "4a463bd62727cf33f783a31d9627afdb576a077f")
  testthat::expect_equal(identity$source$analysis_end_week, "2026-W44")
  testthat::expect_false(isTRUE(fit$outputs$overwrite))
})

testthat::test_that("the original formula retains every frozen term and excludes C-1-only terms", {
  expected <- original_refresh_fixed_names()
  testthat::expect_length(expected, 16L)
  testthat::expect_identical(original_refresh_fixed_terms(),
    c("north", "road_dens", "night_illum", "mintemp", "soilmoist", "leafarea", "rhum",
      "mintemp:soilmoist", "mintemp:leafarea", "cattle", "horses", "pigs", "goats", "sheep"))
  source(file.path(repo_root, "R", "joint_inla_spec.R"))
  priors <- list(
    pc_rw = list(prec = list(prior = "pc.prec", param = c(1, 0.01))),
    pc_rw_strong = list(prec = list(prior = "pc.prec", param = c(0.3, 0.01))),
    pc_rw_cat = list(prec = list(prior = "pc.prec", param = c(0.5, 0.05))),
    hyper_copy = list(beta = list(prior = "normal", param = c(0.5, 0.2)))
  )
  reference_formula <- make_joint_formula(list(n.spde = 1L), list(n.spde = 1L), priors,
    list(covariate_registry = NULL))
  reference_labels <- attr(stats::terms(reference_formula), "term.labels")
  reference_fixed <- reference_labels[!grepl("^f\\(", reference_labels)]
  testthat::expect_setequal(reference_fixed, expected)
  testthat::expect_identical(
    paste(deparse(reference_formula, width.cutoff = 500L), collapse = " "),
    paste(deparse(make_joint_formula(list(n.spde = 1L), list(n.spde = 1L), priors,
      list(covariate_registry = NULL)), width.cutoff = 500L), collapse = " ")
  )
  build <- list(
    model_signature = list(fixed_effect_names = expected,
      fixed_effect_formula_order = expected),
    covariate_registry = NULL, config = list(covariate_registry = NULL),
    family = c("binomial", "nbinomial"), provenance = list(executed_fit = FALSE)
  )
  audit <- original_refresh_formula_audit(build)
  testthat::expect_true(all(audit$status == "PASS"))
  altered <- build
  altered$model_signature$fixed_effect_names <- c(expected, "clay")
  testthat::expect_equal(original_refresh_formula_audit(altered)$status[4L], "FAIL")
})

testthat::test_that("Stage 1 reuse requires the approved provenance and original predictor schema", {
  tier1 <- data.frame(road_density = 2, night_illumination = 3, x = 4, y = 5, Yi = 1L, sc_Exp = 0.0001)
  tier2 <- data.frame(road_density = 2, night_illumination = 3, mintemp = 4,
    soilmoist = 5, leafarea = 6, rhum = 7, cattle = 8, horses = 9,
    pigs = 10, goats = 11, sheep = 12, x = 13, y = 14, count = 1L,
    area_km2 = 100, terrestrial_area_km2 = 100, sc_Exp = 100, clay = 15)
  inputs <- list(
    tier1 = tier1, tier2 = tier2, prediction_grid = tier2,
    mesh = structure(list(loc = matrix(c(0, 0, 1, 1), ncol = 2)), class = "inla.mesh"), spatial_support = list(),
    time_index = data.frame(), configuration = list(
      temporal = list(start_week = "2022-W01", resolved_end_week = "2026-W44"),
      study = list(end_date = "2026-11-01"),
      transformations = list(temperature_hinge = 12, dynamic_missing_policy = "fail",
        livestock_missing_policy = "impute_zero")),
    provenance = list(
      observation_expected_sha256 = "abc", observation_sha256_before_read = "abc",
      observation_sha256_after_read = "abc", observation_checksum_verified = TRUE,
      covariate_manifest = list(manifest_sha256 = "def")),
    preprocessing_metadata = list()
  )
  audit <- original_refresh_stage1_audit(inputs, "abc", "def")
  testthat::expect_true(all(audit$status == "PASS"))
  inputs$configuration$temporal$resolved_end_week <- "2026-W45"
  testthat::expect_equal(original_refresh_stage1_audit(inputs, "abc", "def")$status[4L], "FAIL")
})

testthat::test_that("marginal effect scaling uses the observed predictor range", {
  posterior <- data.frame(term = "clay", posterior_mean = 0.01, posterior_median = 0.01,
    q025 = 0.005, q975 = 0.015)
  distribution <- data.frame(term = "clay", sample = "all rows", iqr = 20, range_10_90 = 40)
  effect <- c1_effect_scale_summary(posterior, distribution)
  testthat::expect_equal(effect$multiplicative_median_iqr, exp(0.2))
  testthat::expect_equal(effect$multiplicative_q025_iqr, exp(0.1))
  testthat::expect_equal(effect$multiplicative_q975_10_90, exp(0.6))
  units <- c1_effect_join_source_units(data.frame(term = c("clay", "wv0010", "spressure")))
  testthat::expect_identical(units$source_units,
    c("SoilGrids mapped g/kg; coefficient per g/kg",
      "SoilGrids mapped 10^-3 cm3 cm-3; coefficient per mapped unit",
      "ERA5-Land product Pa; C-1 fitted column kPa per manifest"))
})

testthat::test_that("holdout matching reports exact paired coverage and Tier 2 error differences", {
  c1 <- data.frame(tier = "tier2", .row_id = c("a", "b", "c"),
    response_observed = c(1, 4, 2), expected_count = c(1, 3, 4))
  refreshed <- data.frame(tier = "tier2", .row_id = c("b", "c", "d"),
    response_observed = c(4, 2, 1), expected_count = c(5, 3, 1))
  matched <- original_refresh_match_holdouts(c1, refreshed)
  testthat::expect_equal(matched$matched_n, 2L)
  testthat::expect_equal(matched$c1_only_n, 1L)
  testthat::expect_equal(matched$refreshed_only_n, 1L)
  metrics <- original_refresh_paired_tier2_errors(matched)
  testthat::expect_equal(metrics$value[metrics$metric == "paired_valid_rows"], 2)
  testthat::expect_equal(metrics$value[metrics$metric == "paired_mae_difference_refreshed_minus_c1"], -0.5)
  testthat::expect_error(original_refresh_match_holdouts(rbind(c1, c1[1, ]), refreshed), "unique")
})
