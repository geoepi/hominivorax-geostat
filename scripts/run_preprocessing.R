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
repo_root <- normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)
invisible(run_preprocessing(config_path, repo_root))
