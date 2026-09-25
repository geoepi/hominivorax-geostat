repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_project.R"))

mapping1 <- c(north = "northing_km_s", road_dens = "road_dens_s", night_illum = "night_illum_s", admin_f = "admin_f", week_steps = "timestep")
mapping2 <- c(mintemp = "mintemp_s", soilmoist = "soilmoist_s", leafarea = "leafarea_s", rhum = "rhum_s",
              cattle = "cattle_log1p", horses = "horses_log1p", pigs = "pigs_log1p", goats = "goats_log1p", sheep = "sheep_log1p",
              cattle_q = "cattle_q", cattle_mid_log1p = "cattle_mid_log1p", tier2_week = "timestep")

fixed <- c(intercept1 = 1, intercept2 = 2, north = 3, road_dens = 4, night_illum = 5,
           mintemp = 6, soilmoist = 7, leafarea = 8, rhum = 9, cattle = 10,
           horses = 11, pigs = 12, goats = 13, sheep = 14,
           `mintemp:soilmoist` = 15, `mintemp:leafarea` = 16)

tier1 <- data.frame(northing_km_s = c(1, 2), road_dens_s = c(2, 3), night_illum_s = c(3, 4), admin_f = c(1L, 2L), timestep = c(1L, 2L))
tier1_fixed <- joint_inla_project_fixed_contributions(tier1, fixed, mapping1, "intercept1", "tier1")
stopifnot(all.equal(tier1_fixed$fixed_intercept1, c(1, 1)),
          all.equal(tier1_fixed$fixed_north, c(3, 6)),
          all.equal(tier1_fixed$fixed_total, c(1 + 3 + 8 + 15, 1 + 6 + 12 + 20)))

tier2 <- data.frame(
  mintemp_s = c(1, 2), soilmoist_s = c(2, 3), leafarea_s = c(3, 4), rhum_s = c(4, 5),
  cattle_log1p = c(1, 2), horses_log1p = c(2, 3), pigs_log1p = c(3, 4), goats_log1p = c(4, 5), sheep_log1p = c(5, 6),
  cattle_q = c(1L, 2L), cattle_mid_log1p = c(.5, 1), timestep = c(1L, 2L)
)
tier2_fixed <- joint_inla_project_fixed_contributions(tier2, fixed, mapping2, "intercept2", "tier2")
stopifnot(all.equal(tier2_fixed$fixed_mintemp_soilmoist, c(30, 90)),
          all.equal(tier2_fixed$fixed_mintemp_leafarea, c(48, 128)))

cattle <- joint_inla_project_cattle_contribution(
  tier2, mapping2,
  data.frame(model_index = 1:2, mean = c(.4, .8)),
  tier2
)
stopifnot(all.equal(cattle$cattle_rw2_contribution, c(.2, .8)))

field <- data.frame(
  latent_row = c(1L, 2L, 3L, 4L), mesh_node = c(1L, 2L, 1L, 2L),
  group_index = c(1L, 1L, 2L, 2L), mean = c(1, 2, 10, 20)
)
A <- Matrix::sparseMatrix(i = c(1L, 1L, 2L, 2L), j = c(1L, 2L, 3L, 4L), x = c(.25, .75, .5, .5), dims = c(2L, 4L))
stopifnot(all.equal(joint_inla_project_spatial_contribution(A, field), c(1.75, 15)),
          all.equal(joint_inla_project_field_matrix(field, 2L, "field"), matrix(c(1, 2, 10, 20), nrow = 2L)))

admin <- data.frame(model_index = 1:2, mean = c(.25, -.5))
admin_data <- data.frame(admin_f = c(1L, 3L))
unseen_error <- tryCatch({ joint_inla_project_admin_contribution(admin_data, admin); FALSE }, error = function(e) grepl("without fitted admin_f support", conditionMessage(e), fixed = TRUE))
stopifnot(unseen_error)
admin_zero <- joint_inla_project_admin_contribution(admin_data, admin, allow_unseen_zero = TRUE)
stopifnot(all.equal(admin_zero$contribution, c(.25, 0)), identical(admin_zero$source, c("fitted_summary_random", "unseen_level_zero_mean")))

