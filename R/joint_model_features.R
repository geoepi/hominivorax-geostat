fit_quantile_feature <- function(values, bins = 22L) {
  values <- as.numeric(values)
  finite <- is.finite(values)
  if (!any(finite)) stop("Cannot fit a quantile feature without finite values.")
  if (any(values[finite] < -1)) stop("Livestock values must be at least -1 for log1p transformation.")
  requested <- as.integer(bins)
  probabilities <- seq(0, 1, length.out = requested + 1L)
  breaks <- as.numeric(stats::quantile(values[finite], probs = probabilities, na.rm = TRUE, names = FALSE, type = 7))
  breaks <- unique(breaks)
  effective <- max(1L, length(breaks) - 1L)
  if (length(breaks) == 1L) {
    midpoints <- breaks
  } else {
    midpoints <- (head(breaks, -1L) + tail(breaks, -1L)) / 2
  }
  list(
    requested_bins = requested,
    effective_bins = effective,
    breaks = breaks,
    midpoints = midpoints,
    transformation = "log1p(midpoint)",
    ties_reduced_bins = effective < requested,
    type = 7L
  )
}

apply_quantile_feature <- function(values, specification) {
  values <- as.numeric(values)
  q <- rep(NA_integer_, length(values))
  mid <- rep(NA_real_, length(values))
  finite <- is.finite(values)
  if (any(finite)) {
    if (length(specification$breaks) == 1L) {
      q[finite] <- 1L
    } else {
      q[finite] <- findInterval(values[finite], specification$breaks[-1L], rightmost.closed = TRUE) + 1L
      q[finite] <- pmax(1L, pmin(specification$effective_bins, q[finite]))
    }
    mid[finite] <- specification$midpoints[q[finite]]
  }
  list(q = q, mid = mid, mid_log1p = log1p(mid))
}

add_livestock_rw2_features <- function(tier2, prediction_grid, cfg) {
  if (!isTRUE(cfg$livestock_rw2$enabled)) return(list(tier2 = tier2, prediction_grid = prediction_grid, metadata = list(enabled = FALSE, specifications = list())))
  variables <- as.character(cfg$livestock_rw2$variables)
  require_columns(tier2, variables, "Tier 2 livestock feature training data")
  require_columns(prediction_grid, variables, "prediction-grid livestock features")
  specifications <- setNames(vector("list", length(variables)), variables)
  for (variable in variables) {
    specification <- fit_quantile_feature(tier2[[variable]], cfg$livestock_rw2$bins)
    specifications[[variable]] <- specification
    training_feature <- apply_quantile_feature(tier2[[variable]], specification)
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
