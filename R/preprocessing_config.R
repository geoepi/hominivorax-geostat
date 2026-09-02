resolve_preprocessing_path <- function(path, repo_root) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) normalizePath(path, mustWork = FALSE) else file.path(repo_root, path)
}
read_preprocessing_config <- function(path, repo_root = getwd()) {
  stopifnot(requireNamespace("yaml", quietly = TRUE)); cfg <- yaml::read_yaml(path)
  cfg$project$output_directory <- resolve_preprocessing_path(cfg$project$output_directory, repo_root)
  cfg$inputs <- lapply(cfg$inputs, resolve_preprocessing_path, repo_root = repo_root)
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
  if (as.Date(cfg$study$start_date) > as.Date(cfg$study$end_date)) stop("study start_date is after end_date")
  if (isTRUE(require_inputs)) { p <- unlist(c(cfg$inputs, cfg$dynamic_covariates, cfg$static_covariates)); p <- p[!vapply(p, file.exists, logical(1))]; if (length(p)) stop("Required input paths are absent: ", paste(p, collapse = ", ")) }
  invisible(TRUE)
}
make_week_index <- function(start_date, end_date) {
  dates <- seq(as.Date(start_date), as.Date(end_date), by = "day"); out <- unique(data.frame(epiyear = lubridate::isoyear(dates), epiweek = lubridate::isoweek(dates))); out <- out[order(out$epiyear, out$epiweek), , drop = FALSE]; out$time_index <- seq_len(nrow(out)); rownames(out) <- NULL; stopifnot(!anyDuplicated(out$time_index)); out
}
