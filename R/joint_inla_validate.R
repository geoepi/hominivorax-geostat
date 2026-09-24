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

joint_inla_validate_audit <- function(holdout, stage2, tier1_presence, tier2, posterior_support, expected_counts = NULL, reference_background = NULL) {
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
  background_ok <- !is.null(reference_background) && identical(reference_background$status, "PASS")
  add("tier1", "withheld_presence_population", if (background_ok && reference_background$occurrence_rows == 6638L) "PASS" else "FAIL",
      if (is.null(reference_background)) "missing" else reference_background$occurrence_rows, 6638, "Stage 2 test points with occurrence provenance; background rows are not used as confirmed absence.", blocking = TRUE)
  add("tier1", "reference_background_identified", if (background_ok) "PASS" else "FAIL",
      if (is.null(reference_background)) "missing" else reference_background$background_rows, "identified", "Reference background is established from Yi=0 quadrature provenance, not response_observed alone.", blocking = TRUE)
  add("tier1", "background_terrestrial_support", if (background_ok && reference_background$background_rows > 0) "PASS" else "FAIL",
      if (is.null(reference_background)) "missing" else reference_background$background_rows, "positive", "Rows are inside_domain terrestrial integration support and exclude outside-domain rows.", blocking = TRUE)
  add("tier1", "background_biological_status", "PASS", "unknown", "unknown / not treated as absence", "Integration/quadrature rows represent availability support; no biological absence label is assigned.")
  add("tier1", "background_weighting", if (background_ok && is.finite(reference_background$total_weight) && reference_background$weight_min > 0) "PASS" else "FAIL",
      if (is.null(reference_background)) "missing" else paste(reference_background$weight_min, reference_background$weight_max, sep = "/"), "finite positive sc_Exp", "Area-weighted calculations use retained positive terrestrial integration weights.", blocking = TRUE)
  add("tier1", "PB_AUC_area_weighted", if (is.finite(tier1_presence$weighted_auc)) "PASS" else "WARNING", tier1_presence$weighted_auc, "finite", "Weighted presence-background AUC with half credit for ties.")
  add("tier1", "PB_AUC_unweighted", if (is.finite(tier1_presence$unweighted_auc)) "PASS" else "WARNING", tier1_presence$unweighted_auc, "finite", "Unweighted presence-background AUC with half credit for ties.")
  add("tier1", "continuous_boyce_area_weighted", if (is.finite(tier1_presence$weighted_cbi)) "PASS" else "WARNING", tier1_presence$weighted_cbi, "finite", "Area-weighted moving-window Continuous Boyce Index.")
  add("tier1", "continuous_boyce_unweighted", if (is.finite(tier1_presence$unweighted_cbi)) "PASS" else "WARNING", tier1_presence$unweighted_cbi, "finite", "Unweighted moving-window Continuous Boyce Index.")
  add("tier1", "same_week_percentile_coverage", if (all(is.finite(tier1_presence$percentiles$weighted_percentile)) && all(is.finite(tier1_presence$percentiles$unweighted_percentile))) "PASS" else "FAIL",
      sum(is.finite(tier1_presence$percentiles$weighted_percentile) & is.finite(tier1_presence$percentiles$unweighted_percentile)), nrow(tier1_presence$percentiles), "Exact year/week/time matching for occurrence-level presence-background percentiles.", blocking = TRUE)
  add("tier1", "required_presence_background_metrics", if (all(tier1_presence$metrics$status == "PASS")) "PASS" else "WARNING",
      paste(unique(tier1_presence$metrics$status), collapse = "/"), "PASS", tier1_presence$details, blocking = FALSE)
  add("tier2", "expected_count_scale", tier2$scale$status, tier2$scale$scale, "intensity_rate", tier2$scale$details, blocking = tier2$scale$status != "PASS")
  add("tier2", "required_point_metrics", if (all(tier2$metrics$status[tier2$metrics$metric %in% c("mae", "rmse", "pearson", "spearman")] == "PASS")) "PASS" else "WARNING",
      paste(unique(tier2$metrics$status), collapse = "/"), "PASS", tier2$details)
  add("tier2", "posterior_predictive_intervals", posterior_support$status, posterior_support$method,
      "A_joint_posterior_sampling or B_marginal_monte_carlo", posterior_support$details, blocking = FALSE)
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
    paste0("Tier 1 weighted PB-AUC: ", format(tier1$weighted_auc, digits = 10), "; unweighted PB-AUC: ", format(tier1$unweighted_auc, digits = 10)),
    paste0("Tier 1 weighted CBI: ", format(tier1$weighted_cbi, digits = 10), "; unweighted CBI: ", format(tier1$unweighted_cbi, digits = 10)),
    paste0("Tier 2 scale: ", tier2$scale$details),
    paste0("Tier 2 posterior interval support: ", posterior_support$details),
    "",
    "Scope: no Stage 3B refit, no model/prior/SPDE/copy/random-walk change, no prediction-grid projection, no surfaces, no biological interpretation.",
    "",
    paste0("Metrics: ", paths[["metrics"]]),
    paste0("Tier 1 presence-background metrics: ", paths[["tier1_metrics"]]),
    paste0("Tier 1 Boyce curve: ", paths[["tier1_boyce_curve"]]),
    paste0("Tier 1 occurrence percentiles: ", paths[["tier1_percentiles"]]),
    paste0("Tier 1 weekly rank summary: ", paths[["tier1_weekly"]]),
    paste0("Tier 2 calibration: ", paths[["tier2_calibration"]]),
    paste0("Tier 2 predictive intervals: ", paths[["tier2_intervals"]]),
    paste0("Audit: ", paths[["audit"]])
  )
}

