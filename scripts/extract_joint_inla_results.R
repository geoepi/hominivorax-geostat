args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else default
}
flag <- function(name) paste0("--", name) %in% args

repo_root <- normalizePath(option("repo-root", getwd()), mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_extract.R"))
build_path <- option("build", file.path(repo_root, "outputs", "joint_inla", "joint_inla_build.rds"))
fit_path <- option("fit", file.path(repo_root, "outputs", "joint_inla_fit", "joint_model_fit.rds"))
stage2_path <- option("stage2", file.path(repo_root, "outputs", "joint_model", "joint_model_inputs.rds"))
output_dir <- option("output-dir", file.path(dirname(fit_path)))
run_id <- option("run-id", format(Sys.time(), "%Y%m%dT%H%M%S"))
overwrite <- flag("overwrite")

if (!file.exists(build_path)) stop("Build artifact does not exist: ", build_path)
if (!file.exists(fit_path)) stop("Fit artifact does not exist: ", fit_path)
if (!file.exists(stage2_path)) stop("Stage 2 artifact does not exist: ", stage2_path)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
paths <- c(
  audit = file.path(output_dir, paste0("extraction_audit_", run_id, ".csv")),
  details = file.path(output_dir, paste0("extraction_audit_", run_id, "_details.txt")),
  holdout = file.path(output_dir, paste0("holdout_predictions_", run_id, ".csv"))
)
if (!overwrite && any(file.exists(paths))) stop("Refusing to overwrite existing extraction outputs; use --overwrite intentionally.")

build <- readRDS(build_path)
fit_artifact <- readRDS(fit_path)
stage2 <- readRDS(stage2_path)
result <- joint_inla_extract_audit(build, fit_artifact, stage2)
utils::write.csv(result$audit, paths[["audit"]], row.names = FALSE, na = "")
writeLines(result$details, paths[["details"]])
holdout <- joint_inla_extract_holdout_predictions(build, fit_artifact, stage2)
utils::write.csv(holdout, paths[["holdout"]], row.names = FALSE, na = "")

cat("Joint-INLA extraction complete\n",
    "  audit: ", paths[["audit"]], "\n",
    "  details: ", paths[["details"]], "\n",
    "  holdout predictions: ", paths[["holdout"]], " (", nrow(holdout), " rows)\n",
    "  PASS/WARNING/FAIL: ", paste(names(table(result$audit$status)), as.integer(table(result$audit$status)), collapse = "/"), "\n", sep = "")
