parse_joint_inla_arguments <- function(args) {
  parsed <- list(config = "config/joint_inla.example.yml", output = NULL, help = FALSE)
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
parsed <- parse_joint_inla_arguments(args)
if (isTRUE(parsed$help)) {
  cat("Usage: Rscript scripts/build_joint_inla.R [--config PATH] [--output PATH]\n")
  cat("Assemble Stage 3A INLA objects from the Stage 2 artifact; do not fit the model.\n")
  quit(save = "no", status = 0L)
}
file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(file_arg)) stop("Unable to determine the running script location.")
script_path <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla.R"))
load_joint_inla(repo_root)
invisible(run_joint_inla_build(normalizePath(parsed$config, mustWork = TRUE), repo_root, parsed$output))
