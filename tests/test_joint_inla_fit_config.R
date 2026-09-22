repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)

cfg <- read_joint_inla_fit_config(file.path(repo_root, "config", "joint_inla_fit.example.yml"), repo_root)
validate_joint_inla_fit_config(cfg, require_input = FALSE)
stopifnot(identical(cfg$fit$initialization$mode, "historical"))
stopifnot(identical(cfg$fit$control_compute$dic, TRUE), identical(cfg$fit$control_compute$waic, TRUE))
stopifnot(identical(cfg$fit$control_compute$cpo, FALSE))
stopifnot(identical(cfg$threads$num_threads, 12L))
stopifnot(identical(cfg$version_compatibility$policy, "warn"))
paths <- joint_inla_fit_output_paths(cfg)
stopifnot(grepl("joint_model_fit\\.rds$", paths$fit), grepl("joint_model_fit_audit\\.csv$", paths$audit))

external_config <- file.path(tempdir(), "joint_inla_fit_external.yml")
stopifnot(file.copy(file.path(repo_root, "config", "joint_inla_fit.example.yml"), external_config, overwrite = TRUE))
external <- read_joint_inla_fit_config(external_config, repo_root)
stopifnot(identical(external$repo_root, repo_root))
stopifnot(identical(external$inputs$stage3a_build,
                    normalizePath(file.path(repo_root, "outputs", "joint_inla", "joint_inla_build.rds"), mustWork = FALSE)))

cat("Stage 3B configuration tests passed\n")
