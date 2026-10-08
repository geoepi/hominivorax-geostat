production_orchestration_null_coalesce <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}
assign("%||%", production_orchestration_null_coalesce, envir = .GlobalEnv)

production_orchestration_require <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) stop("Production orchestration requires: ", paste(missing, collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

production_orchestration_hash_file <- function(path) {
  production_orchestration_require("digest")
  if (!file.exists(path)) stop("Cannot hash missing file: ", path, call. = FALSE)
  digest::digest(file = path, algo = "sha256")
}

production_orchestration_resolve_path <- function(path, base_dir) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) return(path)
  value <- as.character(path[[1L]])
  if (grepl("^[A-Za-z]:[/\\\\]|^/", value)) normalizePath(value, mustWork = FALSE) else normalizePath(file.path(base_dir, value), mustWork = FALSE)
}

production_orchestration_parse_week <- function(value) {
  value <- as.character(value[[1L]])
  match <- regexec("^(20[0-9]{2})-W([0-9]{1,2})$", value, ignore.case = TRUE)
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) != 3L) stop("Epiweek must use YYYY-Www: ", value, call. = FALSE)
  year <- as.integer(parts[[2L]])
  week <- as.integer(parts[[3L]])
  if (!is.finite(year) || !is.finite(week) || week < 1L || week > 53L) stop("Invalid epiweek: ", value, call. = FALSE)
  list(year = year, week = week, label = sprintf("%04d-W%02d", year, week))
}

production_orchestration_week_start <- function(year, week) {
  jan4 <- as.Date(sprintf("%04d-01-04", as.integer(year)))
  jan4 - (as.integer(format(jan4, "%u")) - 1L) + 7L * (as.integer(week) - 1L)
}

production_orchestration_week_label <- function(date) {
  date <- as.Date(date)
  if (is.na(date)) stop("Cannot construct an epiweek from a missing date.", call. = FALSE)
  monday <- date - (as.integer(format(date, "%u")) - 1L)
  iso_year <- as.integer(format(monday + 3L, "%Y"))
  first_monday <- production_orchestration_week_start(iso_year, 1L)
  iso_week <- as.integer(round(as.numeric(monday - first_monday) / 7)) + 1L
  sprintf("%04d-W%02d", iso_year, iso_week)
}

production_orchestration_week_sequence <- function(start_label, end_label) {
  start <- production_orchestration_parse_week(start_label)
  end <- production_orchestration_parse_week(end_label)
  starts <- seq(production_orchestration_week_start(start$year, start$week),
                production_orchestration_week_start(end$year, end$week), by = "7 days")
  vapply(starts, production_orchestration_week_label, character(1L))
}

