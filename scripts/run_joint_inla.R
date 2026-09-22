parse_joint_inla_fit_arguments <- function(args) {
  parsed <- list(config = "config/joint_inla_fit.example.yml", output = NULL,
                 dry_run = FALSE, overwrite = FALSE, help = FALSE)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      parsed$help <- TRUE
    } else if (arg == "--dry-run") {
      parsed$dry_run <- TRUE
    } else if (arg == "--overwrite") {
      parsed$overwrite <- TRUE
    } else if (arg == "--config") {
      i <- i + 1L
      if (i > length(args)) stop("--config requires a path.")
      parsed$config <- args[[i]]
    } else if (grepl("^--config=", arg)) {
      parsed$config <- sub("^--config=", "", arg)
    } else if (arg == "--output") {
      i <- i + 1L
      if (i > length(args)) stop("--output requires a path.")
      parsed$output <- args[[i]]
    } else if (grepl("^--output=", arg)) {
      parsed$output <- sub("^--output=", "", arg)
    } else {
      stop("Unknown argument: ", arg)
    }
    i <- i + 1L
  }
  parsed
}

args <- commandArgs(trailingOnly = TRUE)
parsed <- parse_joint_inla_fit_arguments(args)
if (isTRUE(parsed$help)) {
  cat("Usage: Rscript scripts/run_joint_inla.R --config PATH [--output PATH] [--dry-run] [--overwrite]\n")
  cat("Execute the validated Stage 3A joint INLA model; --dry-run resolves the call without fitting.\n")
  cat("Repository root is discovered from this script, independently of the configuration path.\n")
  quit(save = "no", status = 0L)
}

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(file_arg)) stop("Unable to determine the running script location.")
script_path <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)
config_path <- normalizePath(path.expand(parsed$config), mustWork = TRUE)

tryCatch(
  run_joint_inla_fit(config_path, repo_root, output_override = parsed$output,
                     dry_run = parsed$dry_run, overwrite_override = parsed$overwrite),
  error = function(error) {
    cat("Stage 3B error: ", conditionMessage(error), "\n", file = stderr())
    quit(save = "no", status = 1L)
  }
)
