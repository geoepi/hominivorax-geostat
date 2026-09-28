stage1_livestock_imputation <- function(variable, transformation_spec) {
  if (is.null(transformation_spec) || is.null(transformation_spec$static) || is.null(transformation_spec$static[[variable]])) {
    stop("Stage 1 transformation metadata is missing the livestock imputation value for ", variable, ".")
  }
  value <- transformation_spec$static[[variable]][["impute"]]
  if (length(value) != 1L || is.na(value) || !is.finite(as.numeric(value)) || as.numeric(value) < -1) {
    stop("Stage 1 livestock imputation value for ", variable, " must be a finite value at least -1.")
  }
  as.numeric(value)
}

historical_rank_quantile <- function(values, requested_bins) {
  rank_fraction <- rank(values, ties.method = "average") / length(values)
  as.integer(cut(rank_fraction, breaks = seq(0, 1, length.out = requested_bins + 1L), labels = FALSE))
}

fit_quantile_feature <- function(values, bins = 22L, imputation_value = NULL) {
  raw_values <- as.numeric(values)
  if (is.null(imputation_value) && any(!is.finite(raw_values))) stop("An explicit livestock imputation value is required for missing values.")
  if (is.null(imputation_value)) imputation_value <- NA_real_
  working_values <- raw_values
  working_values[!is.finite(working_values)] <- imputation_value
  if (any(!is.finite(working_values))) stop("Cannot fit a quantile feature without finite values after imputation.")
  if (any(working_values < -1)) stop("Livestock values must be at least -1 for log1p transformation.")
  requested <- as.integer(bins)
  probabilities <- seq(0, 1, length.out = requested + 1L)
  breaks <- as.numeric(stats::quantile(working_values, probs = probabilities, na.rm = TRUE, names = FALSE, type = 7))
  midpoints <- if (length(breaks) == 1L) breaks else (head(breaks, -1L) + tail(breaks, -1L)) / 2
  training_q <- historical_rank_quantile(working_values, requested)
  effective <- length(unique(training_q))
  list(
    requested_bins = requested,
    effective_bins = effective,
    breaks = breaks,
    midpoints = midpoints,
    transformation = "log1p(midpoint)",
    method = "historical_rank_quantile",
    rank_ties_method = "average",
    imputation_value = as.numeric(imputation_value),
    imputation_source = "Stage 1 transformations$static[[variable]]$impute",
    quantile_type = 7L,
    type = 7L,
    ties_reduced_bins = effective < requested,
    training_q = training_q
  )
}

apply_quantile_feature <- function(values, specification) {
  values <- as.numeric(values)
  working_values <- values
  if (!is.null(specification$imputation_value)) working_values[!is.finite(working_values)] <- specification$imputation_value
  q <- rep(NA_integer_, length(working_values))
  mid <- rep(NA_real_, length(working_values))
  finite <- is.finite(working_values)
  if (any(finite)) {
    if (length(specification$breaks) == 1L) {
      q[finite] <- 1L
    } else {
      q[finite] <- findInterval(working_values[finite], specification$breaks[-1L], rightmost.closed = TRUE) + 1L
      q[finite] <- pmax(1L, pmin(length(specification$midpoints), q[finite]))
    }
    mid[finite] <- specification$midpoints[q[finite]]
  }
  list(q = q, mid = mid, mid_log1p = log1p(mid))
}

add_livestock_rw2_features <- function(tier2, prediction_grid, cfg, transformation_spec = NULL) {
  if (!isTRUE(cfg$livestock_rw2$enabled)) return(list(tier2 = tier2, prediction_grid = prediction_grid, metadata = list(enabled = FALSE, specifications = list())))
  variables <- as.character(cfg$livestock_rw2$variables)
  require_columns(tier2, variables, "Tier 2 livestock feature training data")
  require_columns(prediction_grid, variables, "prediction-grid livestock features")
  specifications <- setNames(vector("list", length(variables)), variables)
  for (variable in variables) {
    imputation_value <- stage1_livestock_imputation(variable, transformation_spec)
    specification <- fit_quantile_feature(tier2[[variable]], cfg$livestock_rw2$bins, imputation_value)
    training_q <- specification$training_q
    specification$training_q <- NULL
    specifications[[variable]] <- specification
    training_feature <- list(
      q = training_q,
      mid = specification$midpoints[training_q],
      mid_log1p = log1p(specification$midpoints[training_q])
    )
    prediction_feature <- apply_quantile_feature(prediction_grid[[variable]], specification)
    tier2[[paste0(variable, "_q")]] <- training_feature$q
    tier2[[paste0(variable, "_mid")]] <- training_feature$mid
    tier2[[paste0(variable, "_mid_log1p")]] <- training_feature$mid_log1p
    prediction_grid[[paste0(variable, "_q")]] <- prediction_feature$q
    prediction_grid[[paste0(variable, "_mid")]] <- prediction_feature$mid
    prediction_grid[[paste0(variable, "_mid_log1p")]] <- prediction_feature$mid_log1p
  }
  list(
    tier2 = tier2,
    prediction_grid = prediction_grid,
    metadata = list(enabled = TRUE, bins = as.integer(cfg$livestock_rw2$bins), specifications = specifications)
  )
}
