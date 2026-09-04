joint_pc_precision <- function(sigma, probability) list(prec = list(prior = "pc.prec", param = c(as.numeric(sigma), as.numeric(probability))))

make_joint_priors <- function(cfg) {
  list(
    pc_rw = joint_pc_precision(1, 0.01),
    pc_rw_strong = joint_pc_precision(0.3, 0.01),
    pc_rw_cat = joint_pc_precision(cfg$livestock_rw2$prior_sigma, cfg$livestock_rw2$prior_probability),
    hyper_copy = list(beta = list(prior = "normal", param = c(as.numeric(cfg$shared_field$beta_prior_mean), as.numeric(cfg$shared_field$beta_prior_sd))))
  )
}

make_joint_formula <- function(spde_tier1, spde_tier2, priors, cfg) {
  pc_rw <- priors$pc_rw
  pc_rw_strong <- priors$pc_rw_strong
  pc_rw_cat <- priors$pc_rw_cat
  hyper_copy <- priors$hyper_copy
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
  attr(formula, "joint_inla_semantics") <- list(copy = "tier2_copy_field copies tier1_field with an estimated coefficient", group_model = "iid")
  formula
}

introspect_nbinomial_default <- function() {
  require_joint_inla()
  models <- INLA::inla.models()
  likelihood <- models[["likelihood"]]
  model <- likelihood[["nbinomial"]]
  if (is.null(model)) return(list(available = FALSE, reason = "INLA does not expose likelihood nbinomial."))
  hyper <- model[["hyper"]]
  concise <- lapply(hyper, function(specification) {
    keys <- intersect(c("name", "short.name", "prior", "param", "initial", "fixed"), names(specification))
    values <- specification[keys]
    for (key in names(values)) {
      values[[key]] <- if (is.logical(values[[key]])) isTRUE(values[[key]]) else if (is.numeric(values[[key]])) as.numeric(values[[key]]) else as.character(values[[key]])
    }
    values
  })
  list(available = TRUE, model = "nbinomial", hyper = concise)
}

make_joint_fit_reference <- function(cfg, nbinomial_default) {
  list(
    execution = "reference only; Stage 3A does not call INLA::inla()",
    quantiles = cfg$fit_reference$quantiles,
    control_fixed = cfg$fit_reference$control_fixed,
    control_mode = cfg$fit_reference$control_mode,
    control_inla = cfg$fit_reference$control_inla,
    control_compute = cfg$fit_reference$control_compute,
    nbinomial_default = nbinomial_default
  )
}
