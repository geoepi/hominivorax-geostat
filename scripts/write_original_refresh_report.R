parse_args <- function(args) {
  parsed <- list(fit_job = NULL, elapsed = NA_character_, max_rss = NA_character_,
    exit_status = "0", cpus = "12", memory = "280G", overwrite = FALSE)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/write_original_refresh_report.R --fit-job JOB [--elapsed TIME] [--max-rss SIZE] [--exit-status CODE] [--cpus N] [--memory SIZE] [--overwrite]\n")
      quit(save = "no", status = 0L)
    } else if (arg == "--overwrite") {
      parsed$overwrite <- TRUE
    } else {
      name <- sub("^--", "", sub("=.*$", "", arg))
      if (!name %in% c("fit-job", "elapsed", "max-rss", "exit-status", "cpus", "memory")) stop("Unknown argument: ", arg)
      key <- gsub("-", "_", name, fixed = TRUE)
      if (grepl("=", arg, fixed = TRUE)) parsed[[key]] <- sub("^[^=]+=", "", arg)
      else {
        i <- i + 1L
        if (i > length(args)) stop("--", name, " requires a value.")
        parsed[[key]] <- args[[i]]
      }
    }
    i <- i + 1L
  }
  if (is.null(parsed$fit_job)) stop("--fit-job is required.")
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
run_root <- file.path(repo_root, "outputs", "original_refresh_w44_2026")
run_id <- "ORIGINAL_REFRESH_W44_2026"
validation_dir <- file.path(run_root, "validation", paste0("validation_presence_background_", run_id))
extraction_dir <- file.path(run_root, "extraction")
archive_root <- file.path(repo_root, "docs", "archive")
c1_archive <- file.path(archive_root, "configuration-c-1-2026")
out_dir <- file.path(archive_root, "original-refresh-w44-2026")

input_paths <- c(
  stage1_audit = file.path(run_root, "stage1", "stage1_reuse_audit.csv"),
  stage2_audit = file.path(run_root, "stage2", "joint_model_preparation_audit.csv"),
  stage3a_audit = file.path(run_root, "stage3a", "joint_inla_build_audit.csv"),
  formula_audit = file.path(run_root, "validation", "original_refresh_formula_audit.csv"),
  dry_run_preflight = file.path(run_root, "validation", "stage3b_dry_run", "joint_inla_fit_preflight.csv"),
  fit_health = file.path(run_root, "stage3b", "fit_health", paste0("fit_health_", run_id, ".csv")),
  extraction_audit = file.path(extraction_dir, paste0("extraction_audit_", run_id, ".csv")),
  fixed_effects = file.path(extraction_dir, "original_refresh_fixed_effect_summaries.csv"),
  hyperparameters = file.path(extraction_dir, "original_refresh_hyperparameter_summaries.csv"),
  random_effects = file.path(extraction_dir, "original_refresh_random_effect_summaries.csv"),
  validation_metrics = file.path(validation_dir, paste0("holdout_validation_metrics_", run_id, ".csv")),
  validation_audit = file.path(validation_dir, paste0("holdout_validation_audit_", run_id, ".csv")),
  validation_metadata = file.path(validation_dir, paste0("holdout_validation_metadata_", run_id, ".rds")),
  comparison_report = file.path(run_root, "comparison", "matched_c1_original_refresh_comparison.md"),
  comparison_counts = file.path(run_root, "comparison", "matched_holdout_counts.csv"),
  comparison_paired = file.path(run_root, "comparison", "matched_tier2_paired_absolute_error.csv"),
  subgroup_report = file.path(validation_dir, "original_refresh_predictive_subgroup_summary.md"),
  subgroup_tier1_admin = file.path(validation_dir, "tier1_same_week_percentiles_by_admin.csv"),
  subgroup_tier2_admin = file.path(validation_dir, "tier2_spatial_admin_metrics.csv"),
  subgroup_tier2_year = file.path(validation_dir, "tier2_temporal_year_metrics.csv"),
  subgroup_tier2_week = file.path(validation_dir, "tier2_temporal_epiweek_metrics.csv"),
  subgroup_tier2_yearweek = file.path(validation_dir, "tier2_temporal_yearweek_metrics.csv"),
  fit = file.path(run_root, "stage3b", "joint_model_fit.rds"),
  fit_metadata = file.path(run_root, "stage3b", "joint_model_fit_metadata.rds"),
  fit_stdout = file.path(repo_root, paste0("original-refresh-fit-", args$fit_job, ".out")),
  fit_stderr = file.path(repo_root, paste0("original-refresh-fit-", args$fit_job, ".err")),
  stage1 = file.path(run_root, "stage1", "model_inputs.rds"),
  stage2 = file.path(run_root, "stage2", "joint_model_inputs.rds"),
  stage3a = file.path(run_root, "stage3a", "joint_inla_build.rds"),
  c1_report = file.path(c1_archive, "configuration-c-1-final-assessment-2026.md"),
  c1_manifest = file.path(c1_archive, "configuration-c-1-archive-artifact-manifest-2026.csv")
)
missing <- input_paths[!file.exists(input_paths)]
if (length(missing)) stop("Required original-refresh reporting inputs are missing: ", paste(names(missing), collapse = ", "))
fit_stdout_lines <- readLines(input_paths[["fit_stdout"]], warn = FALSE)
fit_commit_line <- grep("^Repository:[[:space:]]+", fit_stdout_lines, value = TRUE)
if (length(fit_commit_line) != 1L) stop("Could not identify a unique fit-source commit in the Slurm stdout log.")
fit_repository_commit <- sub("^Repository:[[:space:]]+", "", fit_commit_line[[1L]])
fit_stderr_lines <- readLines(input_paths[["fit_stderr"]], warn = FALSE)
warning_lines <- grep("warning|reinstall|vb\\.correction", fit_stderr_lines,
  ignore.case = TRUE, value = TRUE)
