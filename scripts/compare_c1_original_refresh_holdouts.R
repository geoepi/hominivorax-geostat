parse_args <- function(args) {
  parsed <- list()
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/compare_c1_original_refresh_holdouts.R --c1-holdout PATH --refreshed-holdout PATH --c1-tier2-rows PATH --c1-metrics PATH --refreshed-metrics PATH --output-dir PATH\n")
      quit(save = "no", status = 0L)
    }
    name <- sub("^--", "", sub("=.*$", "", arg))
    if (!name %in% c("c1-holdout", "refreshed-holdout", "c1-tier2-rows",
                     "c1-metrics", "refreshed-metrics", "output-dir")) {
      stop("Unknown argument: ", arg)
    }
    key <- gsub("-", "_", name, fixed = TRUE)
    if (grepl("=", arg, fixed = TRUE)) parsed[[key]] <- sub("^[^=]+=", "", arg)
    else {
      i <- i + 1L
      if (i > length(args)) stop("--", name, " requires a path.")
      parsed[[key]] <- args[[i]]
    }
    i <- i + 1L
  }
  required <- c("c1_holdout", "refreshed_holdout", "c1_tier2_rows",
                "c1_metrics", "refreshed_metrics", "output_dir")
  missing <- required[vapply(required, function(key) is.null(parsed[[key]]), logical(1L))]
  if (length(missing)) stop("Missing required arguments: ", paste(missing, collapse = ", "))
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
resolve <- function(path) if (grepl("^/", path)) path else file.path(repo_root, path)
source(file.path(repo_root, "R", "original_refresh_comparison.R"))
read_csv <- function(path) utils::read.csv(normalizePath(resolve(path), mustWork = TRUE),
  stringsAsFactors = FALSE, check.names = FALSE)
c1_holdout <- read_csv(args$c1_holdout)
refreshed_holdout <- read_csv(args$refreshed_holdout)
c1_tier2 <- read_csv(args$c1_tier2_rows)
c1_metrics <- read_csv(args$c1_metrics)
refreshed_metrics <- read_csv(args$refreshed_metrics)

if (!all(c("tier", "expected_count") %in% names(c1_tier2))) stop("C-1 Tier 2 diagnostic rows need tier and expected_count.")
if (!"expected_count" %in% names(refreshed_holdout)) {
  if (!all(c("fitted_mean", "exposure") %in% names(refreshed_holdout))) {
    stop("Refreshed holdout rows need expected_count or fitted_mean and exposure.")
  }
  refreshed_holdout$expected_count <- as.numeric(refreshed_holdout$fitted_mean) * as.numeric(refreshed_holdout$exposure)
}

matched_by_tier <- lapply(c("tier1", "tier2"), function(tier) {
  c1 <- c1_holdout[c1_holdout$tier == tier, , drop = FALSE]
  refreshed <- refreshed_holdout[refreshed_holdout$tier == tier, , drop = FALSE]
  result <- original_refresh_match_holdouts(c1, refreshed)
  data.frame(
    tier = tier, c1_rows = nrow(c1), refreshed_rows = nrow(refreshed),
    matched_rows = result$matched_n, c1_only_rows = result$c1_only_n,
    refreshed_only_rows = result$refreshed_only_n,
    exact_identity_match = result$matched_n == nrow(c1) && result$matched_n == nrow(refreshed),
    key_columns = paste(result$key_columns, collapse = ","),
    stringsAsFactors = FALSE
  )
})
counts <- do.call(rbind, matched_by_tier)
exact_all <- all(counts$exact_identity_match)

c1_tier2 <- c1_tier2[c1_tier2$tier == "tier2", , drop = FALSE]
refreshed_tier2 <- refreshed_holdout[refreshed_holdout$tier == "tier2", , drop = FALSE]
matched_tier2 <- original_refresh_match_holdouts(c1_tier2, refreshed_tier2)
paired <- original_refresh_paired_tier2_errors(matched_tier2)

valid <- is.finite(as.numeric(matched_tier2$c1$response_observed)) &
  is.finite(as.numeric(matched_tier2$c1$expected_count)) &
  is.finite(as.numeric(matched_tier2$refreshed$expected_count)) &
  as.numeric(matched_tier2$c1$response_observed) == as.numeric(matched_tier2$refreshed$response_observed)
