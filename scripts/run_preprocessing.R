parse_config_argument <- function(args) {
  if (!length(args)) stop("Usage: Rscript scripts/run_preprocessing.R --config=config/preprocessing.yml")
  inline <- grep("^--config=", args)
  if (length(inline)) return(sub("^--config=", "", args[inline[1]]))
  separate <- which(args == "--config")
  if (length(separate) && length(args) >= separate[1] + 1L) return(args[separate[1] + 1L])
  stop("Missing --config argument. Use --config=path or --config path.")
}

args <- commandArgs(trailingOnly = TRUE)
config_path <- parse_config_argument(args)
repo_arg <- {
  inline <- grep("^--repo-root=", args, value = TRUE)
  if (length(inline)) sub("^--repo-root=", "", inline[[1L]]) else {
    position <- which(args == "--repo-root")
    if (length(position) && position[[1L]] < length(args)) args[[position[[1L]] + 1L]] else NULL
  }
}
script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
if (is.null(repo_arg)) repo_arg <- file.path(dirname(sub("^--file=", "", script_arg)), "..")
repo_root <- normalizePath(repo_arg, mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)
invisible(run_preprocessing(config_path, repo_root))