build <- list(
  effect_mapping = list(tier1 = mapping1, tier2 = mapping2),
  fields = list(tier1 = list(tier1_field.group = c(1L, 1L, 2L, 2L)), tier2 = list(tier2_field.group = c(1L, 1L, 2L, 2L))),
  formula = stats::as.formula("Y ~ -1 + intercept1 + intercept2 + north + road_dens + night_illum + mintemp + soilmoist + leafarea + rhum + cattle + horses + pigs + goats + sheep + mintemp:soilmoist + mintemp:leafarea")
)
components <- list(
  fixed = fixed, mapping = list(tier1 = mapping1, tier2 = mapping2), n_groups = 2L,
  random = list(
    week_steps = data.frame(model_index = 1:2, mean = c(.1, .2)),
    tier2_week = data.frame(model_index = 1:2, mean = c(.3, .4))
  )
)
grid <- data.frame(
  space_time_id = paste0("r", 1:4), .row_id = 1:4, cell_id = c(1L, 2L, 1L, 2L), x = c(0, 1, 0, 1), y = c(0, 0, 0, 0),
  epiyear = c(2024L, 2024L, 2024L, 2024L), epiweek = c(1L, 1L, 2L, 2L), time_index = 1:4, timestep = c(1L, 1L, 2L, 2L), quarter_index = c(1L, 2L, 1L, 2L),
  admin_u = "A", admin_f = 1L, northing_km_s = 1, road_dens_s = 1, night_illum_s = 1,
  mintemp_s = 1, soilmoist_s = 1, leafarea_s = 1, rhum_s = 1, cattle_log1p = 1, horses_log1p = 1, pigs_log1p = 1, goats_log1p = 1, sheep_log1p = 1,
  cattle_q = 1L, cattle_mid_log1p = 1, stringsAsFactors = FALSE
)
stage2 <- list(prediction_grid = grid)
contract <- joint_inla_project_prediction_grid_contract(stage2, build, expected_rows = NULL, expected_weeks = 2L, components = components)
stopifnot(identical(contract$n_rows, 4L), identical(contract$n_weeks, 2L), identical(contract$n_cells, 2L))
projected_fixture <- grid
projected_fixture$spatial_group_index <- projected_fixture$quarter_index
projected_fixture$eta1_mean <- 0
projected_fixture$tier1_probability_plugin <- .5
projected_fixture$eta2_mean <- 0
projected_fixture$tier2_intensity_plugin <- 1
output_validation <- joint_inla_project_validate_prediction_output(projected_fixture, grid, contract)
stopifnot(isTRUE(output_validation$pass), all(output_validation$audit$status == "PASS"))

bad_duplicate <- grid
bad_duplicate$space_time_id[2] <- bad_duplicate$space_time_id[1]
stopifnot(inherits(try(joint_inla_project_prediction_grid_contract(list(prediction_grid = bad_duplicate), build, expected_rows = NULL, expected_weeks = 2L, components = components), silent = TRUE), "try-error"))
bad_group <- grid
bad_group$quarter_index[1] <- 3L
stopifnot(inherits(try(joint_inla_project_prediction_grid_contract(list(prediction_grid = bad_group), build, expected_rows = NULL, expected_weeks = 2L, components = components), silent = TRUE), "try-error"))
bad_time <- grid
bad_time$timestep[1] <- 3L
stopifnot(inherits(try(joint_inla_project_prediction_grid_contract(list(prediction_grid = bad_time), build, expected_rows = NULL, expected_weeks = 2L, components = components), silent = TRUE), "try-error"))
bad_predictor <- grid
bad_predictor$mintemp_s[1] <- NA_real_
stopifnot(inherits(try(joint_inla_project_prediction_grid_contract(list(prediction_grid = bad_predictor), build, expected_rows = NULL, expected_weeks = 2L, components = components), silent = TRUE), "try-error"))

manual <- data.frame(tier = c("tier1", "tier2"), stack_row = 1:2, component_sum = c(0, 1), linear_predictor_mean = c(0, 1), difference = 0)
metrics <- joint_inla_project_reconstruction_metrics(manual, data.frame(), n_worst = 2L)
stopifnot(isTRUE(metrics$pass), all(metrics$audit$n == 1L))
stopifnot(all.equal(stats::plogis(0), .5), all.equal(exp(1), exp(1)))

