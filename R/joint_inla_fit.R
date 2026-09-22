joint_inla_fit_hash_file <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(as.character(path)) ||
      !file.exists(path) || !requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  tryCatch(digest::digest(file = path, algo = "sha256"), error = function(e) NA_character_)
}

joint_inla_fit_require_inla <- function() {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("Stage 3B requires the INLA package.")
  invisible(TRUE)
}

joint_inla_fit_validate_build <- function(build, build_path = NULL) {
  if (!is.list(build)) stop("Stage 3A artifact must contain a list-like joint_inla_build object.")
  required <- c("formula", "family", "stacks", "priors", "fit_reference", "provenance", "config")
  missing <- setdiff(required, names(build))
  if (length(missing)) stop("Stage 3A artifact is missing required sections: ", paste(missing, collapse = ", "))
  if (!inherits(build$formula, "formula")) stop("Stage 3A artifact formula is not an R formula.")
  if (!identical(as.character(build$family), c("binomial", "nbinomial"))) {
    stop("Stage 3A artifact must inherit family = c('binomial', 'nbinomial').")
  }
  if (!is.list(build$stacks) || is.null(build$stacks$joint)) stop("Stage 3A artifact is missing stacks$joint.")
  if (!is.list(build$fit_reference)) stop("Stage 3A artifact fit_reference must be a list.")
  if (!is.list(build$provenance)) stop("Stage 3A artifact provenance must be a list.")
  if (!isFALSE(build$provenance$executed_fit)) {
    stop("Stage 3B requires a Stage 3A artifact with provenance$executed_fit == FALSE.")
  }
  if (is.null(build$provenance$stage) || !identical(as.character(build$provenance$stage), "joint_inla_assembly")) {
    stop("Stage 3A artifact provenance does not identify a joint_inla_assembly.")
  }
  if (!is.list(build$config)) stop("Stage 3A artifact config must be a list.")
  invisible(TRUE)
}

joint_inla_fit_read_build <- function(path) {
  if (!file.exists(path)) stop("Stage 3A joint_inla_build.rds does not exist: ", path)
  build <- readRDS(path)
  joint_inla_fit_validate_build(build, path)
  build
}

joint_inla_fit_runtime_version <- function() {
  joint_inla_fit_require_inla()
  as.character(utils::packageVersion("INLA"))
}

joint_inla_fit_version_check <- function(build, cfg, runtime_version = NULL, emit_warning = TRUE) {
  if (is.null(runtime_version)) runtime_version <- joint_inla_fit_runtime_version()
  expected <- build$provenance$INLA
  expected <- if (is.null(expected) || !length(expected) || is.na(expected[[1L]])) NA_character_ else as.character(expected[[1L]])
  compatible <- !is.na(expected) && identical(as.character(runtime_version), expected)
  if (is.na(expected)) {
    message <- paste0("Cannot verify INLA compatibility: Stage 3A provenance does not record an INLA version; runtime is ", runtime_version, ".")
    if (identical(cfg$version_compatibility$policy, "error")) stop(message)
    if (isTRUE(emit_warning)) warning(message, call. = FALSE)
    return(list(compatible = NA, expected = expected, runtime = runtime_version, message = message))
  }
  if (!compatible) {
    message <- paste0("INLA version mismatch: Stage 3A was assembled with INLA ", expected,
                      ", but Stage 3B is running with INLA ", runtime_version,
                      ". Reference defaults, including likelihood hyperpriors, may differ.")
    if (identical(cfg$version_compatibility$policy, "error")) stop(message)
    if (isTRUE(emit_warning)) warning(message, call. = FALSE)
    return(list(compatible = FALSE, expected = expected, runtime = runtime_version, message = message))
  }
  list(compatible = TRUE, expected = expected, runtime = runtime_version, message = NULL)
}

