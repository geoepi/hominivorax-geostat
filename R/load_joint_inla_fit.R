load_joint_inla_fit <- function(repo_root = getwd()) {
  files <- c("joint_inla_fit_config.R", "joint_inla_fit.R", "joint_inla_preflight.R")
  for (file in files) source(file.path(repo_root, "R", file), local = .GlobalEnv)
  invisible(files)
}