# Presence-background validation ------------------------------------------------

joint_inla_validate_source_origin <- function(source) {
  required <- c(".row_id", "Yi", "source_obs_id")
  missing <- setdiff(required, names(source))
  if (length(missing)) stop("Tier 1 source rows are missing provenance columns: ", paste(missing, collapse = ", "))
  occurrence <- source$Yi == 1L & !is.na(source$source_obs_id) & grepl("^obs_", source$.row_id)
  quadrature <- source$Yi == 0L & is.na(source$source_obs_id) & grepl("^quad_", source$.row_id)
  list(occurrence = occurrence, quadrature = quadrature, unclassified = !(occurrence | quadrature))
}

joint_inla_validate_reference_background <- function(stage2, fitted, expected_holdouts = 6638L) {
  if (!is.list(stage2) || !is.data.frame(stage2$tier1)) stop("Stage 2 artifact must contain a Tier 1 data frame.")
  source <- stage2$tier1
  required <- c("inside_domain", "sc_Exp", "is_censored", "is_test_point", "epiyear", "epiweek", "time_index", "x", "y")
  missing <- setdiff(required, names(source))
  if (length(missing)) stop("Cannot establish the Tier 1 terrestrial reference-background contract; missing: ", paste(missing, collapse = ", "))
  if (!is.data.frame(fitted) || !all(c("tier", "source_row", "fitted_mean") %in% names(fitted))) stop("Aligned fitted extraction is missing the established row-index fields.")
  tier1_fitted <- fitted[fitted$tier == "tier1", , drop = FALSE]
  if (nrow(tier1_fitted) != nrow(source) || !identical(as.integer(tier1_fitted$source_row), seq_len(nrow(source)))) {
    stop("Tier 1 fitted predictions cannot be mapped unambiguously to Stage 2 source rows.")
  }
  origin <- joint_inla_validate_source_origin(source)
  if (any(origin$unclassified)) stop("Tier 1 source rows contain unclassified occurrence/background provenance rows: ", sum(origin$unclassified))
  if (any(origin$quadrature & source$is_test_point %in% TRUE)) stop("Tier 1 quadrature/background rows are marked as holdouts; background provenance cannot be used safely.")
  occurrence <- origin$occurrence & source$is_test_point %in% TRUE & !source$is_censored
  if (sum(occurrence) != as.integer(expected_holdouts)) stop("Tier 1 withheld occurrence count is ", sum(occurrence), "; expected ", expected_holdouts, ".")
  valid_terrestrial <- origin$quadrature & source$inside_domain %in% TRUE & !source$is_censored &
    is.finite(source$sc_Exp) & source$sc_Exp > 0 & is.finite(tier1_fitted$fitted_mean)
  if (!any(valid_terrestrial)) stop("No valid terrestrial Tier 1 integration/background rows remain after provenance, domain, censoring, weight, and prediction checks.")
  if (any(origin$quadrature & source$inside_domain %in% TRUE & !source$is_censored &
          (!is.finite(source$sc_Exp) | source$sc_Exp <= 0))) {
    stop("Terrestrial Tier 1 integration/background rows contain invalid or nonpositive integration weights.")
  }
  occurrence_rows <- cbind(
    source[occurrence, c("epiyear", "epiweek", "time_index", "x", "y", "source_obs_id"), drop = FALSE],
    output_id = tier1_fitted$output_id[occurrence], prediction = tier1_fitted$fitted_mean[occurrence],
    source_row = tier1_fitted$source_row[occurrence]
  )
  occurrence_rows$holdout_id <- paste0("source_obs_id:", occurrence_rows$source_obs_id)
  background_rows <- cbind(
    source[valid_terrestrial, c("epiyear", "epiweek", "time_index", "x", "y", "sc_Exp", "inside_domain"), drop = FALSE],
    output_id = tier1_fitted$output_id[valid_terrestrial], prediction = tier1_fitted$fitted_mean[valid_terrestrial],
    source_row = tier1_fitted$source_row[valid_terrestrial]
  )
  names(background_rows)[names(background_rows) == "sc_Exp"] <- "weight"
  background_rows$spatial_node_id <- paste(format(background_rows$x, digits = 17), format(background_rows$y, digits = 17), sep = "|")
  occurrence_rows$prediction <- as.numeric(occurrence_rows$prediction)
  background_rows$prediction <- as.numeric(background_rows$prediction)
  weeks <- unique(paste(background_rows$epiyear, background_rows$epiweek, background_rows$time_index, sep = "|"))
  occurrence_weeks <- paste(occurrence_rows$epiyear, occurrence_rows$epiweek, occurrence_rows$time_index, sep = "|")
  if (!all(occurrence_weeks %in% weeks)) stop("Tier 1 reference background does not cover every held-out occurrence week.")
  list(
    occurrence = occurrence_rows,
    background = background_rows,
    status = "PASS",
    background_rule = "Yi == 0, source_obs_id is NA, .row_id begins quad_, inside_domain == TRUE, is_censored == FALSE, sc_Exp > 0, finite extracted fitted prediction",
    background_rows = nrow(background_rows),
    unique_spatial_nodes = length(unique(background_rows$spatial_node_id)),
    represented_weeks = length(weeks),
    total_weight = sum(background_rows$weight),
    weight_min = min(background_rows$weight),
    weight_max = max(background_rows$weight),
    weights_vary = diff(range(background_rows$weight)) > 1e-12,
    occurrence_rows = nrow(occurrence_rows),
    occurrence_weeks = length(unique(occurrence_weeks))
  )
}

