repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla.R"))
load_joint_inla(repo_root)

if (!requireNamespace("INLA", quietly = TRUE)) {
  cat("Stage 3A assembly tests skipped: INLA is unavailable\n")
} else {
  cfg <- read_joint_inla_config(file.path(repo_root, "config", "joint_inla.example.yml"), repo_root)
  validate_joint_inla_config(cfg, require_inputs = FALSE)
  stopifnot(identical(cfg$inputs$joint_model_inputs, file.path(repo_root, "outputs", "joint_model", "joint_model_inputs.rds")))
  stopifnot(identical(cfg$model$tier1$family, "binomial"), identical(cfg$model$tier2$family, "nbinomial"))
  stopifnot(identical(cfg$shared_field$beta_prior_sd, 0.2))

  make_common <- function(n, x, y, group) {
    data.frame(x = x, y = y, quarter_index = group, timestep = seq_len(n), admin_f = rep(1L, n), admin_u = rep("A", n),
      northing_km_s = seq_len(n) / n, road_dens_s = seq_len(n) / n, night_illum_s = seq_len(n) / n,
      mintemp_s = seq_len(n) / n, soilmoist_s = seq_len(n) / n, leafarea_s = seq_len(n) / n, rhum_s = seq_len(n) / n,
      cattle_log1p = seq_len(n) / n, horses_log1p = seq_len(n) / n, pigs_log1p = seq_len(n) / n,
      goats_log1p = seq_len(n) / n, sheep_log1p = seq_len(n) / n,
      cattle_q = rep(1:2, length.out = n), cattle_mid_log1p = seq_len(n) / n,
      cattle = seq_len(n), horses = seq_len(n), pigs = seq_len(n), goats = seq_len(n), sheep = seq_len(n),
      terrestrial_area_km2 = rep(1, n), stringsAsFactors = FALSE)
  }
  tier1 <- make_common(4L, c(0.2, 0.8, 0.2, 0.8), c(0.2, 0.2, 0.8, 0.8), c(1L, 1L, 2L, 2L))
  tier1$response_training <- c(0, 1, 0, 1)
  tier1$admin_u <- c("A", "A", "Unk", "Unk")
  tier2 <- make_common(4L, c(0.2, 0.8, 0.2, 0.8), c(0.2, 0.2, 0.8, 0.8), c(1L, 1L, 2L, 2L))
  tier2$response_training <- c(1, NA, 2, NA)
  prediction <- make_common(2L, c(0.4, 0.6), c(0.4, 0.6), c(1L, 2L))
  mesh <- INLA::inla.mesh.2d(loc = matrix(c(0, 0, 1, 0, 0, 1, 1, 1), ncol = 2, byrow = TRUE), max.edge = c(0.6, 2), cutoff = 0.01)
  inputs <- list(tier1 = tier1, tier2 = tier2, prediction_grid = prediction, mesh = mesh,
    spatial_support = list(linear_unit_to_m = 1), preprocessing_metadata = list(stage = "test"))

  first <- build_joint_inla_from_inputs(inputs, cfg)
  second <- build_joint_inla_from_inputs(inputs, cfg)
  stopifnot(identical(first$family, c("binomial", "nbinomial")), identical(first$family, second$family))
  stopifnot(identical(dim(first$A$tier1), dim(second$A$tier1)), identical(first$A$tier1, second$A$tier1))
  stopifnot(identical(first$effect_mapping, second$effect_mapping), identical(first$build_audit, second$build_audit))
  stopifnot(nrow(first$stacks$joint$data$Y) == 8L, ncol(first$stacks$joint$data$Y) == 2L)
  stopifnot(all(is.na(first$stacks$joint$data$Y[5:8, 1])), all(is.na(first$stacks$joint$data$Y[1:4, 2])))
  stopifnot(grepl("copy", paste(deparse(first$formula), collapse = " "), fixed = TRUE))
  stopifnot(grepl("nbinomial", paste(first$family, collapse = " "), fixed = TRUE))
  stopifnot(identical(first$priors$hyper_copy, list(beta = list(prior = "normal", param = c(0.5, 0.2)))))
  stopifnot(isFALSE(first$provenance$executed_fit), identical(first$provenance$INLA, as.character(utils::packageVersion("INLA"))))
  stopifnot(first$fit_reference$nbinomial_default$available, identical(first$fit_reference$nbinomial_default$hyper$theta$prior, "pc.mgamma"))
  contains_fit_call <- function(expr) {
    if (is.call(expr) && identical(as.character(expr[[1L]]), "inla")) return(TRUE)
    if (is.recursive(expr)) any(vapply(as.list(expr), contains_fit_call, logical(1L))) else FALSE
  }
  parsed_build <- parse(file.path(repo_root, "R", "joint_inla_build.R"))
  stopifnot(!any(vapply(as.list(parsed_build), contains_fit_call, logical(1L))))
  cat("Joint-INLA Stage 3A assembly regression tests passed\n")
}
