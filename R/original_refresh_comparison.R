original_refresh_match_holdouts <- function(c1, refreshed, key_columns = NULL) {
  if (is.null(key_columns)) {
    shared <- function(columns) all(columns %in% names(c1)) && all(columns %in% names(refreshed))
    candidates <- list(
      c("source_.row_id"), c("source_observation_id"), c("source_source_obs_id"),
      c("source_obs_id"), c("output_id"), c(".row_id"), c("source_row_id"),
      c("source_poly_id", "source_time_index"), c("poly_id", "time_index"),
      c("source_epiyear", "source_epiweek", "source_x", "source_y"),
      c("epiyear", "epiweek", "x", "y")
    )
    identity <- NULL
    for (candidate in candidates) {
      columns <- c("tier", candidate)
      if (!shared(columns)) next
      identity <- columns
      break
    }
    key_columns <- identity
  }
  if (!length(key_columns)) stop("No shared holdout identity columns were found.")
  if (!all(key_columns %in% names(c1)) || !all(key_columns %in% names(refreshed))) {
    stop("Holdout key columns are missing from one or both inputs.")
  }
  key <- function(x) do.call(paste, c(lapply(x[key_columns], function(v) {
    ifelse(is.na(v), "<NA>", as.character(v))
  }), sep = "\035"))
  c1_key <- key(c1)
  refreshed_key <- key(refreshed)
  if (anyDuplicated(c1_key) || anyDuplicated(refreshed_key)) {
    stop("Holdout identifiers must be unique within each evaluation data set.")
  }
  common <- intersect(c1_key, refreshed_key)
  c1_order <- match(common, c1_key)
  refreshed_order <- match(common, refreshed_key)
  list(
    key_columns = key_columns,
    matched_n = length(common),
    c1_only_n = sum(!c1_key %in% refreshed_key),
    refreshed_only_n = sum(!refreshed_key %in% c1_key),
    matched_ids = common,
    c1 = c1[c1_order, , drop = FALSE],
    refreshed = refreshed[refreshed_order, , drop = FALSE]
  )
}

original_refresh_paired_tier2_errors <- function(match, observed = "response_observed",
                                                 c1_prediction = "expected_count",
                                                 refreshed_prediction = "expected_count") {
  if (!all(c(observed, c1_prediction) %in% names(match$c1)) ||
      !all(c(observed, refreshed_prediction) %in% names(match$refreshed))) {
    stop("Matched Tier 2 inputs lack observed counts or expected predictions.")
  }
  obs_c1 <- suppressWarnings(as.numeric(match$c1[[observed]]))
  obs_ref <- suppressWarnings(as.numeric(match$refreshed[[observed]]))
  pred_c1 <- suppressWarnings(as.numeric(match$c1[[c1_prediction]]))
  pred_ref <- suppressWarnings(as.numeric(match$refreshed[[refreshed_prediction]]))
  valid <- is.finite(obs_c1) & is.finite(obs_ref) & is.finite(pred_c1) & is.finite(pred_ref) &
    obs_c1 == obs_ref & obs_c1 >= 0 & obs_c1 == floor(obs_c1)
  if ("source_is_censored" %in% names(match$c1)) valid <- valid & !(match$c1$source_is_censored %in% TRUE)
  if ("source_is_censored" %in% names(match$refreshed)) valid <- valid & !(match$refreshed$source_is_censored %in% TRUE)
  abs_c1 <- abs(obs_c1[valid] - pred_c1[valid])
  abs_ref <- abs(obs_ref[valid] - pred_ref[valid])
  data.frame(
    metric = c("matched_tier2_rows", "paired_valid_rows", "mean_absolute_error_c1",
               "mean_absolute_error_refreshed", "paired_mae_difference_refreshed_minus_c1"),
    value = c(match$matched_n, sum(valid),
      if (any(valid)) mean(abs_c1) else NA_real_,
      if (any(valid)) mean(abs_ref) else NA_real_,
      if (any(valid)) mean(abs_ref - abs_c1) else NA_real_),
    stringsAsFactors = FALSE
  )
}