joint_inla_validate_weighted_percentile <- function(score, background_score, background_weight = NULL) {
  score <- as.numeric(score)
  background_score <- as.numeric(background_score)
  if (is.null(background_weight)) background_weight <- rep(1, length(background_score))
  background_weight <- as.numeric(background_weight)
  keep <- is.finite(background_score) & is.finite(background_weight) & background_weight > 0
  if (!is.finite(score) || !any(keep)) return(NA_real_)
  background_score <- background_score[keep]
  background_weight <- background_weight[keep]
  order_index <- order(background_score)
  score_ordered <- background_score[order_index]
  weight_ordered <- background_weight[order_index]
  cumulative <- cumsum(weight_ordered)
  index <- findInterval(score, score_ordered)
  less <- if (!index) 0 else cumulative[index]
  equal_index <- which(score_ordered == score)
  equal <- if (length(equal_index)) sum(weight_ordered[equal_index]) else 0
  total <- sum(weight_ordered)
  (less - equal + equal / 2) / total
}

joint_inla_validate_presence_background_auc <- function(presence_score, background_score, background_weight = NULL) {
  presence_score <- as.numeric(presence_score)
  background_score <- as.numeric(background_score)
  if (is.null(background_weight)) background_weight <- rep(1, length(background_score))
  background_weight <- as.numeric(background_weight)
  presence_score <- presence_score[is.finite(presence_score)]
  keep <- is.finite(background_score) & is.finite(background_weight) & background_weight > 0
  background_score <- background_score[keep]
  background_weight <- background_weight[keep]
  if (!length(presence_score) || !length(background_score)) return(NA_real_)
  order_index <- order(background_score)
  sorted_score <- background_score[order_index]
  sorted_weight <- background_weight[order_index]
  run_start <- c(TRUE, sorted_score[-1L] != sorted_score[-length(sorted_score)])
  run_start_index <- which(run_start)
  run_end_index <- c(run_start_index[-1L] - 1L, length(sorted_score))
  cumulative_rows <- cumsum(sorted_weight)
  previous_cumulative <- c(0, cumulative_rows[run_end_index[-length(run_end_index)]])
  unique_score <- sorted_score[run_start_index]
  score_weight <- cumulative_rows[run_end_index] - previous_cumulative
  cumulative <- cumsum(score_weight)
  total_weight <- sum(score_weight)
  contributions <- vapply(presence_score, function(value) {
    index <- findInterval(value, unique_score)
    less <- if (!index) 0 else cumulative[index]
    equal_index <- match(value, unique_score, nomatch = 0L)
    equal <- if (equal_index) score_weight[equal_index] else 0
    (less - equal + equal / 2) / total_weight
  }, numeric(1L))
  mean(contributions)
}

