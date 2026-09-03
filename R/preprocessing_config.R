resolve_preprocessing_path <- function(path, repo_root) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) normalizePath(path, mustWork = FALSE) else file.path(repo_root, path)
}
read_preprocessing_config <- function(path, repo_root = getwd()) {
  stopifnot(requireNamespace("yaml", quietly = TRUE)); cfg <- yaml::read_yaml(path)
  cfg$project$output_directory <- resolve_preprocessing_path(cfg$project$output_directory, repo_root)
  input_path_names <- setdiff(names(cfg$inputs), c("observation_mode", "observation_crs"))
  cfg$inputs[input_path_names] <- lapply(cfg$inputs[input_path_names], resolve_preprocessing_path, repo_root = repo_root)
  if (is.null(cfg$inputs$observation_mode)) cfg$inputs$observation_mode <- "raw"
  if (is.null(cfg$mesh$use_observation_locations)) cfg$mesh$use_observation_locations <- FALSE
  cfg$dynamic_covariates <- lapply(cfg$dynamic_covariates, resolve_preprocessing_path, repo_root = repo_root)
  cfg$static_covariates <- lapply(cfg$static_covariates, resolve_preprocessing_path, repo_root = repo_root)
  if (is.null(names(cfg$dynamic_covariates)) || any(!nzchar(names(cfg$dynamic_covariates)))) {
    names(cfg$dynamic_covariates) <- c("minimum_temperature", "soil_moisture", "leaf_area_low", "relative_humidity")
  }
  if (is.null(names(cfg$static_covariates)) || any(!nzchar(names(cfg$static_covariates)))) {
    names(cfg$static_covariates) <- c("cattle", "horses", "pigs", "sheep", "goats", "road_density", "night_illumination")
  }
  if (is.null(cfg$extraction$search_radius_km) && !is.null(cfg$extraction$search_radius_m)) {
    stop("extraction.search_radius_m is deprecated and ambiguous; use extraction.search_radius_km.")
  }
  cfg$config_path <- normalizePath(path, mustWork = FALSE); cfg
}
validate_preprocessing_config <- function(cfg, require_inputs = TRUE) {
  stopifnot(all(c("project", "study", "inputs", "mesh", "extraction", "transformations", "outputs") %in% names(cfg)))
  if (is.null(cfg$extraction$search_radius_km) || !is.finite(cfg$extraction$search_radius_km) || cfg$extraction$search_radius_km < 0) stop("extraction.search_radius_km must be a non-negative number")
  if (is.null(cfg$extraction$dynamic_search_radius_km)) cfg$extraction$dynamic_search_radius_km <- cfg$extraction$search_radius_km
  if (!is.finite(cfg$extraction$dynamic_search_radius_km) || cfg$extraction$dynamic_search_radius_km < 0) stop("extraction.dynamic_search_radius_km must be a non-negative number")
  if (length(cfg$mesh$use_observation_locations) != 1L || is.na(cfg$mesh$use_observation_locations) || !is.logical(cfg$mesh$use_observation_locations)) stop("mesh.use_observation_locations must be TRUE or FALSE")
  if (!cfg$inputs$observation_mode %in% c("raw", "standardized")) stop("inputs.observation_mode must be 'raw' or 'standardized'")
  if (identical(cfg$inputs$observation_mode, "standardized")) invisible(get_observation_source_crs(cfg))
  if (as.Date(cfg$study$start_date) > as.Date(cfg$study$end_date)) stop("study start_date is after end_date")
  if (isTRUE(require_inputs)) { input_paths <- cfg$inputs[setdiff(names(cfg$inputs), c("observation_mode", "observation_crs"))]; p <- unlist(c(input_paths, cfg$dynamic_covariates, cfg$static_covariates)); p <- p[!vapply(p, file.exists, logical(1))]; if (length(p)) stop("Required input paths are absent: ", paste(p, collapse = ", ")) }
  invisible(TRUE)
}
get_observation_source_crs <- function(cfg) {
  value <- cfg$inputs$observation_crs
  if (is.null(value) || !length(value) || is.na(value[1]) || !nzchar(as.character(value[1]))) stop("inputs.observation_crs is required when inputs.observation_mode is 'standardized'")
  crs <- tryCatch(sf::st_crs(value[1]), error = function(e) NULL)
  if (is.null(crs) || is.na(crs$wkt)) stop("inputs.observation_crs is not a valid CRS: ", as.character(value[1]))
  crs
}
make_week_index <- function(start_date, end_date) {
  dates <- seq(as.Date(start_date), as.Date(end_date), by = "day"); out <- unique(data.frame(epiyear = lubridate::isoyear(dates), epiweek = lubridate::isoweek(dates))); out <- out[order(out$epiyear, out$epiweek), , drop = FALSE]; out$time_index <- seq_len(nrow(out)); rownames(out) <- NULL; stopifnot(!anyDuplicated(out$time_index)); out
}
