c1_effect_distribution <- function(x, term, sample_name) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) stop("No finite predictor values were found for ", term, " in ", sample_name, ".")
  q <- stats::quantile(x, probs = c(0.1, 0.25, 0.5, 0.75, 0.9),
                       na.rm = TRUE, names = FALSE, type = 7)
  data.frame(
    term = term, sample = sample_name, n_finite = length(x),
    minimum = min(x), q10 = q[[1L]], q25 = q[[2L]], median = q[[3L]],
    q75 = q[[4L]], q90 = q[[5L]], maximum = max(x),
    iqr = q[[4L]] - q[[2L]], range_10_90 = q[[5L]] - q[[1L]],
    stringsAsFactors = FALSE
  )
}

c1_effect_marginal_summary <- function(marginal, term) {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required to summarize saved one-dimensional marginals.")
  if (is.null(marginal) || !is.matrix(marginal) || ncol(marginal) != 2L) {
    stop("Saved INLA marginal is missing or malformed for ", term, ".")
  }
  mean_value <- INLA::inla.emarginal(function(x) x, marginal)
  second_moment <- INLA::inla.emarginal(function(x) x^2, marginal)
  q <- vapply(c(0.025, 0.5, 0.975), function(p) INLA::inla.qmarginal(p, marginal), numeric(1L))
  data.frame(
    term = term, posterior_mean = as.numeric(mean_value),
    posterior_median = as.numeric(q[[2L]]),
    posterior_sd = sqrt(max(0, as.numeric(second_moment) - as.numeric(mean_value)^2)),
    q025 = as.numeric(q[[1L]]), q975 = as.numeric(q[[3L]]),
    interval_contains_zero = as.numeric(q[[1L]]) <= 0 && as.numeric(q[[3L]]) >= 0,
    probability_positive = 1 - as.numeric(INLA::inla.pmarginal(0, marginal)),
    stringsAsFactors = FALSE
  )
}

c1_effect_scale_summary <- function(posterior, distribution) {
  result <- data.frame(
    term = posterior$term, sample = distribution$sample,
    predictor_iqr = distribution$iqr, predictor_10_90 = distribution$range_10_90,
    stringsAsFactors = FALSE
  )
  for (scale in c("iqr", "10_90")) {
    spread <- if (scale == "iqr") distribution$iqr else distribution$range_10_90
    suffix <- if (scale == "iqr") "iqr" else "10_90"
    result[[paste0("multiplicative_mean_", suffix)]] <- exp(posterior$posterior_mean * spread)
    result[[paste0("multiplicative_median_", suffix)]] <- exp(posterior$posterior_median * spread)
    result[[paste0("multiplicative_q025_", suffix)]] <- exp(posterior$q025 * spread)
    result[[paste0("multiplicative_q975_", suffix)]] <- exp(posterior$q975 * spread)
  }
  result
}

c1_effect_join_source_units <- function(summary, units = c(
  clay = "SoilGrids mapped g/kg; coefficient per g/kg",
  wv0010 = "SoilGrids mapped 10^-3 cm3 cm-3; coefficient per mapped unit",
  spressure = "ERA5-Land product Pa; C-1 fitted column kPa per manifest"
)) {
  summary$source_units <- unname(units[summary$term])
  if (anyNA(summary$source_units)) stop("Source units are not defined for every C-1 effect.")
  summary
}
