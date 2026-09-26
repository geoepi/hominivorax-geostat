preprocessing_temporal_defaults <- function() {
  list(start_week = NULL, end_week = "auto_last_complete_observation_week")
}

preprocessing_start_date <- function(cfg) {
  start_week <- if (!is.null(cfg$temporal)) cfg$temporal$start_week else NULL
  if (!is.null(start_week) && length(start_week) && nzchar(as.character(start_week[[1L]]))) {
    return(preprocessing_epiweek_start(start_week[[1L]]))
  }
  as.Date(cfg$study$start_date)
}

preprocessing_epiweek_start <- function(value) {
  value <- as.character(value[[1L]])
  match <- regexec("^(20[0-9]{2})-W([0-9]{1,2})$", value, ignore.case = TRUE)
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) != 3L) stop("Epiweek must use the form YYYY-Www: ", value)
  year <- as.integer(parts[[2L]])
  week <- as.integer(parts[[3L]])
  if (!is.finite(year) || !is.finite(week) || week < 1L || week > 53L) stop("Invalid epiweek: ", value)
  jan4 <- as.Date(sprintf("%04d-01-04", year))
  jan4 - (as.integer(format(jan4, "%u")) - 1L) + 7L * (week - 1L)
}

preprocessing_epiweek_label <- function(epiyear, epiweek) {
  sprintf("%04d-W%02d", as.integer(epiyear), as.integer(epiweek))
}

preprocessing_epiweek_end <- function(epiyear, epiweek) {
  preprocessing_epiweek_start(preprocessing_epiweek_label(epiyear, epiweek)) + 6L
}

preprocessing_date_epiweek <- function(date) {
  date <- as.Date(date)
  if (!length(date) || anyNA(date)) stop("Cannot construct an epiweek from missing dates.")
  data.frame(
    epiyear = lubridate::isoyear(date),
    epiweek = lubridate::isoweek(date),
    stringsAsFactors = FALSE
  )
}

preprocessing_temporal_spec <- function(cfg) {
  supplied <- if (is.null(cfg$temporal)) list() else cfg$temporal
  end_week <- supplied$end_week
  if (is.null(end_week) || !length(end_week) || !nzchar(as.character(end_week[[1L]]))) {
    end_week <- "auto_last_complete_observation_week"
  }
  mode <- if (identical(as.character(end_week[[1L]]), "auto_last_complete_observation_week")) "auto" else "explicit"
  list(
    mode = mode,
    start_week = supplied$start_week,
    end_week = as.character(end_week[[1L]]),
    requested_study_end_date = cfg$study$end_date
  )
}

preprocessing_source_max_date <- function(observations, cfg) {
  if ("date" %in% names(observations)) {
    date <- suppressWarnings(as.Date(as.character(observations$date),
      tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y")
    ))
    date <- date[!is.na(date)]
    if (length(date)) return(max(date))
  }
  year_name <- if ("epiyear" %in% names(observations)) "epiyear" else if ("year" %in% names(observations)) "year" else NULL
  week_name <- if ("epiweek" %in% names(observations)) "epiweek" else if ("week" %in% names(observations)) "week" else NULL
  if (is.null(year_name) || is.null(week_name)) stop("Automatic temporal resolution requires date or year/week observation fields.")
  year <- suppressWarnings(as.integer(observations[[year_name]]))
  week <- suppressWarnings(as.integer(observations[[week_name]]))
  valid <- is.finite(year) & is.finite(week) & week >= 1L & week <= 53L
  if (!any(valid)) stop("Automatic temporal resolution requires at least one valid observation epiweek.")
  keys <- year[valid] * 100L + week[valid]
  i <- which.max(keys)
  preprocessing_epiweek_end(year[valid][i], week[valid][i])
}

