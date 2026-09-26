parse_joint_inla_preflight_arguments <- function(args) {
  parsed <- list(config = "config/joint_inla_fit.example.yml", output = NULL, help = FALSE)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) parsed$help <- TRUE
    else if (arg == "--config") { i <- i + 1L; if (i > length(args)) stop("--config requires a path."); parsed$config <- args[[i]] }
    else if (grepl("^--config=", arg)) parsed$config <- sub("^--config=", "", arg)
    else if (arg == "--output") { i <- i + 1L; if (i > length(args)) stop("--output requires a path."); parsed$output <- args[[i]] }
    else if (grepl("^--output=", arg)) parsed$output <- sub("^--output=", "", arg)
    else stop("Unknown argument: ", arg)
    i <- i + 1L
  }
  parsed
}

args <- commandArgs(trailingOnly = TRUE)
parsed <- parse_joint_inla_preflight_arguments(args)
if (isTRUE(parsed$help)) {
  cat("Usage: Rscript scripts/check_joint_inla_fit.R --config PATH [--output PATH]\n")
  cat("Validate the production Stage 3A artifact without calling the INLA model fit.\n")
  quit(save = "no", status = 0L)
}

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(file_arg)) stop("Unable to determine the running script location.")
script_path <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)

tryCatch({
  config_path <- normalizePath(path.expand(parsed$config), mustWork = TRUE)
  cfg <- read_joint_inla_fit_config(config_path, repo_root)
  validate_joint_inla_fit_config(cfg)
  build <- joint_inla_fit_read_build(cfg$inputs$stage3a_build)
  result <- joint_inla_preflight_build(build, cfg$inputs$stage3a_build)
  paths <- joint_inla_fit_output_paths(cfg)
  audit_path <- paths$preflight
  if (!is.null(parsed$output) && nzchar(parsed$output)) {
    override <- resolve_joint_inla_fit_path(parsed$output, repo_root)
    audit_path <- if (grepl("\\.csv$", override, ignore.case = TRUE)) override else file.path(override, basename(paths$preflight))
  }
  audit_path <- joint_inla_preflight_write_audit(result, audit_path, overwrite = cfg$outputs$overwrite)
  joint_inla_preflight_print(result, audit_path)
  if (!isTRUE(result$success)) stop("Production Stage 3B preflight failed. Review: ", audit_path, call. = FALSE)
}, error = function(error) {
  cat("Stage 3B preflight error: ", conditionMessage(error), "\n", file = stderr())
  quit(save = "no", status = 1L)
})
