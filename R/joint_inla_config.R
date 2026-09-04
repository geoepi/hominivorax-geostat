resolve_joint_inla_path <- function(path, repo_root) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) return(path)
  path <- as.character(path[[1L]])
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) normalizePath(path, mustWork = FALSE) else file.path(repo_root, path)
}

joint_inla_defaults <- function() {
  list(
    project = list(output_directory = "outputs/joint_inla"),
    inputs = list(joint_model_inputs = "outputs/joint_model/joint_model_inputs.rds"),
    model = list(tier1 = list(family = "binomial"), tier2 = list(family = "nbinomial")),
    spatial = list(
      grouping_variable = "quarter_index", group_model = "iid",
      tier1 = list(alpha = 2, prior_range_km = 150, prior_range_probability = 0.05,
                   prior_sigma = 0.5, prior_sigma_probability = 0.05, constr = TRUE),
      tier2 = list(alpha = 2, prior_range_km = 90, prior_range_probability = 0.5,
                   prior_sigma = 1, prior_sigma_probability = 0.5, constr = TRUE)
    ),
    shared_field = list(
      enabled = TRUE, source = "tier1_field", target = "tier2_copy_field",
      estimate_copy_coefficient = TRUE, beta_prior_mean = 0.5, beta_prior_sd = 0.2
    ),
    temporal = list(
      tier1 = list(variable = "timestep", formula_name = "week_steps", model = "rw1", constr = TRUE, scale_model = TRUE),
      tier2 = list(variable = "timestep", formula_name = "tier2_week", model = "rw1", constr = TRUE, scale_model = TRUE)
    ),
    administrative_effect = list(
      tier1 = list(enabled = TRUE, variable = "admin_f", model = "iid", constr = TRUE,
                   prior_sigma = 0.3, prior_probability = 0.01)
    ),
    livestock_rw2 = list(
      enabled = TRUE, variable = "cattle", index = "cattle_q", value = "cattle_mid_log1p",
      model = "rw2", constr = TRUE, scale_model = TRUE, prior_sigma = 0.5, prior_probability = 0.05
    ),
    outputs = list(build = "joint_inla_build.rds", audit = "joint_inla_build_audit.csv"),
    fit_reference = list(
      quantiles = c(0.025, 0.25, 0.5, 0.75, 0.975),
      control_fixed = list(prec = 1, prec_intercept = 1),
      control_mode = list(restart = FALSE,
                          theta = c(4.65719676, 0.98772497, -2.01980363, -3.61447715,
                                    2.30258509, 5.02993340, -0.02897474, 0.50323804,
                                    5.42034311, 0.39783963)),
      control_inla = list(strategy = "adaptive", int_strategy = "eb"),
      control_compute = list(dic = TRUE, cpo = FALSE, waic = TRUE)
    )
  )
}

merge_joint_inla_config <- function(defaults, supplied) {
  if (is.null(supplied)) return(defaults)
  for (nm in names(supplied)) {
    if (is.list(supplied[[nm]]) && is.list(defaults[[nm]])) {
      defaults[[nm]] <- merge_joint_inla_config(defaults[[nm]], supplied[[nm]])
    } else {
      defaults[[nm]] <- supplied[[nm]]
    }
  }
  defaults
}

read_joint_inla_config <- function(path, repo_root = getwd()) {
  if (!file.exists(path)) stop("Joint-INLA configuration does not exist: ", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to read joint-INLA configuration.")
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  cfg <- merge_joint_inla_config(joint_inla_defaults(), yaml::read_yaml(path))
  cfg$project$output_directory <- resolve_joint_inla_path(cfg$project$output_directory, repo_root)
  cfg$inputs$joint_model_inputs <- resolve_joint_inla_path(cfg$inputs$joint_model_inputs, repo_root)
  cfg$config_path <- normalizePath(path, mustWork = FALSE)
  cfg$repo_root <- repo_root
  cfg
}

validate_joint_inla_config <- function(cfg, require_inputs = TRUE) {
  required <- c("project", "inputs", "model", "spatial", "shared_field", "temporal", "administrative_effect", "livestock_rw2", "outputs", "fit_reference")
  missing <- setdiff(required, names(cfg))
  if (length(missing)) stop("Joint-INLA configuration is missing sections: ", paste(missing, collapse = ", "))
  if (!identical(as.character(cfg$model$tier1$family), "binomial") || !identical(as.character(cfg$model$tier2$family), "nbinomial")) {
    stop("Stage 3A requires Tier 1 binomial and Tier 2 nbinomial families.")
  }
  if (!identical(as.character(cfg$spatial$grouping_variable), "quarter_index") || !identical(as.character(cfg$spatial$group_model), "iid")) {
    stop("Stage 3A requires quarter_index grouped with an iid group model.")
  }
  scalar_positive <- function(x, label) {
    if (length(x) != 1L || is.na(x) || !is.finite(as.numeric(x)) || as.numeric(x) <= 0) stop(label, " must be positive.")
  }
  for (tier in c("tier1", "tier2")) {
    for (nm in c("alpha", "prior_range_km", "prior_range_probability", "prior_sigma", "prior_sigma_probability")) {
      scalar_positive(cfg$spatial[[tier]][[nm]], paste0("spatial.", tier, ".", nm))
    }
    if (cfg$spatial[[tier]]$prior_range_probability >= 1 || cfg$spatial[[tier]]$prior_sigma_probability >= 1) stop("SPDE prior probabilities must be less than 1.")
    if (!isTRUE(cfg$spatial[[tier]]$constr)) stop("SPDE constraints must be enabled.")
  }
  if (!isTRUE(cfg$shared_field$enabled) || !isTRUE(cfg$shared_field$estimate_copy_coefficient)) stop("The shared field must be enabled with an estimated copy coefficient.")
  if (!identical(cfg$shared_field$source, "tier1_field") || !identical(cfg$shared_field$target, "tier2_copy_field")) stop("Unexpected shared-field source or target.")
  if (!identical(cfg$temporal$tier1$model, "rw1") || !identical(cfg$temporal$tier2$model, "rw1")) stop("Both temporal effects must use rw1.")
  if (!identical(cfg$administrative_effect$tier1$model, "iid") || !isTRUE(cfg$administrative_effect$tier1$enabled)) stop("The Tier 1 administrative effect must be enabled with model iid.")
  if (!identical(cfg$livestock_rw2$model, "rw2") || !isTRUE(cfg$livestock_rw2$enabled) || !identical(cfg$livestock_rw2$variable, "cattle")) stop("The cattle RW2 effect is required.")
  scalar_positive(cfg$shared_field$beta_prior_sd, "shared_field.beta_prior_sd")
  scalar_positive(cfg$livestock_rw2$prior_sigma, "livestock_rw2.prior_sigma")
  if (isTRUE(require_inputs) && !file.exists(cfg$inputs$joint_model_inputs)) stop("Stage 2 joint_model_inputs.rds does not exist: ", cfg$inputs$joint_model_inputs)
  invisible(TRUE)
}
