repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)

build_path <- file.path(tempdir(), "joint_inla_build_cli_root.rds")
if (!requireNamespace("INLA", quietly = TRUE)) {
  cat("Stage 3B CLI-root test skipped: INLA is unavailable\n")
} else {
  build <- list(
    formula = Y ~ -1 + intercept1,
    family = c("binomial", "nbinomial"),
    stacks = list(joint = INLA::inla.stack(
      data = list(Y = matrix(c(0, NA_real_), nrow = 1L, ncol = 2L), e = c(NA_real_), link = c(1L)),
      A = list(matrix(1, nrow = 1L, ncol = 1L)),
      effects = list(list(intercept1 = 1)), tag = "joint")),
    priors = list(),
    fit_reference = list(control_mode = list(theta = 1), nbinomial_default = list()),
    provenance = list(stage = "joint_inla_assembly", executed_fit = FALSE,
                      INLA = as.character(utils::packageVersion("INLA"))),
    config = list(inputs = list(joint_model_inputs = "stage2.rds"))
  )
  saveRDS(build, build_path)
  cfg <- joint_inla_fit_defaults()
  cfg$inputs$stage3a_build <- build_path
  cfg$project$output_directory <- file.path(tempdir(), "joint_inla_cli_root_output")
  external_config <- file.path(tempdir(), "external", "joint_inla_fit.yml")
  dir.create(dirname(external_config), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(cfg, external_config)
  script <- normalizePath(file.path(repo_root, "scripts", "run_joint_inla.R"), mustWork = TRUE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  output <- system2(rscript, c(shQuote(script), "--config", shQuote(external_config), "--dry-run"), stdout = TRUE, stderr = TRUE)
  stopifnot(any(grepl("Stage 3B dry run", output, fixed = TRUE)),
            any(grepl(normalizePath(build_path, mustWork = TRUE), output, fixed = TRUE)),
            any(grepl("INLA::inla\\(\\) called: FALSE", output)))
  discovered_root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
  stopifnot(identical(discovered_root, repo_root), !identical(discovered_root, dirname(dirname(external_config))))
  cat("Stage 3B CLI repository-root regression test passed\n")
}