preprocessing_prepare_input_temporal_domain <- function(observations, cfg) {
  spec <- preprocessing_temporal_spec(cfg)
  start_date <- preprocessing_start_date(cfg)
  requested_end_date <- as.Date(cfg$study$end_date)
  if (is.na(requested_end_date)) stop("study.end_date must be a valid date before automatic temporal resolution.")
  requested_endpoint <- preprocessing_date_epiweek(requested_end_date)
  requested_endpoint_label <- preprocessing_epiweek_label(requested_endpoint$epiyear, requested_endpoint$epiweek)
  if (identical(spec$mode, "auto")) {
    source_max_date <- preprocessing_source_max_date(observations, cfg)
    initial_end_date <- max(source_max_date, start_date)
    cfg$temporal$source_max_date <- as.character(source_max_date)
    cfg$temporal$initial_input_end_date <- as.character(initial_end_date)
    cfg$temporal$requested_study_end_date <- spec$requested_study_end_date
    cfg$temporal$requested_current_modeled_final_epiweek <- requested_endpoint_label
    cfg$study$start_date <- as.character(start_date)
    cfg$study$end_date <- as.character(initial_end_date)
  } else {
    if (grepl("^20[0-9]{2}-W[0-9]{1,2}$", spec$end_week, ignore.case = TRUE)) {
      end_date <- preprocessing_epiweek_end(
        as.integer(sub("-W.*$", "", spec$end_week, ignore.case = TRUE)),
        as.integer(sub("^20[0-9]{2}-W", "", spec$end_week, ignore.case = TRUE))
      )
    } else {
      end_date <- as.Date(spec$end_week)
      if (is.na(end_date)) stop("temporal.end_week must be auto_last_complete_observation_week, YYYY-Www, or an ISO date.")
    }
    cfg$temporal$requested_study_end_date <- spec$requested_study_end_date
    cfg$temporal$requested_current_modeled_final_epiweek <- requested_endpoint_label
    cfg$study$start_date <- as.character(start_date)
    cfg$study$end_date <- as.character(end_date)
  }
  cfg
}

