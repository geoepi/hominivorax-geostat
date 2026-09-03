validate_joint_model_input_contract <- function(model_inputs) {
  if (!is.list(model_inputs)) stop("Stage 2 input must be an RDS list produced by Stage 1.")
  required_top <- c("tier1", "tier2", "prediction_grid", "mesh", "time_index")
  missing_top <- setdiff(required_top, names(model_inputs))
  if (length(missing_top)) stop("Stage 1 model_inputs is missing required fields: ", paste(missing_top, collapse = ", "))
  required_rows <- list(
    tier1 = c("admin_u", "epiyear", "epiweek", "time_index", "Yi"),
    tier2 = c("admin_u", "epiyear", "epiweek", "time_index", "count"),
    prediction_grid = c("admin_u", "epiyear", "epiweek", "time_index")
  )
  for (scope in names(required_rows)) {
    if (!is.data.frame(model_inputs[[scope]])) stop("Stage 1 field '", scope, "' must be a data frame.")
    require_columns(model_inputs[[scope]], required_rows[[scope]], paste0("Stage 1 ", scope))
  }
  if (!all(c("epiyear", "epiweek", "time_index") %in% names(model_inputs$time_index))) stop("Stage 1 time_index must contain epiyear, epiweek, and time_index.")
  invisible(TRUE)
}

canonical_response <- function(data, tier) {
  if (tier == "tier1") {
    require_columns(data, "Yi", "Stage 1 Tier 1")
    return(as.numeric(data$Yi))
  }
  candidates <- c("count")
  found <- candidates[candidates %in% names(data)]
  if (!length(found)) stop("Stage 1 Tier 2 must contain its canonical count response: count.")
  as.numeric(data[[found[[1L]]]])
}

time_key_before_cutoff <- function(epiyear, epiweek, cutoff_epiyear, cutoff_epiweek) {
  epiyear < cutoff_epiyear | (epiyear == cutoff_epiyear & epiweek < cutoff_epiweek)
}

apply_reporting_censoring <- function(tier1, tier2, cfg) {
  tier1$response_observed <- canonical_response(tier1, "tier1")
  tier2$response_observed <- canonical_response(tier2, "tier2")
  tier1$is_censored <- FALSE
  tier2$is_censored <- FALSE
  affected <- character()
  admin_status <- data.frame()
  if (isTRUE(cfg$reporting_censoring$enabled)) {
    before <- time_key_before_cutoff(tier2$epiyear, tier2$epiweek, cfg$reporting_censoring$cutoff_epiyear, cfg$reporting_censoring$cutoff_epiweek)
    after <- !before
    split_status <- split(seq_len(nrow(tier2)), as.character(tier2$admin_u))
    admin_status <- dplyr::bind_rows(lapply(names(split_status), function(unit) {
      i <- split_status[[unit]]
      data.frame(
        admin_u = unit,
        had_reports_before = any(before[i] & tier2$response_observed[i] > 0, na.rm = TRUE),
        has_reports_after = any(after[i] & tier2$response_observed[i] > 0, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }))
    affected <- admin_status$admin_u[admin_status$had_reports_before & !admin_status$has_reports_after]
    tier1$is_censored <- tier1$admin_u %in% affected & !time_key_before_cutoff(tier1$epiyear, tier1$epiweek, cfg$reporting_censoring$cutoff_epiyear, cfg$reporting_censoring$cutoff_epiweek)
    tier2$is_censored <- tier2$admin_u %in% affected & !before
  }
  tier1$response_censored <- tier1$response_observed
  tier2$response_censored <- tier2$response_observed
  tier1$response_censored[tier1$is_censored] <- NA_real_
  tier2$response_censored[tier2$is_censored] <- NA_real_
  metadata <- list(
    enabled = isTRUE(cfg$reporting_censoring$enabled),
    rule = cfg$reporting_censoring$rule,
    cutoff = list(epiyear = as.integer(cfg$reporting_censoring$cutoff_epiyear), epiweek = as.integer(cfg$reporting_censoring$cutoff_epiweek)),
    affected_admin_units = affected,
    admin_status = admin_status,
    affected_tier1_rows = sum(tier1$is_censored),
    affected_tier2_rows = sum(tier2$is_censored)
  )
  list(tier1 = tier1, tier2 = tier2, metadata = metadata)
}

stable_row_id <- function(data, tier) {
  keys <- if (tier == "tier1") c(".row_id", "source_obs_id", "point_id", "time_index", "epiyear", "epiweek") else c("poly_id", ".row_id", "time_index", "epiyear", "epiweek")
  keys <- keys[keys %in% names(data)]
  if (!length(keys)) stop("Cannot construct stable ", tier, " holdout identifiers.")
  values <- lapply(data[keys], function(x) ifelse(is.na(x), "<NA>", as.character(x)))
  do.call(paste, c(values, sep = "|"))
}

select_response_holdouts <- function(data, tier, enabled, positive_fraction, seed) {
  data$is_test_point <- FALSE
  data$response_training <- data$response_censored
  stable_id <- stable_row_id(data, tier)
  eligible <- !data$is_censored & !is.na(data$response_observed) & data$response_observed > 0
  eligible_ids <- stable_id[eligible]
  if (anyDuplicated(eligible_ids)) stop("Stable holdout identifiers are duplicated in eligible ", tier, " rows.")
  ordered <- order(eligible_ids)
  eligible_indices <- which(eligible)[ordered]
  n_select <- if (!isTRUE(enabled) || !length(eligible_indices) || positive_fraction == 0) 0L else ceiling(length(eligible_indices) * positive_fraction)
  selected_indices <- integer()
  if (n_select > 0L) {
    had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    set.seed(as.integer(seed))
    selected_indices <- sample(eligible_indices, size = n_select, replace = FALSE)
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  }
  if (length(selected_indices)) {
    data$is_test_point[selected_indices] <- TRUE
    data$response_training[selected_indices] <- NA_real_
  }
  list(
    data = data,
    metadata = list(
      tier = tier,
      enabled = isTRUE(enabled),
      positive_fraction = positive_fraction,
      seed = as.integer(seed),
      eligible_ids = sort(eligible_ids),
      selected_ids = sort(stable_id[selected_indices]),
      eligible_count = length(eligible_indices),
      selected_count = length(selected_indices)
    )
  )
}

apply_zero_count_policy <- function(tier2, policy) {
  zero_response <- !is.na(tier2$response_training) & tier2$response_training == 0
  if (identical(policy, "exclude")) tier2$response_training[zero_response] <- NA_real_
  list(data = tier2, zero_count = sum(zero_response), excluded_count = if (identical(policy, "exclude")) sum(zero_response) else 0L)
}
