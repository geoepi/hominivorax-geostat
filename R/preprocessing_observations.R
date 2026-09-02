clean_host_values <- function(x) stringr::str_replace_all(tolower(trimws(as.character(x))), "[^a-z]", "")

legacy_host_standardization <- function(x) {
  dplyr::case_when(
    x %in% c("bovine", "bovino", "bovinos", "bovinoequinosuinocanino", "bovinocaninosuino", "bovinosuino", "bovinocanino", "bovinoovino", "bovinoequino", "bufalino", "buffalino") ~ "bovine",
    x %in% c("caprine", "caprino", "caprinoequino") ~ "caprine",
    x %in% c("ovine", "ovino", "suinoovino") ~ "ovine",
    x %in% c("porcine", "porcino") ~ "porcine",
    x %in% c("canine", "canino", "carine", "caninosuino", "caninobovino", "caninoequino") ~ "canine",
    x %in% c("feline", "felino") ~ "feline",
    x %in% c("equine", "equino", "mule", "equinoburro", "equinobovino") ~ "equine",
    x %in% c("bird", "wildbird", "birdwild", "ave", "ardeidae", "aviar") ~ "bird",
    x %in% c("wildterrestrial", "kinkaju", "sloth", "perezoso", "porcupine", "porcuspine", "rabbit", "lapine", "procyonlotor", "deer", "leon", "crvido", "leopard", "leporido", "lion", "monkey") ~ "wildlife",
    x %in% c("human", "humano") ~ "human",
    x %in% c("other", "unknown", "faunasilvestreencautiverio", "faunasilvestrebajocuidadoprofesional", "faunasilvestre") ~ "unknown",
    TRUE ~ NA_character_
  )
}

read_observations <- function(path) {
  if (!file.exists(path)) stop("Observation file not found: ", path)
  readr::read_csv(path, show_col_types = FALSE)
}

read_host_lookup <- function(path) {
  lookup <- readr::read_csv(path, show_col_types = FALSE)
  require_columns(lookup, c("host_cleaned", "host_standardized", "host_group", "multiple_host_flag"), "host lookup")
  assert_unique_keys(lookup, "host_cleaned", "host lookup")
  lookup
}

preprocess_observations <- function(observations, boundary, cfg, host_lookup) {
  require_columns(observations, c("date", "lon", "lat", "host"), "observations")
  x <- observations
  x$observation_id <- seq_len(nrow(x))
  x$host_raw <- as.character(x$host)
  excluded <- list()
  add_excluded <- function(rows, reason) {
    if (nrow(rows)) {
      rows$exclusion_reason <- reason
      excluded[[length(excluded) + 1L]] <<- rows
    }
  }
  raw_date <- as.character(x$date)
  x$date <- suppressWarnings(as.Date(raw_date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y")))
  add_excluded(x[is.na(x$date), , drop = FALSE], ifelse(is.na(raw_date[is.na(x$date)]), "missing_date", "invalid_date"))
  x <- x[!is.na(x$date), , drop = FALSE]
  in_period <- x$date >= as.Date(cfg$study$start_date) & x$date <= as.Date(cfg$study$end_date)
  add_excluded(x[!in_period, , drop = FALSE], "outside_study_period")
  x <- x[in_period, , drop = FALSE]
  valid_xy <- is.finite(x$lon) & is.finite(x$lat) & x$lon >= -180 & x$lon <= 180 & x$lat >= -90 & x$lat <= 90
  add_excluded(x[!valid_xy, , drop = FALSE], "invalid_coordinates")
  x <- x[valid_xy, , drop = FALSE]
  pts <- sf::st_transform(sf::st_as_sf(x, coords = c("lon", "lat"), crs = 4326, remove = FALSE), sf::st_crs(boundary))
  inside <- lengths(sf::st_within(pts, boundary)) > 0
  add_excluded(x[!inside, , drop = FALSE], "outside_spatial_domain")
  x <- x[inside, , drop = FALSE]
  xy <- sf::st_coordinates(pts[inside, , drop = FALSE])
  x$x <- xy[, 1]; x$y <- xy[, 2]
  x$epiyear <- lubridate::isoyear(x$date); x$epiweek <- lubridate::isoweek(x$date)
  x$location_date_key <- paste(x$date, signif(x$x, 12), signif(x$y, 12), sep = "|")
  duplicate <- duplicated(x$location_date_key)
  duplicate_audit <- x[duplicate, c("observation_id", "date", "x", "y", "location_date_key"), drop = FALSE]
  if (nrow(duplicate_audit)) duplicate_audit$exclusion_reason <- "exact_date_location_duplicate"
  add_excluded(x[duplicate, , drop = FALSE], "exact_date_location_duplicate")
  x <- x[!duplicate, , drop = FALSE]
  x$host_cleaned <- clean_host_values(x$host_raw)
  x <- dplyr::left_join(x, host_lookup, by = "host_cleaned")
  unmapped <- is.na(x$host_standardized)
  fallback_host <- legacy_host_standardization(x$host_cleaned)
  x$host_standardized[unmapped] <- fallback_host[unmapped]
  recognized_fallback <- unmapped & !is.na(fallback_host)
  x$host_group[recognized_fallback] <- dplyr::case_when(
    x$host_standardized[recognized_fallback] %in% c("bovine", "caprine", "ovine", "porcine", "equine") ~ "livestock",
    x$host_standardized[recognized_fallback] %in% c("canine", "feline") ~ "domestic",
    x$host_standardized[recognized_fallback] == "bird" ~ "wildlife",
    x$host_standardized[recognized_fallback] == "human" ~ "human",
    TRUE ~ "unknown"
  )
  x$host_standardized[is.na(x$host_standardized)] <- "unknown"
  x$host_group[is.na(x$host_group)] <- "unknown"
  x$multiple_host_flag[unmapped] <- grepl("(bovino|bovine).*(equino|canino|suino|ovino)", x$host_cleaned[unmapped])
  unmapped_host_values <- sort(unique(x$host_cleaned[unmapped]))
  time <- make_week_index(cfg$study$start_date, cfg$study$end_date)
  x <- dplyr::left_join(x, time, by = c("epiyear", "epiweek"))
  excluded_df <- if (length(excluded)) dplyr::bind_rows(excluded) else x[0, , drop = FALSE]
  audit <- data.frame(
    stage = c("input", "invalid_date", "outside_study_period", "invalid_coordinates", "outside_spatial_domain", "exact_date_location_duplicate", "retained"),
    count = c(nrow(observations), sum(excluded_df$exclusion_reason == "invalid_date"), sum(excluded_df$exclusion_reason == "outside_study_period"), sum(excluded_df$exclusion_reason == "invalid_coordinates"), sum(excluded_df$exclusion_reason == "outside_spatial_domain"), sum(excluded_df$exclusion_reason == "exact_date_location_duplicate"), nrow(x))
  )
  list(data = x, excluded = excluded_df, duplicate_audit = duplicate_audit, audit = audit, unmapped_hosts = unmapped_host_values)
}
