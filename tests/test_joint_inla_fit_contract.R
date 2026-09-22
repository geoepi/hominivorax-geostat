repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)

if (!requireNamespace("INLA", quietly = TRUE)) {
  cat("Stage 3B contract tests skipped: INLA is unavailable\n")
} else {
  make_build <- function(path) {
    joint_stack <- INLA::inla.stack(
      data = list(
        Y = matrix(c(0, NA_real_, NA_real_, 1), nrow = 2L, ncol = 2L, byrow = TRUE),
        e = c(NA_real_, 1),
        link = c(1L, 2L)
      ),
      A = list(diag(2), diag(2)),
      effects = list(
        list(intercept1 = c(1, 1), intercept2 = c(0, 0)),
        list(intercept1 = c(0, 0), intercept2 = c(1, 1))
      ),
      tag = "joint"
    )
    build <- list(
      formula = Y ~ -1 + intercept1 + intercept2,
      family = c("binomial", "nbinomial"),
      stacks = list(joint = joint_stack),
      priors = list(hyper_copy = list(beta = list(prior = "normal", param = c(0.5, 0.2)))),
      fit_reference = list(
        control_mode = list(restart = FALSE, theta = c(4.65719676, 0.98772497, -2.01980363)),
        nbinomial_default = list(available = TRUE, hyper = list(theta = list(prior = "pc.mgamma", param = 7, initial = 2.30258509299405, fixed = FALSE)))
      ),
      provenance = list(stage = "joint_inla_assembly", executed_fit = FALSE,
                        INLA = as.character(utils::packageVersion("INLA")),
                        source_artifact = "outputs/joint_model/joint_model_inputs.rds",
                        source_artifact_sha256 = "stage2-sha"),
      config = list(inputs = list(joint_model_inputs = "outputs/joint_model/joint_model_inputs.rds"))
    )
    saveRDS(build, path)
    build
  }

  build_path <- file.path(tempdir(), "joint_inla_build_contract.rds")
  build <- make_build(build_path)
  cfg <- joint_inla_fit_defaults()
  cfg$repo_root <- repo_root
  cfg$config_path <- file.path(repo_root, "config", "joint_inla_fit.example.yml")
  cfg$inputs$stage3a_build <- build_path
  cfg$project$output_directory <- file.path(tempdir(), "joint_inla_fit_contract_output")
  validate_joint_inla_fit_config(cfg)

  loaded <- joint_inla_fit_read_build(build_path)
  stopifnot(identical(loaded$family, c("binomial", "nbinomial")))
  stopifnot(isTRUE(all.equal(loaded$formula, build$formula)))
  stopifnot(identical(loaded$stacks$joint, build$stacks$joint))

  historical <- joint_inla_fit_initialization(loaded, cfg)
  stopifnot(identical(historical$mode, "historical"), identical(historical$control_mode$restart, FALSE))
  stopifnot(identical(historical$control_mode$theta, loaded$fit_reference$control_mode$theta))
  cfg$fit$initialization$mode <- "default"
  default <- joint_inla_fit_initialization(loaded, cfg)
  stopifnot(is.null(default$control_mode), identical(default$mode, "default"))
  default_call <- joint_inla_fit_construct_call(loaded, cfg, default)
  stopifnot(!"control.mode" %in% names(default_call),
            !any(grepl("theta", names(default_call), fixed = TRUE)))
  cfg$fit$initialization$mode <- "historical"

  executed_build <- loaded
  executed_build$provenance$executed_fit <- TRUE
  executed_error <- tryCatch({
    joint_inla_fit_validate_build(executed_build)
    FALSE
  }, error = function(error) grepl("executed_fit", conditionMessage(error), fixed = TRUE))
  stopifnot(executed_error)

  call <- joint_inla_fit_construct_call(loaded, cfg, historical)
  stack_data <- INLA::inla.stack.data(loaded$stacks$joint)
  stack_A <- INLA::inla.stack.A(loaded$stacks$joint)
  stopifnot(identical(call$formula, loaded$formula), identical(call$family, loaded$family))
  stopifnot(identical(call$data, stack_data), identical(call$A, stack_A))
  stopifnot(identical(call$E, stack_data$e), identical(call$link, stack_data$link))
  stopifnot("control.mode" %in% names(call), identical(call$control.mode, historical$control_mode))

  runtime_version <- as.character(utils::packageVersion("INLA"))
  version_warning <- FALSE
  mismatch_cfg <- cfg
  mismatch_cfg$version_compatibility$policy <- "warn"
  mismatch <- withCallingHandlers(
    joint_inla_fit_version_check(loaded, mismatch_cfg, runtime_version = "0.0.0", emit_warning = TRUE),
    warning = function(warning) {
      version_warning <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  stopifnot(identical(mismatch$compatible, FALSE), version_warning,
            grepl("version mismatch", tolower(mismatch$message), fixed = TRUE))
  mismatch_cfg$version_compatibility$policy <- "error"
  version_error <- tryCatch({
    joint_inla_fit_version_check(loaded, mismatch_cfg, runtime_version = "0.0.0", emit_warning = FALSE)
    FALSE
  }, error = function(error) grepl("version mismatch", tolower(conditionMessage(error)), fixed = TRUE))
  stopifnot(version_error)

  dry_config <- file.path(tempdir(), "joint_inla_fit_contract.yml")
  yaml::write_yaml(cfg, dry_config)
  dry <- run_joint_inla_fit(dry_config, repo_root, dry_run = TRUE,
                            inla_function = function(...) stop("INLA::inla must not be called during dry-run"))
  stopifnot(identical(dry$audit$fit_status[[1L]], "dry_run"), isTRUE(dry$audit$dry_run[[1L]]))
  stopifnot("link" %in% names(dry$call), "A" %in% names(dry$call), "E" %in% names(dry$call))

  failure_output <- file.path(tempdir(), "joint_inla_fit_failure_output")
  failure_cfg <- cfg
  failure_cfg$project$output_directory <- failure_output
  failure_config <- file.path(tempdir(), "joint_inla_fit_failure.yml")
  yaml::write_yaml(failure_cfg, failure_config)
  failed <- tryCatch({
    run_joint_inla_fit(failure_config, repo_root,
                       inla_function = function(...) stop("synthetic fit failure"))
    FALSE
  }, error = function(error) grepl("synthetic fit failure", conditionMessage(error), fixed = TRUE))
  stopifnot(failed,
            !file.exists(file.path(failure_output, "joint_model_fit.rds")),
            !file.exists(file.path(failure_output, "joint_model_fit_metadata.rds")),
            file.exists(file.path(failure_output, "joint_model_fit_audit.csv")))
  failure_audit <- utils::read.csv(file.path(failure_output, "joint_model_fit_audit.csv"), stringsAsFactors = FALSE)
  stopifnot(identical(failure_audit$fit_status[[1L]], "failure"))

  success_output <- file.path(tempdir(), "joint_inla_fit_success_output")
  success_cfg <- cfg
  success_cfg$project$output_directory <- success_output
  success_config <- file.path(tempdir(), "joint_inla_fit_success.yml")
  yaml::write_yaml(success_cfg, success_config)
  fake_fit <- list(
    summary.hyperpar = data.frame(mean = 1),
    summary.fixed = data.frame(mean = c(1, 2)),
    summary.random = list(one = data.frame(mean = 1)),
    dic = list(dic = 3), waic = list(waic = 4),
    mlik = data.frame(`log marginal likelihood` = -5)
  )
  run_joint_inla_fit(success_config, repo_root, inla_function = function(...) fake_fit)
  overwrite_blocked <- tryCatch({
    run_joint_inla_fit(success_config, repo_root, inla_function = function(...) fake_fit)
    FALSE
  }, error = function(error) grepl("Refusing to overwrite", conditionMessage(error), fixed = TRUE))
  stopifnot(overwrite_blocked,
            file.exists(file.path(success_output, "joint_model_fit.rds")),
            file.exists(file.path(success_output, "joint_model_fit_metadata.rds")))

  cat("Stage 3B contract tests passed\n")
}
