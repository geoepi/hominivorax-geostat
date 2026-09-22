resolve_joint_inla_fit_path <- function(path, repo_root) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) return(path)
  path <- path.expand(as.character(path[[1L]]))
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) {
    normalizePath(path, mustWork = FALSE)
  } else {
    normalizePath(file.path(repo_root, path), mustWork = FALSE)
  }
}

joint_inla_fit_defaults <- function() {
  list(
    project = list(output_directory = "outputs/joint_inla_fit"),
    inputs = list(stage3a_build = "outputs/joint_inla/joint_inla_build.rds"),
    outputs = list(
      fit = "joint_model_fit.rds",
      audit = "joint_model_fit_audit.csv",
      metadata = "joint_model_fit_metadata.rds",
      overwrite = FALSE
    ),
    fit = list(
      quantiles = c(0.025, 0.25, 0.5, 0.75, 0.975),
      control_fixed = list(prec = 1, prec.intercept = 1),
      control_inla = list(strategy = "adaptive", int.strategy = "eb"),
      control_compute = list(dic = TRUE, cpo = FALSE, waic = TRUE),
      control_predictor = list(compute = TRUE),
      control_family = NULL,
      initialization = list(mode = "historical")
    ),
    threads = list(num_threads = 12, blas_threads = NULL),
    version_compatibility = list(policy = "warn")
  )
}

merge_joint_inla_fit_config <- function(defaults, supplied) {
  if (is.null(supplied)) return(defaults)
  for (nm in names(supplied)) {
    if (is.list(supplied[[nm]]) && is.list(defaults[[nm]])) {
      defaults[[nm]] <- merge_joint_inla_fit_config(defaults[[nm]], supplied[[nm]])
    } else {
      defaults[[nm]] <- supplied[[nm]]
    }
  }
  defaults
}

read_joint_inla_fit_config <- function(path, repo_root = getwd()) {
  if (!file.exists(path)) stop("Stage 3B configuration does not exist: ", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to read Stage 3B configuration.")
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  path <- normalizePath(path, mustWork = TRUE)
  supplied <- yaml::read_yaml(path)
  cfg <- merge_joint_inla_fit_config(joint_inla_fit_defaults(), supplied)
  cfg$project$output_directory <- resolve_joint_inla_fit_path(cfg$project$output_directory, repo_root)
  cfg$inputs$stage3a_build <- resolve_joint_inla_fit_path(cfg$inputs$stage3a_build, repo_root)
  cfg$config_path <- path
  cfg$repo_root <- repo_root
  cfg
}

validate_joint_inla_fit_config <- function(cfg, require_input = TRUE) {
  required <- c("project", "inputs", "outputs", "fit", "threads", "version_compatibility")
  missing <- setdiff(required, names(cfg))
  if (length(missing)) stop("Stage 3B configuration is missing sections: ", paste(missing, collapse = ", "))

  scalar_logical <- function(x, label) {
    if (length(x) != 1L || is.na(x) || !is.logical(x)) stop(label, " must be TRUE or FALSE.")
  }
  scalar_positive_integer <- function(x, label, allow_null = FALSE) {
    if (allow_null && is.null(x)) return(invisible(TRUE))
    if (length(x) != 1L || is.na(x) || !is.finite(as.numeric(x)) || as.numeric(x) != as.integer(x) || as.integer(x) < 1L) {
      stop(label, " must be a positive integer.")
    }
    invisible(TRUE)
  }

  if (length(cfg$inputs$stage3a_build) != 1L || !nzchar(as.character(cfg$inputs$stage3a_build))) {
    stop("inputs.stage3a_build must identify the Stage 3A joint_inla_build.rds artifact.")
  }
  if (isTRUE(require_input) && !file.exists(cfg$inputs$stage3a_build)) {
    stop("Stage 3A joint_inla_build.rds does not exist: ", cfg$inputs$stage3a_build)
  }
  for (name in c("fit", "audit", "metadata")) {
    if (length(cfg$outputs[[name]]) != 1L || !nzchar(as.character(cfg$outputs[[name]]))) {
      stop("outputs.", name, " must be a non-empty path.")
    }
  }
  scalar_logical(cfg$outputs$overwrite, "outputs.overwrite")

  if (!is.list(cfg$fit$control_fixed) || !is.list(cfg$fit$control_inla) ||
      !is.list(cfg$fit$control_compute) || !is.list(cfg$fit$control_predictor)) {
    stop("fit control sections must be lists.")
  }
  quantiles <- as.numeric(cfg$fit$quantiles)
  if (!length(quantiles) || any(!is.finite(quantiles)) || any(quantiles < 0 | quantiles > 1)) {
    stop("fit.quantiles must contain finite probabilities between 0 and 1.")
  }
  mode <- tolower(as.character(cfg$fit$initialization$mode))
  if (length(mode) != 1L || !mode %in% c("historical", "default")) {
    stop("fit.initialization.mode must be 'historical' or 'default'.")
  }
  scalar_positive_integer(cfg$threads$num_threads, "threads.num_threads")
  scalar_positive_integer(cfg$threads$blas_threads, "threads.blas_threads", allow_null = TRUE)

  policy <- tolower(as.character(cfg$version_compatibility$policy))
  if (length(policy) != 1L || !policy %in% c("warn", "error")) {
    stop("version_compatibility.policy must be 'warn' or 'error'.")
  }
  invisible(TRUE)
}

joint_inla_fit_output_paths <- function(cfg, output_override = NULL) {
  output_directory <- cfg$project$output_directory
  fit_name <- cfg$outputs$fit
  if (!is.null(output_override) && length(output_override) && nzchar(as.character(output_override[[1L]]))) {
    override <- resolve_joint_inla_fit_path(output_override[[1L]], cfg$repo_root)
    if (grepl("\\.rds$", override, ignore.case = TRUE)) {
      fit_path <- override
      output_directory <- dirname(override)
    } else {
      output_directory <- override
      fit_path <- file.path(output_directory, fit_name)
    }
  } else {
    fit_path <- if (grepl("^[A-Za-z]:[/\\\\]|^/", fit_name)) {
      normalizePath(fit_name, mustWork = FALSE)
    } else {
      file.path(output_directory, fit_name)
    }
  }
  audit_name <- cfg$outputs$audit
  metadata_name <- cfg$outputs$metadata
  audit_path <- if (grepl("^[A-Za-z]:[/\\\\]|^/", audit_name)) normalizePath(audit_name, mustWork = FALSE) else file.path(output_directory, audit_name)
  metadata_path <- if (grepl("^[A-Za-z]:[/\\\\]|^/", metadata_name)) normalizePath(metadata_name, mustWork = FALSE) else file.path(output_directory, metadata_name)
  list(
    fit = normalizePath(fit_path, mustWork = FALSE),
    audit = normalizePath(audit_path, mustWork = FALSE),
    metadata = normalizePath(metadata_path, mustWork = FALSE)
  )
}
