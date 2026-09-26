repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "postfit_orchestration.R"))

paths <- postfit_acceptance_output_paths(file.path(tempdir(), "production_postfit_test"), "new-run")
stopifnot(grepl("production_postfit_test", paths$root, fixed = TRUE),
          identical(basename(paths$summary_rds), "postfit_acceptance_summary_new-run.rds"),
          identical(basename(paths$summary_yaml), "postfit_acceptance_summary_new-run.yml"))

stopifnot(isTRUE(postfit_acceptance_output_root_available(paths$root)))
dir.create(paths$root, recursive = TRUE, showWarnings = FALSE)
writeLines("sentinel", file.path(paths$root, "sentinel.txt"))
stopifnot(!isTRUE(postfit_acceptance_output_root_available(paths$root)),
          isTRUE(postfit_acceptance_output_root_available(paths$root, overwrite = TRUE)))
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = function(e) e)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
expect_error(postfit_acceptance_require_output_root(paths$root), "non-empty")

gates <- rbind(postfit_acceptance_gate("one", "PASS", "ok"), postfit_acceptance_gate("two", "WARNING", "context"))
stopifnot(identical(postfit_acceptance_overall_status(gates), "PASS_WITH_NONBLOCKING_WARNINGS"))
stopifnot(identical(postfit_acceptance_overall_status(rbind(gates, postfit_acceptance_gate("three", "FAIL"))), "FAIL"))

validation_text <- paste(readLines(file.path(repo_root, "scripts", "run_joint_inla_validation.R")), collapse = "\n")
projection_text <- paste(readLines(file.path(repo_root, "scripts", "run_joint_inla_projection.R")), collapse = "\n")
raster_text <- paste(readLines(file.path(repo_root, "scripts", "run_joint_inla_rasterization.R")), collapse = "\n")
wrapper_text <- paste(readLines(file.path(repo_root, "scripts", "run_postfit_acceptance_atlas.sh")), collapse = "\n")
stopifnot(grepl("acceptance_mode", validation_text, fixed = TRUE),
          grepl("new_production", validation_text, fixed = TRUE),
          grepl("expected_tier1_holdouts <- if", validation_text, fixed = TRUE),
          grepl("nrow(stage2$tier1)", projection_text, fixed = TRUE),
          grepl("nrow(stage2$prediction_grid)", projection_text, fixed = TRUE),
          grepl("--acceptance-mode=production", wrapper_text, fixed = TRUE),
          grepl("module load udunits proj geos/3.12.1 gdal/3.8.5 intel-oneapi-mkl/2023.2.0 r/4.4.3", wrapper_text, fixed = TRUE),
          grepl("--fit-job-id", wrapper_text, fixed = TRUE),
          grepl("run-id", raster_text, fixed = TRUE),
          grepl("stage2-artifact", raster_text, fixed = TRUE))

stopifnot(grepl("acceptance-mode.*reference", validation_text),
          grepl("historical_metric_regression_applied", validation_text, fixed = TRUE),
          grepl("Refusing to write into a non-empty", validation_text, fixed = TRUE))

cat("Post-fit acceptance orchestration tests passed\n")
