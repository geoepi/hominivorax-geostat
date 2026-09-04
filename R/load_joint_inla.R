load_joint_inla <- function(repo_root = getwd()) {
  files <- c("preprocessing_validation.R", "joint_inla_config.R", "joint_inla_spde.R", "joint_inla_effects.R", "joint_inla_spec.R", "joint_inla_stacks.R", "joint_inla_build.R")
  for (file in files) source(file.path(repo_root, "R", file), local = .GlobalEnv)
  invisible(files)
}

read_joint_inla_inputs <- function(path) {
  if (!file.exists(path)) stop("Stage 2 joint_model_inputs.rds does not exist: ", path)
  readRDS(path)
}