preprocessing_resolve_cleaned_temporal_domain <- function(cleaned_data, cfg) {
  spec <- preprocessing_temporal_spec(cfg)
  if (!nrow(cleaned_data)) stop("No cleaned observations remain for temporal-domain resolution.")
  start_date <- preprocessing_start_date(cfg)
  initial_end_date <- as.Date(cfg$study$end_date)
  if (identical(spec$mode, "auto")) {
    if ("date" %in% names(cleaned_data)) {
      cleaned_dates <- as.Date(cleaned_data$date)
      cleaned_dates <- cleaned_dates[!is.na(cleaned_dates)]
      if (!length(cleaned_dates)) stop("Automatic temporal resolution found no valid cleaned observation dates.")
      cleaned_max_date <- max(cleaned_dates)
      candidate <- preprocessing_date_epiweek(cleaned_max_date)
      candidate_end <- preprocessing_epiweek_end(candidate$epiyear, candidate$epiweek)
      if (candidate_end > cleaned_max_date) {
        candidate_start <- preprocessing_epiweek_start(preprocessing_epiweek_label(candidate$epiyear, candidate$epiweek)) - 7L
        candidate <- preprocessing_date_epiweek(candidate_start)
        candidate_end <- preprocessing_epiweek_end(candidate$epiyear, candidate$epiweek)
      }
      keep <- !is.na(cleaned_data$date) & as.Date(cleaned_data$date) <= candidate_end
      raw_max_date <- if (is.null(cfg$temporal$source_max_date)) as.character(cleaned_max_date) else cfg$temporal$source_max_date
    } else {
      require_columns(cleaned_data, c("epiyear", "epiweek"), "cleaned observations")
      valid <- is.finite(cleaned_data$epiyear) & is.finite(cleaned_data$epiweek)
      if (!any(valid)) stop("Automatic temporal resolution found no valid cleaned observation epiweeks.")
      keys <- as.integer(cleaned_data$epiyear) * 100L + as.integer(cleaned_data$epiweek)
      endpoint <- max(keys[valid])
      candidate <- list(epiyear = endpoint %/% 100L, epiweek = endpoint %% 100L)
      candidate_end <- preprocessing_epiweek_end(candidate$epiyear, candidate$epiweek)
      keep <- valid & keys <= endpoint
      cleaned_max_date <- as.character(candidate_end)
      raw_max_date <- if (is.null(cfg$temporal$source_max_date)) cleaned_max_date else cfg$temporal$source_max_date
    }
    if (candidate_end < start_date) stop("The last complete cleaned observation epiweek precedes the configured temporal start.")
    final_label <- preprocessing_epiweek_label(candidate$epiyear, candidate$epiweek)
    time_index <- make_week_index(start_date, candidate_end)
    excluded <- cleaned_data[!keep, , drop = FALSE]
    if (nrow(excluded)) excluded$exclusion_reason <- "after_auto_last_complete_observation_week"
    data <- cleaned_data[keep, , drop = FALSE]
    if ("time_index" %in% names(data)) data$time_index <- NULL
    data <- dplyr::left_join(data, time_index, by = c("epiyear", "epiweek"))
    if (anyNA(data$time_index)) stop("Resolved temporal domain could not map all retained observations to a time index.")
    cfg$study$start_date <- as.character(start_date)
    cfg$study$end_date <- as.character(candidate_end)
    cfg$temporal$resolved_end_week <- final_label
    cfg$temporal$resolved_end_date <- as.character(candidate_end)
    cfg$temporal$cleaned_max_date <- as.character(cleaned_max_date)
    cfg$temporal$eligible_observations_after_current_endpoint <- nrow(excluded)
    provenance <- list(
      mode = "auto_last_complete_observation_week",
      raw_maximum_date = as.character(raw_max_date),
      cleaned_maximum_date = as.character(cleaned_max_date),
      current_input_endpoint = if (is.null(cfg$temporal$requested_current_modeled_final_epiweek)) NA_character_ else cfg$temporal$requested_current_modeled_final_epiweek,
      initial_input_endpoint = preprocessing_epiweek_label(lubridate::isoyear(initial_end_date), lubridate::isoweek(initial_end_date)),
      current_modeled_final_epiweek = if (is.null(cfg$temporal$requested_current_modeled_final_epiweek)) NA_character_ else cfg$temporal$requested_current_modeled_final_epiweek,
      last_complete_epiweek = final_label,
      last_complete_week_end = as.character(candidate_end),
      eligible_observations_after_current_endpoint = nrow(excluded),
      new_week_count = nrow(time_index),
      excluded_observation_count = nrow(excluded)
    )
    return(list(data = data, excluded = excluded, time_index = time_index, config = cfg, provenance = provenance))
  }

  time_index <- make_week_index(start_date, as.Date(cfg$study$end_date))
  data <- cleaned_data
  if ("time_index" %in% names(data)) data$time_index <- NULL
  data <- dplyr::left_join(data, time_index, by = c("epiyear", "epiweek"))
  cfg$temporal$resolved_end_week <- preprocessing_epiweek_label(
    lubridate::isoyear(as.Date(cfg$study$end_date)), lubridate::isoweek(as.Date(cfg$study$end_date))
  )
  cfg$temporal$resolved_end_date <- as.character(as.Date(cfg$study$end_date))
  list(
    data = data, excluded = cleaned_data[0, , drop = FALSE], time_index = time_index, config = cfg,
    provenance = list(
      mode = "explicit",
      raw_maximum_date = NA_character_, cleaned_maximum_date = NA_character_,
      current_input_endpoint = if (is.null(cfg$temporal$requested_current_modeled_final_epiweek)) cfg$temporal$resolved_end_week else cfg$temporal$requested_current_modeled_final_epiweek,
      initial_input_endpoint = cfg$temporal$resolved_end_week,
      current_modeled_final_epiweek = cfg$temporal$resolved_end_week,
      last_complete_epiweek = cfg$temporal$resolved_end_week,
      last_complete_week_end = as.character(as.Date(cfg$study$end_date)),
      eligible_observations_after_current_endpoint = 0L,
      new_week_count = nrow(time_index), excluded_observation_count = 0L
    )
  )
}
