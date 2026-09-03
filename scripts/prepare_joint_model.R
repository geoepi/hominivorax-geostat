parse_joint_model_arguments <- function(args) {
  if (any(args %in% c("--help", "-h"))) return(list(help = TRUE))
  value <- function(name, required = TRUE) {
    inline <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(inline)) return(sub(paste0("^--", name, "="), "", inline[[1L]]))
    position <- which(args == paste0("--", name))
    if (length(position) && position[[1L]] < length(args)) return(args[[position[[1L]] + 1L]])
    if (required) stop("Missing --", name, " argument.")
    NULL
  }
  list(help = FALSE, config = value("config"), output = value("output", required = FALSE))
}

args <- commandArgs(trailingOnly = TRUE)
parsed <- parse_joint_model_arguments(args)
if (isTRUE(parsed$help)) {
  cat("Usage: Rscript scripts/prepare_joint_model.R --config config/joint_model.example.yml [--output path]\n")
  quit(save = "no", status = 0L)
}
config_path <- normalizePath(parsed$config, mustWork = TRUE)
script_path <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]])
script_path <- normalizePath(script_path, mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)
repo_root <- repository_root_from_script(script_path)
invisible(run_joint_model_preparation(config_path, repo_root, output_override = parsed$output))
