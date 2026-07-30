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
  cfg$config_path <- normalizePath(path, mustWork = FALSE); cfg
}
validate_preprocessing_config <- function(cfg, require_inputs = TRUE) {
  stopifnot(all(c("project", "study", "inputs", "mesh", "extraction", "transformations", "outputs") %in% names(cfg)))
  if (as.Date(cfg$study$start_date) > as.Date(cfg$study$end_date)) stop("study start_date is after end_date")
  if (isTRUE(require_inputs)) { p <- unlist(c(cfg$inputs, cfg$dynamic_covariates, cfg$static_covariates)); p <- p[!vapply(p, file.exists, logical(1))]; if (length(p)) stop("Required input paths are absent: ", paste(p, collapse = ", ")) }
  invisible(TRUE)
}
make_week_index <- function(start_date, end_date) {
  dates <- seq(as.Date(start_date), as.Date(end_date), by = "day"); out <- unique(data.frame(epiyear = lubridate::isoyear(dates), epiweek = lubridate::isoweek(dates))); out <- out[order(out$epiyear, out$epiweek), , drop = FALSE]; out$time_index <- seq_len(nrow(out)); rownames(out) <- NULL; stopifnot(!anyDuplicated(out$time_index)); out
}
