parse_args <- function(args) {
  parsed <- list(
    build = "outputs/original_refresh_w44_2026/stage3a/joint_inla_build.rds",
    stage2 = "outputs/original_refresh_w44_2026/stage2/joint_model_inputs.rds",
    output = "outputs/original_refresh_w44_2026/validation/original_refresh_formula_audit.csv"
  )
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/check_original_refresh_stage3a.R [--build PATH] [--stage2 PATH] [--output PATH]\n")
      quit(save = "no", status = 0L)
    }
    name <- sub("^--", "", sub("=.*$", "", args[[i]]))
    if (!name %in% c("build", "stage2", "output")) stop("Unknown argument: ", args[[i]])
    if (grepl("=", args[[i]], fixed = TRUE)) {
      parsed[[name]] <- sub("^[^=]+=", "", args[[i]])
    } else {
      i <- i + 1L
      if (i > length(args)) stop("--", name, " requires a path.")
      parsed[[name]] <- args[[i]]
    }
    i <- i + 1L
  }
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
resolve <- function(path) if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) path else file.path(repo_root, path)
source(file.path(repo_root, "R", "load_joint_inla.R"))
load_joint_inla(repo_root)
source(file.path(repo_root, "R", "original_refresh_contracts.R"))
build_path <- normalizePath(resolve(args$build), mustWork = TRUE)
stage2_path <- normalizePath(resolve(args$stage2), mustWork = TRUE)
output_path <- resolve(args$output)
build <- readRDS(build_path)
stage2 <- readRDS(stage2_path)
checks <- original_refresh_formula_audit(build)
reference_formula <- make_joint_formula(build$spde$tier1, build$spde$tier2, build$priors, build$config)
formula_text <- function(value) paste(deparse(value, width.cutoff = 500L), collapse = " ")
checks <- rbind(checks, data.frame(
  check = "frozen_reference_formula_regeneration",
  status = if (identical(formula_text(build$formula), formula_text(reference_formula))) "PASS" else "FAIL",
  observed = formula_text(build$formula),
  expected = formula_text(reference_formula),
  details = "The Stage 3A formula is compared with the unchanged manifest-free formula generator at the base commit.",
  stringsAsFactors = FALSE
))

add_check <- function(name, pass, observed, expected, details) {
  data.frame(check = name, status = if (isTRUE(unname(pass))) "PASS" else "FAIL",
             observed = as.character(observed), expected = as.character(expected),
             details = details, stringsAsFactors = FALSE)
}
row_map <- tryCatch(joint_inla_extract_row_map(build, stage2), error = identity)
checks <- rbind(checks,
  add_check("stack_row_map", !inherits(row_map, "error"),
    if (inherits(row_map, "error")) conditionMessage(row_map) else nrow(row_map),
    nrow(stage2$tier1) + nrow(stage2$tier2),
    "The INLA stack rows map to the authoritative Stage 2 tier rows."),
  add_check("prediction_grid_compatibility", isTRUE(build$prediction_compatibility$compatible),
    build$prediction_compatibility$compatible, "TRUE",
    "Original fixed predictors and temporal indices resolve over the prediction grid."),
  add_check("tier1_projection_rows", as.integer(nrow(build$A$tier1)) == as.integer(nrow(stage2$tier1)),
    nrow(build$A$tier1), nrow(stage2$tier1),
    "Tier 1 projection rows match the authoritative Stage 2 Tier 1 rows."),
  add_check("tier2_projection_rows", as.integer(nrow(build$A$tier2)) == as.integer(nrow(stage2$tier2)),
    nrow(build$A$tier2), nrow(stage2$tier2),
    "Tier 2 projection rows match the authoritative Stage 2 Tier 2 rows."),
  add_check("tier_projection_common_columns", as.integer(ncol(build$A$tier1)) == as.integer(ncol(build$A$tier2)),
    paste(ncol(build$A$tier1), ncol(build$A$tier2), sep = "/"), "equal Tier 1/Tier 2 mesh/group columns",
    "Both tier projections must use a common spatial and temporal field dimension."),
  add_check("fit_not_executed", isFALSE(build$provenance$executed_fit),
    build$provenance$executed_fit, "FALSE", "Stage 3A assembly remains deterministic and fit-free.")
)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(checks, output_path, row.names = FALSE, na = "")
cat("Original formula / Stage 3A audit: ", if (all(checks$status == "PASS")) "PASS" else "FAIL", "\n", sep = "")
cat("Audit: ", output_path, "\n", sep = "")
print(checks, row.names = FALSE)
if (any(checks$status != "PASS")) quit(save = "no", status = 1L)
