load_preprocessing <- function(repo_root = getwd()) {
  files <- c(
    "preprocessing_validation.R", "preprocessing_config.R", "preprocessing_observations.R",
    "convert_mesh_poly.R", "preprocessing_spatial.R", "preprocessing_covariates.R",
    "preprocessing_transformations.R", "preprocessing_outputs.R", "preprocessing_pipeline.R"
  )
  for (file in files) source(file.path(repo_root, "R", file), local = .GlobalEnv)
  invisible(files)
}
