parse_args <- function(args) {
  parsed <- list(
    fit = NULL, stage2 = NULL, stage1 = NULL, stage3a = NULL, holdout = NULL,
    tier2_rows = NULL, predictive_metrics = NULL, predictive_manifest = NULL,
    fit_job = "21304948",
    output_dir = "docs/archive/configuration-c-1-2026",
    predictive_report = NULL, predictive_report_sha256 = NA_character_,
    stage1_sha256 = "64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af",
    stage2_sha256 = "55f5e2854461a1f7c694745a68f33b0d441471dd0efa492f840f12d2bb3cbb04",
    stage3a_sha256 = "a204351363216b1fc6fcbb7aa4271b0bdb7803324a803ee1834ec5df0a4b43d5",
    fit_sha256 = "c1662497af6e26313ead3055686195880673ad21efeb6c05f51bfe878080b28d",
    fit_commit = "923c1c0ad3d1c19c524b3dc981bbb8170620c6a0",
    config_sha256 = "1d24b041875d9d10995240d64add12e4d8ec796cb32f85a738d38a42c9027a84",
    manifest_sha256 = "9f1509e98906c77cfcaa57b6146212d5e60eab7a569d309788d6f6fd738dfc8d",
    overwrite = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript scripts/assess_c1_effects.R --fit PATH --stage1 PATH --stage2 PATH --stage3a PATH --holdout PATH --tier2-rows PATH --predictive-metrics PATH --predictive-manifest PATH --predictive-report PATH [--output-dir PATH]\n")
      quit(save = "no", status = 0L)
    } else if (arg == "--overwrite") {
      parsed$overwrite <- TRUE
    } else {
      name <- sub("^--", "", sub("=.*$", "", arg))
      if (!name %in% c("fit", "stage2", "stage1", "stage3a", "holdout", "tier2-rows",
                       "predictive-metrics", "predictive-manifest", "output-dir",
                       "predictive-report", "predictive-report-sha256", "fit-job")) {
        stop("Unknown argument: ", arg)
      }
      key <- gsub("-", "_", name, fixed = TRUE)
      if (grepl("=", arg, fixed = TRUE)) parsed[[key]] <- sub("^[^=]+=", "", arg)
      else {
        i <- i + 1L
        if (i > length(args)) stop("--", name, " requires a path.")
        parsed[[key]] <- args[[i]]
      }
    }
    i <- i + 1L
  }
  parsed
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
required_args <- c("fit", "stage1", "stage2", "stage3a", "holdout", "tier2_rows",
                   "predictive_metrics", "predictive_manifest", "predictive_report")
