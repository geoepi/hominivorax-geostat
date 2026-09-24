# Pure validation helpers for the completed Stage 3B joint-INLA holdouts.
#
# This layer deliberately does not refit INLA, create validation backgrounds,
# project prediction grids, or substitute posterior-summary quantiles for
# observation-level predictive intervals.

`%||%` <- function(x, y) if (is.null(x)) y else x

joint_inla_validate_as_numeric <- function(x, name) {
  out <- suppressWarnings(as.numeric(x))
  if (length(out) && any(!is.finite(out) & !is.na(out))) stop(name, " contains non-finite values.")
  out
}

joint_inla_validate_clip_probability <- function(x, eps = 1e-12) {
  pmin(pmax(as.numeric(x), eps), 1 - eps)
}

joint_inla_validate_rank_auc <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  if (!length(observed) || any(!observed %in% c(0, 1))) return(NA_real_)
  n_positive <- sum(observed == 1)
  n_negative <- sum(observed == 0)
  if (!n_positive || !n_negative) return(NA_real_)
  ranks <- rank(predicted, ties.method = "average")
  (sum(ranks[observed == 1]) - n_positive * (n_positive + 1) / 2) /
    (n_positive * n_negative)
}

joint_inla_validate_brier <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted)
  if (!any(keep)) return(NA_real_)
  mean((observed[keep] - joint_inla_validate_clip_probability(predicted[keep]))^2)
}

joint_inla_validate_log_loss <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted)
  if (!any(keep)) return(NA_real_)
  p <- joint_inla_validate_clip_probability(predicted[keep])
  -mean(observed[keep] * log(p) + (1 - observed[keep]) * log1p(-p))
}

