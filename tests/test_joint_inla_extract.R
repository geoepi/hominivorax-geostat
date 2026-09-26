repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"))
source(file.path(repo_root, "R", "joint_inla_fit.R"))

stack_data <- data.frame(
  Y.1 = c(1, NA, 0, NA, NA, NA),
  Y.2 = c(NA, NA, NA, 2, NA, 4),
  link = c(1L, 1L, 1L, 2L, 2L, 2L),
  e = c(NA, NA, NA, 1, 1, 1)
)
stack <- list(
  data = list(data = stack_data, index = list(tier1 = 1:3, tier2 = 4:6)),
  A = matrix(0, nrow = 6, ncol = 2), effects = list(), responses = list(NULL)
)
class(stack) <- c("inla.data.stack", "list")
build <- list(
  family = c("binomial", "nbinomial"),
  stacks = list(joint = stack),
  fields = list(
    tier1 = list(tier1_field = 1:4, tier1_field.group = c(1L, 1L, 2L, 2L), tier1_field.repl = rep("1", 4)),
    tier2 = list(tier2_field = 1:4, tier2_field.group = c(1L, 1L, 2L, 2L), tier2_field.repl = rep("1", 4)),
    copy = list(tier2_copy_field = 1:4, tier2_copy_field.group = c(1L, 1L, 2L, 2L), tier2_copy_field.repl = rep("1", 4))
  ),
  spde = list(tier1 = list(n.spde = 2L), tier2 = list(n.spde = 2L))
)
stage2 <- list(
  tier1 = data.frame(.row_id = 1:3, x = 1:3, y = 1:3, epiyear = 2024L, epiweek = 1:3, time_index = 1:3,
                     response_training = c(1, NA, 0), response_observed = c(1, 1, 0), is_test_point = c(FALSE, TRUE, FALSE),
                     is_censored = FALSE, admin_u = c("A", "B", "A"), admin_f = c(1L, 2L, 1L), admin = c("A", "B", "A")),
  tier2 = data.frame(.row_id = 4:6, poly_id = 4:6, x = 1:3, y = 1:3, epiyear = 2024L, epiweek = 1:3, time_index = 1:3,
                     response_training = c(2, NA, 4), response_observed = c(2, 2, 4), is_test_point = c(FALSE, TRUE, FALSE),
                     is_censored = FALSE, admin_u = c("A", "B", "A"), admin_f = c(1L, 2L, 1L),
                     cattle_q = c(1L, 1L, 2L), cattle_mid_log1p = c(0.1, 0.1, 0.2), cattle_mid = c(0.1, 0.1, 0.2)),
  temporal_mapping = data.frame(timestep = 1:2, epiyear = 2024L, epiweek = 1:2, week_start = as.Date("2024-01-01") + c(0, 7)),
  admin_mapping = data.frame(admin_u = c("A", "B", "Unk"), admin_f = 1:3),
  prediction_grid = data.frame(.row_id = 1:2)
)
summary_table <- function(ids) data.frame(ID = ids, mean = seq_along(ids), sd = rep(1, length(ids)), check.names = FALSE)
fit <- list(
  size.linear.predictor = list(n = 2L, N = 2L, Ntotal = 8L),
  summary.linear.predictor = data.frame(mean = 1:8, sd = rep(1, 8)),
  summary.fitted.values = data.frame(mean = c(0.2, 0.3, 0.4, 2, 3, 4, 9, 10), sd = rep(1, 8)),
  summary.fixed = data.frame(mean = 1:2, row.names = c("a", "b")),
  summary.hyperpar = data.frame(mean = 1:2, row.names = c("h1", "h2")),
  summary.random = list(
    tier1_field = summary_table(0:3),
    week_steps = summary_table(1:2),
    admin_f = summary_table(c(1, 3)),
    tier2_field = summary_table(0:3),
    tier2_week = summary_table(1:2),
    cattle_q = summary_table(1:2),
    tier2_copy_field = summary_table(rep(1:2, 2))
  ),
  dic = list(dic = 10, family = c(1L, 1L, 2L, 2L, NA_integer_, NA_integer_), local.dic = c(1, 2, 3, 4, NA, NA)),
  waic = list(waic = 10, local.waic = c(1, 2, 3, 4, NA, NA)),
  mlik = matrix(c(-5, -4), nrow = 2, dimnames = list(c("log marginal-likelihood (integration)", "log marginal-likelihood (Gaussian)"), NULL)),
  .args = list(data = list(link = stack_data$link, Y = as.matrix(stack_data[c("Y.1", "Y.2")]), e = stack_data$e))
)

stopifnot(identical(joint_inla_stack_tags(build), c("tier1", "tier2")))
row_map <- joint_inla_extract_row_map(build, stage2)
stopifnot(identical(row_map$stack_row, 1:6), identical(row_map$tier, c(rep("tier1", 3), rep("tier2", 3))),
          identical(row_map$source_row, c(1:3, 1:3)), identical(row_map$family_index, stack_data$link),
          identical(row_map$source_is_test_point, c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE)))
fitted <- joint_inla_extract_fitted_values(build, fit, stage2)
stopifnot(identical(fitted$output_index, 1:6), identical(fitted$fitted_mean, fit$summary.fitted.values$mean[1:6]))
holdout <- joint_inla_extract_holdout_predictions(build, fit, stage2)
stopifnot(nrow(holdout) == 2L, identical(holdout$source_row, c(2L, 2L)))
stopifnot(nrow(joint_inla_extract_fixed_effects(fit)) == 2L, nrow(joint_inla_extract_hyperparameters(fit)) == 2L,
          nrow(joint_inla_extract_random_effects(fit)) == 20L)
temporal <- joint_inla_extract_temporal_effects(build, fit, stage2)
stopifnot(all(temporal$timestep %in% 1:2), all(c("week_steps", "tier2_week") %in% unique(temporal$component)))
admin <- joint_inla_extract_admin_effects(fit, stage2)
stopifnot(nrow(admin) == 3L, sum(admin$fitted_level) == 2L)
cattle <- joint_inla_extract_cattle_effects(fit, stage2)
stopifnot(identical(cattle$model_index, 1:2), cattle$active_count[1] == 1L, cattle$active_count[2] == 1L)
spde <- joint_inla_extract_spde_fields(build, fit)
stopifnot(all(vapply(spde, nrow, integer(1L)) == 4L), identical(spde$tier1_field$mesh_node, spde$tier2_copy_field$mesh_node))
criteria <- joint_inla_extract_criteria(build, fit)
stopifnot(all(criteria$reconciliation$pass), abs(criteria$reconciliation$difference) < 1e-12)
mlik <- joint_inla_extract_marginal_log_likelihood(fit)
stopifnot(identical(mlik$value[1], -5), identical(joint_inla_fit_marginal_log_likelihood(fit$mlik), -5),
          identical(joint_inla_fit_summary_values(list(mlik = fit$mlik))$marginal_log_likelihood, -5))
cat("Stage 3B extraction tests passed\n")
