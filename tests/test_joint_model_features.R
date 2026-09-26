repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)

transformation_spec <- list(static = setNames(lapply(c("cattle", "pigs", "sheep", "goats", "horses"), function(x) c(impute = 0, center = 0, scale = 1)), c("cattle", "pigs", "sheep", "goats", "horses")))
spec <- fit_quantile_feature(c(0, 0, 1, 2, 3, NA), bins = 5L, imputation_value = 0)
stopifnot(spec$requested_bins == 5L, spec$effective_bins <= 5L, length(spec$breaks) == 6L, spec$method == "historical_rank_quantile", spec$rank_ties_method == "average")
values <- apply_quantile_feature(c(0, 1, 3, NA), spec)
stopifnot(is.finite(values$q[4]), values$q[4] >= 1L, values$q[4] <= length(spec$midpoints), all(is.finite(values$mid)), all(is.finite(values$mid_log1p)))

cfg <- joint_model_defaults()
tier2 <- data.frame(cattle = c(0, 1, 1, 2), pigs = c(1, 2, 3, 4), sheep = 1:4, goats = 2:5, horses = 3:6)
prediction <- data.frame(cattle = c(0, 3), pigs = c(1, 5), sheep = c(1, 5), goats = c(2, 6), horses = c(3, 7))
features <- add_livestock_rw2_features(tier2, prediction, cfg, transformation_spec)
stopifnot(all(c("cattle_q", "cattle_mid", "cattle_mid_log1p") %in% names(features$tier2)))
stopifnot(identical(features$tier2$cattle_q, historical_rank_quantile(tier2$cattle, cfg$livestock_rw2$bins)), features$prediction_grid$cattle_q[2] <= length(features$metadata$specifications$cattle$midpoints))
stopifnot(features$metadata$specifications$cattle$requested_bins == 22L, features$metadata$specifications$cattle$imputation_value == 0, features$metadata$specifications$cattle$quantile_type == 7L)
stopifnot(all(is.finite(unlist(features$prediction_grid[paste0("cattle", c("_q", "_mid", "_mid_log1p"))]))))
stopifnot(identical(features$metadata$specifications$cattle$method, "historical_rank_quantile"))

tier2_missing <- tier2
tier2_missing$cattle[2] <- NA_real_
prediction_missing <- prediction
prediction_missing$cattle[2] <- NA_real_
missing_features <- add_livestock_rw2_features(tier2_missing, prediction_missing, cfg, transformation_spec)
stopifnot(is.na(missing_features$tier2$cattle[2]), is.na(missing_features$prediction_grid$cattle[2]))
stopifnot(all(is.finite(missing_features$tier2$cattle_q)), all(is.finite(missing_features$tier2$cattle_mid_log1p)))
stopifnot(all(is.finite(missing_features$prediction_grid$cattle_q)), all(is.finite(missing_features$prediction_grid$cattle_mid_log1p)))

prediction_reordered <- prediction[c(2, 1), , drop = FALSE]
reordered_features <- add_livestock_rw2_features(tier2, prediction_reordered, cfg, transformation_spec)
stopifnot(identical(features$prediction_grid$cattle_q[order(prediction$cattle)], reordered_features$prediction_grid$cattle_q[order(prediction_reordered$cattle)]))

cat("Joint-model feature regression tests passed\n")
