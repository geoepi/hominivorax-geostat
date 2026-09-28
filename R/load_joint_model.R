load_joint_model <- function(repo_root = getwd()) {
  files <- c("preprocessing_validation.R", "joint_model_config.R", "joint_model_responses.R", "joint_model_features.R", "joint_model_preparation.R")
  for (file in files) source(file.path(repo_root, "R", file), local = .GlobalEnv)
  invisible(files)
}

read_joint_model_inputs <- function(path) {
  if (!file.exists(path)) stop("Joint-model input artifact does not exist: ", path)
  readRDS(path)
}
