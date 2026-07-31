repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)
config_path <- file.path(repo_root, "config", "preprocessing.demo.yml")
if (!file.exists(config_path)) {
  source(file.path(repo_root, "scripts", "create_preprocessing_demo_inputs.R"))
  create_preprocessing_demo_inputs(repo_root, config_path)
}
invisible(run_preprocessing(config_path, repo_root))
