repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
source(file.path(repo_root, "R", "load_joint_model.R"))
source(file.path(repo_root, "R", "load_joint_inla.R"))
load_preprocessing(repo_root)
load_joint_model(repo_root)
load_joint_inla(repo_root)
source(file.path(repo_root, "R", "joint_inla_preflight.R"))
source(file.path(repo_root, "R", "joint_inla_project.R"))
source(file.path(repo_root, "R", "postfit_reporting.R"))
testthat::local_edition(3)

manifest_path <- file.path(repo_root, "docs", "input-audits", "2026-11-13", "configuration-c-input-manifest.yml")
preprocessing_path <- file.path(repo_root, "config", "configuration_c", "preprocessing.example.yml")
joint_model_path <- file.path(repo_root, "config", "configuration_c", "joint_model.example.yml")
joint_inla_path <- file.path(repo_root, "config", "configuration_c", "joint_inla.example.yml")

testthat::test_that("Configuration C source manifest and stage configs agree", {
  preprocessing_cfg <- read_preprocessing_config(preprocessing_path, repo_root)
  joint_model_cfg <- read_joint_model_config(joint_model_path, repo_root)
  joint_inla_cfg <- read_joint_inla_config(joint_inla_path, repo_root)

  testthat::expect_true(validate_preprocessing_config(preprocessing_cfg, require_inputs = FALSE) == TRUE)
  testthat::expect_true(validate_joint_model_config(joint_model_cfg, require_inputs = FALSE) == TRUE)
  testthat::expect_true(validate_joint_inla_config(joint_inla_cfg, require_inputs = FALSE) == TRUE)
  testthat::expect_equal(preprocessing_cfg$covariate_registry$manifest_sha256,
                         joint_model_cfg$covariate_registry$manifest_sha256)
  testthat::expect_equal(preprocessing_cfg$covariate_registry$manifest_sha256,
                         joint_inla_cfg$covariate_registry$manifest_sha256)
  testthat::expect_equal(preprocessing_cfg$covariate_registry$manifest_sha256,
                         covariate_registry_sha256(manifest_path))
  testthat::expect_equal(preprocessing_cfg$inputs$observations,
    "/project/disease_ecology/NWScrewworm/data/processed_data/case_detections/combined_clean_obs_2026-11-13.csv")
  testthat::expect_equal(preprocessing_cfg$covariate_registry$observations$sha256,
    "784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac")
  testthat::expect_equal(preprocessing_cfg$temporal$start_week, "2022-W01")
  testthat::expect_equal(preprocessing_cfg$temporal$end_week, "2026-W44")
  testthat::expect_equal(preprocessing_cfg$static_covariates$clay,
    preprocessing_cfg$covariate_registry$covariates$clay$source$path)
  testthat::expect_equal(preprocessing_cfg$static_covariates$wv0010,
    preprocessing_cfg$covariate_registry$covariates$wv0010$source$path)
  testthat::expect_equal(preprocessing_cfg$dynamic_covariates$spressure,
    preprocessing_cfg$covariate_registry$covariates$spressure$source$path)
  invalid_missing_policy <- preprocessing_cfg
  invalid_missing_policy$transformations$dynamic_missing_policy <- "complete_case"
  testthat::expect_error(validate_preprocessing_config(invalid_missing_policy, require_inputs = FALSE),
    "dynamic_missing_policy: fail")
  testthat::expect_match(preprocessing_cfg$project$output_directory, "outputs[/\\\\]configuration_c[/\\\\]preprocessing$")
  testthat::expect_match(joint_model_cfg$project$output_directory, "outputs[/\\\\]configuration_c[/\\\\]joint_model$")
  testthat::expect_match(joint_inla_cfg$project$output_directory, "outputs[/\\\\]configuration_c[/\\\\]joint_inla$")
})

testthat::test_that("Configuration C retains the full ISO-week window and later source rows", {
  cfg <- read_preprocessing_config(preprocessing_path, repo_root)
  first <- preprocessing_start_date(cfg)
  last <- preprocessing_epiweek_end(2026L, 44L)
  weeks <- make_week_index(first, last)
  testthat::expect_equal(nrow(weeks), 252L)
  testthat::expect_equal(preprocessing_epiweek_label(weeks$epiyear[[1L]], weeks$epiweek[[1L]]), "2022-W01")
  testthat::expect_equal(preprocessing_epiweek_label(tail(weeks$epiyear, 1L), tail(weeks$epiweek, 1L)), "2026-W44")
  testthat::expect_equal(cfg$covariate_registry$observations$date_max, "2026-11-13")
  testthat::expect_equal(cfg$covariate_registry$observations$expected_observations_after_endpoint, 968L)
  testthat::expect_true(isTRUE(cfg$covariate_registry$observations$source_archive_modified == FALSE))
  testthat::expect_equal(cfg$covariate_registry$spatial_template$classification, "TEMPLATE_PROVENANCE_RESOLVED")
  testthat::expect_equal(cfg$covariate_registry$spatial_template$comparison$binary_identity, "distinct")
  testthat::expect_true(isTRUE(cfg$covariate_registry$spatial_template$comparison$crs_equivalent))
  testthat::expect_equal(as.character(unlist(cfg$covariate_registry$schema_contract$environmental$weekly_variables, use.names = FALSE)), "spressure")
  testthat::expect_true(isTRUE(cfg$covariate_registry$schema_contract$environmental$no_week_substitution))
})

