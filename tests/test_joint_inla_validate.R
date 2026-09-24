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

cat("Joint-INLA validation tests passed\n")
