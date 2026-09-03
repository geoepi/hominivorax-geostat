resolve_joint_model_path <- function(path, repo_root) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) return(path)
  path <- as.character(path[[1L]])
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) normalizePath(path, mustWork = FALSE) else file.path(repo_root, path)
}

joint_model_defaults <- function() {
  list(
    project = list(output_directory = "outputs/joint_model"),
    inputs = list(model_inputs = "outputs/preprocessing/model_inputs.rds"),
    reporting_censoring = list(enabled = TRUE, cutoff_epiyear = 2025L, cutoff_epiweek = 32L, rule = "stopped_reporting_after_cutoff"),
    holdout = list(seed = 123L, tier1 = list(enabled = TRUE, positive_fraction = 0.10), tier2 = list(enabled = TRUE, positive_fraction = 0.20)),
    tier2 = list(zero_count_policy = "exclude"),
    temporal = list(derive_two_week_index = TRUE, derive_quarter_index = TRUE, derive_six_month_index = TRUE, derive_year_index = TRUE),
    livestock_rw2 = list(enabled = TRUE, bins = 22L, variables = c("cattle", "pigs", "sheep", "goats", "horses")),
    outputs = list(joint_model_inputs = "joint_model_inputs.rds", preparation_audit = "joint_model_preparation_audit.csv")
  )
}

merge_joint_model_config <- function(defaults, supplied) {
  if (is.null(supplied)) return(defaults)
  for (nm in names(supplied)) {
    if (is.list(supplied[[nm]]) && is.list(defaults[[nm]])) {
      defaults[[nm]] <- merge_joint_model_config(defaults[[nm]], supplied[[nm]])
    } else {
      defaults[[nm]] <- supplied[[nm]]
    }
  }
  defaults
}

read_joint_model_config <- function(path, repo_root = getwd()) {
  if (!file.exists(path)) stop("Joint-model configuration does not exist: ", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to read joint-model configuration.")
  cfg <- merge_joint_model_config(joint_model_defaults(), yaml::read_yaml(path))
  cfg$project$output_directory <- resolve_joint_model_path(cfg$project$output_directory, repo_root)
  cfg$inputs$model_inputs <- resolve_joint_model_path(cfg$inputs$model_inputs, repo_root)
  cfg$config_path <- normalizePath(path, mustWork = FALSE)
  cfg$repo_root <- normalizePath(repo_root, mustWork = TRUE)
  cfg
}

validate_joint_model_config <- function(cfg, require_inputs = TRUE) {
  required <- c("project", "inputs", "reporting_censoring", "holdout", "tier2", "temporal", "livestock_rw2", "outputs")
  missing <- setdiff(required, names(cfg))
  if (length(missing)) stop("Joint-model configuration is missing sections: ", paste(missing, collapse = ", "))
  scalar_logical <- function(x, label) {
    if (length(x) != 1L || is.na(x) || !is.logical(x)) stop(label, " must be TRUE or FALSE.")
  }
  scalar_integer <- function(x, label, minimum = NULL) {
    if (length(x) != 1L || is.na(x) || !is.finite(as.numeric(x)) || as.numeric(x) != as.integer(x)) stop(label, " must be an integer.")
    if (!is.null(minimum) && as.integer(x) < minimum) stop(label, " must be at least ", minimum, ".")
  }
  scalar_logical(cfg$reporting_censoring$enabled, "reporting_censoring.enabled")
  scalar_integer(cfg$reporting_censoring$cutoff_epiyear, "reporting_censoring.cutoff_epiyear", 1L)
  scalar_integer(cfg$reporting_censoring$cutoff_epiweek, "reporting_censoring.cutoff_epiweek", 1L)
  if (cfg$reporting_censoring$cutoff_epiweek > 53L) stop("reporting_censoring.cutoff_epiweek must be between 1 and 53.")
  if (!cfg$reporting_censoring$rule %in% "stopped_reporting_after_cutoff") stop("Unknown reporting-censoring rule: ", cfg$reporting_censoring$rule)
  scalar_integer(cfg$holdout$seed, "holdout.seed")
  for (tier in c("tier1", "tier2")) {
    scalar_logical(cfg$holdout[[tier]]$enabled, paste0("holdout.", tier, ".enabled"))
    fraction <- as.numeric(cfg$holdout[[tier]]$positive_fraction)
    if (length(fraction) != 1L || is.na(fraction) || !is.finite(fraction) || fraction < 0 || fraction > 1) stop("holdout.", tier, ".positive_fraction must be between 0 and 1.")
  }
  if (!cfg$tier2$zero_count_policy %in% c("exclude", "retain")) stop("tier2.zero_count_policy must be 'exclude' or 'retain'.")
  for (nm in c("derive_two_week_index", "derive_quarter_index", "derive_six_month_index", "derive_year_index")) scalar_logical(cfg$temporal[[nm]], paste0("temporal.", nm))
  scalar_logical(cfg$livestock_rw2$enabled, "livestock_rw2.enabled")
  scalar_integer(cfg$livestock_rw2$bins, "livestock_rw2.bins", 1L)
  if (!length(cfg$livestock_rw2$variables) || any(!nzchar(as.character(cfg$livestock_rw2$variables)))) stop("livestock_rw2.variables must contain at least one variable name.")
  if (isTRUE(require_inputs) && !file.exists(cfg$inputs$model_inputs)) stop("Stage 1 model_inputs.rds does not exist: ", cfg$inputs$model_inputs)
  invisible(TRUE)
}