# End-to-end synthetic response-stack identity test, including extract-layer mappings.
source(file.path(repo_root, "R", "joint_inla_extract.R"))
stack_data <- data.frame(Y.1 = c(1, 0, NA, NA), Y.2 = c(NA, NA, 1, 2), link = c(1L, 1L, 2L, 2L), e = c(NA, NA, 1, 1))
stack <- list(data = list(data = stack_data, index = list(tier1 = 1:2, tier2 = 3:4)), A = matrix(0, 4, 4), effects = list(), responses = list(NULL))
class(stack) <- c("inla.data.stack", "list")
full_build <- list(
  family = c("binomial", "nbinomial"), stacks = list(joint = stack), A = list(tier1 = A, tier2 = A),
  fields = list(
    tier1 = list(tier1_field = 1:4, tier1_field.group = c(1L, 1L, 2L, 2L), tier1_field.repl = rep("1", 4)),
    tier2 = list(tier2_field = 1:4, tier2_field.group = c(1L, 1L, 2L, 2L), tier2_field.repl = rep("1", 4)),
    copy = list(tier2_copy_field = 1:4, tier2_copy_field.group = c(1L, 1L, 2L, 2L), tier2_copy_field.repl = rep("1", 4))
  ),
  effect_mapping = list(tier1 = mapping1, tier2 = mapping2),
  formula = stats::as.formula("Y ~ -1 + intercept1 + intercept2 + north + road_dens + night_illum + mintemp + soilmoist + leafarea + rhum + cattle + horses + pigs + goats + sheep + mintemp:soilmoist + mintemp:leafarea")
)
full_tier1 <- tier1
full_tier1$response_training <- c(1, 0)
full_tier1$response_observed <- c(1, 0)
full_tier1$is_test_point <- FALSE
full_tier1$is_censored <- FALSE
full_tier1$admin_u <- c("A", "B")
full_tier1$x <- c(0, 1); full_tier1$y <- c(0, 0); full_tier1$quarter_index <- c(1L, 2L); full_tier1$.row_id <- c("t1a", "t1b")
full_tier2 <- tier2
full_tier2$response_training <- c(1, 2)
full_tier2$response_observed <- c(1, 2)
full_tier2$is_test_point <- FALSE
full_tier2$is_censored <- FALSE
full_tier2$admin_u <- c("A", "B")
full_tier2$x <- c(0, 1); full_tier2$y <- c(0, 0); full_tier2$quarter_index <- c(1L, 2L); full_tier2$.row_id <- c("t2a", "t2b"); full_tier2$poly_id <- 1:2
full_stage2 <- list(
  tier1 = full_tier1, tier2 = full_tier2,
  temporal_mapping = data.frame(timestep = 1:2, epiyear = 2024L, epiweek = 1:2),
  admin_mapping = data.frame(admin_u = c("A", "B"), admin_f = 1:2), prediction_grid = data.frame(.row_id = 1:2)
)
full_fit <- list(
  size.linear.predictor = list(n = 0L, Ntotal = 4L),
  summary.linear.predictor = data.frame(mean = c(29.1, 53.7, 352.425, 596.55)),
  summary.fitted.values = data.frame(mean = c(.9, .9, 2, 2)),
  summary.fixed = data.frame(mean = fixed, row.names = names(fixed)),
  summary.random = list(
    tier1_field = data.frame(ID = 1:4, mean = c(1, 2, 10, 20), sd = 1),
    tier2_field = data.frame(ID = 1:4, mean = c(1, 2, 10, 20), sd = 1),
    tier2_copy_field = data.frame(ID = 1:4, mean = c(.1, .2, .3, .4), sd = 1),
    week_steps = data.frame(ID = 1:2, mean = c(.1, .2), sd = 1),
    tier2_week = data.frame(ID = 1:2, mean = c(.3, .4), sd = 1),
    admin_f = data.frame(ID = 1:2, mean = c(.25, -.5), sd = 1),
    cattle_q = data.frame(ID = 1:2, mean = c(.4, .8), sd = 1)
  )
)
full_components <- joint_inla_project_prepare_components(full_build, full_fit, full_stage2)
full_fitted <- joint_inla_extract_fitted_values(full_build, full_fit, full_stage2)
full_manual <- joint_inla_project_reconstruct_response(full_build, full_fit, full_stage2, full_components, full_fitted)
full_metrics <- joint_inla_project_reconstruction_metrics(full_manual, full_fitted, n_worst = 2L)
stopifnot(isTRUE(full_metrics$pass), max(abs(full_manual$difference)) < 1e-12)

cat("Joint-INLA Phase 2 projection helper tests passed\n")
