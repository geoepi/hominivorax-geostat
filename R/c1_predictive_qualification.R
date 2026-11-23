# Configuration C-1 predictive qualification summaries and figures.
# This layer consumes existing fitted holdout rows and existing Stage 2
# presence-background support. It never fits, labels availability rows as
# absences, or turns marginal mean intervals into observation intervals.

c1_predictive_group_metrics <- function(data, group, observed, predicted, min_n = 30L) {
  if (!group %in% names(data)) return(data.frame(
    group = group, level = character(), n = integer(), observed_mean = numeric(), predicted_mean = numeric(),
    mae = numeric(), rmse = numeric(), mean_bias = numeric(), pearson = numeric(), spearman = numeric(),
    calibration_ratio = numeric(), status = character(), details = character(), stringsAsFactors = FALSE
  ))
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  if (length(observed) != nrow(data) || length(predicted) != nrow(data)) stop("Grouped predictive metrics are not aligned to rows.")
  key <- as.character(data[[group]])
  key[is.na(key) | !nzchar(key)] <- "<missing>"
  levels <- sort(unique(key))
  rows <- lapply(levels, function(level) {
    use <- key == level & is.finite(observed) & is.finite(predicted)
    y <- observed[use]
    p <- predicted[use]
    supported <- length(y) >= as.integer(min_n)
    corr <- function(method) if (supported && length(unique(y)) > 1L && length(unique(p)) > 1L) {
      suppressWarnings(stats::cor(y, p, method = method))
    } else NA_real_
    data.frame(
      group = group, level = level, n = length(y), observed_mean = if (length(y)) mean(y) else NA_real_,
      predicted_mean = if (length(p)) mean(p) else NA_real_,
      mae = if (supported) mean(abs(y - p)) else NA_real_,
      rmse = if (supported) sqrt(mean((y - p)^2)) else NA_real_,
      mean_bias = if (supported) mean(p - y) else NA_real_,
      pearson = corr("pearson"), spearman = corr("spearman"),
      calibration_ratio = if (supported && mean(p) != 0) mean(y) / mean(p) else NA_real_,
      status = if (supported) "DESCRIPTIVE" else "LOW_SUPPORT",
      details = if (supported) "Descriptive subgroup summaries; no performance cutoff is applied." else
        paste0("n below the preregistered subgroup display threshold of ", as.integer(min_n), "; metrics suppressed."),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

c1_predictive_tier1_binary_metrics <- function(holdout) {
  result <- joint_inla_validate_tier1(holdout)
  unavailable <- c("auc", "brier", "log_loss", "calibration_intercept", "calibration_slope")
  if (result$negatives == 0L) {
    selected <- result$metrics$metric %in% unavailable
    result$metrics$status[selected] <- "NOT_ESTIMABLE"
    result$metrics$details[selected] <- paste0(
      "Positive-only Tier 1 holdout (n_positive=", result$positives,
      "; n_negative=0); terrestrial availability rows are not confirmed absences."
    )
    result$status <- "NOT_ESTIMABLE"
  }
  result
}

c1_predictive_check_analysis_window <- function(data, year = "source_epiyear", week = "source_epiweek",
                                                start_year = 2022L, start_week = 1L,
                                                end_year = 2026L, end_week = 44L) {
  if (!all(c(year, week) %in% names(data))) {
    return(list(pass = FALSE, observed = "missing year/week fields", expected = "2022-W01 through 2026-W44",
                details = "Holdout rows must retain source ISO year and week fields."))
  }
  y <- suppressWarnings(as.integer(data[[year]]))
  w <- suppressWarnings(as.integer(data[[week]]))
  valid <- !is.na(y) & !is.na(w) & w >= 1L & w <= 53L &
    (y > start_year | (y == start_year & w >= start_week)) &
    (y < end_year | (y == end_year & w <= end_week))
  pass <- nrow(data) > 0L && length(valid) == nrow(data) && all(valid)
  complete <- which(!is.na(y) & !is.na(w))
  observed <- if (length(complete)) {
    order_key <- y[complete] * 100L + w[complete]
    first <- complete[[which.min(order_key)]]
    last <- complete[[which.max(order_key)]]
    paste0("min=", y[[first]], "-W", sprintf("%02d", w[[first]]),
      "; max=", y[[last]], "-W", sprintf("%02d", w[[last]]), "; invalid_or_outside=", sum(!valid))
  } else "no valid ISO weeks"
  list(pass = pass, observed = observed, expected = "2022-W01 through 2026-W44",
       details = "Both Tier 1 and Tier 2 holdout rows must remain within the approved C-1 analysis window.")
}

c1_predictive_admin_percentiles <- function(percentiles, tier1_holdout, min_n = 30L) {
  if (!nrow(percentiles) || !"source_admin_u" %in% names(tier1_holdout)) return(data.frame())
  admin <- tier1_holdout[c("output_id", "source_admin_u")]
  x <- merge(percentiles, admin, by = "output_id", all.x = TRUE, sort = FALSE)
  key <- as.character(x$source_admin_u)
  key[is.na(key) | !nzchar(key)] <- "<missing>"
  rows <- lapply(sort(unique(key)), function(level) {
    use <- key == level & is.finite(x$weighted_percentile) & is.finite(x$unweighted_percentile)
    n <- sum(use)
    data.frame(
      admin = level, n = n,
      mean_area_weighted_percentile = if (n) mean(x$weighted_percentile[use]) else NA_real_,
      median_area_weighted_percentile = if (n) stats::median(x$weighted_percentile[use]) else NA_real_,
      mean_unweighted_percentile = if (n) mean(x$unweighted_percentile[use]) else NA_real_,
      status = if (n >= min_n) "DESCRIPTIVE" else "LOW_SUPPORT",
      details = if (n >= min_n) "Descriptive same-week occurrence ranks by administrative unit." else
        paste0("n below the preregistered subgroup display threshold of ", min_n, "."),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

c1_predictive_sha256 <- function(path) {
  result <- tryCatch(system2("sha256sum", shQuote(path), stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(result)) return(NA_character_)
  sub("[[:space:]].*$", "", result[[1L]])
}

c1_predictive_write_artifact_manifest <- function(output_dir, source_paths, manifest_path) {
  outputs <- sort(list.files(output_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE))
  outputs <- outputs[outputs != manifest_path & !dir.exists(outputs)]
  output_rows <- lapply(outputs, function(path) {
    info <- file.info(path)
    data.frame(kind = "OUTPUT", role = NA_character_, path = normalizePath(path, mustWork = TRUE),
      sha256 = c1_predictive_sha256(path), bytes = as.numeric(info$size),
      modified_utc = format(info$mtime, tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE)
  })
  input_rows <- lapply(names(source_paths), function(role) {
    path <- unname(source_paths[[role]])
    info <- file.info(path)
    data.frame(kind = "INPUT", role = role, path = normalizePath(path, mustWork = TRUE),
      sha256 = c1_predictive_sha256(path), bytes = as.numeric(info$size),
      modified_utc = format(info$mtime, tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE)
  })
  manifest <- do.call(rbind, c(input_rows, output_rows))
  if (anyNA(manifest$sha256) || any(!grepl("^[0-9a-f]{64}$", manifest$sha256))) {
    stop("SHA-256 could not be recorded for every qualification input and output.")
  }
  utils::write.csv(manifest, manifest_path, row.names = FALSE, na = "")
  manifest
}

c1_predictive_write_outputs <- function(output_dir, run_id, holdout, tier1_presence, tier2_holdout,
                                        tier2_expected_count, posterior_support, audit,
                                        protocol_path, source_paths, source_fit_job,
                                        repository_head,
                                        fit_warning = c(
                                          "***[0] thread_num[0] warning *** iterative process seems to diverge, 'vb.correction' is aborted",
                                          "*** Please (re-)consider your model, priors, confounding, etc.",
                                          "***[0] thread_num[0] warning *** iterative process seems to diverge, 'vb.correction' is aborted",
                                          "*** Please (re-)consider your model, priors, confounding, etc."
                                        )) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(
    tier1_binary = file.path(output_dir, paste0("tier1_binary_metrics_", run_id, ".csv")),
    tier1_admin = file.path(output_dir, paste0("tier1_same_week_percentiles_by_admin_", run_id, ".csv")),
    tier2_rows = file.path(output_dir, paste0("tier2_holdout_diagnostics_", run_id, ".csv")),
    tier2_admin = file.path(output_dir, paste0("tier2_spatial_admin_metrics_", run_id, ".csv")),
    tier2_year = file.path(output_dir, paste0("tier2_temporal_year_metrics_", run_id, ".csv")),
    tier2_week = file.path(output_dir, paste0("tier2_temporal_week_metrics_", run_id, ".csv")),
    decision = file.path(output_dir, paste0("c1_predictive_qualification_decision_", run_id, ".csv")),
    provenance = file.path(output_dir, paste0("c1_predictive_qualification_provenance_", run_id, ".csv")),
    report = file.path(output_dir, paste0("c1_predictive_qualification_report_", run_id, ".md")),
    artifact_manifest = file.path(output_dir, paste0("c1_predictive_artifact_manifest_", run_id, ".csv")),
    figure_tier1 = file.path(output_dir, paste0("tier1_presence_background_scores_", run_id, ".png")),
    figure_count = file.path(output_dir, paste0("tier2_observed_vs_expected_", run_id, ".png")),
    figure_spatial = file.path(output_dir, paste0("tier2_spatial_residuals_", run_id, ".png")),
    figure_temporal = file.path(output_dir, paste0("tier2_temporal_means_", run_id, ".png"))
  )
  if (any(file.exists(paths))) stop("Refusing to overwrite existing C-1 qualification outputs.")

  tier1_holdout <- holdout[holdout$tier == "tier1", , drop = FALSE]
  tier1_binary <- c1_predictive_tier1_binary_metrics(tier1_holdout)
  utils::write.csv(tier1_binary$metrics, paths[["tier1_binary"]], row.names = FALSE, na = "")
  t1_admin <- c1_predictive_admin_percentiles(tier1_presence$percentiles, tier1_holdout, min_n = 30L)
  utils::write.csv(t1_admin, paths[["tier1_admin"]], row.names = FALSE, na = "")

  if (length(tier2_expected_count) != nrow(tier2_holdout)) stop("Tier 2 expected counts do not align with the saved holdout.")
  observed <- suppressWarnings(as.numeric(tier2_holdout$response_observed))
  expected <- suppressWarnings(as.numeric(tier2_expected_count))
  censored <- if ("source_is_censored" %in% names(tier2_holdout)) tier2_holdout$source_is_censored %in% TRUE else rep(FALSE, nrow(tier2_holdout))
  eligible <- is.finite(observed) & observed >= 0 & observed == floor(observed) & is.finite(expected) & !censored
  tier2_rows <- tier2_holdout
  tier2_rows$expected_count <- expected
  tier2_rows$residual_observed_minus_expected <- observed - expected
  tier2_rows$bias_expected_minus_observed <- expected - observed
  tier2_rows$absolute_error <- abs(observed - expected)
  tier2_rows$metric_eligible <- eligible
  tier2_rows$exclusion_reason <- ifelse(!is.finite(observed), "nonfinite_response",
    ifelse(!is.finite(expected), "nonfinite_expected_count",
      ifelse(censored, "reporting_censored", ifelse(observed < 0 | observed != floor(observed), "invalid_count", ""))))
  utils::write.csv(tier2_rows, paths[["tier2_rows"]], row.names = FALSE, na = "")
  tier2_zero_count_rows <- sum(observed == 0, na.rm = TRUE)

  admin_col <- if ("source_admin_u" %in% names(tier2_rows)) "source_admin_u" else "source_admin_f"
  group_observed <- observed
  group_expected <- expected
  group_observed[!eligible] <- NA_real_
  group_expected[!eligible] <- NA_real_
  admin_metrics <- c1_predictive_group_metrics(tier2_rows, admin_col, group_observed, group_expected, 30L)
  utils::write.csv(admin_metrics, paths[["tier2_admin"]], row.names = FALSE, na = "")
  year <- suppressWarnings(as.integer(tier2_rows$source_epiyear))
  week <- suppressWarnings(as.integer(tier2_rows$source_epiweek))
  tier2_rows$epi_year_group <- ifelse(is.na(year), NA_character_, as.character(year))
  tier2_rows$epi_week_group <- ifelse(is.na(year) | is.na(week), NA_character_, sprintf("%04d-W%02d", year, week))
  year_metrics <- c1_predictive_group_metrics(tier2_rows, "epi_year_group", group_observed, group_expected, 30L)
  week_metrics <- c1_predictive_group_metrics(tier2_rows, "epi_week_group", group_observed, group_expected, 30L)
  utils::write.csv(year_metrics, paths[["tier2_year"]], row.names = FALSE, na = "")
  utils::write.csv(week_metrics, paths[["tier2_week"]], row.names = FALSE, na = "")

  # All figures are diagnostics on existing held-out rows or existing
  # integration support. No background row is assigned an absence label.
  reference <- tier1_presence
  grDevices::png(paths[["figure_tier1"]], width = 1200, height = 850, res = 130)
  if (nrow(reference$percentiles)) {
    graphics::plot(reference$percentiles$weighted_percentile, pch = 16, cex = 0.5,
      xlab = "Held-out occurrence (row order)", ylab = "Same-week area-weighted availability percentile",
      main = "Tier 1 held-out detections vs terrestrial availability")
    graphics::abline(h = c(0.5, 0.75, 0.9), lty = 3, col = "grey55")
    graphics::mtext("Availability support has unknown biological status; it is not a confirmed-absence sample.", side = 3, line = 0.2, cex = 0.8)
  } else {
    graphics::plot.new(); graphics::title("Tier 1 same-week availability comparison unavailable")
  }
  grDevices::dev.off()

  grDevices::png(paths[["figure_count"]], width = 1000, height = 850, res = 130)
  count_ok <- eligible
  if (any(count_ok)) {
    graphics::plot(log1p(expected[count_ok]), log1p(observed[count_ok]), pch = 16, cex = 0.65,
      xlab = "log(1 + expected held-out count)", ylab = "log(1 + observed held-out count)",
      main = "Tier 2 held-out counts (positive-count sampling design)")
    graphics::abline(0, 1, lty = 2, col = "firebrick")
    graphics::mtext(paste0("Eligible rows: ", sum(count_ok), "; no numeric acceptance cutoff."), side = 3, line = 0.2, cex = 0.8)
  } else {
    graphics::plot.new(); graphics::title("Tier 2 expected count comparison unavailable")
  }
  grDevices::dev.off()

  grDevices::png(paths[["figure_spatial"]], width = 1100, height = 900, res = 130)
  if (all(c("source_x", "source_y") %in% names(tier2_rows)) && any(count_ok & is.finite(tier2_rows$source_x) & is.finite(tier2_rows$source_y))) {
    spatial_ok <- count_ok & is.finite(tier2_rows$source_x) & is.finite(tier2_rows$source_y)
    residual <- expected[spatial_ok] - observed[spatial_ok]
    palette <- grDevices::colorRampPalette(c("#2166ac", "#f7f7f7", "#b2182b"))(101L)
    span <- max(abs(residual), na.rm = TRUE)
    color_index <- if (span > 0) pmax(1L, pmin(101L, as.integer(round((residual / span + 1) * 50) + 1L))) else rep(51L, length(residual))
    graphics::plot(tier2_rows$source_x[spatial_ok], tier2_rows$source_y[spatial_ok], pch = 16, cex = 0.7,
      col = grDevices::adjustcolor(palette[color_index], alpha.f = 0.65), xlab = "x (model coordinate units)", ylab = "y (model coordinate units)",
      main = "Tier 2 held-out count residuals at observation locations")
    graphics::mtext("Blue: underprediction; red: overprediction. This is not a prediction surface.", side = 3, line = 0.2, cex = 0.8)
  } else {
    graphics::plot.new(); graphics::title("Spatial residual display unavailable: coordinates absent")
  }
  grDevices::dev.off()

  grDevices::png(paths[["figure_temporal"]], width = 1100, height = 850, res = 130)
  year_ok <- year_metrics$status == "DESCRIPTIVE" & is.finite(year_metrics$observed_mean) & is.finite(year_metrics$predicted_mean)
  if (any(year_ok)) {
    xx <- suppressWarnings(as.numeric(year_metrics$level[year_ok]))
    ord <- order(xx)
    graphics::plot(xx[ord], year_metrics$observed_mean[year_ok][ord], type = "b", pch = 16,
      xlab = "ISO year", ylab = "Mean count", main = "Tier 2 observed and expected counts by ISO year")
    graphics::lines(xx[ord], year_metrics$predicted_mean[year_ok][ord], type = "b", pch = 17, col = "firebrick")
    graphics::legend("topleft", legend = c("Observed", "Expected"), col = c("black", "firebrick"), lty = 1, pch = c(16, 17), bty = "n")
  } else {
    graphics::plot.new(); graphics::title("Temporal grouped display unavailable")
  }
  grDevices::dev.off()

  blocking_failure <- any(audit$blocking %in% TRUE & audit$status == "FAIL")
  metrics_present <- any(eligible) && all(is.finite(observed[eligible])) && all(is.finite(expected[eligible]))
  decision <- if (blocking_failure) "C1_PREDICTIVE_VALIDATION_NOT_SUPPORTED" else if (!metrics_present) "C1_PREDICTIVE_VALIDATION_INCOMPLETE" else "C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS"
  explanation <- if (blocking_failure) "One or more blocking provenance/alignment gates failed." else if (!metrics_present) {
    "No eligible finite Tier 2 observed/predicted pairs were available."
  } else {
    "Integrity and metric-computation gates passed. Tier 1 discrimination/calibration against confirmed absences is not estimable from a positive-only holdout; observation-level negative-binomial predictive intervals were not produced; and no numerical predictive-performance cutoffs are specified by the repository standards. Results are descriptive and do not establish scientific model qualification."
  }
  utils::write.csv(data.frame(configuration = "C-1", decision = decision, explanation = explanation,
    tier1_holdout_rows = nrow(tier1_holdout), tier1_positive_rows = sum(as.numeric(tier1_holdout$response_observed) == 1, na.rm = TRUE),
    tier1_negative_rows = sum(as.numeric(tier1_holdout$response_observed) == 0, na.rm = TRUE),
    tier2_holdout_rows = nrow(tier2_holdout), tier2_metric_eligible_rows = sum(eligible),
    tier2_censored_exclusions = sum(censored), subgroup_minimum_n = 30L,
    predictive_intervals = "NOT_PRODUCED; conditional-mean marginals are not observation-level predictive intervals",
    posterior_support_method = posterior_support$method,
    stringsAsFactors = FALSE), paths[["decision"]], row.names = FALSE, na = "")

  protocol_hash <- if (file.exists(protocol_path)) {
    x <- tryCatch(system2("sha256sum", protocol_path, stdout = TRUE, stderr = FALSE), error = function(e) character())
    if (length(x)) sub("[[:space:]].*$", "", x[[1L]]) else NA_character_
  } else NA_character_
  provenance <- data.frame(
    item = c("configuration", "run_id", "source_fit_job", "repository_head", "protocol_path", "protocol_sha256", "posterior_support_method", "predictive_interval_status", "fit_warning_class", "fit_warning_occurrences", "fit_warning_text", "decision"),
    value = c("C-1", run_id, source_fit_job, repository_head, normalizePath(protocol_path, mustWork = FALSE), protocol_hash,
      posterior_support$method, "NOT_PRODUCED; no observation-level predictive draws were created", "INLA_EXPERIMENTAL_VB_WARNING", "2 occurrences recorded by the completed fit job", paste(fit_warning, collapse = "\n"), decision),
    stringsAsFactors = FALSE
  )
  utils::write.csv(provenance, paths[["provenance"]], row.names = FALSE, na = "")

  mean_if <- function(x) if (length(x) && all(is.finite(x))) mean(x) else NA_real_
  tier2_metrics <- c(
    eligible_rows = sum(eligible), mean_observed = mean_if(observed[eligible]),
    mean_expected = mean_if(expected[eligible]), MAE = mean_if(abs(observed[eligible] - expected[eligible])),
    RMSE = if (any(eligible)) sqrt(mean((observed[eligible] - expected[eligible])^2)) else NA_real_,
    Pearson = if (sum(eligible) > 1L && length(unique(observed[eligible])) > 1L && length(unique(expected[eligible])) > 1L) suppressWarnings(stats::cor(observed[eligible], expected[eligible])) else NA_real_,
    Spearman = if (sum(eligible) > 1L && length(unique(observed[eligible])) > 1L && length(unique(expected[eligible])) > 1L) suppressWarnings(stats::cor(observed[eligible], expected[eligible], method = "spearman")) else NA_real_,
    mean_prediction_bias = mean_if(expected[eligible] - observed[eligible]),
    observed_to_expected_mean_ratio = if (any(eligible) && mean(expected[eligible]) != 0) mean(observed[eligible]) / mean(expected[eligible]) else NA_real_,
    calibration_intercept = if (sum(eligible) >= 3L && length(unique(expected[eligible])) > 1L) unname(stats::coef(stats::lm(observed[eligible] ~ expected[eligible]))[[1L]]) else NA_real_,
    calibration_slope = if (sum(eligible) >= 3L && length(unique(expected[eligible])) > 1L) unname(stats::coef(stats::lm(observed[eligible] ~ expected[eligible]))[[2L]]) else NA_real_
  )
  format_metric <- function(x) if (is.finite(x)) format(x, digits = 7, scientific = FALSE) else "NOT_ESTIMABLE"
  tier1_metrics <- c(
    area_weighted_PB_AUC = tier1_presence$weighted_auc,
    unweighted_PB_AUC = tier1_presence$unweighted_auc,
    area_weighted_Continuous_Boyce_Index = tier1_presence$weighted_cbi,
    unweighted_Continuous_Boyce_Index = tier1_presence$unweighted_cbi,
    mean_same_week_area_weighted_percentile = mean_if(tier1_presence$percentiles$weighted_percentile),
    mean_same_week_unweighted_percentile = mean_if(tier1_presence$percentiles$unweighted_percentile)
  )
  metric_table <- c(
    "| Tier | Metric | Value |",
    "|---|---|---:|",
    vapply(names(tier1_metrics), function(name) paste0("| Tier 1 | ", name, " | ", format_metric(tier1_metrics[[name]]), " |"), character(1L)),
    vapply(c("auc", "brier", "log_loss", "calibration_intercept", "calibration_slope"), function(name) {
      value <- tier1_binary$metrics$value[tier1_binary$metrics$metric == name]
      paste0("| Tier 1 binary | ", name, " | ", if (length(value) == 1L && is.finite(value)) format_metric(value) else "NOT_ESTIMABLE", " |")
    }, character(1L)),
    vapply(names(tier2_metrics), function(name) paste0("| Tier 2 | ", name, " | ", format_metric(tier2_metrics[[name]]), " |"), character(1L))
  )
  report <- c(
    "# Configuration C-1 predictive validation",
    "",
    paste0("Run: `", run_id, "`"),
    paste0("Decision: **", decision, "**"),
    "",
    "Analysis window: 2022-W01 through 2026-W44 (final date 2026-11-01).",
    "",
    "## Pre-registered interpretation",
    "",
    "This is a predictive validation summary, not scientific model qualification. Repository validation standards define the metric families but provide no numeric performance cutoffs; therefore all performance metrics are descriptive, and no acceptance threshold was selected after seeing results. Technical acceptance requires exact saved-holdout alignment, finite scale-valid predictions, valid source outcomes, and no failed blocking audit checks. Subgroup error summaries are shown only for n >= 30; smaller groups retain counts and are marked LOW_SUPPORT.",
    "",
    "## Scope and sampling design",
    "",
    paste0("Tier 1 rows: ", nrow(tier1_holdout), "; positives: ", sum(as.numeric(tier1_holdout$response_observed) == 1, na.rm = TRUE), "; negatives: ", sum(as.numeric(tier1_holdout$response_observed) == 0, na.rm = TRUE), "."),
    "The Tier 1 holdout consists of withheld detections. Terrestrial quadrature rows support area-weighted and unweighted presence-background AUC, Continuous Boyce Index, and same-week percentile comparisons; their biological status is unknown and they are not treated as absences. Binary ROC-AUC, Brier score, log loss, sensitivity/specificity as a balanced classification assessment, and logistic calibration are not estimable from this positive-only sample.",
    "",
    paste0("Tier 2 rows: ", nrow(tier2_holdout), "; eligible finite uncensored rows: ", sum(eligible), "; observed zero-count rows: ", tier2_zero_count_rows, "; censored exclusions: ", sum(censored), "."),
    "Tier 2 count point metrics use expected count = terrestrial-area exposure × fitted intensity. The established selector holds out positive counts; the report records the observed zero-count total and does not interpret quadrature/background rows as count absences.",
    "",
    "## Predictive uncertainty and fit warning",
    "",
    paste0("Saved posterior support reported by the existing audit: `", posterior_support$method, "`. Observation-level negative-binomial predictive intervals were not produced by this validation run. Marginal uncertainty summaries for a fitted mean are not substituted for observation-level predictive intervals."),
    "",
    "Retained fit warning class: `INLA_EXPERIMENTAL_VB_WARNING`. It appeared twice in the completed fit log. Exact text:",
    "```text",
    fit_warning,
    "```",
    "Per the approved policy, this warning is recorded and is not treated as a fit failure or followed by another fit.",
    "",
    "## Descriptive results",
    "",
    metric_table,
    "",
    "## Artifacts",
    "",
    "Core Tier 1 presence-background metrics, Boyce curve, same-week percentiles, weekly summaries, Tier 2 point metrics, calibration, interval-unavailable table, full audit, and run metadata are recorded beside this report. Additional C-1 files include positive-only Tier 1 binary metric status, Tier 2 row residuals and exclusions, administrative/year/week grouped summaries, and four diagnostic figures. The spatial plot contains held-out residual points only; no prediction surface was generated.",
    "",
    paste0("Decision rationale: ", explanation),
    "",
    "No Stage 3B refit, geographic prediction, or production artifact replacement was performed."
  )
  writeLines(report, paths[["report"]], useBytes = TRUE)
  list(paths = paths, decision = decision, explanation = explanation, protocol_sha256 = protocol_hash,
       tier1_binary = tier1_binary, eligible_tier2 = sum(eligible), provenance_path = paths[["provenance"]])
}
