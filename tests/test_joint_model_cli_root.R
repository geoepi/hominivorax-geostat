repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)

script_path <- file.path(repo_root, "scripts", "prepare_joint_model.R")
external_config <- file.path(tempdir(), "external-config", "joint_model.atlas.yml")
discovered_root <- repository_root_from_script(
  command_args = c("Rscript", paste0("--file=", script_path), paste0("--config=", external_config))
)
stopifnot(identical(discovered_root, repo_root))
stopifnot(!identical(discovered_root, normalizePath(file.path(dirname(external_config), ".."), mustWork = FALSE)))

cat("Joint-model CLI repository-root regression test passed\n")