if ("source_is_censored" %in% names(matched_tier2$c1)) valid <- valid & !(matched_tier2$c1$source_is_censored %in% TRUE)
spatial_temporal <- data.frame()
if (any(valid)) {
  rows <- matched_tier2$c1[valid, , drop = FALSE]
  rows$observed <- as.numeric(matched_tier2$c1$response_observed[valid])
  rows$expected_c1 <- as.numeric(matched_tier2$c1$expected_count[valid])
  rows$expected_refreshed <- as.numeric(matched_tier2$refreshed$expected_count[valid])
  rows$abs_error_c1 <- abs(rows$observed - rows$expected_c1)
  rows$abs_error_refreshed <- abs(rows$observed - rows$expected_refreshed)
  rows$admin <- if ("source_admin_u" %in% names(rows)) as.character(rows$source_admin_u) else "ALL"
  rows$epiyear_group <- if ("source_epiyear" %in% names(rows)) as.character(rows$source_epiyear) else "ALL"
  rows$epiweek_group <- if ("source_epiweek" %in% names(rows)) as.character(rows$source_epiweek) else "ALL"
  rows$time_group <- paste(rows$epiyear_group, rows$epiweek_group, sep = "-W")
  summarize_group <- function(group_cols) {
    key <- do.call(interaction, c(rows[group_cols], list(drop = TRUE, lex.order = TRUE)))
    groups <- split(seq_len(nrow(rows)), key)
    do.call(rbind, lapply(groups, function(index) {
      data.frame(
        admin = if ("admin" %in% group_cols) rows$admin[index[[1L]]] else "ALL",
        time_group = if ("time_group" %in% group_cols) rows$time_group[index[[1L]]] else "ALL",
        n = length(index),
        mae_c1 = mean(rows$abs_error_c1[index]),
        mae_refreshed = mean(rows$abs_error_refreshed[index]),
        paired_mae_difference = mean(rows$abs_error_refreshed[index] - rows$abs_error_c1[index]),
        support = if (length(index) >= 30L) "DESCRIPTIVE" else "LOW_SUPPORT",
        stringsAsFactors = FALSE
      )
    }))
  }
  spatial_temporal <- rbind(summarize_group("admin"), summarize_group("time_group"),
    summarize_group(c("admin", "time_group")))
}

metric_comparison <- merge(
  c1_metrics, refreshed_metrics, by = c("tier", "metric", "details"),
  suffixes = c("_c1", "_refreshed"), all = TRUE
)
metric_comparison$comparable_on_exact_holdouts <- exact_all
metric_comparison$difference_refreshed_minus_c1 <- if (exact_all) {
  as.numeric(metric_comparison$value_refreshed) - as.numeric(metric_comparison$value_c1)
} else NA_real_

output_dir <- resolve(args$output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(counts, file.path(output_dir, "matched_holdout_counts.csv"), row.names = FALSE, na = "")
utils::write.csv(paired, file.path(output_dir, "matched_tier2_paired_absolute_error.csv"), row.names = FALSE, na = "")
utils::write.csv(spatial_temporal, file.path(output_dir, "matched_tier2_spatial_temporal_errors.csv"), row.names = FALSE, na = "")
utils::write.csv(metric_comparison, file.path(output_dir, "matched_summary_metric_comparison.csv"), row.names = FALSE, na = "")
summary_lines <- if (exact_all) {
  c("Holdout identities match exactly in both tiers. The aggregate descriptive metric tables use the same holdout identities and are compared in matched_summary_metric_comparison.csv.",
    "Tier 1 metrics retain the established presence-background design: the common saved Stage 2 terrestrial integration rows are availability support, not confirmed absences.")
} else {
  c("The two evaluation data sets do not have exact identity coverage in both tiers. Aggregate metric differences are withheld because unmatched summaries would not be a controlled paired comparison.",
    "Tier 2 paired absolute-error differences are computed only for common, uncensored records with identical observed counts. Tier 1 aggregate summaries remain descriptive and are not compared as though they used identical rows.")
}
report <- c(
  "# C-1 and refreshed original holdout comparison",
  "",
  paste0("Exact identity match across both tiers: **", if (exact_all) "yes" else "no", "**."),
  "",
  "## Holdout alignment",
  "",
  "| Tier | C-1 rows | Refreshed rows | Matched | C-1 only | Refreshed only | Exact match |",
  "|---|---:|---:|---:|---:|---:|:---:|",
  vapply(seq_len(nrow(counts)), function(i) paste0("| ", counts$tier[[i]], " | ", counts$c1_rows[[i]], " | ",
    counts$refreshed_rows[[i]], " | ", counts$matched_rows[[i]], " | ", counts$c1_only_rows[[i]],
    " | ", counts$refreshed_only_rows[[i]], " | ", if (counts$exact_identity_match[[i]]) "yes" else "no", " |"), character(1L)),
  "",
  summary_lines,
  "",
  "## Tier 2 paired point errors",
  "",
  paste0("Matched rows: ", matched_tier2$matched_n, "; C-1 only: ", matched_tier2$c1_only_n,
    "; refreshed only: ", matched_tier2$refreshed_only_n, "."),
  "Paired MAE differences are refreshed minus C-1; negative values favor the refreshed point prediction on the shared rows. This is descriptive and has no prespecified numeric acceptance threshold.",
  "",
  "## Geographic and temporal error patterns",
  "",
  "Matched Tier 2 absolute errors are summarized by administrative unit, epiweek, and their combination in matched_tier2_spatial_temporal_errors.csv. Groups with fewer than 30 rows are retained as LOW_SUPPORT.",
  "",
  "## Files",
  "",
  "- matched_holdout_counts.csv",
  "- matched_tier2_paired_absolute_error.csv",
  "- matched_tier2_spatial_temporal_errors.csv",
  "- matched_summary_metric_comparison.csv",
  "",
  "This is a descriptive comparison of the completed C-1 fit and one refreshed original-specification fit. It does not establish exact model equivalence, causal effects, or production superiority."
)
writeLines(report, file.path(output_dir, "matched_c1_original_refresh_comparison.md"), useBytes = TRUE)
cat("Holdout comparison written to ", output_dir, "\n", sep = "")
print(counts, row.names = FALSE)