testthat::test_that("new environmental covariates keep source units and identity transformations", {
  cfg <- read_preprocessing_config(preprocessing_path, repo_root)
  training <- data.frame(
    mintemp = c(5, 6, 7), soilmoist = c(10, 11, 12), leafarea = c(1, 2, 3), rhum = c(60, 70, 80),
    cattle = c(0, 1, 2), horses = c(0, 1, 2), pigs = c(0, 1, 2), sheep = c(0, 1, 2), goats = c(0, 1, 2),
    road_density = c(0, 1, 2), night_illumination = c(0, 1, 2), x = c(1, 2, 3), y = c(1, 2, 3),
    clay = c(100, 200, 300), wv0010 = c(100, 150, 200), spressure = c(95, 96, 97)
  )
  transformations <- estimate_transformations(training, cfg)
  transformed <- apply_transformations(training, transformations)
  testthat::expect_identical(transformed$clay, training$clay)
  testthat::expect_identical(transformed$wv0010, training$wv0010)
  testthat::expect_identical(transformed$spressure, training$spressure)
  testthat::expect_equal(transformations$registered_covariates$clay$stored_units, "g/kg")
  testthat::expect_equal(transformations$registered_covariates$wv0010$stored_units, "10^-3 cm3 cm-3 (Mapped_units tag)")
  testthat::expect_equal(transformations$registered_covariates$spressure$source_units, "Pa")
  testthat::expect_equal(transformations$registered_covariates$spressure$stored_units, "kPa")

  complete <- data.frame(clay = c(1, 2), wv0010 = c(3, 4), spressure = c(95, 96))
  missing <- complete
  missing$clay[[2L]] <- NA_real_
  audit <- covariate_registry_missingness(
    list(tier2 = missing, prediction_grid = complete),
    c("tier2", "prediction_grid"), cfg$covariate_registry
  )
  testthat::expect_equal(audit$status[audit$scope == "tier2" & audit$covariate == "clay"], "FAIL")
  testthat::expect_equal(audit$missing_or_nonfinite[audit$scope == "tier2" & audit$covariate == "clay"], 1L)
  testthat::expect_true(all(audit$status[audit$scope == "prediction_grid"] == "PASS"))
})