joint_inla_validate_boyce <- function(presence_score, background_score, background_weight = NULL,
                                      weighting = "unweighted", width_fraction = 0.1, resolution = 100L) {
  presence_score <- as.numeric(presence_score)
  background_score <- as.numeric(background_score)
  if (is.null(background_weight)) background_weight <- rep(1, length(background_score))
  background_weight <- as.numeric(background_weight)
  keep_presence <- is.finite(presence_score)
  keep_background <- is.finite(background_score) & is.finite(background_weight) & background_weight > 0
  presence_score <- presence_score[keep_presence]
  background_score <- background_score[keep_background]
  background_weight <- background_weight[keep_background]
  if (!length(presence_score) || !length(background_score)) {
    return(list(cbi = NA_real_, status = "WARNING", details = "Missing finite presence or reference-background predictions.", curve = data.frame()))
  }
  prediction_range <- range(c(presence_score, background_score))
  span <- diff(prediction_range)
  if (!is.finite(span) || span <= 0) {
    return(list(cbi = NA_real_, status = "WARNING", details = "Presence/background prediction distribution is degenerate.", curve = data.frame()))
  }
  width <- span * as.numeric(width_fraction)
  midpoint <- seq(prediction_range[[1L]], prediction_range[[2L]], length.out = as.integer(resolution))
  total_weight <- sum(background_weight)
  curve <- do.call(rbind, lapply(seq_along(midpoint), function(i) {
    lower <- midpoint[[i]] - width / 2
    upper <- midpoint[[i]] + width / 2
    in_presence <- presence_score >= lower & presence_score <= upper
    in_background <- background_score >= lower & background_score <= upper
    background_weight_in_window <- sum(background_weight[in_background])
    expected <- background_weight_in_window / total_weight
    fraction_presence <- sum(in_presence) / length(presence_score)
    data.frame(
      weighting = weighting, window_id = i, lower_prediction_bound = lower, upper_prediction_bound = upper,
      window_midpoint = midpoint[[i]], n_withheld_presences = sum(in_presence), n_background_rows = sum(in_background),
      background_integration_weight = background_weight_in_window, fraction_withheld_presences = fraction_presence,
      expected_background_fraction = expected,
      p_over_e = if (expected > 0) fraction_presence / expected else NA_real_,
      retained_for_cbi = FALSE, duplicate_p_over_e = FALSE, stringsAsFactors = FALSE
    )
  }))
  valid <- is.finite(curve$p_over_e) & curve$expected_background_fraction > 0
  if (any(valid)) {
    valid_index <- which(valid)
    curve$duplicate_p_over_e[valid_index[-1L]] <- FALSE
    if (length(valid_index) > 1L) curve$duplicate_p_over_e[valid_index[-1L]] <- curve$p_over_e[valid_index[-1L]] == curve$p_over_e[valid_index[-length(valid_index)]]
    retained <- valid & !curve$duplicate_p_over_e
    curve$retained_for_cbi <- retained
  } else {
    retained <- valid
  }
  cbi <- if (sum(retained) >= 2L) suppressWarnings(stats::cor(curve$window_midpoint[retained], curve$p_over_e[retained], method = "spearman")) else NA_real_
  status <- if (is.finite(cbi)) "PASS" else "WARNING"
  details <- if (is.finite(cbi)) paste0("Moving-window Boyce index with width=prediction_range/10, resolution=", resolution, ", Spearman correlation, successive duplicate P/E values removed.") else "Fewer than two valid nonduplicate P/E windows remained for the Boyce correlation."
  list(cbi = cbi, status = status, details = details, curve = curve)
}