joint_inla_fit_compact_hyperprior <- function(model) {
  if (is.null(model) || is.null(model$hyper)) return(list(available = FALSE, reason = "No nbinomial hyperprior metadata was exposed."))
  compact <- lapply(model$hyper, function(specification) {
    keys <- intersect(c("name", "short.name", "prior", "param", "initial", "fixed"), names(specification))
    values <- specification[keys]
    lapply(values, function(value) {
      if (is.logical(value)) isTRUE(value) else if (is.numeric(value)) as.numeric(value) else as.character(value)
    })
  })
  list(available = TRUE, model = "nbinomial", hyper = compact)
}

joint_inla_fit_effective_nbinomial_prior <- function() {
  joint_inla_fit_require_inla()
  tryCatch({
    models <- INLA::inla.models()
    likelihood <- models[["likelihood"]]
    model <- likelihood[["nbinomial"]]
    if (is.null(model)) return(list(available = FALSE, reason = "INLA does not expose likelihood nbinomial."))
    joint_inla_fit_compact_hyperprior(model)
  }, error = function(e) {
    list(available = FALSE, reason = paste0("Unable to introspect the runtime nbinomial hyperprior: ", conditionMessage(e)))
  })
}

joint_inla_fit_initialization <- function(build, cfg) {
  mode <- tolower(as.character(cfg$fit$initialization$mode))
  if (identical(mode, "default")) return(list(mode = mode, control_mode = NULL, theta_length = NA_integer_))
  historical <- build$fit_reference$control_mode
  if (!is.list(historical) || is.null(historical$theta)) {
    stop("Historical initialization was requested, but Stage 3A fit_reference$control_mode$theta is unavailable.")
  }
  theta <- as.numeric(historical$theta)
  if (!length(theta) || any(!is.finite(theta))) stop("Historical initialization theta must be a finite numeric vector.")
  list(mode = mode, control_mode = list(restart = FALSE, theta = theta), theta_length = length(theta))
}

joint_inla_fit_thread_argument <- function(cfg) {
  num_threads <- as.integer(cfg$threads$num_threads)
  blas_threads <- cfg$threads$blas_threads
  if (is.null(blas_threads)) return(num_threads)
  paste(num_threads, as.integer(blas_threads), sep = ":")
}

joint_inla_fit_control_value <- function(control, dotted_name, underscored_name = sub("\\.", "_", dotted_name)) {
  if (!is.null(control[[dotted_name]])) return(control[[dotted_name]])
  control[[underscored_name]]
}

joint_inla_fit_control_predictor <- function(cfg, A, link) {
  control <- cfg$fit$control_predictor
  if (is.null(control)) control <- list()
  if (!is.list(control)) stop("fit.control_predictor must be a list.")
  control$A <- A
  control$link <- link
  control$compute <- TRUE
  control
}

joint_inla_fit_construct_call <- function(build, cfg, initialization = NULL) {
  joint_inla_fit_require_inla()
  if (is.null(initialization)) initialization <- joint_inla_fit_initialization(build, cfg)
  data <- INLA::inla.stack.data(build$stacks$joint)
  A <- INLA::inla.stack.A(build$stacks$joint)
  if (is.null(data$e) || is.null(data$link)) stop("Stage 3A joint stack data must contain e and link vectors.")
  if (length(data$e) != length(data$link)) stop("Stage 3A joint stack e and link vectors must have the same length.")

  call <- list(
    formula = build$formula,
    data = data,
    family = build$family,
    E = data$e,
    quantiles = as.numeric(cfg$fit$quantiles),
    control.fixed = cfg$fit$control_fixed,
    control.inla = cfg$fit$control_inla,
    control.compute = cfg$fit$control_compute,
    control.predictor = joint_inla_fit_control_predictor(cfg, A, data$link),
    num.threads = joint_inla_fit_thread_argument(cfg)
  )
  if (!is.null(initialization$control_mode)) call$control.mode <- initialization$control_mode
  if (!is.null(cfg$fit$control_family)) call$control.family <- cfg$fit$control_family
  call
}

