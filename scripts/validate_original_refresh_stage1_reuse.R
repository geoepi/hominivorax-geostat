parse_args <- function(args) {
  parsed <- list(config = "config/original_refresh_w44_2026/stage1_reuse.yml")
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/validate_original_refresh_stage1_reuse.R [--config PATH]\n")
      quit(save = "no", status = 0L)
    } else if (args[[i]] == "--config") {
      i <- i + 1L
      if (i > length(args)) stop("--config requires a path.")
      parsed$config <- args[[i]]
    } else if (grepl("^--config=", args[[i]])) {
      parsed$config <- sub("^--config=", "", args[[i]])
    } else stop("Unknown argument: ", args[[i]])
    i <- i + 1L
  }
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
config_path <- if (grepl("^[A-Za-z]:[/\\\\]|^/", args$config)) args$config else file.path(repo_root, args$config)
config_path <- normalizePath(config_path, mustWork = TRUE)
if (!requireNamespace("yaml", quietly = TRUE) || !requireNamespace("digest", quietly = TRUE)) {
  stop("yaml and digest packages are required for the Stage 1 reuse gate.")
}
cfg <- yaml::read_yaml(config_path)
artifact_path <- file.path(repo_root, cfg$reuse$output_artifact)
if (!file.exists(artifact_path)) stop("Copied Stage 1 artifact does not exist: ", artifact_path)
observed_sha <- digest::digest(file = artifact_path, algo = "sha256")
expected_sha <- tolower(as.character(cfg$reuse$expected_artifact_sha256))
checks <- data.frame(
  check = "reused_stage1_sha256",
  status = if (identical(tolower(observed_sha), expected_sha)) "PASS" else "FAIL",
  observed = observed_sha, expected = expected_sha,
  details = "The isolated refresh copy is byte-identical to the existing C-1 Stage 1 artifact.",
  stringsAsFactors = FALSE
)
model_inputs <- readRDS(artifact_path)
source(file.path(repo_root, "R", "original_refresh_contracts.R"))
contract <- original_refresh_stage1_audit(
  model_inputs,
  expected_observation_sha256 = cfg$reuse$expected_observation_sha256,
  expected_manifest_sha256 = cfg$reuse$expected_source_manifest_sha256,
  expected_start_week = cfg$reuse$expected_analysis_start_week,
  expected_end_week = cfg$reuse$expected_analysis_end_week,
  expected_end_date = cfg$reuse$expected_analysis_end_date
)
checks <- rbind(checks, contract)
audit_path <- file.path(dirname(artifact_path), "stage1_reuse_audit.csv")
utils::write.csv(checks, audit_path, row.names = FALSE, na = "")
cat("Stage 1 reuse validation: ", if (all(checks$status == "PASS")) "PASS" else "FAIL", "\n", sep = "")
cat("Audit: ", audit_path, "\n", sep = "")
print(checks, row.names = FALSE)
if (any(checks$status != "PASS")) quit(save = "no", status = 1L)
