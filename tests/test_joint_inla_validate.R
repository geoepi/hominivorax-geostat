repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_validate.R"))

binary <- data.frame(
  response_observed = rep(c(0, 0, 1, 1, 0, 1), 4),
  fitted_mean = rep(c(0.05, 0.15, 0.70, 0.90, 0.20, 0.80), 4)
)
stopifnot(abs(joint_inla_validate_rank_auc(binary$response_observed, binary$fitted_mean) - 1) < 1e-12)
stopifnot(is.finite(joint_inla_validate_brier(binary$response_observed, binary$fitted_mean)),
          is.finite(joint_inla_validate_log_loss(binary$response_observed, binary$fitted_mean)))
stopifnot(nrow(joint_inla_validate_equal_frequency_bins(binary$response_observed, binary$fitted_mean, 3L)) == 3L)
binary_result <- suppressWarnings(joint_inla_validate_tier1(binary))
stopifnot(identical(binary_result$status, "PASS"), nrow(binary_result$calibration) == 10L,
          all(binary_result$metrics$status == "PASS"))

positive_only <- data.frame(response_observed = rep(1, 4), fitted_mean = c(0.2, 0.4, 0.6, 0.8))
positive_result <- joint_inla_validate_tier1(positive_only)
stopifnot(identical(positive_result$status, "WARNING"), identical(positive_result$negatives, 0L),
          all(positive_result$metrics$status[positive_result$metrics$metric %in% c("auc", "brier", "log_loss")] == "WARNING"))

count <- data.frame(
  output_id = paste0("row", 1:20),
  response_observed = rep(1:5, 4),
  exposure = rep(c(10, 20, 30, 40), each = 5),
  linear_predictor_mean = log(rep(c(0.10, 0.20, 0.30, 0.40), each = 5)),
  fitted_mean = rep(c(0.10, 0.20, 0.30, 0.40), each = 5)
)
count_result <- joint_inla_validate_tier2(count)
stopifnot(identical(count_result$status, "PASS"), identical(count_result$scale$scale, "intensity_rate"),
          nrow(count_result$calibration) == 10L,
          all(count_result$metrics$status[count_result$metrics$metric %in% c("mae", "rmse", "pearson", "spearman")] == "PASS"))
stopifnot(all.equal(count_result$predicted[1:5], rep(1, 5)), count_result$predicted[20] == 16)

summary_only <- list(
  fit = list(
    marginals.linear.predictor = NULL,
    marginals.fitted.values = NULL,
    marginals.hyperpar = list(size = matrix(c(1, 1), ncol = 2L)),
    misc = list(configs = NULL)
  )
)
posterior <- joint_inla_validate_posterior_support(summary_only)
stopifnot(identical(posterior$method, "D_insufficient_saved_posterior"), identical(posterior$status, "WARNING"))

stopifnot(
  joint_inla_validate_presence_background_auc(c(3, 4), c(1, 2)) == 1,
  joint_inla_validate_presence_background_auc(c(1, 2), c(3, 4)) == 0,
  joint_inla_validate_presence_background_auc(c(1, 1), c(1, 1)) == 0.5,
  joint_inla_validate_presence_background_auc(c(1, 2), c(1, 2), c(1, 1)) == joint_inla_validate_presence_background_auc(c(1, 2), c(1, 2)),
  abs(joint_inla_validate_presence_background_auc(2, c(1, 3), c(0.9, 0.1)) - 0.9) < 1e-12
)
stopifnot(
  joint_inla_validate_weighted_percentile(0, c(1, 2, 3)) == 0,
  joint_inla_validate_weighted_percentile(4, c(1, 2, 3)) == 1,
  joint_inla_validate_weighted_percentile(2, c(1, 2, 3)) == 0.5,
  abs(joint_inla_validate_weighted_percentile(2, c(1, 2, 3), c(1, 2, 1)) - 0.5) < 1e-12,
  joint_inla_validate_weighted_percentile(2, c(1, 2, 3), c(1, 1, 1)) == joint_inla_validate_weighted_percentile(2, c(1, 2, 3))
)
boyce_positive <- joint_inla_validate_boyce(seq(0.5, 0.9, 0.1), seq(0.1, 0.9, 0.1), resolution = 100L)
boyce_reversed <- joint_inla_validate_boyce(seq(0.1, 0.5, 0.1), seq(0.1, 0.9, 0.1), resolution = 100L)
boyce_constant <- joint_inla_validate_boyce(rep(1, 3), rep(1, 3), resolution = 100L)
stopifnot(boyce_positive$cbi > 0, boyce_reversed$cbi < 0, is.na(boyce_constant$cbi),
          abs(joint_inla_validate_boyce(seq(0.5, 0.9, 0.1), seq(0.1, 0.9, 0.1), c(1, 1, 1, 1, 1, 1, 1, 1, 1))$cbi - boyce_positive$cbi) < 1e-12)

stage2_contract <- list(tier1 = data.frame(
  .row_id = c("obs_1", "obs_2", "quad_1", "quad_2", "quad_3", "quad_4"),
  source_obs_id = c(1L, 2L, NA_integer_, NA_integer_, NA_integer_, NA_integer_),
  Yi = c(1L, 1L, 0L, 0L, 0L, 0L),
  inside_domain = c(NA, NA, TRUE, TRUE, FALSE, TRUE),
  sc_Exp = c(0.0001, 0.0001, 2, 3, 0.0001, 4),
  is_censored = FALSE,
  is_test_point = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE),
  epiyear = 2024L, epiweek = c(1L, 2L, 1L, 2L, 3L, 3L), time_index = c(1L, 2L, 1L, 2L, 3L, 3L),
  x = 1:6, y = 1:6,
  stringsAsFactors = FALSE
))
fitted_contract <- data.frame(
  tier = rep("tier1", 6), source_row = 1:6, output_id = paste0("stack:", 1:6),
  fitted_mean = c(0.9, 0.8, 0.1, 0.2, 0.05, 0.3), stringsAsFactors = FALSE
)
reference <- joint_inla_validate_reference_background(stage2_contract, fitted_contract, expected_holdouts = 2L)
stopifnot(reference$background_rows == 3L, reference$unique_spatial_nodes == 3L,
          reference$occurrence_rows == 2L, reference$represented_weeks == 3L,
          all(reference$background$weight > 0), all(reference$background$inside_domain))

cat("Joint-INLA validation tests passed\n")
