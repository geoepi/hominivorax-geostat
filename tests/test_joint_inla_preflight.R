repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_joint_inla_fit.R"))
load_joint_inla_fit(repo_root)

if (!requireNamespace("INLA", quietly = TRUE)) {
  cat("Stage 3B production preflight tests skipped: INLA is unavailable\n")
} else {
  make_production_shaped_build <- function(path, invalid_cattle_bin = FALSE, effect_overrides = list()) {
    n_tier1 <- 8L
    n_tier2 <- 22L
    n <- n_tier1 + n_tier2
    tier1 <- seq_len(n) <= n_tier1
    tier2 <- !tier1
    value <- function(tier, values) {
      result <- rep(NA_real_, n)
      result[tier] <- values
      result
    }

    effects <- data.frame(
      intercept1 = value(tier1, rep(1, n_tier1)),
      intercept2 = value(tier2, rep(1, n_tier2)),
      north = value(tier1, seq_len(n_tier1) / n_tier1),
      road_dens = value(tier1, seq_len(n_tier1) / n_tier1 + 1),
      night_illum = value(tier1, seq_len(n_tier1) / n_tier1 + 2),
      mintemp = value(tier2, seq_len(n_tier2) / n_tier2),
      soilmoist = value(tier2, seq_len(n_tier2) / n_tier2 + 1),
      leafarea = value(tier2, seq_len(n_tier2) / n_tier2 + 2),
      rhum = value(tier2, seq_len(n_tier2) / n_tier2 + 3),
      cattle = value(tier2, seq_len(n_tier2) / n_tier2 + 4),
      horses = value(tier2, seq_len(n_tier2) / n_tier2 + 5),
      pigs = value(tier2, seq_len(n_tier2) / n_tier2 + 6),
      goats = value(tier2, seq_len(n_tier2) / n_tier2 + 7),
      sheep = value(tier2, seq_len(n_tier2) / n_tier2 + 8),
      tier1_field = value(tier1, seq_len(n_tier1)),
      tier1_field.group = value(tier1, seq_len(n_tier1)),
      week_steps = value(tier1, seq_len(n_tier1)),
      admin_f = value(tier1, seq_len(n_tier1)),
      tier2_field = value(tier2, seq_len(n_tier2)),
      tier2_field.group = value(tier2, rep(seq_len(8L), length.out = n_tier2)),
      tier2_copy_field = value(tier2, seq_len(n_tier2)),
      tier2_copy_field.group = value(tier2, rep(seq_len(8L), length.out = n_tier2)),
      tier2_week = value(tier2, seq_len(n_tier2)),
      cattle_q = value(tier2, if (invalid_cattle_bin) c(23, seq_len(21L)) else seq_len(n_tier2)),
      cattle_mid_log1p = value(tier2, seq_len(n_tier2) / n_tier2),
      stringsAsFactors = FALSE
    )
    if (length(effect_overrides)) {
      for (name in names(effect_overrides)) effects[[name]] <- effect_overrides[[name]]
    }

    Y <- matrix(NA_real_, nrow = n, ncol = 2L, dimnames = list(NULL, c("binomial", "nbinomial")))
    Y[tier1, 1L] <- c(0, 1, 0, 1, 0, 1, 0, 1)
    Y[tier2, 2L] <- seq_len(n_tier2)
    e <- c(rep(NA_real_, n_tier1), seq_len(n_tier2) + 10)
    link <- c(rep(1L, n_tier1), rep(2L, n_tier2))
    joint_stack <- INLA::inla.stack(data = list(Y = Y, e = e, link = link),
                                     A = list(diag(n)), effects = list(effects), tag = "joint")

    spde_tier1 <- structure(list(n.spde = 13449L), class = "inla.spde")
    spde_tier2 <- structure(list(n.spde = 13449L), class = "inla.spde")
    pc_rw <- list(prec = list(prior = "pc.prec", param = c(1, 0.01)))
    pc_rw_strong <- list(prec = list(prior = "pc.prec", param = c(0.3, 0.01)))
    pc_rw_cat <- list(prec = list(prior = "pc.prec", param = c(0.5, 0.05)))
    hyper_copy <- list(beta = list(prior = "normal", param = c(0.5, 0.2)))
    formula <- Y ~ -1 + intercept1 + intercept2 +
      f(tier1_field, model = spde_tier1, group = tier1_field.group,
        control.group = list(model = "iid", hyper = pc_rw)) +
      f(week_steps, model = "rw1", constr = TRUE, scale.model = TRUE, hyper = pc_rw) +
      f(admin_f, model = "iid", constr = TRUE, hyper = pc_rw_strong) +
      f(tier2_field, model = spde_tier2, group = tier2_field.group,
        control.group = list(model = "iid", hyper = pc_rw)) +
      f(tier2_copy_field, copy = "tier1_field", group = tier2_copy_field.group,
        fixed = FALSE, hyper = hyper_copy) +
      f(tier2_week, model = "rw1", constr = TRUE, scale.model = TRUE, hyper = pc_rw) +
      f(cattle_q, cattle_mid_log1p, model = "rw2", constr = TRUE, scale.model = TRUE, hyper = pc_rw_cat) +
      north + road_dens + night_illum + mintemp + soilmoist + leafarea + rhum +
      mintemp:soilmoist + mintemp:leafarea + cattle + horses + pigs + goats + sheep

    build <- list(
      spde = list(tier1 = list(n.spde = 13449L), tier2 = list(n.spde = 13449L)),
      stacks = list(joint = joint_stack), formula = formula,
      family = c("binomial", "nbinomial"), priors = list(hyper_copy = hyper_copy),
      fit_reference = list(
        control_mode = list(restart = FALSE, theta = seq_len(10L) / 10),
        nbinomial_default = list(available = TRUE, hyper = list(theta = list(prior = "pc.mgamma", param = 7, initial = 2.30258509299405, fixed = FALSE)))
      ),
      prediction_compatibility = list(
        compatible = TRUE,
        required_columns = c("x", "y", "quarter_index", "northing_km_s", "mintemp_s"),
        nonfinite_counts = c(x = 0L, y = 0L, quarter_index = 0L, northing_km_s = 0L, mintemp_s = 0L)
      ),
      provenance = list(stage = "joint_inla_assembly", executed_fit = FALSE,
                        INLA = as.character(utils::packageVersion("INLA")),
                        source_artifact = "outputs/joint_model/joint_model_inputs.rds"),
      config = list(inputs = list(joint_model_inputs = "outputs/joint_model/joint_model_inputs.rds"))
    )
    saveRDS(build, path)
    build
  }

  build_path <- file.path(tempdir(), "joint_inla_production_shaped_build.rds")
  build <- make_production_shaped_build(build_path)
  result <- joint_inla_preflight_build(joint_inla_fit_read_build(build_path), build_path)
  stopifnot(isTRUE(result$success), result$summary$failures == 0L,
            nrow(result$theta_inventory) == 10L,
            any(result$audit$check == "tier1_mesh_nspde"),
            any(result$audit$check == "cattle_q_levels"),
            any(result$audit$check == "object_hyper_copy"),
            any(result$audit$check == "prediction_required_variables_finite"),
            any(result$audit$status == "warning"))

  # Storage type is accepted independently of length and index semantics.
  integer_values <- c(seq_len(8L), rep(NA_integer_, 22L))
  double_integer_values <- as.numeric(integer_values)
  double_non_integer_values <- c(seq_len(8L) + 0.5, rep(NA_real_, 22L))
  run_variant <- function(label, effect_overrides) {
    variant_path <- file.path(tempdir(), paste0("joint_inla_preflight_", label, ".rds"))
    make_production_shaped_build(variant_path, effect_overrides = effect_overrides)
    joint_inla_preflight_build(joint_inla_fit_read_build(variant_path), variant_path)
  }
  integer_result <- run_variant("integer_storage", list(tier1_field = integer_values))
  double_result <- run_variant("double_integer_values", list(tier1_field = double_integer_values))
  non_integer_result <- run_variant("double_non_integer_values", list(tier1_field = double_non_integer_values))
  stopifnot(isTRUE(integer_result$success), isTRUE(double_result$success),
            integer_result$audit$storage_accepted[integer_result$audit$check == "tier1_field_type"],
            double_result$audit$storage_accepted[double_result$audit$check == "tier1_field_type"],
            identical(integer_result$audit$typeof[integer_result$audit$check == "tier1_field_type"], "integer"),
            identical(double_result$audit$typeof[double_result$audit$check == "tier1_field_type"], "double"),
            isFALSE(non_integer_result$success),
            any(non_integer_result$audit$check == "tier1_field_integer_valued" & non_integer_result$audit$status == "fail"))

  invalid_storage <- list(
    factor = factor(c(1, 2)), ordered = ordered(c(1, 2)),
    character = c("1", "2"), logical = c(TRUE, FALSE), list_column = list(1, 2)
  )
  stopifnot(all(!vapply(invalid_storage, joint_inla_preflight_numeric_storage_ok, logical(1L))))

  cattle_mid_summary <- result$audit[result$audit$check == "cattle_mid_log1p_summary", , drop = FALSE]
  stopifnot(nrow(cattle_mid_summary) == 1L,
            isFALSE(cattle_mid_summary$integer_valued_required[[1L]]),
            isFALSE(cattle_mid_summary$integer_valued_observed[[1L]]),
            isTRUE(cattle_mid_summary$storage_accepted[[1L]]),
            isTRUE(cattle_mid_summary$active_finite_count[[1L]] > 0))
  malformed_cattle_mid <- c(rep(NA_real_, 8L), Inf, seq_len(21L) / 22)
  malformed_result <- run_variant("malformed_cattle_mid", list(cattle_mid_log1p = malformed_cattle_mid))
  stopifnot(isFALSE(malformed_result$success),
            any(malformed_result$audit$check == "cattle_mid_log1p_active_finite" & malformed_result$audit$status == "fail"))

  fixed_summary <- result$audit[result$audit$section == "fixed_effects" & grepl("_summary$", result$audit$check), , drop = FALSE]
  required_fixed_columns <- c("intercept1", "intercept2", "north", "road_dens", "night_illum",
                              "mintemp", "soilmoist", "leafarea", "rhum", "cattle", "horses",
                              "pigs", "goats", "sheep")
  stopifnot(all(required_fixed_columns %in% fixed_summary$source_column),
            all(c("class", "typeof", "storage_accepted", "active_finite_count",
                  "active_nonfinite_count", "minimum", "maximum", "unique_count") %in% names(result$audit)))
  fixed_rows <- fixed_summary[match(required_fixed_columns, fixed_summary$source_column), , drop = FALSE]
  stopifnot(all(fixed_rows$storage_accepted), all(fixed_rows$active_nonfinite_count == 0),
            all(is.finite(fixed_rows$minimum)), all(is.finite(fixed_rows$maximum)),
            all(fixed_rows$unique_count > 0))

  audit_path <- file.path(tempdir(), "joint_inla_fit_preflight_production.csv")
  written_audit <- joint_inla_preflight_write_audit(result, audit_path)
  stopifnot(file.exists(written_audit), nrow(utils::read.csv(written_audit)) == nrow(result$audit))

  cfg <- joint_inla_fit_defaults()
  cfg$repo_root <- repo_root
  cfg$config_path <- file.path(repo_root, "config", "joint_inla_fit.example.yml")
  cfg$inputs$stage3a_build <- build_path

  invalid_path <- file.path(tempdir(), "joint_inla_invalid_build.rds")
  invalid_build <- make_production_shaped_build(invalid_path, invalid_cattle_bin = TRUE)
  invalid <- joint_inla_preflight_build(joint_inla_fit_read_build(invalid_path), invalid_path)
  stopifnot(isFALSE(invalid$success), any(invalid$audit$check == "cattle_q_levels" & invalid$audit$status == "fail"))

  invalid_cfg <- cfg
  invalid_cfg$inputs$stage3a_build <- invalid_path
  invalid_cfg$project$output_directory <- file.path(tempdir(), "joint_inla_invalid_preflight_dry_run")
  invalid_config <- file.path(tempdir(), "joint_inla_invalid_preflight_dry_run.yml")
  yaml::write_yaml(invalid_cfg, invalid_config)
  invalid_dry <- tryCatch({
    run_joint_inla_fit(invalid_config, repo_root, dry_run = TRUE,
                       inla_function = function(...) stop("INLA::inla must not be called after preflight failure"))
    FALSE
  }, error = function(error) grepl("preflight failed", tolower(conditionMessage(error)), fixed = TRUE))
  stopifnot(invalid_dry,
            file.exists(file.path(invalid_cfg$project$output_directory, "joint_inla_fit_preflight.csv")),
            !file.exists(file.path(invalid_cfg$project$output_directory, "joint_model_fit.rds")))

  cfg$project$output_directory <- file.path(tempdir(), "joint_inla_preflight_dry_run")
  dry_config <- file.path(tempdir(), "joint_inla_preflight_dry_run.yml")
  yaml::write_yaml(cfg, dry_config)
  dry <- run_joint_inla_fit(dry_config, repo_root, dry_run = TRUE,
                            inla_function = function(...) stop("INLA::inla must not be called"))
  stopifnot(isTRUE(dry$audit$dry_run[[1L]]), file.exists(dry$paths$preflight),
            !file.exists(dry$paths$fit))

  cat("Stage 3B production-shaped preflight tests passed\n")
}
