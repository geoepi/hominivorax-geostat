repo_root <- normalizePath(".", mustWork = TRUE)
invisible(parse(file.path(repo_root, "R", "c1_predictive_qualification.R")))
invisible(parse(file.path(repo_root, "scripts", "run_joint_inla_validation.R")))
source(file.path(repo_root, "R", "joint_inla_validate.R"))
source(file.path(repo_root, "R", "c1_predictive_qualification.R"))

positive_only <- data.frame(response_observed = rep(1, 5), fitted_mean = c(.1, .25, .5, .75, .9))
binary <- c1_predictive_tier1_binary_metrics(positive_only)
stopifnot(binary$status == "NOT_ESTIMABLE", binary$negatives == 0L,
          all(binary$metrics$status[binary$metrics$metric %in% c("auc", "brier", "log_loss", "calibration_intercept", "calibration_slope")] == "NOT_ESTIMABLE"))

window_ok <- c1_predictive_check_analysis_window(data.frame(source_epiyear = c(2022L, 2026L), source_epiweek = c(1L, 44L)))
window_late <- c1_predictive_check_analysis_window(data.frame(source_epiyear = 2026L, source_epiweek = 45L))
stopifnot(window_ok$pass, !window_late$pass)

grouped <- data.frame(admin = c(rep("A", 30), rep("B", 2)))
observed <- c(rep(2, 30), 1, 3)
predicted <- c(rep(2, 30), 1, 2)
summary <- c1_predictive_group_metrics(grouped, "admin", observed, predicted, min_n = 30L)
stopifnot(nrow(summary) == 2L, summary$n[summary$level == "A"] == 30L,
          summary$status[summary$level == "A"] == "DESCRIPTIVE",
          is.finite(summary$mae[summary$level == "A"]),
          summary$n[summary$level == "B"] == 2L,
          summary$status[summary$level == "B"] == "LOW_SUPPORT",
          is.na(summary$mae[summary$level == "B"]))

unaligned <- data.frame(admin = c("A", "A"))
alignment_failed <- try(c1_predictive_group_metrics(unaligned, "admin", 1:3, 1:3), silent = TRUE)
stopifnot(inherits(alignment_failed, "try-error"))

stopifnot(grepl("must not be assigned confirmed-absence", paste(readLines(file.path(repo_root, "docs", "validation", "configuration-c1-predictive-qualification-protocol-2026-11-23.md")), collapse = " "), fixed = TRUE))
