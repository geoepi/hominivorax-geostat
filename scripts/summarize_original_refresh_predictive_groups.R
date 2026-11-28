parse_args <- function(args) {
  parsed <- list(holdout = NULL, percentiles = NULL, output_dir = NULL)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/summarize_original_refresh_predictive_groups.R --holdout PATH --percentiles PATH --output-dir PATH\n")
      quit(save = "no", status = 0L)
    }
    name <- sub("^--", "", sub("=.*$", "", arg))
    if (!name %in% c("holdout", "percentiles", "output-dir")) stop("Unknown argument: ", arg)
    key <- gsub("-", "_", name, fixed = TRUE)
    if (grepl("=", arg, fixed = TRUE)) parsed[[key]] <- sub("^[^=]+=", "", arg)
    else {
      i <- i + 1L
      if (i > length(args)) stop("--", name, " requires a path.")
      parsed[[key]] <- args[[i]]
    }
    i <- i + 1L
  }
  if (any(vapply(parsed, is.null, logical(1L)))) stop("--holdout, --percentiles, and --output-dir are required.")
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
resolve <- function(path) if (grepl("^/", path)) path else file.path(repo_root, path)
holdout_path <- normalizePath(resolve(args$holdout), mustWork = TRUE)
percentile_path <- normalizePath(resolve(args$percentiles), mustWork = TRUE)
output_dir <- resolve(args$output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(repo_root, "R", "joint_inla_validate.R"))
source(file.path(repo_root, "R", "c1_predictive_qualification.R"))
holdout <- utils::read.csv(holdout_path, stringsAsFactors = FALSE, check.names = FALSE)
percentiles <- utils::read.csv(percentile_path, stringsAsFactors = FALSE, check.names = FALSE)
tier1 <- holdout[holdout$tier == "tier1", , drop = FALSE]
tier2 <- holdout[holdout$tier == "tier2", , drop = FALSE]
admin_tier1 <- c1_predictive_admin_percentiles(percentiles, tier1, min_n = 30L)

observed <- as.numeric(tier2$response_observed)
expected <- as.numeric(tier2$exposure) * as.numeric(tier2$fitted_mean)
censored <- if ("source_is_censored" %in% names(tier2)) tier2$source_is_censored %in% TRUE else rep(FALSE, nrow(tier2))
eligible <- is.finite(observed) & is.finite(expected) & !censored
observed[!eligible] <- NA_real_
expected[!eligible] <- NA_real_
admin_tier2 <- c1_predictive_group_metrics(tier2, "source_admin_u", observed, expected, 30L)
year_tier2 <- c1_predictive_group_metrics(tier2, "source_epiyear", observed, expected, 30L)
week_tier2 <- c1_predictive_group_metrics(tier2, "source_epiweek", observed, expected, 30L)
tier2_with_time <- tier2
tier2_with_time$epi_week_group <- ifelse(is.na(tier2$source_epiyear) | is.na(tier2$source_epiweek), NA_character_,
  sprintf("%04d-W%02d", as.integer(tier2$source_epiyear), as.integer(tier2$source_epiweek)))
yearweek_tier2 <- c1_predictive_group_metrics(tier2_with_time, "epi_week_group", observed, expected, 30L)

files <- c(
  tier1_admin = file.path(output_dir, "tier1_same_week_percentiles_by_admin.csv"),
  tier2_admin = file.path(output_dir, "tier2_spatial_admin_metrics.csv"),
  tier2_year = file.path(output_dir, "tier2_temporal_year_metrics.csv"),
  tier2_week = file.path(output_dir, "tier2_temporal_epiweek_metrics.csv"),
  tier2_yearweek = file.path(output_dir, "tier2_temporal_yearweek_metrics.csv"),
  report = file.path(output_dir, "original_refresh_predictive_subgroup_summary.md")
)
if (any(file.exists(files))) stop("Refusing to overwrite original-refresh subgroup outputs.")
utils::write.csv(admin_tier1, files[["tier1_admin"]], row.names = FALSE, na = "")
utils::write.csv(admin_tier2, files[["tier2_admin"]], row.names = FALSE, na = "")
utils::write.csv(year_tier2, files[["tier2_year"]], row.names = FALSE, na = "")
utils::write.csv(week_tier2, files[["tier2_week"]], row.names = FALSE, na = "")
utils::write.csv(yearweek_tier2, files[["tier2_yearweek"]], row.names = FALSE, na = "")
writeLines(c(
  "# Original refresh predictive subgroup summaries",
  "",
  paste0("Tier 1 rows: ", nrow(tier1), "; Tier 2 rows: ", nrow(tier2), "; uncensored finite Tier 2 rows: ", sum(eligible), "."),
  "Tier 1 subgroup output summarizes same-week area-weighted and unweighted percentiles by administration. Tier 2 subgroup metrics use expected count = exposure × fitted intensity. Administrative, year, epiweek, and combined year-week summaries suppress metrics where n < 30.",
  "Quadrature/background rows retain unknown biological status and are not treated as confirmed absences. These summaries are descriptive and apply no numeric performance cutoff.",
  "",
  "- tier1_same_week_percentiles_by_admin.csv",
  "- tier2_spatial_admin_metrics.csv",
  "- tier2_temporal_year_metrics.csv",
  "- tier2_temporal_epiweek_metrics.csv",
  "- tier2_temporal_yearweek_metrics.csv"
), files[["report"]], useBytes = TRUE)
cat("Wrote original-refresh predictive subgroup summaries to ", output_dir, "\n", sep = "")