warning_classes <- vapply(warning_lines, function(line) {
  if (grepl("vb.correction", line, fixed = TRUE)) return("INLA_EXPERIMENTAL_VB_WARNING")
  if (grepl("GEOS|GDAL|PROJ|terra|sf|reinstall", line, ignore.case = TRUE)) return("ATLAS_RUNTIME_WARNING")
  "UNCLASSIFIED_FIT_WARNING"
}, character(1L))
warning_provenance <- if (length(warning_lines)) {
  data.frame(
    warning_class = warning_classes, occurrence = seq_along(warning_lines),
    source_log = normalizePath(input_paths[["fit_stderr"]], mustWork = TRUE),
    exact_message = trimws(warning_lines),
    disposition = ifelse(warning_classes == "INLA_EXPERIMENTAL_VB_WARNING",
      "Retained under the supplied policy; nonblocking by itself.",
      ifelse(warning_classes == "ATLAS_RUNTIME_WARNING",
        "Retained as runtime context.", "Retained for operator review.")),
    stringsAsFactors = FALSE
  )
} else {
  data.frame(warning_class = "NONE", occurrence = 0L,
    source_log = normalizePath(input_paths[["fit_stderr"]], mustWork = TRUE),
    exact_message = "No warning-like lines found.", disposition = "No stderr warnings detected.",
    stringsAsFactors = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!isTRUE(args$overwrite) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
  stop("Refusing to overwrite the existing original-refresh archive directory.")
}

read_csv <- function(path) utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
stage1_audit <- read_csv(input_paths[["stage1_audit"]])
stage2_audit <- read_csv(input_paths[["stage2_audit"]])
stage3a_audit <- read_csv(input_paths[["stage3a_audit"]])
formula_audit <- read_csv(input_paths[["formula_audit"]])
dry_run_audit <- read_csv(input_paths[["dry_run_preflight"]])
fit_health <- read_csv(input_paths[["fit_health"]])
extraction_audit <- read_csv(input_paths[["extraction_audit"]])
fixed <- read_csv(input_paths[["fixed_effects"]])
hyper <- read_csv(input_paths[["hyperparameters"]])
random <- read_csv(input_paths[["random_effects"]])
metrics <- read_csv(input_paths[["validation_metrics"]])
validation_audit <- read_csv(input_paths[["validation_audit"]])
validation_metadata <- readRDS(input_paths[["validation_metadata"]])
fit_metadata <- readRDS(input_paths[["fit_metadata"]])
build <- readRDS(input_paths[["stage3a"]])
stage2 <- readRDS(input_paths[["stage2"]])
comparison_counts <- read_csv(input_paths[["comparison_counts"]])
comparison_paired <- read_csv(input_paths[["comparison_paired"]])

all_pass <- function(x) is.data.frame(x) && "status" %in% names(x) && nrow(x) > 0L && all(x$status == "PASS")
no_fail <- function(x) is.data.frame(x) && "status" %in% names(x) && !any(x$status == "FAIL")
stage_gates <- c(
  Stage1 = all_pass(stage1_audit),
  Stage2 = nrow(stage2_audit) > 0L &&
    all(c("tier1", "tier2") %in% as.character(stage2_audit$scope[stage2_audit$metric == "rows"])),
  Stage3A = all_pass(formula_audit) && nrow(stage3a_audit) > 0L,
  Stage3B_dry_run = no_fail(dry_run_audit),
  Stage3B_fit_health = no_fail(fit_health) && no_fail(extraction_audit),
  predictive_validation = no_fail(validation_audit)
)
refresh_decision <- if (all(stage_gates) && identical(as.character(args$exit_status), "0")) {
  "ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS"
} else {
  "ORIGINAL_REFRESH_W44_NOT_SUPPORTED"
}
c1_decision <- if (file.exists(input_paths[["c1_report"]]) && file.exists(input_paths[["c1_manifest"]])) {
  "C1_ARCHIVED_NOT_SELECTED_FOR_PRODUCTION"
} else "C1_ARCHIVAL_INCOMPLETE"

sha256 <- function(path) {
  result <- tryCatch(system2("sha256sum", path, stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(result)) return(NA_character_)
  sub("[[:space:]].*$", "", result[[1L]])
}
hash_paths <- c(
  config_identity = file.path(repo_root, "config", "original_refresh_w44_2026", "identity.yml"),
  config_stage2 = file.path(repo_root, "config", "original_refresh_w44_2026", "joint_model.yml"),
  config_stage3a = file.path(repo_root, "config", "original_refresh_w44_2026", "joint_inla.yml"),
  config_fit = file.path(repo_root, "config", "original_refresh_w44_2026", "joint_inla_fit.yml"),
  stage1 = input_paths[["stage1"]], stage1_audit = input_paths[["stage1_audit"]],
  stage2 = input_paths[["stage2"]], stage2_audit = input_paths[["stage2_audit"]],
  stage3a = input_paths[["stage3a"]], formula_audit = input_paths[["formula_audit"]],
  fit = input_paths[["fit"]], fit_metadata = input_paths[["fit_metadata"]],
  fit_stdout = input_paths[["fit_stdout"]],
  fit_stderr = input_paths[["fit_stderr"]],
  fit_health = input_paths[["fit_health"]], extraction_audit = input_paths[["extraction_audit"]],
  validation_metrics = input_paths[["validation_metrics"]], validation_audit = input_paths[["validation_audit"]],
  comparison_counts = input_paths[["comparison_counts"]], comparison_paired = input_paths[["comparison_paired"]],
  comparison_report = input_paths[["comparison_report"]],
  subgroup_report = input_paths[["subgroup_report"]],
  subgroup_tier1_admin = input_paths[["subgroup_tier1_admin"]],
  subgroup_tier2_admin = input_paths[["subgroup_tier2_admin"]],
  subgroup_tier2_year = input_paths[["subgroup_tier2_year"]],
  subgroup_tier2_week = input_paths[["subgroup_tier2_week"]],
  subgroup_tier2_yearweek = input_paths[["subgroup_tier2_yearweek"]],
  c1_archive_report = input_paths[["c1_report"]], c1_archive_manifest = input_paths[["c1_manifest"]]
)
manifest <- data.frame(
  role = names(hash_paths), path = unname(hash_paths),
  sha256 = vapply(hash_paths, sha256, character(1L)),
  bytes = as.numeric(file.info(hash_paths)$size),
  stringsAsFactors = FALSE
)
manifest$fit_job <- as.character(args$fit_job)
manifest$repository_commit <- paste(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE), collapse = "")
manifest$fit_repository_commit <- fit_repository_commit

fixed_file <- file.path(out_dir, "original_refresh_fixed_effect_summaries.csv")
hyper_file <- file.path(out_dir, "original_refresh_hyperparameter_summaries.csv")
random_file <- file.path(out_dir, "original_refresh_random_component_summary.csv")
metrics_file <- file.path(out_dir, "original_refresh_predictive_metrics.csv")
fit_health_file <- file.path(out_dir, "original_refresh_fit_health.csv")
extraction_audit_file <- file.path(out_dir, "original_refresh_extraction_audit.csv")
validation_audit_file <- file.path(out_dir, "original_refresh_validation_audit.csv")
stage1_audit_file <- file.path(out_dir, "original_refresh_stage1_reuse_audit.csv")
formula_audit_file <- file.path(out_dir, "original_refresh_formula_audit.csv")
comparison_counts_file <- file.path(out_dir, "matched_holdout_counts.csv")
comparison_paired_file <- file.path(out_dir, "matched_tier2_paired_absolute_error.csv")
comparison_report_file <- file.path(out_dir, "matched_c1_original_refresh_comparison.md")
subgroup_report_file <- file.path(out_dir, "original_refresh_predictive_subgroup_summary.md")
subgroup_tier1_admin_file <- file.path(out_dir, "tier1_same_week_percentiles_by_admin.csv")
subgroup_tier2_admin_file <- file.path(out_dir, "tier2_spatial_admin_metrics.csv")
subgroup_tier2_year_file <- file.path(out_dir, "tier2_temporal_year_metrics.csv")
subgroup_tier2_week_file <- file.path(out_dir, "tier2_temporal_epiweek_metrics.csv")
subgroup_tier2_yearweek_file <- file.path(out_dir, "tier2_temporal_yearweek_metrics.csv")
manifest_file <- file.path(out_dir, "original_refresh_artifact_manifest.csv")
execution_file <- file.path(out_dir, "slurm_execution_summary.csv")
warning_file <- file.path(out_dir, "original_refresh_fit_warnings.csv")
copy_paths <- c(fixed_file, hyper_file, random_file, metrics_file, fit_health_file,
  extraction_audit_file, validation_audit_file, stage1_audit_file, formula_audit_file,
  comparison_counts_file, comparison_paired_file, comparison_report_file, subgroup_tier1_admin_file,
  subgroup_tier2_admin_file, subgroup_tier2_year_file, subgroup_tier2_week_file,
  subgroup_tier2_yearweek_file, subgroup_report_file, warning_file, manifest_file, execution_file)
if (!isTRUE(args$overwrite) && any(file.exists(copy_paths))) stop("Refusing to overwrite archive summary files.")

utils::write.csv(fixed, fixed_file, row.names = FALSE, na = "")
utils::write.csv(hyper, hyper_file, row.names = FALSE, na = "")
random_summary <- do.call(rbind, lapply(split(random, random$component), function(x) {
  values <- suppressWarnings(as.numeric(x$mean))
  sd_values <- suppressWarnings(as.numeric(x$sd))
  data.frame(component = as.character(x$component[[1L]]), rows = nrow(x),
    finite_mean_rows = sum(is.finite(values)), mean_of_posterior_means = mean(values[is.finite(values)]),
    median_posterior_sd = stats::median(sd_values[is.finite(sd_values)]),
    mean_q025 = if ("0.025quant" %in% names(x)) mean(as.numeric(x[["0.025quant"]]), na.rm = TRUE) else NA_real_,
    mean_q975 = if ("0.975quant" %in% names(x)) mean(as.numeric(x[["0.975quant"]]), na.rm = TRUE) else NA_real_,
    stringsAsFactors = FALSE)
}))
utils::write.csv(random_summary, random_file, row.names = FALSE, na = "")
utils::write.csv(metrics, metrics_file, row.names = FALSE, na = "")
utils::write.csv(fit_health, fit_health_file, row.names = FALSE, na = "")
utils::write.csv(extraction_audit, extraction_audit_file, row.names = FALSE, na = "")
utils::write.csv(validation_audit, validation_audit_file, row.names = FALSE, na = "")
utils::write.csv(stage1_audit, stage1_audit_file, row.names = FALSE, na = "")
utils::write.csv(formula_audit, formula_audit_file, row.names = FALSE, na = "")
utils::write.csv(warning_provenance, warning_file, row.names = FALSE, na = "")
utils::write.csv(comparison_counts, comparison_counts_file, row.names = FALSE, na = "")
utils::write.csv(comparison_paired, comparison_paired_file, row.names = FALSE, na = "")
if (!file.copy(input_paths[["comparison_report"]], comparison_report_file, overwrite = isTRUE(args$overwrite))) {
  stop("Could not copy the matched C-1 comparison report into the original-refresh archive.")
}
subgroup_sources <- c(input_paths[["subgroup_report"]], input_paths[["subgroup_tier1_admin"]],
  input_paths[["subgroup_tier2_admin"]], input_paths[["subgroup_tier2_year"]],
  input_paths[["subgroup_tier2_week"]], input_paths[["subgroup_tier2_yearweek"]])
subgroup_targets <- c(subgroup_report_file, subgroup_tier1_admin_file, subgroup_tier2_admin_file,
  subgroup_tier2_year_file, subgroup_tier2_week_file, subgroup_tier2_yearweek_file)
if (!all(file.copy(subgroup_sources, subgroup_targets, overwrite = isTRUE(args$overwrite)))) {
  stop("Could not copy all predictive subgroup tables into the original-refresh archive.")
}
execution <- data.frame(
  fit_job = as.character(args$fit_job), fit_repository_commit = fit_repository_commit,
  report_repository_commit = manifest$repository_commit[[1L]],
  fit_configuration_sha256 = sha256(file.path(repo_root, "config", "original_refresh_w44_2026", "joint_inla_fit.yml")),
  cpus = args$cpus, requested_memory = args$memory, elapsed = args$elapsed,
  peak_rss = args$max_rss, exit_status = args$exit_status,
  fit_stderr_sha256 = sha256(input_paths[["fit_stderr"]]),
  inla_experimental_vb_warning_occurrences = sum(warning_provenance$warning_class == "INLA_EXPERIMENTAL_VB_WARNING"),
  unclassified_stderr_warning_lines = sum(warning_provenance$warning_class == "UNCLASSIFIED_FIT_WARNING"),
  R_version = R.version.string, INLA_version = if (requireNamespace("INLA", quietly = TRUE)) as.character(utils::packageVersion("INLA")) else "not-loaded",
  stringsAsFactors = FALSE
)
utils::write.csv(execution, execution_file, row.names = FALSE, na = "")
manifest <- rbind(manifest, data.frame(
  role = "fit_warning_provenance", path = warning_file, sha256 = sha256(warning_file),
  bytes = as.numeric(file.info(warning_file)$size), fit_job = as.character(args$fit_job),
  repository_commit = manifest$repository_commit[[1L]], fit_repository_commit = fit_repository_commit,
  stringsAsFactors = FALSE
))
utils::write.csv(manifest, manifest_file, row.names = FALSE, na = "")

get_audit_value <- function(data, scope, metric) {
  value <- data$value[data$scope == scope & data$metric == metric]
  if (length(value) == 1L) as.character(value) else "not recorded"
}
fixed_lines <- vapply(seq_len(nrow(fixed)), function(i) {
  x <- fixed[i, ]
  paste0("| ", x$term, " | ", formatC(x$mean, digits = 4, format = "fg", flag = "#"), " | ",
    formatC(x$sd, digits = 4, format = "fg", flag = "#"), " | [",
    formatC(x[["0.025quant"]], digits = 4, format = "fg", flag = "#"), ", ",
    formatC(x[["0.975quant"]], digits = 4, format = "fg", flag = "#"), "] |")
}, character(1L))
metric_lines <- vapply(seq_len(nrow(metrics)), function(i) {
  x <- metrics[i, ]
  value <- if (is.finite(as.numeric(x$value))) formatC(as.numeric(x$value), digits = 6, format = "fg", flag = "#") else "not estimable"
  paste0("| ", x$tier, " | ", x$metric, " | ", value, " | ", x$status, " | ", x$n, " |")
}, character(1L))
stage_lines <- vapply(names(stage_gates), function(name) paste0("| ", name, " | ", if (stage_gates[[name]]) "PASS" else "FAIL", " |"), character(1L))
matched_rows <- if ("matched_rows" %in% names(comparison_counts)) sum(comparison_counts$matched_rows) else NA_integer_
unmatched_rows <- if (all(c("c1_only_rows", "refreshed_only_rows") %in% names(comparison_counts))) {
  sum(comparison_counts$c1_only_rows + comparison_counts$refreshed_only_rows)
} else NA_integer_
paired_mae <- comparison_paired$value[comparison_paired$metric == "paired_mae_difference_refreshed_minus_c1"]
paired_text <- if (length(paired_mae) == 1L && is.finite(paired_mae)) as.character(paired_mae) else "not estimable"
vb_warning_count <- sum(warning_provenance$warning_class == "INLA_EXPERIMENTAL_VB_WARNING")
runtime_warning_count <- sum(warning_provenance$warning_class == "ATLAS_RUNTIME_WARNING")
unclassified_warning_count <- sum(warning_provenance$warning_class == "UNCLASSIFIED_FIT_WARNING")
warning_count <- sum(fit_health$status == "WARNING") + sum(validation_audit$status == "WARNING") +
  vb_warning_count + unclassified_warning_count

report <- c(
  "# Original model refresh through 2026-W44",
  "",
  paste0("Model: **ORIGINAL_REFRESH_W44_2026**. Final qualification: **", refresh_decision, "**. C-1 disposition: **", c1_decision, "**."),
  "",
  "## Decision summary",
  "",
  "The frozen original fixed-effect specification was restored from the manifest-free branch of R/joint_inla_spec.R at the development base commit. It contains 14 established predictor terms plus intercept1 and intercept2 (16 fixed coefficients total), including mintemp:soilmoist and mintemp:leafarea. C-1-only clay, wv0010, and spressure are absent from the Stage 3A design.",
  "The refreshed data revision is the approved 2026-11-13 observation release through 2026-W44 (2026-11-01). The C-1 Stage 1 artifact was reused only after its artifact hash, source checksum, manifest, explicit window, predictor schema, mesh, coordinate, and exposure contracts passed. Stage 2 and Stage 3A were rebuilt in this isolated output tree.",
  "",
  "## Separate qualification evidence",
  "",
  "| Gate | Result |",
  "|---|---|",
  stage_lines,
  "",
  paste0("The Stage 3B fit-health and production extraction gates recorded ", sum(fit_health$status == "PASS"), " and ", sum(fit_health$status == "WARNING"), " checks, with ", sum(fit_health$status == "FAIL"), " failures. Extraction recorded ", sum(extraction_audit$status == "PASS"), " PASS and ", sum(extraction_audit$status == "FAIL"), " FAIL checks. Model/validation warnings retained: ", warning_count, "; Atlas runtime warning lines retained separately: ", runtime_warning_count, "."),
  "",
  "### Computational qualification",
  "",
  paste0("Stage 1/2/3A prepared through 2026-W44. Stage 2 Tier 1/Tier 2 source rows: ",
    get_audit_value(stage2_audit, "tier1", "rows"), " / ", get_audit_value(stage2_audit, "tier2", "rows"),
    "; Stage 3A mesh vertices: ", get_audit_value(stage3a_audit, "mesh", "vertices"),
    "; quarter groups: ", get_audit_value(stage3a_audit, "temporal", "quarter_groups"),
    ". The formula audit confirms 16 fixed effects, original interactions, both likelihoods, and executed_fit = FALSE."),
  paste0("Stage 3B job ", args$fit_job, " used ", args$cpus, " CPUs and ", args$memory,
    " requested memory; elapsed ", args$elapsed, "; peak RSS ", args$max_rss,
    ". Fit artifact SHA-256: ", sha256(input_paths[["fit"]]), "."),
  "",
  paste0("The Slurm stderr log contained ", vb_warning_count, " occurrence(s) of INLA_EXPERIMENTAL_VB_WARNING and ", unclassified_warning_count, " unclassified warning line(s). Exact messages, occurrence counts, source log, and dispositions are archived in original_refresh_fit_warnings.csv. Atlas runtime warnings are retained there separately. The documented experimental VB correction warning was not treated as a fit failure, and no refit was attempted in response to it."),
  "",
  "### Predictive performance",
  "",
  "| Tier | Metric | Value | Status | n |",
  "|---|---|---:|---|---:|",
  metric_lines,
  "",
  "Tier 1 uses held-out detections against same-week terrestrial integration/background support; these locations have unknown biological status and are not confirmed absences. Tier 2 point metrics are on expected-count scale. Observation-level negative-binomial predictive intervals were reported unavailable; conditional-mean marginals were not substituted. Geographic and temporal subgroup summaries use the established 30-row display threshold.",
  "",
  "### Model parsimony and scientific interpretation",
  "",
  "The refreshed candidate uses the established 16-term original formula and excludes the three C-1 additions. This restores the simpler operational specification while preserving the joint binomial/negative-binomial architecture, row-specific family links, tier-specific intercepts, SPDE fields, quarter grouping, temporal RW1 effects, Tier 1 administrative IID effect, shared/copy field, cattle RW2, original priors, reporting censoring, Tier 2 zero/background policy, exposures, holdout selectors, and prediction-grid convention.",
  "Fixed-effect summaries are conditional on the retained spatial and random-effect structure. Random-effect and hyperparameter diagnostics are summarized separately; no individual predictor is interpreted causally. Results do not establish model superiority or exact equivalence to C-1.",
  "",
  "### Production readiness",
  "",
  if (identical(refresh_decision, "ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS")) {
    "The refreshed original specification is the next production candidate, **not yet a production replacement**. It passed the documented technical gates with limitations from positive-only Tier 1 holdouts, absent observation-level predictive intervals, and descriptive predictive metrics without numeric acceptance cutoffs. No production merge or artifact replacement was performed."
  } else {
    "The refreshed original specification did not pass all documented qualification gates and is not a production replacement. Review the gate table and audit files before any further use. No production merge or artifact replacement was performed."
  },
  "",
  "## Refreshed inputs and Stage 2 support",
  "",
  paste0("- Observation source SHA-256: 784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac; source rows: 164,767."),
  paste0("- Stage 1 Tier 1/Tier 2/prediction-grid rows: ", stage1_audit$observed[stage1_audit$check == "tier_data"], "; reused artifact path: outputs/original_refresh_w44_2026/stage1/model_inputs.rds."),
  paste0("- Stage 2 active Tier 2 response rows: ", sum(!is.na(stage2$tier2$response_training)), "; Tier 1 holdouts: ", get_audit_value(stage2_audit, "tier1", "selected_positive_holdouts"), "; Tier 2 holdouts: ", get_audit_value(stage2_audit, "tier2", "selected_positive_holdouts"), "."),
  paste0("- Tier 1/Tier 2 A-matrix dimensions: ", get_audit_value(stage3a_audit, "A", "tier1_dimensions"), " / ", get_audit_value(stage3a_audit, "A", "tier2_dimensions"), "."),
  "",
  "## Fixed-effect posterior summaries",
  "",
  "| Term | Mean | SD | 95% marginal interval |",
  "|---|---:|---:|---:|",
  fixed_lines,
  "",
  "Full fixed-effect and hyperparameter summaries, a compact random-component summary, and validation audit tables are preserved beside this report.",
  "",
  "## Configuration C-1 comparison",
  "",
  paste0("Matched holdout rows: ", matched_rows, "; unmatched C-1 plus refreshed rows: ", unmatched_rows, "; paired Tier 2 MAE difference (refreshed minus C-1): ", paired_text, "."),
  "Read the matched-comparison report for Tier 1/2 identity counts, aggregate metrics when exact identity coverage permits, and geographic/temporal paired error summaries. Unmatched aggregate metrics are not presented as a controlled comparison. The refreshed-model subgroup tables separately summarize Tier 1 availability percentiles and Tier 2 errors by administrative unit, year, epiweek, and year-week.",
  "",
  "## Slurm and software provenance",
  "",
  paste0("- Fit Slurm job: ", args$fit_job, "; allocation: ", args$cpus, " CPUs / ", args$memory, "; elapsed: ", args$elapsed, "; peak RSS: ", args$max_rss, "; exit status: ", args$exit_status, "."),
  paste0("- Fit-source repository commit: ", fit_repository_commit, "; report-generator repository commit: ", manifest$repository_commit[[1L]], "."),
  paste0("- R: ", R.version.string, "; INLA: ", if (requireNamespace("INLA", quietly = TRUE)) as.character(utils::packageVersion("INLA")) else validation_metadata$software$INLA_validation_runtime, "."),
  paste0("- Fit SHA-256: ", sha256(input_paths[["fit"]]), "; Stage 3A SHA-256: ", sha256(input_paths[["stage3a"]]), "; Stage 2 SHA-256: ", sha256(input_paths[["stage2"]]), "; copied Stage 1 SHA-256: ", sha256(input_paths[["stage1"]]), "."),
  "",
  "## Archived evidence files",
  "",
  "- original_refresh_fixed_effect_summaries.csv",
  "- original_refresh_hyperparameter_summaries.csv",
  "- original_refresh_random_component_summary.csv",
  "- original_refresh_predictive_metrics.csv",
  "- original_refresh_fit_health.csv",
  "- original_refresh_fit_warnings.csv",
  "- original_refresh_extraction_audit.csv",
  "- original_refresh_validation_audit.csv",
  "- original_refresh_stage1_reuse_audit.csv",
  "- original_refresh_formula_audit.csv",
  "- matched_holdout_counts.csv",
  "- matched_tier2_paired_absolute_error.csv",
  "- matched_c1_original_refresh_comparison.md",
  "- tier1_same_week_percentiles_by_admin.csv",
  "- tier2_spatial_admin_metrics.csv",
  "- tier2_temporal_year_metrics.csv",
  "- tier2_temporal_epiweek_metrics.csv",
  "- tier2_temporal_yearweek_metrics.csv",
  "- original_refresh_predictive_subgroup_summary.md",
  "- original_refresh_artifact_manifest.csv",
  "- slurm_execution_summary.csv",
  "",
  "Full serialized model artifacts and row-level validation files remain in their immutable Atlas run paths recorded in original_refresh_artifact_manifest.csv. No geographic posterior surface or raster was generated."
)
report_path <- file.path(out_dir, "original-refresh-w44-2026.md")
writeLines(report, report_path, useBytes = TRUE)
cat("Original refresh qualification report: ", report_path, "\n", sep = "")
cat("Decision: ", refresh_decision, "; C-1: ", c1_decision, "\n", sep = "")
