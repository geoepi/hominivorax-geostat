repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)

cfg <- joint_model_defaults()
cfg$reporting_censoring$cutoff_epiyear <- 2025L
cfg$reporting_censoring$cutoff_epiweek <- 32L
tier2 <- data.frame(
  .row_id = paste0("b", 1:4), poly_id = c(1L, 1L, 2L, 2L),
  admin_u = c("A", "A", "B", "B"), epiyear = c(2025L, 2025L, 2025L, 2025L),
  epiweek = c(31L, 32L, 31L, 32L), time_index = 1:4, count = c(1, 0, 1, 1)
)
tier1 <- data.frame(
  .row_id = paste0("t", 1:4), source_obs_id = 1:4, point_id = 1:4,
  admin_u = c("A", "A", "B", "B"), epiyear = rep(2025L, 4), epiweek = c(31L, 32L, 31L, 32L),
  time_index = 1:4, Yi = c(1, 1, 1, 1)
)
result <- apply_reporting_censoring(tier1, tier2, cfg)
stopifnot(
  identical(result$metadata$affected_admin_units, "A"),
  result$tier1$is_censored[2], !result$tier1$is_censored[4],
  is.na(result$tier2$response_censored[2]),
  identical(result$tier2$response_observed, as.numeric(tier2$count))
)

holdout_input <- result$tier1
holdout_input$response_censored <- c(1, 1, 1, 1)
holdout_input$is_censored <- FALSE
a <- select_response_holdouts(holdout_input, "tier1", TRUE, 0.5, 123L)
b <- select_response_holdouts(holdout_input[4:1, , drop = FALSE], "tier1", TRUE, 0.5, 123L)
stopifnot(identical(sort(a$metadata$selected_ids), sort(b$metadata$selected_ids)))

zero <- holdout_input
zero$response_training <- c(0, 1, 0, 1)
zero_result <- apply_zero_count_policy(zero, "exclude")
retain_result <- apply_zero_count_policy(zero, "retain")
stopifnot(sum(is.na(zero_result$data$response_training)) == 2L, sum(zero_result$data$response_training == 0, na.rm = TRUE) == 0L)
stopifnot(sum(retain_result$data$response_training == 0, na.rm = TRUE) == 2L)

cat("Joint-model response regression tests passed\n")
