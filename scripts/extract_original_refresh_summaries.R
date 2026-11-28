parse_args <- function(args) {
  parsed <- list(fit = NULL, build = NULL, stage2 = NULL,
                 output_dir = "outputs/original_refresh_w44_2026/extraction")
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/extract_original_refresh_summaries.R --fit PATH --build PATH --stage2 PATH [--output-dir PATH]\n")
      quit(save = "no", status = 0L)
    }
    name <- sub("^--", "", sub("=.*$", "", arg))
    if (!name %in% c("fit", "build", "stage2", "output-dir")) stop("Unknown argument: ", arg)
    key <- gsub("-", "_", name, fixed = TRUE)
    if (grepl("=", arg, fixed = TRUE)) parsed[[key]] <- sub("^[^=]+=", "", arg)
    else {
      i <- i + 1L
      if (i > length(args)) stop("--", name, " requires a path.")
      parsed[[key]] <- args[[i]]
    }
    i <- i + 1L
  }
  if (any(vapply(parsed[c("fit", "build", "stage2")], is.null, logical(1L)))) {
    stop("--fit, --build, and --stage2 are required.")
  }
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
resolve <- function(path) if (grepl("^/", path)) path else file.path(repo_root, path)
paths <- vapply(args[c("fit", "build", "stage2")], function(path) normalizePath(resolve(path), mustWork = TRUE), character(1L))
output_dir <- resolve(args$output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(repo_root, "R", "load_joint_inla.R"))
load_joint_inla(repo_root)
fit_artifact <- readRDS(paths[["fit"]])
fit <- joint_inla_extract_fit(fit_artifact)
fixed <- joint_inla_extract_fixed_effects(fit_artifact)
source(file.path(repo_root, "R", "original_refresh_contracts.R"))
expected <- original_refresh_fixed_names()
observed <- as.character(fixed$term)
if (!setequal(observed, expected) || length(observed) != 16L) {
  stop("Fitted fixed-effect table does not match the restored original 16-term specification.")
}
hyper <- joint_inla_extract_summary_table(fit$summary.hyperpar, "parameter")
random <- do.call(rbind, lapply(names(fit$summary.random), function(component) {
  out <- joint_inla_extract_summary_table(fit$summary.random[[component]], "index")
  out$component <- component
  out[, c("component", setdiff(names(out), "component")), drop = FALSE]
}))

out_paths <- c(
  fixed_effects = file.path(output_dir, "original_refresh_fixed_effect_summaries.csv"),
  hyperparameters = file.path(output_dir, "original_refresh_hyperparameter_summaries.csv"),
  random_effects = file.path(output_dir, "original_refresh_random_effect_summaries.csv"),
  artifact_manifest = file.path(output_dir, "original_refresh_extraction_manifest.csv")
)
if (any(file.exists(out_paths))) stop("Refusing to overwrite original-refresh extraction outputs.")
utils::write.csv(fixed, out_paths[["fixed_effects"]], row.names = FALSE, na = "")
utils::write.csv(hyper, out_paths[["hyperparameters"]], row.names = FALSE, na = "")
utils::write.csv(random, out_paths[["random_effects"]], row.names = FALSE, na = "")
sha <- function(path) {
  value <- system2("sha256sum", path, stdout = TRUE, stderr = FALSE)
  sub("[[:space:]].*$", "", value[[1L]])
}
manifest <- data.frame(
  role = c("fit", "stage3a", "stage2"),
  path = unname(paths[c("fit", "build", "stage2")]),
  sha256 = vapply(paths[c("fit", "build", "stage2")], sha, character(1L)),
  bytes = as.numeric(file.info(paths[c("fit", "build", "stage2")])$size),
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, out_paths[["artifact_manifest"]], row.names = FALSE, na = "")
cat("Fixed effects: ", nrow(fixed), "; hyperparameters: ", nrow(hyper),
    "; random-effect summaries: ", length(fit$summary.random), "\n", sep = "")
cat("Extraction outputs: ", output_dir, "\n", sep = "")