if (any(vapply(args[required_args], is.null, logical(1L)))) {
  stop("Fit, Stage 1/2/3A, extracted holdout, predictive metrics, manifest, and report paths are required.")
}
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
resolve <- function(path) if (is.null(path) || !nzchar(path)) path else if (grepl("^/", path)) path else file.path(repo_root, path)
fit_path <- normalizePath(resolve(args$fit), mustWork = TRUE)
stage2_path <- normalizePath(resolve(args$stage2), mustWork = TRUE)
stage1_path <- normalizePath(resolve(args$stage1), mustWork = TRUE)
stage3a_path <- normalizePath(resolve(args$stage3a), mustWork = TRUE)
holdout_path <- normalizePath(resolve(args$holdout), mustWork = TRUE)
tier2_rows_path <- normalizePath(resolve(args$tier2_rows), mustWork = TRUE)
predictive_metrics_path <- normalizePath(resolve(args$predictive_metrics), mustWork = TRUE)
predictive_manifest_path <- normalizePath(resolve(args$predictive_manifest), mustWork = TRUE)
predictive_path <- if (is.null(args$predictive_report)) NA_character_ else normalizePath(resolve(args$predictive_report), mustWork = TRUE)
output_dir <- resolve(args$output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("INLA", quietly = TRUE)) {
  stop("digest and INLA are required to assess the saved fitted marginals.")
}
fit_sha <- digest::digest(file = fit_path, algo = "sha256")
if (!identical(tolower(fit_sha), tolower(args$fit_sha256))) stop("C-1 fit SHA-256 does not match its archived identifier.")
stage1_sha <- digest::digest(file = stage1_path, algo = "sha256")
stage2_sha <- digest::digest(file = stage2_path, algo = "sha256")
stage3a_sha <- digest::digest(file = stage3a_path, algo = "sha256")
if (!identical(tolower(stage1_sha), tolower(args$stage1_sha256))) stop("C-1 Stage 1 SHA-256 does not match the Stage 1 artifact inventory.")
if (!identical(tolower(stage2_sha), tolower(args$stage2_sha256))) stop("C-1 Stage 2 SHA-256 does not match the C-1 predictive artifact manifest.")
if (!identical(tolower(stage3a_sha), tolower(args$stage3a_sha256))) stop("C-1 Stage 3A SHA-256 does not match the C-1 predictive artifact manifest.")
if (!is.na(predictive_path)) {
  predictive_sha <- digest::digest(file = predictive_path, algo = "sha256")
  if (!is.na(args$predictive_report_sha256) &&
      !identical(tolower(predictive_sha), tolower(args$predictive_report_sha256))) {
    stop("C-1 predictive report SHA-256 does not match its artifact manifest.")
  }
} else predictive_sha <- NA_character_
holdout_sha <- digest::digest(file = holdout_path, algo = "sha256")
tier2_rows_sha <- digest::digest(file = tier2_rows_path, algo = "sha256")
predictive_metrics_sha <- digest::digest(file = predictive_metrics_path, algo = "sha256")
manifest <- utils::read.csv(predictive_manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
manifest_input <- function(role, observed_sha) {
  row <- manifest[manifest$kind == "INPUT" & manifest$role == role, , drop = FALSE]
  if (nrow(row) != 1L ||
      !identical(normalizePath(row$path, mustWork = TRUE),
                 normalizePath(switch(role, fit = fit_path, stage2 = stage2_path,
                   build = stage3a_path, holdout = holdout_path), mustWork = TRUE)) ||
      !identical(tolower(as.character(row$sha256)), tolower(observed_sha))) {
    stop("C-1 predictive manifest input does not match ", role, ".")
  }
}
manifest_input("fit", fit_sha)
manifest_input("stage2", stage2_sha)
manifest_input("build", stage3a_sha)
manifest_input("holdout", holdout_sha)
for (item in list(
  list(path = predictive_path, sha = predictive_sha, pattern = "c1_predictive_qualification_report_"),
  list(path = predictive_metrics_path, sha = predictive_metrics_sha, pattern = "holdout_validation_metrics_"),
  list(path = tier2_rows_path, sha = tier2_rows_sha, pattern = "tier2_holdout_diagnostics_")
)) {
  rows <- manifest[manifest$kind == "OUTPUT" & grepl(item$pattern, basename(manifest$path)), , drop = FALSE]
  if (nrow(rows) != 1L || !identical(normalizePath(rows$path, mustWork = TRUE), item$path) ||
      !identical(tolower(as.character(rows$sha256)), tolower(item$sha))) {
    stop("C-1 predictive artifact does not match its archived manifest: ", item$pattern)
  }
}

source(file.path(repo_root, "R", "c1_effect_assessment.R"))
source(file.path(repo_root, "R", "joint_inla_extract.R"))
fit_artifact <- readRDS(fit_path)
fit <- joint_inla_extract_fit(fit_artifact)
if (is.null(fit$marginals.fixed)) stop("Existing C-1 fit does not contain saved fixed-effect marginals.")
stage2 <- readRDS(stage2_path)
if (is.null(stage2$tier2) || !is.data.frame(stage2$tier2)) stop("C-1 Stage 2 artifact has no Tier 2 analytical support.")
terms <- c("clay", "wv0010", "spressure")
missing_marginals <- setdiff(terms, names(fit$marginals.fixed))
missing_predictors <- setdiff(terms, names(stage2$tier2))
if (length(missing_marginals)) stop("Saved fixed-effect marginals are missing: ", paste(missing_marginals, collapse = ", "))
if (length(missing_predictors)) stop("Stage 2 Tier 2 support is missing: ", paste(missing_predictors, collapse = ", "))

posterior <- do.call(rbind, lapply(terms, function(term) c1_effect_marginal_summary(fit$marginals.fixed[[term]], term)))
all_support <- do.call(rbind, lapply(terms, function(term) {
  c1_effect_distribution(stage2$tier2[[term]], term, "all finite Stage 2 Tier 2 analytical-support rows")
}))
active_rows <- !is.na(stage2$tier2$response_training)
active_support <- do.call(rbind, lapply(terms, function(term) {
  c1_effect_distribution(stage2$tier2[[term]][active_rows], term, "active Tier 2 response_training rows")
}))
distributions <- rbind(all_support, active_support)
effects <- do.call(rbind, lapply(seq_len(nrow(posterior)), function(i) {
  do.call(rbind, lapply(seq_len(nrow(distributions)), function(j) {
    if (!identical(posterior$term[[i]], distributions$term[[j]])) return(NULL)
    c1_effect_scale_summary(posterior[i, , drop = FALSE], distributions[j, , drop = FALSE])
  }))
}))
posterior <- c1_effect_join_source_units(posterior)

paths <- c(
  posterior = file.path(output_dir, "configuration-c-1-fixed-effect-posterior-2026.csv"),
  distributions = file.path(output_dir, "configuration-c-1-predictor-distributions-2026.csv"),
  effects = file.path(output_dir, "configuration-c-1-practical-effects-2026.csv"),
  report = file.path(output_dir, "configuration-c-1-final-assessment-2026.md"),
  manifest = file.path(output_dir, "configuration-c-1-archive-artifact-manifest-2026.csv")
)
if (!isTRUE(args$overwrite) && any(file.exists(paths))) stop("Refusing to overwrite C-1 archival assessment outputs.")
utils::write.csv(posterior, paths[["posterior"]], row.names = FALSE, na = "")
utils::write.csv(distributions, paths[["distributions"]], row.names = FALSE, na = "")
utils::write.csv(effects, paths[["effects"]], row.names = FALSE, na = "")

fmt <- function(x, digits = 5L) if (!is.finite(as.numeric(x))) "not estimable" else formatC(as.numeric(x), digits = digits, format = "fg", flag = "#")
posterior_lines <- vapply(seq_len(nrow(posterior)), function(i) {
  row <- posterior[i, ]
  paste0("| ", row$term, " | ", row$source_units, " | ", fmt(row$posterior_mean), " | ",
         fmt(row$posterior_median), " | ", fmt(row$posterior_sd), " | [",
         fmt(row$q025), ", ", fmt(row$q975), "] | ",
         if (row$interval_contains_zero) "yes" else "no", " | ",
         fmt(row$probability_positive, 4L), " |")
}, character(1L))
effect_lines <- vapply(seq_len(nrow(effects)), function(i) {
  row <- effects[i, ]
  paste0("| ", row$term, " | ", row$sample, " | ", fmt(row$predictor_iqr), " | ",
         fmt(row$multiplicative_median_iqr), " [", fmt(row$multiplicative_q025_iqr), ", ",
         fmt(row$multiplicative_q975_iqr), "] | ",
         fmt(row$multiplicative_median_10_90), " [", fmt(row$multiplicative_q025_10_90), ", ",
         fmt(row$multiplicative_q975_10_90), "] |")
}, character(1L))
predictive_text <- if (is.na(predictive_path)) {
  "Existing report path was not passed to this script; see the archived C-1 predictive validation artifacts."
} else paste0("Existing report: ", predictive_path, " (SHA-256 ", predictive_sha, "). ",
  "Its reported decision is C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS. Tier 1 used 4,768 positive held-out detections and no confirmed negatives, so presence-background AUC, Continuous Boyce Index, and same-week availability percentiles are descriptive; binary classification metrics are not estimable. Reported area-weighted presence-background AUC was 0.9907229; area-weighted CBI was 0.9997558; mean area-weighted same-week percentile was 0.9829135. Tier 2 used 7,471 positive-count holdouts: mean observed 4.3432, mean expected 4.4197, MAE 2.0702, RMSE 3.1523, Pearson 0.7818, Spearman 0.6484, and mean expected-minus-observed bias 0.0765. Observation-level predictive intervals were unavailable.")
report <- c(
  "# Configuration C-1 final fixed-effect assessment",
  "",
  "Disposition: **C1_ARCHIVED_NOT_SELECTED_FOR_PRODUCTION**.",
  "",
  "## Provenance",
  "",
  paste0("- Completed fit: Stage 3B job ", args$fit_job, "; SHA-256 ", fit_sha, "."),
  paste0("- Fit repository commit: ", args$fit_commit, "; C-1 configuration SHA-256 ", args$config_sha256, "."),
  paste0("- C-1 source manifest SHA-256: ", args$manifest_sha256, "."),
  paste0("- Stage 2 artifact: ", stage2_path, "; SHA-256 ", digest::digest(file = stage2_path, algo = "sha256"), "."),
  if (!is.na(stage1_path)) paste0("- Reused Stage 1 artifact: ", stage1_path, "; SHA-256 ", digest::digest(file = stage1_path, algo = "sha256"), ".") else "- Stage 1 artifact path was not passed; see the existing artifact manifest.",
  "- Observation release: combined_clean_obs_2026-11-13.csv; SHA-256 784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac; 164,767 source rows; analyzed through 2026-W44 (2026-11-01).",
  paste0("- Runtime: R ", R.version.string, "; INLA ", as.character(utils::packageVersion("INLA")), "."),
  "",
  "The C-1 fit was reused as completed. No C-1 refit, preprocessing rerun, Stage 3A rebuild, joint latent posterior sampling, or prediction surface was performed. All coefficient summaries below use the saved one-dimensional INLA fixed-effect marginals.",
  "",
  "## Fixed-effect posterior summaries",
  "",
  "| Term | Source units | Mean | Median | SD | 95% credible interval | Contains zero | P(beta > 0) |",
  "|---|---|---:|---:|---:|---:|:---:|---:|",
  posterior_lines,
  "",
  "## Observed predictor distributions and practical effects",
  "",
  "The primary distribution is all finite Tier 2 rows in the completed C-1 Stage 2 analytical support (including rows not active in the likelihood, such as holdout, censored, and zero-policy rows). The sensitivity distribution is the subset with nonmissing response_training. These ranges describe the stored mapped units and are not restricted to positive counts.",
  "",
  "| Term | Stage 2 sample | IQR | Median multiplicative effect over IQR (95% marginal interval) | Median multiplicative effect over 10th–90th range (95% marginal interval) |",
  "|---|---|---:|---:|---:|",
  effect_lines,
  "",
  "For each linear log-link coefficient beta and predictor spread d, the multiplicative summary is exp(beta × d); the interval endpoints transform the saved marginal 2.5% and 97.5% quantiles. It is a relative conditional intensity/count-rate contrast over the stated predictor difference, not an absolute count change or a causal effect.",
  "",
  "## Scientific interpretation",
  "",
  "Direction and uncertainty are reported directly from the saved coefficient marginals. Practical size should be judged from the transformed effects over the observed predictor ranges rather than from raw coefficient magnitudes. Soil clay and volumetric water content may share spatial structure and can overlap with the spatial field; weekly surface pressure may overlap environmentally with humidity, temperature, and soil-moisture structure. These are plausible redundancy pathways, not demonstrated collinearity or an identified variance partition.",
  "",
  "The existing predictive validation is descriptive and does not identify the incremental contribution of any one term. It uses positive-only Tier 1 holdouts and positive-count Tier 2 holdouts, provides no confirmed absence sample, and did not produce observation-level predictive intervals. The C-1 versus original comparison must use matched holdout records before any performance difference is interpreted; no C-1 inferiority or superiority is established here.",
  "",
  predictive_text,
  "",
  "The three added terms have not demonstrated sufficient incremental practical or predictive value to justify retention in the operational model. The original candidate therefore excludes clay, wv0010, and spressure pending a controlled comparison. This is a model-parsimony and attribution decision; it does not assert that C-1 is inferior.",
  "",
  "## C-1 qualification record",
  "",
  "- Formula: intercept1 + intercept2; north + road_dens + night_illum + mintemp + soilmoist + leafarea + rhum + mintemp:soilmoist + mintemp:leafarea + cattle + horses + pigs + goats + sheep + clay + wv0010 + spressure, with the existing joint binomial/negative-binomial, spatial SPDE, temporal, administrative, shared/copy-field, and cattle RW2 components.",
  "- Fixed-effect count: 19 including two tier intercepts.",
  "- Stage 3B status: C1_STAGE3B_QUALIFIED_WITH_LIMITATIONS; ten hyperparameters and seven random-effect components were retained.",
  "- Stage 1: 164,767 source rows; 163,730 retained; 968 outside the analysis domain/window; 69 duplicate records; zero invalid records. It produced 3,451,435 Tier 1 rows, 2,749,320 Tier 2 rows, 4,007,808 prediction-grid rows, and 252 modeled weeks.",
  "- Stage 2: Tier 1/Tier 2 holdouts 4,768/7,471; 2,701,046 zero-count responses excluded under the original policy; 9,555/10,920 reporting-censored rows; 29,883 active Tier 2 training rows.",
  "- Stage 3A: mesh 13,507 vertices; 20 quarter groups; A matrices 3,451,435 x 270,140 and 2,749,320 x 270,140; 19 fixed effects including both tier intercepts; no fit executed.",
  "- Stage 3B: 12 CPUs, 280G requested memory, 48-hour allocation; elapsed 16:56:29; peak RSS approximately 168.2 GiB; exit status 0; fit artifact 6,893,458,325 bytes.",
  "- Environmental coverage: the approved C-1 manifest records 252 weekly pressure inputs through 2026-W44 and static SoilGrids layers; baseline dynamic covariates retain 2022-W01 through 2026-W44 coverage. The manifest's source bytes and provenance remain part of the preserved C-1 record.",
  "- Predictive status: C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS.",
  "- Recorded warning: INLA_EXPERIMENTAL_VB_WARNING (two occurrences); retained as provenance and not treated as fit failure.",
  "- Limitations: positive-only validation samples; no observation-level predictive intervals; no individual-predictor attribution; SoilGrids product alias is mutable; the ERA5-Land source is in Pa while the C-1 fitted column is recorded in kPa, with exact file-level scaling provenance unresolved.",
  "",
  "The C-1 artifacts remain at their original paths and are not modified by this report."
)
writeLines(report, paths[["report"]], useBytes = TRUE)

artifact_paths <- c(
  fit = fit_path, stage1 = stage1_path, stage2 = stage2_path,
  stage3a = stage3a_path, holdout = holdout_path, tier2_rows = tier2_rows_path,
  predictive_metrics = predictive_metrics_path, predictive_report = predictive_path,
  predictive_manifest = predictive_manifest_path
)
artifact_rows <- lapply(names(artifact_paths), function(role) {
  path <- unname(artifact_paths[[role]])
  if (is.na(path) || !file.exists(path)) return(data.frame(role = role, path = path, sha256 = NA_character_, bytes = NA_real_))
  data.frame(role = role, path = path, sha256 = digest::digest(file = path, algo = "sha256"),
             bytes = as.numeric(file.info(path)$size), stringsAsFactors = FALSE)
})
manifest <- do.call(rbind, artifact_rows)
manifest$fit_job <- args$fit_job
manifest$fit_commit <- args$fit_commit
manifest$observation_sha256 <- "784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac"
utils::write.csv(manifest, paths[["manifest"]], row.names = FALSE, na = "")
cat("Wrote C-1 effect assessment: ", paths[["report"]], "\n", sep = "")
cat("C-1 fit SHA-256: ", fit_sha, "\n", sep = "")