joint_inla_fit_call_metadata <- function(call, cfg, initialization) {
  list(
    argument_names = names(call),
    formula_source = "build$formula",
    data_source = "INLA::inla.stack.data(build$stacks$joint)",
    predictor_A_source = "control.predictor$A <- INLA::inla.stack.A(build$stacks$joint)",
    family_source = "build$family",
    exposure_source = "data$e",
    link_source = "control.predictor$link <- data$link",
    initialization_mode = initialization$mode,
    num_threads = as.integer(cfg$threads$num_threads),
    blas_threads = if (is.null(cfg$threads$blas_threads)) NA_integer_ else as.integer(cfg$threads$blas_threads),
    control_family_overridden = !is.null(cfg$fit$control_family)
  )
}

joint_inla_fit_iso_timestamp <- function(value = Sys.time()) {
  format(value, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

joint_inla_fit_text <- function(value, missing = NA_character_) {
  if (is.null(value) || !length(value)) return(missing)
  if (length(value) == 1L && is.na(value)) return(missing)
  paste(as.character(value), collapse = ",")
}

joint_inla_fit_dput <- function(value) {
  if (is.null(value)) return(NA_character_)
  paste(capture.output(dput(value)), collapse = "")
}

joint_inla_fit_git_commit <- function(repo_root) {
  if (!nzchar(Sys.which("git"))) return(NA_character_)
  value <- tryCatch(suppressWarnings(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (!length(value) || !nzchar(value[[1L]])) NA_character_ else value[[1L]]
}

joint_inla_fit_source_provenance <- function(build, build_path, cfg, paths, runtime_version, version_check, effective_prior) {
  build_provenance <- build$provenance
  stage2_path <- build_provenance$source_artifact
  if (is.null(stage2_path) || !length(stage2_path)) stage2_path <- build$config$inputs$joint_model_inputs
  stage1_path <- build_provenance$stage1_artifact %||% build_provenance$source_stage1_artifact
  list(
    stage = "joint_inla_fit",
    chain = list(
      stage1 = list(artifact_path = if (is.null(stage1_path)) NA_character_ else as.character(stage1_path)),
      stage2 = list(
        artifact_path = if (is.null(stage2_path)) NA_character_ else as.character(stage2_path),
        artifact_sha256 = if (is.null(build_provenance$source_artifact_sha256)) NA_character_ else as.character(build_provenance$source_artifact_sha256)
      ),
      stage3a = list(
        artifact_path = build_path,
        artifact_sha256 = joint_inla_fit_hash_file(build_path),
        assembled_with_inla = if (is.null(build_provenance$INLA)) NA_character_ else as.character(build_provenance$INLA),
        executed_fit = FALSE
      ),
      stage3b = list(
        config_path = cfg$config_path,
        output_fit = paths$fit,
        output_audit = paths$audit,
        output_metadata = paths$metadata,
        output_preflight = paths$preflight,
        runtime_inla = runtime_version,
        version_compatible = version_check$compatible
      )
    ),
    likelihood = list(
      family = c("binomial", "nbinomial"),
      reference_nbinomial_hyperprior = build$fit_reference$nbinomial_default,
      effective_runtime_nbinomial_hyperprior = effective_prior,
      configured_control_family = cfg$fit$control_family,
      overridden = !is.null(cfg$fit$control_family)
    )
  )
}

joint_inla_fit_summary_values <- function(fit) {
  if (is.null(fit)) {
    return(list(number_hyperparameters = NA_integer_, number_fixed_effects = NA_integer_,
                number_random_effect_components = NA_integer_, dic = NA_real_, waic = NA_real_,
                marginal_log_likelihood = NA_real_))
  }
  n_hyper <- if (!is.null(fit$summary.hyperpar)) nrow(fit$summary.hyperpar) else NA_integer_
  n_fixed <- if (!is.null(fit$summary.fixed)) nrow(fit$summary.fixed) else NA_integer_
  n_random <- if (!is.null(fit$summary.random)) length(fit$summary.random) else NA_integer_
  dic <- if (!is.null(fit$dic$dic)) as.numeric(fit$dic$dic)[[1L]] else NA_real_
  waic <- if (!is.null(fit$waic$waic)) as.numeric(fit$waic$waic)[[1L]] else NA_real_
  mlik <- NA_real_
  if (!is.null(fit$mlik)) {
    if (is.data.frame(fit$mlik) || is.matrix(fit$mlik)) {
      col <- grep("log marginal likelihood", colnames(fit$mlik), ignore.case = TRUE)
      if (length(col)) mlik <- as.numeric(fit$mlik[1L, col[[1L]]])
    } else if (is.numeric(fit$mlik) && length(fit$mlik)) {
      mlik <- as.numeric(fit$mlik[[1L]])
    }
  }
  list(number_hyperparameters = n_hyper, number_fixed_effects = n_fixed,
       number_random_effect_components = n_random, dic = dic, waic = waic,
       marginal_log_likelihood = mlik)
}

joint_inla_fit_make_audit <- function(status, started, ended, build, build_path, cfg, paths,
                                      runtime_version, version_check, initialization,
                                      effective_prior, warnings_captured = character(), fit = NULL,
                                      error_message = NULL, dry_run = FALSE) {
  summary <- joint_inla_fit_summary_values(fit)
  stage2_path <- build$provenance$source_artifact
  if (is.null(stage2_path) || !length(stage2_path)) stage2_path <- build$config$inputs$joint_model_inputs
  stage1_path <- build$provenance$stage1_artifact %||% build$provenance$source_stage1_artifact
  row <- list(
    fit_status = status,
    start_timestamp = joint_inla_fit_iso_timestamp(started),
    end_timestamp = joint_inla_fit_iso_timestamp(ended),
    elapsed_seconds = as.numeric(difftime(ended, started, units = "secs")),
    r_version = R.version.string,
    inla_version = runtime_version,
    git_commit = joint_inla_fit_git_commit(cfg$repo_root),
    hostname = unname(Sys.info()[["nodename"]]),
    stage1_artifact_path = if (is.null(stage1_path)) NA_character_ else as.character(stage1_path),
    stage2_artifact_path = if (is.null(stage2_path)) NA_character_ else as.character(stage2_path),
    stage2_artifact_sha256 = if (is.null(build$provenance$source_artifact_sha256)) NA_character_ else as.character(build$provenance$source_artifact_sha256),
    stage3a_artifact_path = build_path,
    stage3a_artifact_sha256 = joint_inla_fit_hash_file(build_path),
    stage3a_inla_version = if (is.null(build$provenance$INLA)) NA_character_ else as.character(build$provenance$INLA),
    stage3b_config_path = cfg$config_path,
    family_1 = build$family[[1L]],
    family_2 = build$family[[2L]],
    initialization_mode = initialization$mode,
    historical_theta_length = initialization$theta_length,
    thread_count = as.integer(cfg$threads$num_threads),
    blas_thread_count = if (is.null(cfg$threads$blas_threads)) NA_integer_ else as.integer(cfg$threads$blas_threads),
    inla_thread_argument = joint_inla_fit_thread_argument(cfg),
    inla_strategy = joint_inla_fit_text(cfg$fit$control_inla$strategy),
    integration_strategy = joint_inla_fit_text(joint_inla_fit_control_value(cfg$fit$control_inla, "int.strategy")),
    dic_requested = isTRUE(cfg$fit$control_compute$dic),
    waic_requested = isTRUE(cfg$fit$control_compute$waic),
    cpo_requested = isTRUE(cfg$fit$control_compute$cpo),
    control_family_overridden = !is.null(cfg$fit$control_family),
    version_compatible = version_check$compatible,
    convergence_fit_completion = identical(status, "success"),
    number_hyperparameters = summary$number_hyperparameters,
    number_fixed_effects = summary$number_fixed_effects,
    number_random_effect_components = summary$number_random_effect_components,
    dic = summary$dic,
    waic = summary$waic,
    marginal_log_likelihood = summary$marginal_log_likelihood,
    effective_likelihood_hyperprior = joint_inla_fit_dput(effective_prior),
    reference_likelihood_hyperprior = joint_inla_fit_dput(build$fit_reference$nbinomial_default),
    configured_control_family = joint_inla_fit_dput(cfg$fit$control_family),
    warnings_captured = if (length(warnings_captured)) paste(unique(warnings_captured), collapse = " | ") else NA_character_,
    error_message = if (is.null(error_message)) NA_character_ else as.character(error_message),
    dry_run = isTRUE(dry_run)
  )
  as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
}

joint_inla_fit_output_preflight <- function(paths, overwrite = FALSE) {
  if (length(unique(unlist(paths))) != length(paths)) stop("Stage 3B output paths must be distinct.")
  existing <- vapply(paths, file.exists, logical(1L))
  if (any(existing) && !isTRUE(overwrite)) {
    stop("Refusing to overwrite existing Stage 3B output(s): ", paste(unname(paths[existing]), collapse = ", "),
         ". Set outputs.overwrite: true or pass --overwrite explicitly.")
  }
  invisible(existing)
}

joint_inla_fit_commit_file <- function(staged, target, overwrite = FALSE) {
  if (file.exists(target)) {
    if (!isTRUE(overwrite)) stop("Refusing to overwrite existing output: ", target)
    if (!file.remove(target)) stop("Unable to remove existing output for explicit overwrite: ", target)
  }
  if (file.rename(staged, target)) return(invisible(TRUE))
  if (!file.copy(staged, target, overwrite = FALSE)) stop("Unable to move staged output to: ", target)
  file.remove(staged)
  invisible(TRUE)
}

joint_inla_fit_write_outputs <- function(fit_artifact, metadata, audit, paths, overwrite = FALSE) {
  for (path in paths) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  stage_dir <- tempfile("joint-inla-fit-stage-", tmpdir = dirname(paths$fit))
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)
  staged_fit <- file.path(stage_dir, "fit.rds")
  staged_metadata <- file.path(stage_dir, "metadata.rds")
  staged_audit <- file.path(stage_dir, "audit.csv")
  saveRDS(fit_artifact, staged_fit)
  saveRDS(metadata, staged_metadata)
  utils::write.csv(audit, staged_audit, row.names = FALSE, na = "NA")
  joint_inla_fit_commit_file(staged_metadata, paths$metadata, overwrite)
  joint_inla_fit_commit_file(staged_audit, paths$audit, overwrite)
  joint_inla_fit_commit_file(staged_fit, paths$fit, overwrite)
  invisible(TRUE)
}

joint_inla_fit_failure_audit_path <- function(paths) {
  if (!file.exists(paths$fit)) return(paths$audit)
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  stem <- sub("\\.csv$", "", basename(paths$audit), ignore.case = TRUE)
  file.path(dirname(paths$audit), paste0(stem, "_failure_", stamp, ".csv"))
}

joint_inla_fit_write_failure_audit <- function(audit, paths, overwrite = FALSE) {
  target <- joint_inla_fit_failure_audit_path(paths)
  if (file.exists(target) && !isTRUE(overwrite)) {
    warning("Could not write failure audit because it already exists: ", target, call. = FALSE)
    return(target)
  }
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  staged <- tempfile("joint-inla-failure-", fileext = ".csv", tmpdir = dirname(target))
  on.exit(unlink(staged, force = TRUE), add = TRUE)
  utils::write.csv(audit, staged, row.names = FALSE, na = "NA")
  joint_inla_fit_commit_file(staged, target, overwrite = overwrite)
  target
}

joint_inla_fit_print_dry_run <- function(build_path, paths, cfg, call, version_check, initialization, effective_prior, preflight_result) {
  cat("Stage 3B dry run\n")
  cat("  Stage 3A build: ", build_path, "\n", sep = "")
  cat("  INLA runtime: ", version_check$runtime, "\n", sep = "")
  cat("  Stage 3A INLA: ", if (is.na(version_check$expected)) "unrecorded" else version_check$expected, "\n", sep = "")
  cat("  Version compatibility: ", joint_inla_fit_text(version_check$compatible), "\n", sep = "")
  if (!is.null(version_check$message)) cat("  Version note: ", version_check$message, "\n", sep = "")
  cat("  Family: binomial,nbinomial\n")
  cat("  Initialization: ", initialization$mode, "\n", sep = "")
  cat("  Threads: ", joint_inla_fit_thread_argument(cfg), "\n", sep = "")
  cat("  INLA strategy: ", cfg$fit$control_inla$strategy, "\n", sep = "")
  cat("  Integration strategy: ", joint_inla_fit_control_value(cfg$fit$control_inla, "int.strategy"), "\n", sep = "")
  cat("  DIC/WAIC/CPO: ", isTRUE(cfg$fit$control_compute$dic), "/", isTRUE(cfg$fit$control_compute$waic), "/", isTRUE(cfg$fit$control_compute$cpo), "\n", sep = "")
  cat("  Effective runtime nbinomial hyperprior: ", joint_inla_fit_dput(effective_prior), "\n", sep = "")
  cat("  INLA call arguments: ", paste(names(call), collapse = ", "), "\n", sep = "")
  cat("  Expected fit output: ", paths$fit, "\n", sep = "")
  cat("  Expected audit output: ", paths$audit, "\n", sep = "")
  cat("  Expected metadata output: ", paths$metadata, "\n", sep = "")
  cat("  Preflight status: ", if (isTRUE(preflight_result$success)) "PASS" else "FAIL", "\n", sep = "")
  cat("  Preflight audit: ", paths$preflight, "\n", sep = "")
  cat("  INLA::inla() called: FALSE\n")
}

`%||%` <- function(x, y) if (is.null(x)) y else x

run_joint_inla_fit <- function(config_path, repo_root = getwd(), output_override = NULL,
                               dry_run = FALSE, overwrite_override = FALSE, inla_function = NULL) {
  cfg <- read_joint_inla_fit_config(config_path, repo_root)
  validate_joint_inla_fit_config(cfg)
  if (isTRUE(overwrite_override)) cfg$outputs$overwrite <- TRUE
  paths <- joint_inla_fit_output_paths(cfg, output_override)
  build <- joint_inla_fit_read_build(cfg$inputs$stage3a_build)
  preflight_result <- if (isTRUE(cfg$preflight$enabled)) {
    joint_inla_preflight_build(build, cfg$inputs$stage3a_build)
  } else {
    list(success = TRUE,
         audit = data.frame(section = "preflight", check = "preflight_enabled", status = "warning",
                            observed = FALSE, expected = TRUE,
                            details = "Production preflight was explicitly disabled.", stringsAsFactors = FALSE),
         summary = list(failures = 0L, warnings = 1L, checks = 1L),
         theta_inventory = joint_inla_preflight_theta_inventory(), build_path = cfg$inputs$stage3a_build)
  }
  paths$preflight <- joint_inla_preflight_write_audit(preflight_result, paths$preflight, overwrite = cfg$outputs$overwrite)
  joint_inla_preflight_print(preflight_result, paths$preflight)
  if (!isTRUE(preflight_result$success)) {
    stop("Stage 3B production-artifact preflight failed. Review: ", paths$preflight, call. = FALSE)
  }
  initialization <- joint_inla_fit_initialization(build, cfg)
  runtime_version <- joint_inla_fit_runtime_version()
  version_check <- joint_inla_fit_version_check(build, cfg, runtime_version, emit_warning = FALSE)
  warnings_captured <- character()
  if (!isTRUE(version_check$compatible)) {
    warnings_captured <- c(warnings_captured, version_check$message)
    if (identical(cfg$version_compatibility$policy, "warn")) warning(version_check$message, call. = FALSE)
  }
  effective_prior <- joint_inla_fit_effective_nbinomial_prior()
  call <- joint_inla_fit_construct_call(build, cfg, initialization)
  call_metadata <- joint_inla_fit_call_metadata(call, cfg, initialization)

  started <- Sys.time()
  if (isTRUE(dry_run)) {
    ended <- Sys.time()
    audit <- joint_inla_fit_make_audit("dry_run", started, ended, build, cfg$inputs$stage3a_build, cfg, paths,
                                      runtime_version, version_check, initialization, effective_prior,
                                      warnings_captured, fit = NULL, dry_run = TRUE)
    joint_inla_fit_print_dry_run(cfg$inputs$stage3a_build, paths, cfg, call, version_check, initialization, effective_prior, preflight_result)
    return(invisible(list(config = cfg, paths = paths, call = call, call_metadata = call_metadata,
                          version_check = version_check, initialization = initialization,
                          effective_nbinomial_prior = effective_prior, audit = audit)))
  }

  joint_inla_fit_output_preflight(paths[c("fit", "audit", "metadata")], overwrite = cfg$outputs$overwrite)
  if (is.null(inla_function)) inla_function <- INLA::inla
  fit <- NULL
  fit_error <- NULL
  fit_warnings <- character()
  fit <- withCallingHandlers(
    tryCatch(
      do.call(inla_function, call),
      error = function(error) {
        fit_error <<- conditionMessage(error)
        NULL
      }
    ),
    warning = function(warning) {
      fit_warnings <<- c(fit_warnings, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )
  ended <- Sys.time()
  warnings_captured <- unique(c(warnings_captured, fit_warnings))
  if (!is.null(fit_error) || is.null(fit)) {
    if (is.null(fit_error)) fit_error <- "INLA returned NULL without a fit object."
    audit <- joint_inla_fit_make_audit("failure", started, ended, build, cfg$inputs$stage3a_build, cfg, paths,
                                      runtime_version, version_check, initialization, effective_prior,
                                      warnings_captured, fit = NULL, error_message = fit_error)
    failure_audit <- tryCatch(joint_inla_fit_write_failure_audit(audit, paths, overwrite = cfg$outputs$overwrite),
                              error = function(error) {
                                warning("Unable to write Stage 3B failure audit: ", conditionMessage(error), call. = FALSE)
                                NA_character_
                              })
    stop("Stage 3B INLA fit failed: ", fit_error,
         if (!is.na(failure_audit)) paste0(". Failure audit: ", failure_audit) else "", call. = FALSE)
  }

  audit <- joint_inla_fit_make_audit("success", started, ended, build, cfg$inputs$stage3a_build, cfg, paths,
                                    runtime_version, version_check, initialization, effective_prior,
                                    warnings_captured, fit = fit)
  provenance <- joint_inla_fit_source_provenance(build, cfg$inputs$stage3a_build, cfg, paths,
                                                runtime_version, version_check, effective_prior)
  provenance$runtime <- list(
    r_version = R.version.string,
    git_commit = joint_inla_fit_git_commit(cfg$repo_root),
    hostname = unname(Sys.info()[["nodename"]]),
    initialization_mode = initialization$mode,
    fit_call = call_metadata
  )
  runtime_config <- list(
    config_path = cfg$config_path,
    quantiles = cfg$fit$quantiles,
    control_fixed = cfg$fit$control_fixed,
    control_inla = cfg$fit$control_inla,
    control_compute = cfg$fit$control_compute,
    control_predictor = cfg$fit$control_predictor,
    initialization = initialization$mode,
    threads = cfg$threads,
    version_policy = cfg$version_compatibility$policy
  )
  fit_artifact <- list(
    fit = fit,
    audit = audit,
    provenance = provenance,
    runtime_config = runtime_config
  )
  metadata <- list(provenance = provenance, runtime_config = runtime_config, audit = audit,
                  output_paths = paths)
  joint_inla_fit_write_outputs(fit_artifact, metadata, audit, paths, overwrite = cfg$outputs$overwrite)
  message("Joint-INLA Stage 3B fit complete:\n",
          "  Family: ", paste(build$family, collapse = ", "), "\n",
          "  INLA version: ", runtime_version, "\n",
          "  Initialization: ", initialization$mode, "\n",
          "  Output: ", paths$fit)
  invisible(list(fit = fit, audit = audit, provenance = provenance, paths = paths,
                 call_metadata = call_metadata))
}