joint_inla_validate_binary_calibration <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted) & observed %in% c(0, 1)
  if (sum(keep) < 3L || length(unique(observed[keep])) < 2L) {
    return(c(intercept = NA_real_, slope = NA_real_))
  }
  x <- qlogis(joint_inla_validate_clip_probability(predicted[keep]))
  fit <- tryCatch(stats::glm(observed[keep] ~ x, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(c(intercept = NA_real_, slope = NA_real_))
  coefficients <- stats::coef(fit)
  c(intercept = unname(coefficients[[1L]] %||% NA_real_), slope = unname(coefficients[[2L]] %||% NA_real_))
}

joint_inla_validate_equal_frequency_bins <- function(observed, predicted, n_bins = 10L) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  if (!length(observed)) return(data.frame())
  n_bins <- min(as.integer(n_bins), length(observed))
  order_index <- order(predicted, seq_along(predicted))
  ranks <- integer(length(predicted))
  ranks[order_index] <- seq_along(order_index)
  bin <- pmin(n_bins, floor((ranks - 1L) * n_bins / length(predicted)) + 1L)
  result <- lapply(seq_len(n_bins), function(i) {
    selected <- bin == i
    data.frame(
      bin = i,
      n = sum(selected),
      predicted_mean = mean(predicted[selected]),
      observed_mean = mean(observed[selected]),
      observed_sum = sum(observed[selected]),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, result)
}

joint_inla_validate_count_calibration <- function(observed, predicted, n_bins = 10L) {
  bins <- joint_inla_validate_equal_frequency_bins(observed, predicted, n_bins)
  if (!nrow(bins)) return(bins)
  bins$observed_to_predicted <- bins$observed_mean / bins$predicted_mean
  bins$status <- ifelse(is.finite(bins$observed_to_predicted), "PASS", "WARNING")
  bins
}

joint_inla_validate_count_regression <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  keep <- is.finite(observed) & is.finite(predicted)
  if (sum(keep) < 3L || length(unique(predicted[keep])) < 2L) {
    return(c(intercept = NA_real_, slope = NA_real_))
  }
  fit <- tryCatch(stats::lm(observed[keep] ~ predicted[keep]), error = function(e) NULL)
  if (is.null(fit)) return(c(intercept = NA_real_, slope = NA_real_))
  coefficients <- stats::coef(fit)
  c(intercept = unname(coefficients[[1L]] %||% NA_real_), slope = unname(coefficients[[2L]] %||% NA_real_))
}

joint_inla_validate_metric_row <- function(tier, metric, value = NA_real_, status = "PASS", n = NA_integer_, details = "") {
  data.frame(tier = as.character(tier), metric = as.character(metric), value = as.numeric(value),
             status = as.character(status), n = as.integer(n), details = as.character(details),
             stringsAsFactors = FALSE)
}

joint_inla_validate_unresolved_metrics <- function(tier, metrics, n, details) {
  do.call(rbind, lapply(metrics, function(metric) joint_inla_validate_metric_row(
    tier, metric, NA_real_, "WARNING", n, details
  )))
}

joint_inla_validate_tier1 <- function(holdout, prediction_column = "fitted_mean", response_column = "response_observed") {
  required <- c(prediction_column, response_column)
  if (!all(required %in% names(holdout))) stop("Tier 1 holdout is missing: ", paste(setdiff(required, names(holdout)), collapse = ", "))
  observed <- as.numeric(holdout[[response_column]])
  predicted <- as.numeric(holdout[[prediction_column]])
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  details <- paste0(
    "Tier 1 validation requires a pre-specified evaluation-background/negative population. ",
    "The supplied holdout contains ", sum(keep), " positive detections and ", sum(observed == 0),
    " zero/background rows; active training backgrounds are not used and no negatives are invented."
  )
  if (!length(observed) || any(!observed %in% c(0, 1)) || length(unique(observed)) < 2L) {
    metrics <- joint_inla_validate_unresolved_metrics(
      "tier1", c("auc", "brier", "log_loss", "calibration_intercept", "calibration_slope"),
      length(observed), details
    )
    metrics <- rbind(
      joint_inla_validate_metric_row("tier1", "holdout_rows", length(observed), "PASS", length(observed), "Observed holdout rows available."),
      joint_inla_validate_metric_row("tier1", "positive_rows", sum(observed == 1), "PASS", length(observed), "All available Tier 1 holdouts are detections."),
      metrics
    )
    calibration <- data.frame(
      tier = "tier1", bin = NA_integer_, n = length(observed), predicted_mean = NA_real_, observed_mean = NA_real_,
      status = "WARNING", details = details, stringsAsFactors = FALSE
    )
    return(list(metrics = metrics, calibration = calibration, status = "WARNING", details = details,
                n = length(observed), positives = sum(observed == 1), negatives = sum(observed == 0)))
  }
  calibration <- joint_inla_validate_binary_calibration(observed, predicted)
  metrics <- rbind(
    joint_inla_validate_metric_row("tier1", "holdout_rows", length(observed), "PASS", length(observed), "Observed holdout rows available."),
    joint_inla_validate_metric_row("tier1", "positive_rows", sum(observed == 1), "PASS", length(observed), "Observed positive rows."),
    joint_inla_validate_metric_row("tier1", "negative_rows", sum(observed == 0), "PASS", length(observed), "Pre-specified evaluation-background rows."),
    joint_inla_validate_metric_row("tier1", "auc", joint_inla_validate_rank_auc(observed, predicted), "PASS", length(observed), "Mann-Whitney rank AUC."),
    joint_inla_validate_metric_row("tier1", "brier", joint_inla_validate_brier(observed, predicted), "PASS", length(observed), "Mean squared probability error."),
    joint_inla_validate_metric_row("tier1", "log_loss", joint_inla_validate_log_loss(observed, predicted), "PASS", length(observed), "Bernoulli log loss."),
    joint_inla_validate_metric_row("tier1", "calibration_intercept", calibration[["intercept"]], "PASS", length(observed), "Logistic calibration intercept."),
    joint_inla_validate_metric_row("tier1", "calibration_slope", calibration[["slope"]], "PASS", length(observed), "Logistic calibration slope.")
  )
  bins <- joint_inla_validate_equal_frequency_bins(observed, predicted, 10L)
  bins$tier <- "tier1"
  bins$status <- "PASS"
  bins$details <- "Approximately equal-frequency calibration bin."
  bins[, c("tier", "bin", "n", "predicted_mean", "observed_mean", "observed_sum", "status", "details"), drop = FALSE]
  list(metrics = metrics, calibration = bins, status = "PASS", details = "Tier 1 validation metrics computed.",
       n = length(observed), positives = sum(observed == 1), negatives = sum(observed == 0))
}

joint_inla_validate_tier2_scale <- function(holdout, tolerance = 0.05) {
  required <- c("exposure", "fitted_mean")
  if (!all(required %in% names(holdout))) {
    return(list(status = "WARNING", scale = NA_character_, expected_count = rep(NA_real_, nrow(holdout)),
                details = paste0("Tier 2 holdout is missing: ", paste(setdiff(required, names(holdout)), collapse = ", ")),
                ratio_median = NA_real_))
  }
  exposure <- as.numeric(holdout[["exposure"]])
  intensity <- as.numeric(holdout[["fitted_mean"]])
  if ("linear_predictor_mean" %in% names(holdout)) {
    lp <- as.numeric(holdout[["linear_predictor_mean"]])
    ratio <- intensity / exp(lp)
    ratio <- ratio[is.finite(ratio) & ratio > 0]
  } else {
    ratio <- numeric()
  }
  ratio_median <- if (length(ratio)) stats::median(ratio) else NA_real_
  rate_scale <- length(ratio) && is.finite(ratio_median) && abs(log(ratio_median)) <= log1p(tolerance)
  if (!rate_scale || any(!is.finite(exposure)) || any(exposure <= 0) || any(!is.finite(intensity))) {
    return(list(status = "WARNING", scale = "unresolved", expected_count = rep(NA_real_, nrow(holdout)),
                details = "The saved fitted value could not be proven to be a response-rate/intensity with finite positive exposure.",
                ratio_median = ratio_median))
  }
  list(status = "PASS", scale = "intensity_rate", expected_count = exposure * intensity,
       details = paste0("fitted_mean / exp(linear_predictor_mean) median = ", format(ratio_median, digits = 8),
                        "; expected count = terrestrial-area exposure * fitted intensity."),
       ratio_median = ratio_median)
}

joint_inla_validate_tier2 <- function(holdout, response_column = "response_observed") {
  if (!response_column %in% names(holdout)) stop("Tier 2 holdout is missing ", response_column, ".")
  observed <- as.numeric(holdout[[response_column]])
  scale <- joint_inla_validate_tier2_scale(holdout)
  predicted <- scale$expected_count
  keep <- is.finite(observed) & is.finite(predicted)
  details <- scale$details
  if (!any(keep)) {
    metrics <- rbind(
      joint_inla_validate_metric_row("tier2", "holdout_rows", sum(is.finite(observed)), "PASS", sum(is.finite(observed)), "Observed count holdout rows available."),
      joint_inla_validate_metric_row("tier2", "zero_count_rows", sum(observed == 0, na.rm = TRUE), "PASS", sum(is.finite(observed)), "No zero-count holdouts are expected under the production selection contract."),
      joint_inla_validate_unresolved_metrics("tier2", c("mae", "rmse", "pearson", "spearman", "calibration_mean_ratio", "calibration_intercept", "calibration_slope"), sum(is.finite(observed)), details)
    )
    calibration <- data.frame(tier = "tier2", bin = NA_integer_, n = sum(is.finite(observed)), predicted_mean = NA_real_, observed_mean = NA_real_, observed_to_predicted = NA_real_, status = "WARNING", details = details, stringsAsFactors = FALSE)
    return(list(metrics = metrics, calibration = calibration, predicted = predicted, scale = scale, status = "WARNING", details = details))
  }
  y <- observed[keep]
  p <- predicted[keep]
  calibration <- joint_inla_validate_count_regression(y, p)
  mean_ratio <- mean(y) / mean(p)
  metrics <- rbind(
    joint_inla_validate_metric_row("tier2", "holdout_rows", length(y), "PASS", length(y), "Observed count holdout rows available."),
    joint_inla_validate_metric_row("tier2", "zero_count_rows", sum(y == 0), if (any(y == 0)) "WARNING" else "PASS", length(y), "Count holdouts are checked on the observed-count scale."),
    joint_inla_validate_metric_row("tier2", "mae", mean(abs(y - p)), "PASS", length(y), "Mean absolute error on expected-count scale."),
    joint_inla_validate_metric_row("tier2", "rmse", sqrt(mean((y - p)^2)), "PASS", length(y), "Root mean squared error on expected-count scale."),
    joint_inla_validate_metric_row("tier2", "pearson", suppressWarnings(stats::cor(y, p, method = "pearson")), "PASS", length(y), "Pearson correlation on expected-count scale."),
    joint_inla_validate_metric_row("tier2", "spearman", suppressWarnings(stats::cor(y, p, method = "spearman")), "PASS", length(y), "Spearman correlation on expected-count scale."),
    joint_inla_validate_metric_row("tier2", "calibration_mean_ratio", mean_ratio, "PASS", length(y), "Mean observed count divided by mean expected count."),
    joint_inla_validate_metric_row("tier2", "calibration_intercept", calibration[["intercept"]], "PASS", length(y), "Ordinary least-squares count calibration intercept."),
    joint_inla_validate_metric_row("tier2", "calibration_slope", calibration[["slope"]], "PASS", length(y), "Ordinary least-squares count calibration slope.")
  )
  bins <- joint_inla_validate_count_calibration(y, p, 10L)
  bins$tier <- "tier2"
  bins$details <- "Approximately equal-frequency calibration bin on expected-count scale."
  bins[, c("tier", "bin", "n", "predicted_mean", "observed_mean", "observed_sum", "observed_to_predicted", "status", "details"), drop = FALSE]
  list(metrics = metrics, calibration = bins, predicted = predicted, scale = scale, status = "PASS", details = details)
}

joint_inla_validate_posterior_support <- function(fit_artifact) {
  fit <- if (is.list(fit_artifact) && !is.null(fit_artifact$fit)) fit_artifact$fit else fit_artifact
  has_configs <- is.list(fit$misc) && !is.null(fit$misc$configs)
  has_lp_marginal <- is.list(fit$marginals.linear.predictor) && length(fit$marginals.linear.predictor) > 0L
  has_hyper_marginal <- is.list(fit$marginals.hyperpar) && length(fit$marginals.hyperpar) > 0L
  method <- if (has_configs) "A_joint_posterior_sampling" else if (has_lp_marginal && has_hyper_marginal) "B_marginal_monte_carlo" else "D_insufficient_saved_posterior"
  details <- if (method == "A_joint_posterior_sampling") {
    "Saved INLA configs support joint posterior sampling."
  } else if (method == "B_marginal_monte_carlo") {
    "Saved predictor and hyperparameter marginals support marginal Monte Carlo; joint dependence is not retained."
  } else {
    "Saved fit has summary predictors and hyperparameter marginals but no predictor marginals or misc$configs; genuine observation-level negative-binomial predictive intervals cannot be reconstructed without an authorized refit or additional posterior artifact."
  }
  list(method = method, has_configs = has_configs, has_linear_predictor_marginals = has_lp_marginal,
       has_hyperparameter_marginals = has_hyper_marginal, status = if (method == "D_insufficient_saved_posterior") "WARNING" else "PASS", details = details)
}

joint_inla_validate_unresolved_intervals <- function(holdout, predicted, posterior_support, details = posterior_support$details) {
  data.frame(
    output_id = if ("output_id" %in% names(holdout)) as.character(holdout$output_id) else paste0("row:", seq_len(nrow(holdout))),
    tier = "tier2",
    response_observed = as.numeric(holdout$response_observed),
    expected_count = as.numeric(predicted),
    lower_0.025 = NA_real_, upper_0.975 = NA_real_,
    method = posterior_support$method,
    status = "WARNING", details = as.character(details),
    stringsAsFactors = FALSE
  )
}

joint_inla_validate_audit_row <- function(section, check, status, observed, expected, details, blocking = FALSE) {
  data.frame(section = as.character(section), check = as.character(check), status = as.character(status),
             observed = as.character(observed), expected = as.character(expected),
             blocking = isTRUE(blocking), details = as.character(details), stringsAsFactors = FALSE)
}

joint_inla_validate_audit <- function(holdout, stage2, tier1, tier2, posterior_support, expected_counts = NULL) {
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- joint_inla_validate_audit_row(...)
  all_true <- function(x) length(x) > 0L && all(!is.na(x) & as.logical(x))
  stage2_counts <- vapply(c("tier1", "tier2"), function(tier) {
    x <- stage2[[tier]]
    sum(isTRUE(x$is_test_point) | (!is.null(x$is_test_point) & x$is_test_point %in% TRUE), na.rm = TRUE)
  }, integer(1L))
  holdout_counts <- table(factor(holdout$tier, levels = c("tier1", "tier2")))
  add("inputs", "holdout_file_rows", "PASS", nrow(holdout), nrow(holdout), "Existing holdout prediction CSV was read; it was not overwritten.")
  add("inputs", "stage2_holdout_counts", if (identical(as.integer(stage2_counts), as.integer(holdout_counts))) "PASS" else "FAIL",
      paste(as.integer(stage2_counts), collapse = "/"), paste(as.integer(holdout_counts), collapse = "/"),
      "Stage 2 is_test_point counts reconcile to the extracted holdout CSV.", blocking = TRUE)
  flag_column <- if ("source_is_test_point" %in% names(holdout)) "source_is_test_point" else if ("is_test_point" %in% names(holdout)) "is_test_point" else NULL
  add("inputs", "holdout_rows_are_test_points", if (!is.null(flag_column) && all_true(holdout[[flag_column]])) "PASS" else "FAIL",
      if (is.null(flag_column)) "missing" else sum(holdout[[flag_column]] %in% TRUE, na.rm = TRUE), nrow(holdout),
      "Every validation row must be explicitly marked as a Stage 2 holdout; active training rows are excluded.", blocking = TRUE)
  response_column <- if ("source_response_observed" %in% names(holdout)) "source_response_observed" else "response_observed"
  add("inputs", "holdout_response_finite", if (all(is.finite(holdout[[response_column]]))) "PASS" else "FAIL",
      sum(is.finite(holdout[[response_column]])), nrow(holdout), "Observed responses are traced to the extracted Stage 2 source response.", blocking = TRUE)
  family_ok <- "family" %in% names(holdout) && all(holdout$family[holdout$tier == "tier1"] == "binomial") && all(holdout$family[holdout$tier == "tier2"] == "nbinomial")
  add("inputs", "family_labels", if (family_ok) "PASS" else "FAIL", if ("family" %in% names(holdout)) paste(unique(holdout$family), collapse = "/") else "missing", "binomial/nbinomial", "Holdout rows retain the production likelihood-family labels.", blocking = TRUE)
  add("tier1", "evaluation_negative_population", tier1$status, tier1$negatives, "at least 1", tier1$details, blocking = tier1$status != "PASS")
  add("tier1", "required_metrics", if (all(tier1$metrics$status == "PASS")) "PASS" else "WARNING",
      paste(unique(tier1$metrics$status), collapse = "/"), "PASS", tier1$details, blocking = FALSE)
  add("tier2", "expected_count_scale", tier2$scale$status, tier2$scale$scale, "intensity_rate", tier2$scale$details, blocking = tier2$scale$status != "PASS")
  add("tier2", "required_point_metrics", if (all(tier2$metrics$status[tier2$metrics$metric %in% c("mae", "rmse", "pearson", "spearman")] == "PASS")) "PASS" else "WARNING",
      paste(unique(tier2$metrics$status), collapse = "/"), "PASS", tier2$details)
  add("tier2", "posterior_predictive_intervals", posterior_support$status, posterior_support$method,
      "A_joint_posterior_sampling or B_marginal_monte_carlo", posterior_support$details, blocking = posterior_support$status != "PASS")
  add("scope", "stage3b_refit", "PASS", "not run", "not run", "Validation reads completed artifacts only.")
  add("scope", "prediction_grid_projection", "PASS", "not run", "not run", "Validation uses held-out response rows only.")
  add("scope", "surface_or_biological_interpretation", "PASS", "not run", "not run", "No surfaces or biological interpretation are produced.")
  do.call(rbind, rows)
}

joint_inla_validate_details <- function(audit, tier1, tier2, posterior_support, paths) {
  counts <- table(audit$status)
  c(
    "Formal holdout validation details",
    paste0("Generated: ", format(Sys.time(), tz = "UTC")),
    paste0("Audit PASS/WARNING/FAIL: ", paste(names(counts), as.integer(counts), collapse = "/")),
    "",
    paste0("Tier 1: ", tier1$details),
    paste0("Tier 2 scale: ", tier2$scale$details),
    paste0("Tier 2 posterior interval support: ", posterior_support$details),
    "",
    "Scope: no Stage 3B refit, no model/prior/SPDE/copy/random-walk change, no prediction-grid projection, no surfaces, no biological interpretation.",
    "",
    paste0("Metrics: ", paths[["metrics"]]),
    paste0("Tier 1 calibration: ", paths[["tier1_calibration"]]),
    paste0("Tier 2 calibration: ", paths[["tier2_calibration"]]),
    paste0("Tier 2 predictive intervals: ", paths[["tier2_intervals"]]),
    paste0("Audit: ", paths[["audit"]])
  )
}