testthat::test_that("formula, INLA effects, and reporting consume the expanded registry", {
  cfg <- read_joint_inla_config(joint_inla_path, repo_root)
  registry <- cfg$covariate_registry
  fixed_terms <- as.character(unlist(registry$configuration$fixed_effects$formula_order, use.names = FALSE))
  priors <- list(
    pc_rw = list(prec = list(prior = "pc.prec", param = c(1, 0.01))),
    pc_rw_strong = list(prec = list(prior = "pc.prec", param = c(0.3, 0.01))),
    pc_rw_cat = list(prec = list(prior = "pc.prec", param = c(0.5, 0.05))),
    hyper_copy = list(beta = list(prior = "normal", param = c(0.5, 0.2)))
  )
  formula <- make_joint_formula(list(n.spde = 1L), list(n.spde = 1L), priors, cfg)
  formula_labels <- attr(stats::terms(formula), "term.labels")
  testthat::expect_true(all(fixed_terms %in% formula_labels))
  random_names <- c("tier1_field", "week_steps", "admin_f", "tier2_field", "tier2_copy_field", "tier2_week", "cattle_q")
  testthat::expect_true(all(vapply(random_names, function(name) any(grepl(paste0("^f\\(", name), formula_labels)), logical(1L))))
  testthat::expect_true(all(c("mintemp:soilmoist", "mintemp:leafarea") %in% formula_labels))
  testthat::expect_equal(joint_inla_extract_expected_fixed_effect_count(list(
    formula = formula,
    model_signature = list(fixed_effect_names = c("intercept1", "intercept2", fixed_terms))
  )), 19L)
  testthat::expect_identical(joint_inla_integer_effect_names(), c("admin_f", "week_steps", "tier2_week", "cattle_q"))
  testthat::expect_equal(cfg$model$tier1$family, "binomial")
  testthat::expect_equal(cfg$model$tier2$family, "nbinomial")

  tier1 <- data.frame(northing_km_s = 1, road_dens_s = 1, night_illum_s = 1, admin_f = 1L, timestep = 1L)
  tier2 <- data.frame(
    mintemp_s = 1, soilmoist_s = 1, leafarea_s = 1, rhum_s = 1,
    cattle_log1p = 1, horses_log1p = 1, pigs_log1p = 1, goats_log1p = 1, sheep_log1p = 1,
    cattle_q = 1L, cattle_mid_log1p = 1, timestep = 1L, clay = 100, wv0010 = 150, spressure = 95
  )
  mapping <- joint_effect_mapping(tier1, tier2, registry)
  testthat::expect_true(all(c("clay", "wv0010", "spressure") %in% names(mapping$tier2)))
  testthat::expect_identical(unname(mapping$tier2[c("clay", "wv0010", "spressure")]), c("clay", "wv0010", "spressure"))
  effects1 <- make_tier1_effects(tier1, list(tier1 = list()), mapping)
  effects2 <- make_tier2_effects(tier2, list(tier2 = list(), copy = list()), mapping)
  testthat::expect_true(all(c("admin_f", "week_steps") %in% names(effects1$fixed)))
  testthat::expect_true(all(c("tier2_week", "cattle_q", "cattle_mid_log1p", "clay", "wv0010", "spressure") %in% names(effects2$fixed)))
  testthat::expect_identical(typeof(effects1$fixed$admin_f), "integer")
  testthat::expect_identical(typeof(effects1$fixed$week_steps), "integer")
  testthat::expect_identical(typeof(effects2$fixed$tier2_week), "integer")
  testthat::expect_identical(typeof(effects2$fixed$cattle_q), "integer")
  parsed_names <- joint_inla_preflight_formula_fixed_names(formula)
  testthat::expect_true(all(c("clay", "wv0010", "spressure") %in% parsed_names))
  prediction_terms <- joint_inla_project_fixed_terms(
    c("intercept2" = 0, stats::setNames(rep(0, length(fixed_terms)), fixed_terms)),
    mapping$tier2, "intercept2", tier2, "tier2"
  )
  testthat::expect_true(all(c("clay", "wv0010", "spressure") %in% prediction_terms))
  projected_fixed <- joint_inla_project_fixed_contributions(
    tier2, c("intercept2" = 0, stats::setNames(rep(0, length(fixed_terms)), fixed_terms)),
    mapping$tier2, "intercept2", "tier2"
  )
  testthat::expect_equal(nrow(projected_fixed), nrow(tier2))
  testthat::expect_true(all(is.finite(projected_fixed$fixed_total)))

  terms <- c("intercept1", registry$configuration$fixed_effects$reporting_order$tier1[-1L],
             registry$configuration$fixed_effects$reporting_order$tier2)
  fixed <- data.frame(mean = seq_along(terms), sd = rep(0.2, length(terms)),
                      `0.025quant` = seq_along(terms) - 0.5, `0.5quant` = seq_along(terms),
                      `0.975quant` = seq_along(terms) + 0.5,
                      row.names = terms, check.names = FALSE)
  report <- postfit_reporting_fixed_effects(list(
    build = list(covariate_registry = registry),
    fit = list(summary.fixed = fixed)
  ))
  testthat::expect_true(all(c("clay", "wv0010", "spressure") %in% report$tier2$term))
  testthat::expect_equal(report$tier2$label[match("clay", report$tier2$term)], "SoilGrids clay, 0-5 cm (per g/kg)")
  testthat::expect_equal(report$tier2$stored_units[match("spressure", report$tier2$term)], "kPa")
  testthat::expect_equal(report$tier2$transformation[match("wv0010", report$tier2$term)], "identity")
  testthat::expect_equal(nrow(report$tier1) + nrow(report$tier2), length(terms))
})

testthat::test_that("new input registration agrees with the audited checksum inventory", {
  registry <- read_covariate_registry(manifest_path, repo_root)
  inventory_path <- file.path(repo_root, "docs", "input-audits", "2026-11-13", "input_file_hashes.tsv")
  inventory <- utils::read.delim(inventory_path, stringsAsFactors = FALSE, check.names = FALSE)
  for (name in c("clay", "wv0010")) {
    source <- registry$covariates[[name]]$source
    row <- inventory[inventory$path == source$path, , drop = FALSE]
    testthat::expect_equal(nrow(row), 1L)
    testthat::expect_equal(row$sha256, source$sha256)
  }
  pressure <- inventory[inventory$source_id == "surface_pressure_weekly_tif", , drop = FALSE]
  testthat::expect_equal(nrow(pressure), 252L)
  weeks <- sub("^.*_(20[0-9]{2}-W[0-9]{2})\\.tif$", "\\1", basename(pressure$path))
  testthat::expect_equal(weeks[[1L]], "2022-W01")
  testthat::expect_equal(tail(weeks, 1L), "2026-W44")
})