production_orchestration_resolve_horizon <- function(observations, start_epiweek, end_rule = "last_complete_epiweek") {
  if (!is.data.frame(observations) || !nrow(observations)) stop("Current observations are empty.", call. = FALSE)
  if (!identical(as.character(end_rule), "last_complete_epiweek")) stop("Only temporal.end_rule=last_complete_epiweek is supported by the production contract.", call. = FALSE)
  start <- production_orchestration_parse_week(start_epiweek)
  if (!"date" %in% names(observations)) stop("Dynamic horizon resolution requires a date column in the authoritative observations.", call. = FALSE)
  dates <- suppressWarnings(as.Date(as.character(observations$date), tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y")))
  valid <- !is.na(dates)
  if (!any(valid)) stop("Dynamic horizon resolution found no valid observation dates.", call. = FALSE)
  raw_max <- max(dates[valid])
  candidate_label <- production_orchestration_week_label(raw_max)
  candidate <- production_orchestration_parse_week(candidate_label)
  candidate_end <- production_orchestration_week_start(candidate$year, candidate$week) + 6L
  if (candidate_end > raw_max) {
    previous <- production_orchestration_week_start(candidate$year, candidate$week) - 7L
    candidate_label <- production_orchestration_week_label(previous)
    candidate <- production_orchestration_parse_week(candidate_label)
    candidate_end <- production_orchestration_week_start(candidate$year, candidate$week) + 6L
  }
  if (candidate_end < production_orchestration_week_start(start$year, start$week)) stop("Resolved final complete epiweek precedes configured start_epiweek.", call. = FALSE)
  weeks <- production_orchestration_week_sequence(start$label, candidate_label)
  excluded <- sum(valid & dates > candidate_end)
  list(
    configured_start_epiweek = start$label,
    resolved_final_complete_epiweek = candidate_label,
    resolved_final_complete_week_end = as.character(candidate_end),
    raw_max_observation_date = as.character(raw_max),
    observations_excluded_after_final_complete_week = as.integer(excluded),
    modeled_weeks = length(weeks),
    modeled_week_labels = weeks
  )
}

production_orchestration_git_commit <- function(repo_root) {
  value <- tryCatch(system2("git", c("-C", repo_root, "-c", "safe.directory=*", "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) NA_character_ else trimws(value[[1L]])
}

production_orchestration_git_branch <- function(repo_root) {
  value <- tryCatch(system2("git", c("-C", repo_root, "-c", "safe.directory=*", "branch", "--show-current"), stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) NA_character_ else trimws(value[[1L]])
}

production_orchestration_assert_resume_repository <- function(contract, repo_root) {
  recorded <- contract$repository$git_commit %||% NA_character_
  recorded <- if (length(recorded)) trimws(as.character(recorded[[1L]])) else NA_character_
  current <- production_orchestration_git_commit(repo_root)
  if (is.na(recorded) || !nzchar(recorded)) {
    stop("Cannot safely resume: run manifest does not record a repository git commit; manual review is required.", call. = FALSE)
  }
  if (is.na(current) || !nzchar(current)) {
    stop("Cannot safely resume: current repository git commit could not be determined.", call. = FALSE)
  }
  if (!identical(recorded, current)) {
    stop(
      "Resume repository SHA does not match the run manifest (recorded ", recorded,
      "; current ", current, ").",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

production_orchestration_run_id <- function(git_commit = NA_character_, now = Sys.time()) {
  short <- if (is.na(git_commit) || !nzchar(git_commit)) "nogit" else substr(git_commit, 1L, 8L)
  paste0(format(as.POSIXct(now, tz = "UTC"), "%Y%m%d_%H%M%S", tz = "UTC"), "_", short)
}

production_orchestration_normalize_chime_execution_id <- function(value) {
  if (is.null(value) || !length(value)) return(NA_character_)
  value <- as.character(value[[1L]])
  if (is.na(value)) return(NA_character_)
  value <- trimws(value)
  if (!nzchar(value)) NA_character_ else value
}

production_orchestration_environment_chime_execution_id <- function() {
  production_orchestration_normalize_chime_execution_id(Sys.getenv("CHIME_EXECUTION_ID", unset = ""))
}

production_orchestration_resolve_chime_execution_id <- function(stored = NULL, supplied = production_orchestration_environment_chime_execution_id()) {
  stored <- production_orchestration_normalize_chime_execution_id(stored)
  supplied <- production_orchestration_normalize_chime_execution_id(supplied)
  if (!is.na(stored) && !is.na(supplied) && !identical(stored, supplied)) {
    stop(
      "CHIME execution ID conflict on resume: run manifest contains '", stored,
      "' but CHIME_EXECUTION_ID supplies '", supplied, "'.",
      call. = FALSE
    )
  }
  list(
    value = if (is.na(stored)) supplied else stored,
    bound = is.na(stored) && !is.na(supplied)
  )
}

production_orchestration_rehydrate_chime_execution_id <- function(contract, supplied = production_orchestration_environment_chime_execution_id()) {
  resolution <- production_orchestration_resolve_chime_execution_id(contract$chime_execution_id, supplied)
  contract$chime_execution_id <- resolution$value
  list(contract = contract, bound = resolution$bound)
}

production_orchestration_read_config <- function(path, repo_root = getwd()) {
  production_orchestration_require("yaml")
  path <- normalizePath(path, mustWork = TRUE)
  cfg <- yaml::read_yaml(path)
  if (!is.list(cfg)) stop("Production config must be a YAML mapping.", call. = FALSE)
  if (is.null(cfg$project$output_root) || !nzchar(as.character(cfg$project$output_root))) stop("Production config requires project.output_root.", call. = FALSE)
  if (is.null(cfg$input$observations) || !nzchar(as.character(cfg$input$observations))) stop("Production config requires input.observations.", call. = FALSE)
  required_stage_configs <- c("preprocessing", "joint_model", "joint_inla", "fit")
  if (is.null(cfg$stage_configs) || length(setdiff(required_stage_configs, names(cfg$stage_configs)))) stop("Production config requires stage_configs for: ", paste(required_stage_configs, collapse = ", "), call. = FALSE)
  base_dir <- dirname(path)
  resolve_config <- function(value) {
    candidates <- unique(c(production_orchestration_resolve_path(value, base_dir), production_orchestration_resolve_path(value, repo_root)))
    candidates[file.exists(candidates)][1L]
  }
  cfg$config_path <- path
  cfg$repo_root <- normalizePath(repo_root, mustWork = TRUE)
  cfg$input$observations <- production_orchestration_resolve_path(cfg$input$observations, base_dir)
  cfg$project$output_root <- production_orchestration_resolve_path(cfg$project$output_root, base_dir)
  for (name in required_stage_configs) {
    resolved <- resolve_config(cfg$stage_configs[[name]])
    if (is.na(resolved) || !length(resolved)) stop("Stage config does not exist for ", name, ": ", cfg$stage_configs[[name]], call. = FALSE)
    cfg$stage_configs[[name]] <- normalizePath(resolved, mustWork = TRUE)
  }
  if (is.null(cfg$temporal$start_epiweek)) stop("Production config requires temporal.start_epiweek.", call. = FALSE)
  if (is.null(cfg$temporal$end_rule)) cfg$temporal$end_rule <- "last_complete_epiweek"
  policy <- cfg$projection$unseen_admin_policy %||% "fail"
  policy <- tolower(trimws(as.character(policy[[1L]])))
  if (!policy %in% c("fail", "zero_mean")) {
    stop("projection.unseen_admin_policy must be one of: fail, zero_mean.", call. = FALSE)
  }
  cfg$projection <- cfg$projection %||% list()
  cfg$projection$unseen_admin_policy <- policy
  cfg
}

production_orchestration_administrative_support_summary <- function(audit, policy, audit_path = NA_character_) {
  policy <- tolower(trimws(as.character(policy[[1L]])))
  if (!policy %in% c("fail", "zero_mean")) stop("Unsupported unseen administrative support policy: ", policy, call. = FALSE)
  observed <- function(check, default = 0) {
    if (!is.data.frame(audit) || !all(c("check", "observed") %in% names(audit))) return(default)
    value <- audit$observed[match(check, audit$check)]
    if (!length(value) || is.na(value)) default else value[[1L]]
  }
  unseen_levels <- as.character(observed("prediction_only_admin_ids", ""))
  unseen_levels <- if (!nzchar(unseen_levels)) character() else strsplit(unseen_levels, ",", fixed = TRUE)[[1L]]
  unseen_levels <- unseen_levels[nzchar(unseen_levels)]
  unseen_count <- suppressWarnings(as.integer(observed("prediction_only_levels", 0)))
  list(
    policy = policy,
    unseen_support_used = isTRUE(unseen_count > 0L),
    affected_admin_levels = unseen_levels,
    affected_admin_level_count = as.integer(unseen_count),
    affected_prediction_rows = suppressWarnings(as.integer(observed("prediction_rows_affected", 0))),
    affected_prediction_cells = suppressWarnings(as.integer(observed("prediction_cells_affected", 0))),
    affected_prediction_weeks = suppressWarnings(as.integer(observed("prediction_weeks_affected", 0))),
    audit_path = if (is.na(audit_path)) NA_character_ else normalizePath(audit_path, mustWork = FALSE),
    audit_sha256 = if (is.na(audit_path) || !file.exists(audit_path)) NA_character_ else production_orchestration_hash_file(audit_path)
  )
}

production_orchestration_read_stage_configs <- function(cfg) {
  production_orchestration_require("yaml")
  lapply(cfg$stage_configs, function(path) yaml::read_yaml(path))
}

production_orchestration_dimension_contract <- function(stage2_path, build_path = NULL) {
  stage2 <- readRDS(stage2_path)
  grid <- stage2$prediction_grid
  if (!is.data.frame(grid) || !all(c("epiyear", "epiweek") %in% names(grid))) stop("Stage 2 prediction_grid cannot establish dynamic dimensions.", call. = FALSE)
  week_key <- paste(as.integer(grid$epiyear), sprintf("W%02d", as.integer(grid$epiweek)), sep = "-")
  order_index <- if ("time_index" %in% names(grid)) order(as.integer(grid$time_index), as.integer(grid$epiyear), as.integer(grid$epiweek)) else order(as.integer(grid$epiyear), as.integer(grid$epiweek))
  weeks <- unique(week_key[order_index])
  if (!all(c("x", "y") %in% names(grid))) stop("Stage 2 prediction_grid lacks x/y support coordinates.", call. = FALSE)
  cells <- unique(grid[c("x", "y", if ("cell_id" %in% names(grid)) "cell_id" else character())])
  temporal <- stage2$temporal_mapping
  if (!is.data.frame(temporal)) stop("Stage 2 temporal_mapping is required for dynamic group dimensions.", call. = FALSE)
  contiguous_levels <- function(data, name) {
    if (!name %in% names(data)) stop("Stage 2 temporal_mapping is missing dynamic group field: ", name, call. = FALSE)
    values <- suppressWarnings(as.integer(data[[name]]))
    levels <- sort(unique(values))
    if (!length(levels) || anyNA(values) || !identical(levels, seq_len(max(levels)))) stop("Stage 2 group field ", name, " is not positive and contiguous from 1:n_groups.", call. = FALSE)
    levels
  }
  two_week_levels <- contiguous_levels(temporal, "timestep_2wk")
  quarter_levels <- contiguous_levels(temporal, "quarter_index")
  six_month_levels <- contiguous_levels(temporal, "sixmo_index")
  year_levels <- contiguous_levels(temporal, "year_index")
  grid_quarter <- suppressWarnings(as.integer(grid$quarter_index))
  if (anyNA(grid_quarter) || !identical(sort(unique(grid_quarter)), quarter_levels)) stop("Stage 2 prediction_grid quarter_index levels disagree with temporal_mapping.", call. = FALSE)
  groups <- list(
    two_week_groups = length(two_week_levels), quarter_groups = length(quarter_levels),
    six_month_groups = length(six_month_levels), year_groups = length(year_levels),
    levels = list(two_week = two_week_levels, quarter = quarter_levels, six_month = six_month_levels, year = year_levels)
  )
  list(
    modeled_weeks = length(weeks), week_labels = weeks, supported_cells = nrow(cells), prediction_rows = nrow(grid),
    expected_prediction_rows = nrow(cells) * length(weeks), groups = groups,
    horizon_start = weeks[[1L]], horizon_end = weeks[[length(weeks)]],
    stage2_path = normalizePath(stage2_path, mustWork = TRUE), stage2_sha256 = production_orchestration_hash_file(stage2_path),
    build_path = if (is.null(build_path)) NA_character_ else normalizePath(build_path, mustWork = FALSE),
    build_sha256 = if (is.null(build_path) || !file.exists(build_path)) NA_character_ else production_orchestration_hash_file(build_path)
  )
}

production_orchestration_scheduler_config <- function(cfg) {
  defaults <- list(account = "disease_ecology", partition = "bigmem", prepare = list(cpus = 4L, mem = "64G", time = "08:00:00"), fit = list(cpus = 12L, mem = "280G", time = "36:00:00"), postfit = list(cpus = 4L, mem = "64G", time = "12:00:00"))
  supplied <- cfg$scheduler %||% list()
  merge_profile <- function(default, value) {
    if (is.null(value)) return(default)
    for (name in names(value)) default[[name]] <- value[[name]]
    default
  }
  list(account = as.character(supplied$account %||% defaults$account), partition = as.character(supplied$partition %||% defaults$partition), prepare = merge_profile(defaults$prepare, supplied$prepare), fit = merge_profile(defaults$fit, supplied$fit), postfit = merge_profile(defaults$postfit, supplied$postfit))
}

production_orchestration_runtime_identity <- function() {
  profile <- Sys.getenv("ATLAS_RUNTIME_PROFILE", unset = "atlas-r44-spatial-v1")
  if (!identical(profile, "atlas-r44-spatial-v1")) {
    stop("Unsupported Atlas runtime profile: ", profile, call. = FALSE)
  }
  list(
    platform = "atlas",
    module_profile = profile,
    modules = c(
      "udunits/2.2.28", "proj/9.7.0", "geos/3.12.1", "gdal/3.8.5",
      "intel-oneapi-mkl/2023.2.0", "r/4.4.3"
    ),
    wrapper = "scripts/run_pipeline_atlas.sh",
    preflight = if (identical(Sys.getenv("ATLAS_RUNTIME_PREFLIGHT", unset = ""), "PASS")) "PASS" else "NOT_RUN",
    r_version = as.character(R.version.string)
  )
}

production_orchestration_assert_runtime_preflight <- function(mode) {
  if (!mode %in% c("submit", "stage")) return(invisible(TRUE))
  profile <- Sys.getenv("ATLAS_RUNTIME_PROFILE", unset = "")
  preflight <- Sys.getenv("ATLAS_RUNTIME_PREFLIGHT", unset = "")
  if (!identical(profile, "atlas-r44-spatial-v1") || !identical(preflight, "PASS")) {
    stop(
      "Atlas runtime preflight is required before ", mode,
      " execution; use scripts/submit_full_pipeline.sh or scripts/run_pipeline_atlas.sh.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

production_orchestration_stage_wrapper <- function(repo_root) {
  normalizePath(file.path(repo_root, "scripts", "run_pipeline_atlas.sh"), mustWork = TRUE)
}

production_orchestration_stage_command <- function(repo_root, stage_args) {
  production_orchestration_command_text("bash", production_orchestration_stage_wrapper(repo_root), stage_args)
}

production_orchestration_contract <- function(config_path, repo_root, run_id = NULL, run_root = NULL) {
  cfg <- production_orchestration_read_config(config_path, repo_root)
  stages <- production_orchestration_read_stage_configs(cfg)
  observations <- utils::read.csv(cfg$input$observations, stringsAsFactors = FALSE, check.names = FALSE)
  git_commit <- production_orchestration_git_commit(repo_root)
  run_id <- run_id %||% production_orchestration_run_id(git_commit)
  if (!grepl("^[A-Za-z0-9_.-]+$", run_id)) stop("run_id contains unsupported characters.", call. = FALSE)
  horizon <- production_orchestration_resolve_horizon(observations, cfg$temporal$start_epiweek, cfg$temporal$end_rule)
  root <- run_root %||% file.path(cfg$project$output_root, run_id)
  root <- normalizePath(root, mustWork = FALSE)
  list(
    run_id = run_id, run_root = root, chime_execution_id = production_orchestration_environment_chime_execution_id(),
    administrative_support_policy = cfg$projection$unseen_admin_policy,
    administrative_support_summary = NULL,
    repository = list(root = normalizePath(repo_root, mustWork = TRUE), branch = production_orchestration_git_branch(repo_root), git_commit = git_commit),
    runtime = production_orchestration_runtime_identity(),
    config = list(path = normalizePath(config_path, mustWork = TRUE), sha256 = production_orchestration_hash_file(config_path)),
    input = list(observations = normalizePath(cfg$input$observations, mustWork = TRUE), sha256 = production_orchestration_hash_file(cfg$input$observations), rows = nrow(observations), columns = names(observations), coordinate_fields = c("lon", "lat"), crs = "EPSG:4326"),
    submission_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), horizon = horizon, dynamic_dimensions = NULL,
    dynamic_rpi_threshold = NA_real_, final_reporting_path = NA_character_, final_summary_path = NA_character_, overall_status = "SUBMITTED",
    prepare_gate_status = "NOT_RUN", fit_gate_status = "NOT_RUN", postfit_gate_status = "NOT_RUN",
    warning_count = 0L, gate_results = list(),
    stage_configs = cfg$stage_configs, settings = list(cfg = cfg, stages = stages), scheduler = production_orchestration_scheduler_config(cfg),
    job_ids = list(prepare = NA_character_, fit = NA_character_, postfit = NA_character_),
    paths = list(stage1 = file.path(root, "stage1"), stage2 = file.path(root, "stage2"), stage3a = file.path(root, "stage3a"), preflight = file.path(root, "preflight"), stage3b = file.path(root, "stage3b"), fit_health = file.path(root, "fit_health"), extraction = file.path(root, "extraction"), validation = file.path(root, "validation"), projection = file.path(root, "projection"), raster = file.path(root, "raster"), structural = file.path(root, "structural"), masked = file.path(root, "masked_structural_rpi"), reporting = file.path(root, "reporting"), metadata = file.path(root, "metadata"), logs = file.path(root, "logs"))
  )
}

production_orchestration_write_yaml <- function(object, path) {
  production_orchestration_require("yaml")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(object, path)
  normalizePath(path, mustWork = TRUE)
}

production_orchestration_write_stage_configs <- function(contract) {
  stages <- contract$settings$stages
  paths <- contract$paths
  configs <- file.path(paths$metadata, "generated_configs")
  dir.create(configs, recursive = TRUE, showWarnings = FALSE)
  preprocessing <- stages$preprocessing
  preprocessing$project$output_directory <- paths$stage1
  preprocessing$inputs$observations <- contract$input$observations
  preprocessing$temporal$start_week <- contract$horizon$configured_start_epiweek
  preprocessing$temporal$end_week <- contract$horizon$resolved_final_complete_epiweek
  preprocessing$temporal$end_rule <- "orchestrator_resolved_last_complete_epiweek"
  joint_model <- stages$joint_model
  joint_model$project$output_directory <- paths$stage2
  joint_model$inputs$model_inputs <- file.path(paths$stage1, "model_inputs.rds")
  joint_model$outputs$joint_model_inputs <- "joint_model_inputs.rds"
  joint_model$outputs$preparation_audit <- "joint_model_preparation_audit.csv"
  joint_inla <- stages$joint_inla
  joint_inla$project$output_directory <- paths$stage3a
  joint_inla$inputs$joint_model_inputs <- file.path(paths$stage2, "joint_model_inputs.rds")
  joint_inla$outputs$build <- "joint_inla_build.rds"
  joint_inla$outputs$audit <- "joint_inla_build_audit.csv"
  fit <- stages$fit
  fit$project$output_directory <- paths$stage3b
  fit$inputs$stage3a_build <- file.path(paths$stage3a, "joint_inla_build.rds")
  fit$outputs$fit <- "joint_model_fit.rds"
  fit$outputs$audit <- "joint_model_fit_audit.csv"
  fit$outputs$metadata <- "joint_model_fit_metadata.rds"
  fit$outputs$theta_init <- "joint_model_theta_init.rds"
  fit$outputs$preflight <- "joint_inla_fit_preflight.csv"
  fit$outputs$overwrite <- FALSE
  fit$threads$num_threads <- as.integer(contract$scheduler$fit$cpus)
  contract$generated_configs <- list(
    preprocessing = production_orchestration_write_yaml(preprocessing, file.path(configs, "preprocessing.yml")),
    joint_model = production_orchestration_write_yaml(joint_model, file.path(configs, "joint_model.yml")),
    joint_inla = production_orchestration_write_yaml(joint_inla, file.path(configs, "joint_inla.yml")),
    fit = production_orchestration_write_yaml(fit, file.path(configs, "joint_inla_fit.yml"))
  )
  contract
}

production_orchestration_write_manifest <- function(contract, path = file.path(contract$paths$metadata, "run_manifest.yml")) {
  manifest <- contract
  manifest$settings <- NULL
  production_orchestration_write_yaml(manifest, path)
  invisible(path)
}

production_orchestration_write_final_summary <- function(contract, path = file.path(contract$paths$metadata, "production_summary.yml")) {
  summary <- list(
    status = "PRODUCTION PIPELINE COMPLETE",
    run_id = contract$run_id,
    chime_execution_id = contract$chime_execution_id %||% NA_character_,
    administrative_support = contract$administrative_support_summary %||% list(policy = contract$administrative_support_policy %||% "fail", unseen_support_used = FALSE),
    stages = list(prepare = contract$prepare_gate_status %||% "NOT_RUN", fit = contract$fit_gate_status %||% "NOT_RUN", postfit = contract$postfit_gate_status %||% "NOT_RUN"),
    runtime = contract$runtime %||% list(),
    modeled_weeks = contract$dynamic_dimensions$modeled_weeks %||% NA_integer_,
    supported_cells = contract$dynamic_dimensions$supported_cells %||% NA_integer_,
    prediction_rows = contract$dynamic_dimensions$prediction_rows %||% NA_integer_,
    dynamic_rpi_threshold = contract$dynamic_rpi_threshold %||% NA_real_,
    run_manifest = file.path(contract$paths$metadata, "run_manifest.yml"),
    upstream_provenance = contract$upstream_provenance %||% list(),
    final_reporting_path = contract$final_reporting_path %||% NA_character_,
    overall_status = contract$overall_status %||% "PASS",
    prepare_gate_status = contract$prepare_gate_status %||% "NOT_RUN",
    fit_gate_status = contract$fit_gate_status %||% "NOT_RUN",
    postfit_gate_status = contract$postfit_gate_status %||% "NOT_RUN",
    warning_count = contract$warning_count %||% 0L
  )
  production_orchestration_write_yaml(summary, path)
  normalizePath(path, mustWork = TRUE)
}

production_orchestration_read_manifest <- function(path) {
  production_orchestration_require("yaml")
  if (!file.exists(path)) stop("Run manifest does not exist: ", path, call. = FALSE)
  yaml::read_yaml(path)
}

production_orchestration_write_status <- function(contract, stage, status, start_time = NULL, end_time = Sys.time(), warnings = character(), error = NULL, job_id = Sys.getenv("SLURM_JOB_ID", unset = "not-under-scheduler"), input_artifact = NULL, output_artifact = NULL) {
  status <- toupper(status)
  if (!status %in% c("PASS", "WARNING", "FAIL", "SKIPPED", "RUNNING")) stop("Unsupported orchestration status: ", status, call. = FALSE)
  artifact_path <- function(path) if (is.null(path) || !length(path) || is.na(path[[1L]]) || !file.exists(path[[1L]])) NA_character_ else normalizePath(path[[1L]], mustWork = TRUE)
  artifact_sha <- function(path) if (is.null(path) || !length(path) || is.na(path[[1L]]) || !file.exists(path[[1L]]) || !requireNamespace("digest", quietly = TRUE)) NA_character_ else digest::digest(file = path[[1L]], algo = "sha256")
  input_path <- artifact_path(input_artifact); output_path <- artifact_path(output_artifact)
  output <- list(stage = stage, status = status, start_time_utc = if (is.null(start_time)) NA_character_ else format(as.POSIXct(start_time, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), end_time_utc = format(as.POSIXct(end_time, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), job_id = as.character(job_id), git_commit = contract$repository$git_commit, input_artifact = input_path, input_sha = artifact_sha(input_artifact), output_artifact = output_path, output_sha = artifact_sha(output_artifact), warnings = as.character(warnings), error = if (is.null(error)) NA_character_ else conditionMessage(error))
  path <- file.path(contract$paths$metadata, paste0("status_", stage, ".yml"))
  production_orchestration_write_yaml(output, path)
  output
}

production_orchestration_stage_alias <- function(stage) {
  stage <- tolower(as.character(stage))
  if (stage %in% c("stage1", "stage2", "stage3a", "prepare")) return("prepare")
  if (stage %in% c("stage3b", "fit")) return("fit")
  if (stage %in% c("postfit", "extraction", "validation", "projection", "raster", "structural", "rpi", "reporting")) return("postfit")
  stop("Unknown pipeline stage alias: ", stage, call. = FALSE)
}

production_orchestration_select_resume_stage <- function(statuses, from = NULL, through = "postfit") {
  through <- production_orchestration_stage_alias(through)
  if (!is.null(from)) return(production_orchestration_stage_alias(from))
  for (stage in c("prepare", "fit", "postfit")) {
    if (stage == "postfit" && through != "postfit") break
    if (is.null(statuses[[stage]]) || !toupper(as.character(statuses[[stage]]$status)) %in% c("PASS", "WARNING")) return(stage)
  }
  NULL
}

production_orchestration_command_text <- function(rscript, script, args) {
  paste(c(shQuote(rscript, type = "sh"), shQuote(script, type = "sh"), vapply(args, shQuote, character(1L), type = "sh")), collapse = " ")
}

production_orchestration_sbatch_wrap_arg <- function(command) {
  paste0("--wrap=", shQuote(command, type = "sh"))
}