joint_inla_validate_same_week_percentiles <- function(occurrence, background) {
  occurrence$key <- paste(occurrence$epiyear, occurrence$epiweek, occurrence$time_index, sep = "|")
  background$key <- paste(background$epiyear, background$epiweek, background$time_index, sep = "|")
  groups <- split(seq_len(nrow(background)), background$key)
  references <- lapply(groups, function(indices) {
    bg <- background[indices, , drop = FALSE]
    keep <- is.finite(bg$prediction) & is.finite(bg$weight) & bg$weight > 0
    score <- as.numeric(bg$prediction[keep])
    weight <- as.numeric(bg$weight[keep])
    if (!length(score)) return(list(score = numeric(), weighted_cumulative = numeric(), weighted_total = 0, unweighted_cumulative = numeric(), unweighted_total = 0))
    order_index <- order(score)
    score <- score[order_index]
    weight <- weight[order_index]
    run_start <- c(TRUE, score[-1L] != score[-length(score)])
    run_start_index <- which(run_start)
    run_end_index <- c(run_start_index[-1L] - 1L, length(score))
    cumulative_rows <- cumsum(weight)
    previous_cumulative <- c(0, cumulative_rows[run_end_index[-length(run_end_index)]])
    unique_score <- score[run_start_index]
    weighted_score_weight <- cumulative_rows[run_end_index] - previous_cumulative
    list(
      score = unique_score,
      weighted_cumulative = cumsum(weighted_score_weight),
      weighted_score_weight = weighted_score_weight,
      weighted_total = sum(weighted_score_weight),
      unweighted_cumulative = cumsum(tabulate(match(score, unique_score), nbins = length(unique_score))),
      unweighted_score_weight = tabulate(match(score, unique_score), nbins = length(unique_score)),
      unweighted_total = length(score)
    )
  })
  percentile_from_reference <- function(value, reference, weighting) {
    if (!is.finite(value) || !length(reference$score)) return(NA_real_)
    cumulative <- reference[[paste0(weighting, "_cumulative")]]
    score_weight <- reference[[paste0(weighting, "_score_weight")]]
    total <- reference[[paste0(weighting, "_total")]]
    index <- findInterval(value, reference$score)
    less <- if (!index) 0 else cumulative[index]
    equal_index <- match(value, reference$score, nomatch = 0L)
    equal <- if (equal_index) score_weight[equal_index] else 0
    (less - equal + equal / 2) / total
  }
  rows <- lapply(seq_len(nrow(occurrence)), function(i) {
    indices <- groups[[occurrence$key[[i]]]]
    if (is.null(indices) || !length(indices)) {
      return(data.frame(output_id = occurrence$output_id[[i]], holdout_id = occurrence$holdout_id[[i]],
                        epiyear = occurrence$epiyear[[i]], epiweek = occurrence$epiweek[[i]], time_index = occurrence$time_index[[i]],
                        prediction = occurrence$prediction[[i]], background_node_count = 0L, total_background_integration_weight = 0,
                        weighted_percentile = NA_real_, unweighted_percentile = NA_real_, stringsAsFactors = FALSE))
    }
    bg <- background[indices, , drop = FALSE]
    data.frame(output_id = occurrence$output_id[[i]], holdout_id = occurrence$holdout_id[[i]],
               epiyear = occurrence$epiyear[[i]], epiweek = occurrence$epiweek[[i]], time_index = occurrence$time_index[[i]],
               prediction = occurrence$prediction[[i]], background_node_count = nrow(bg),
               total_background_integration_weight = sum(bg$weight),
               weighted_percentile = percentile_from_reference(occurrence$prediction[[i]], references[[occurrence$key[[i]]]], "weighted"),
               unweighted_percentile = percentile_from_reference(occurrence$prediction[[i]], references[[occurrence$key[[i]]]], "unweighted"),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

joint_inla_validate_percentile_summary <- function(values, weighting) {
  values <- as.numeric(values)
  values <- values[is.finite(values)]
  if (!length(values)) return(data.frame(weighting = weighting, metric = character(), value = numeric(), n = integer(), stringsAsFactors = FALSE))
  data.frame(
    weighting = weighting,
    metric = c("n", "mean", "sd", "min", "q05", "q25", "median", "q75", "q95", "max", "fraction_above_0.50", "fraction_above_0.75", "fraction_above_0.90"),
    value = c(length(values), mean(values), stats::sd(values), min(values), stats::quantile(values, 0.05, names = FALSE), stats::quantile(values, 0.25, names = FALSE), stats::median(values), stats::quantile(values, 0.75, names = FALSE), stats::quantile(values, 0.95, names = FALSE), max(values), mean(values > 0.50), mean(values > 0.75), mean(values > 0.90)),
    n = length(values), stringsAsFactors = FALSE
  )
}

joint_inla_validate_weekly_rank_summary <- function(percentiles) {
  keys <- unique(percentiles[c("epiyear", "epiweek", "time_index")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    selected <- percentiles$epiyear == keys$epiyear[[i]] & percentiles$epiweek == keys$epiweek[[i]] & percentiles$time_index == keys$time_index[[i]]
    x <- percentiles[selected, , drop = FALSE]
    data.frame(epiyear = keys$epiyear[[i]], epiweek = keys$epiweek[[i]], time_index = keys$time_index[[i]],
               n_withheld_occurrences = nrow(x), n_background_rows = unique(x$background_node_count)[[1L]],
               total_background_integration_weight = unique(x$total_background_integration_weight)[[1L]],
               mean_weighted_percentile = mean(x$weighted_percentile, na.rm = TRUE), median_weighted_percentile = stats::median(x$weighted_percentile, na.rm = TRUE),
               mean_unweighted_percentile = mean(x$unweighted_percentile, na.rm = TRUE), median_unweighted_percentile = stats::median(x$unweighted_percentile, na.rm = TRUE),
               within_week_weighted_PB_AUC = mean(x$weighted_percentile, na.rm = TRUE),
               within_week_unweighted_PB_AUC = mean(x$unweighted_percentile, na.rm = TRUE), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

joint_inla_validate_tier1_presence_background <- function(reference_background) {
  occurrence <- reference_background$occurrence
  background <- reference_background$background
  weighted_auc <- joint_inla_validate_presence_background_auc(occurrence$prediction, background$prediction, background$weight)
  unweighted_auc <- joint_inla_validate_presence_background_auc(occurrence$prediction, background$prediction)
  weighted_boyce <- joint_inla_validate_boyce(occurrence$prediction, background$prediction, background$weight, "area_weighted")
  unweighted_boyce <- joint_inla_validate_boyce(occurrence$prediction, background$prediction, NULL, "unweighted")
  percentiles <- joint_inla_validate_same_week_percentiles(occurrence, background)
  weekly <- joint_inla_validate_weekly_rank_summary(percentiles)
  weighted_values <- percentiles$weighted_percentile[is.finite(percentiles$weighted_percentile)]
  unweighted_values <- percentiles$unweighted_percentile[is.finite(percentiles$unweighted_percentile)]
  if (length(weighted_values) != nrow(occurrence) || length(unweighted_values) != nrow(occurrence)) stop("Not every held-out occurrence received a valid same-week reference-background percentile.")
  summary <- rbind(joint_inla_validate_percentile_summary(weighted_values, "area_weighted"), joint_inla_validate_percentile_summary(unweighted_values, "unweighted"))
  summary_metrics <- data.frame(
    tier = "tier1",
    metric = paste0("same_week_", summary$weighting, "_", summary$metric),
    value = summary$value,
    status = "PASS",
    n = summary$n,
    details = "Same-week presence-background percentile summary.",
    stringsAsFactors = FALSE
  )
  summary_metrics <- rbind(
    summary_metrics,
    data.frame(tier = "tier1", metric = c("same_week_area_weighted_week_equal_mean", "same_week_unweighted_week_equal_mean"),
               value = c(mean(weekly$mean_weighted_percentile), mean(weekly$mean_unweighted_percentile)), status = "PASS",
               n = nrow(weekly), details = "Mean of week-level mean percentiles; occurrence-weighted summaries are retained above.", stringsAsFactors = FALSE)
  )
  metrics <- rbind(
    joint_inla_validate_metric_row("tier1", "withheld_occurrences", nrow(occurrence), "PASS", nrow(occurrence), "Stage 2 test points with Yi=1 and valid occurrence provenance."),
    joint_inla_validate_metric_row("tier1", "reference_background_rows", nrow(background), "PASS", nrow(background), "Terrestrial quadrature rows; not treated as biological absence."),
    joint_inla_validate_metric_row("tier1", "reference_background_spatial_nodes", reference_background$unique_spatial_nodes, "PASS", reference_background$unique_spatial_nodes, "Unique x/y integration nodes."),
    joint_inla_validate_metric_row("tier1", "reference_background_weeks", reference_background$represented_weeks, "PASS", reference_background$represented_weeks, "Unique year/week/time support."),
    joint_inla_validate_metric_row("tier1", "reference_background_total_weight", reference_background$total_weight, "PASS", reference_background$total_weight, "Sum of valid positive sc_Exp weights."),
    joint_inla_validate_metric_row("tier1", "PB_AUC", weighted_auc, "PASS", nrow(occurrence), "Area-weighted presence-background AUC; ties receive half credit."),
    joint_inla_validate_metric_row("tier1", "PB_AUC", unweighted_auc, "PASS", nrow(occurrence), "Unweighted presence-background AUC; ties receive half credit."),
    joint_inla_validate_metric_row("tier1", "continuous_boyce_index", weighted_boyce$cbi, weighted_boyce$status, nrow(occurrence), weighted_boyce$details),
    joint_inla_validate_metric_row("tier1", "continuous_boyce_index", unweighted_boyce$cbi, unweighted_boyce$status, nrow(occurrence), unweighted_boyce$details),
    joint_inla_validate_metric_row("tier1", "same_week_weighted_percentile_rows", length(weighted_values), "PASS", nrow(occurrence), "All held-out occurrences matched exact year/week/time background support."),
    joint_inla_validate_metric_row("tier1", "same_week_unweighted_percentile_rows", length(unweighted_values), "PASS", nrow(occurrence), "All held-out occurrences matched exact year/week/time background support."),
    summary_metrics
  )
  list(metrics = metrics, boyce_curve = rbind(weighted_boyce$curve, unweighted_boyce$curve), percentiles = percentiles, weekly = weekly,
       summary = summary, weighted_auc = weighted_auc, unweighted_auc = unweighted_auc,
       weighted_cbi = weighted_boyce$cbi, unweighted_cbi = unweighted_boyce$cbi, status = "PASS",
       details = "Tier 1 presence-background validation uses withheld occurrences against terrestrial integration/quadrature availability support; background points are unknown biological status and are not treated as absence.")
}
