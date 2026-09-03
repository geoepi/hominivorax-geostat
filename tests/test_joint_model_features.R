repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_model.R"))
load_joint_model(repo_root)

spec <- fit_quantile_feature(c(0, 0, 1, 2, 3, NA), bins = 5L)
stopifnot(spec$requested_bins == 5L, spec$effective_bins < 5L, length(spec$breaks) == spec$effective_bins + 1L)
values <- apply_quantile_feature(c(0, 1, 3, NA), spec)
stopifnot(identical(values$q[4], NA_integer_), all(is.finite(values$mid[1:3])))

cfg <- joint_model_defaults()
tier2 <- data.frame(cattle = c(0, 1, 1, 2), pigs = c(1, 2, 3, 4), sheep = 1:4, goats = 2:5, horses = 3:6)
prediction <- data.frame(cattle = c(0, 3), pigs = c(1, 5), sheep = c(1, 5), goats = c(2, 6), horses = c(3, 7))
features <- add_livestock_rw2_features(tier2, prediction, cfg)
stopifnot(all(c("cattle_q", "cattle_mid", "cattle_mid_log1p") %in% names(features$tier2)))
stopifnot(identical(features$tier2$cattle_q[1], 1L), features$prediction_grid$cattle_q[2] == features$metadata$specifications$cattle$effective_bins)
stopifnot(features$metadata$specifications$cattle$requested_bins == 22L)

cat("Joint-model feature regression tests passed\n")
