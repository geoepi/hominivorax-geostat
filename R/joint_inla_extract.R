# Reusable extraction helpers for the Stage 3B joint-INLA artifact.
#
# The fit object contains two predictor blocks.  The first block is the
# APredictor block (one row per row in the joint stack); the trailing block is
# the latent Predictor block (one row per latent/effect row).  These helpers
# keep those output indices distinct from source-data row numbers and random
# effect model IDs.

joint_inla_extract_fit <- function(fit_artifact) {
  if (is.list(fit_artifact) && !is.null(fit_artifact$fit)) fit_artifact$fit else fit_artifact
}

joint_inla_extract_stack <- function(build) {
  if (!is.list(build$stacks) || is.null(build$stacks$joint)) stop("Stage 3A build is missing stacks$joint.")
  build$stacks$joint
}

joint_inla_extract_stack_info <- function(build) {
  stack <- joint_inla_extract_stack(build)
  info <- stack$data
  if (!is.list(info) || is.null(info$data) || is.null(info$index)) stop("Joint stack does not contain the expected data/index metadata.")
  if (!is.data.frame(info$data)) stop("Joint stack response data is not a data frame.")
  indices <- lapply(info$index, as.integer)
  if (!length(indices) || is.null(names(indices)) || any(!nzchar(names(indices)))) stop("Joint stack data indices are missing named tier mappings.")
  n <- nrow(info$data)
  if (any(vapply(indices, function(x) anyNA(x) || any(x < 1L | x > n), logical(1L)))) stop("Joint stack data indices are outside the response-row range.")
  flat <- unlist(indices, use.names = FALSE)
  if (anyDuplicated(flat) || !identical(sort(flat), seq_len(n))) stop("Joint stack tier indices are not disjoint and exhaustive.")
  list(stack = stack, data = info$data, indices = indices, n = n)
}

joint_inla_stack_tags <- function(build_or_stack) {
  stack <- if (is.list(build_or_stack) && !is.null(build_or_stack$stacks)) joint_inla_extract_stack(build_or_stack) else build_or_stack
  if (!is.list(stack$data) || is.null(stack$data$index)) stop("Joint stack has no named data indices.")
  names(stack$data$index)
}

joint_inla_stack_indices <- function(build_or_stack) {
  stack <- if (is.list(build_or_stack) && !is.null(build_or_stack$stacks)) joint_inla_extract_stack(build_or_stack) else build_or_stack
  if (!is.list(stack$data) || is.null(stack$data$index)) stop("Joint stack has no data indices.")
  lapply(stack$data$index, as.integer)
}

joint_inla_extract_stack_response <- function(data, family_index) {
  if (all(c("Y.1", "Y.2") %in% names(data))) return(as.numeric(data[[paste0("Y.", family_index)]]))
  if ("Y" %in% names(data) && is.matrix(data$Y)) return(as.numeric(data$Y[, family_index]))
  stop("Joint stack response data does not contain Y.1/Y.2 or a two-column Y matrix.")
}

joint_inla_extract_source_columns <- function(out, source, rows = NULL, prefix = "source_") {
  rows <- rows %||% seq_len(nrow(out))
  columns <- c(".row_id", "source_obs_id", "observation_id", ".tier1_row_id", "poly_id", "point_id",
               "x", "y", "admin_u", "admin_f", "epiyear", "epiweek", "time_index", "quarter_index",
               "week_start", "count", "Yi", "n_points", "is_censored", "is_test_point",
               "response_observed", "response_training", "cattle_q", "cattle_mid", "cattle_mid_log1p")
  for (column in intersect(columns, names(source))) {
    values <- out[[paste0(prefix, column)]] %||% rep(NA, nrow(out))
    values[rows] <- source[[column]]
    out[[paste0(prefix, column)]] <- values
  }
  out
}

joint_inla_extract_row_map <- function(build, stage2 = NULL) {
  info <- joint_inla_extract_stack_info(build)
  data <- info$data
  family <- as.integer(data$link)
  if (length(family) != info$n || any(!is.finite(family)) || any(!family %in% seq_along(build$family))) stop("Joint stack link values do not identify the configured likelihood families.")
  response <- lapply(seq_along(build$family), joint_inla_extract_stack_response, data = data)
  response_training <- rep(NA_real_, info$n)
  for (i in seq_along(response)) response_training[family == i] <- response[[i]][family == i]
  out <- data.frame(
    output_id = paste0("stack:", seq_len(info$n)),
    stack_row = seq_len(info$n),
    tier = NA_character_,
    source_row = NA_integer_,
    family_index = family,
    family = as.character(build$family[family]),
    link = family,
    exposure = if ("e" %in% names(data)) as.numeric(data$e) else NA_real_,
    response_training = response_training,
    response_observed = NA_real_,
    is_test_point = NA,
    is_censored = NA,
    stringsAsFactors = FALSE
  )
  for (tier in names(info$indices)) {
    rows <- info$indices[[tier]]
    out$tier[rows] <- tier
    out$source_row[rows] <- seq_along(rows)
  }
  if (anyNA(out$tier)) stop("Joint stack tier indices did not assign every response row.")

  if (!is.null(stage2)) {
    for (tier in names(info$indices)) {
      if (!tier %in% names(stage2) || !is.data.frame(stage2[[tier]])) stop("Stage 2 inputs are missing data frame '", tier, "'.")
      rows <- info$indices[[tier]]
      source <- stage2[[tier]]
      if (nrow(source) != length(rows)) stop("Stage 2 ", tier, " rows do not match the joint stack index length.")
      source_training <- if ("response_training" %in% names(source)) as.numeric(source$response_training) else rep(NA_real_, nrow(source))
      if (!all((is.na(source_training) & is.na(out$response_training[rows])) | source_training == out$response_training[rows])) stop("Stage 2 ", tier, " response_training disagrees with the joint stack.")
      out$response_observed[rows] <- if ("response_observed" %in% names(source)) as.numeric(source$response_observed) else NA_real_
      out$is_test_point[rows] <- if ("is_test_point" %in% names(source)) as.logical(source$is_test_point) else NA
      out$is_censored[rows] <- if ("is_censored" %in% names(source)) as.logical(source$is_censored) else NA
      out <- joint_inla_extract_source_columns(out, source, rows = rows)
    }
  }
  out
}

joint_inla_extract_predictor_layout <- function(build, fit_artifact) {
  fit <- joint_inla_extract_fit(fit_artifact)
  info <- joint_inla_extract_stack_info(build)
  if (is.null(fit$size.linear.predictor) || is.null(fit$size.linear.predictor$n)) stop("Fit is missing size.linear.predictor metadata.")
  n_latent <- as.integer(fit$size.linear.predictor$n)[[1L]]
  n_total <- as.integer(fit$size.linear.predictor$Ntotal %||% (info$n + n_latent))[[1L]]
  if (!identical(n_total, info$n + n_latent)) stop("Fit predictor layout does not reconcile with the joint stack response row count.")
  observed <- seq_len(info$n)
  latent <- info$n + seq_len(n_latent)
  for (object_name in c("summary.linear.predictor", "summary.fitted.values")) {
    object <- fit[[object_name]]
    if (is.null(object) || nrow(object) != n_total) stop("Fit ", object_name, " does not match size.linear.predictor$Ntotal.")
  }
  list(observed = observed, latent = latent, n_observed = info$n, n_latent = n_latent, n_total = n_total,
       observed_block = "APredictor", latent_block = "Predictor")
}

joint_inla_extract_fitted_values <- function(build, fit_artifact, stage2 = NULL) {
  fit <- joint_inla_extract_fit(fit_artifact)
  layout <- joint_inla_extract_predictor_layout(build, fit)
  out <- joint_inla_extract_row_map(build, stage2)
  out$predictor_block <- layout$observed_block
  out$output_index <- layout$observed
  out$linear_predictor_row <- layout$observed
  out$fitted_row <- layout$observed
  lp <- fit$summary.linear.predictor[layout$observed, , drop = FALSE]
  fv <- fit$summary.fitted.values[layout$observed, , drop = FALSE]
  for (column in names(lp)) out[[paste0("linear_predictor_", column)]] <- lp[[column]]
  for (column in names(fv)) out[[paste0("fitted_", column)]] <- fv[[column]]
  out
}

joint_inla_extract_holdout_predictions <- function(build, fit_artifact, stage2) {
  fitted <- joint_inla_extract_fitted_values(build, fit_artifact, stage2)
  if (!"source_is_test_point" %in% names(fitted)) stop("Stage 2 holdout indicators are unavailable.")
  fitted[fitted$source_is_test_point %in% TRUE, , drop = FALSE]
}

joint_inla_extract_summary_table <- function(x, index_name) {
  if (is.null(x)) return(data.frame())
  out <- as.data.frame(x, stringsAsFactors = FALSE)
  out$model_index <- seq_len(nrow(out))
  out[[index_name]] <- rownames(out)
  rownames(out) <- NULL
  out[, c(index_name, "model_index", setdiff(names(out), c(index_name, "model_index"))), drop = FALSE]
}

joint_inla_extract_fixed_effects <- function(fit_artifact) {
  out <- joint_inla_extract_summary_table(joint_inla_extract_fit(fit_artifact)$summary.fixed, "term")
  out$effect_type <- "fixed"
  out
}

joint_inla_extract_hyperparameters <- function(fit_artifact) {
  out <- joint_inla_extract_summary_table(joint_inla_extract_fit(fit_artifact)$summary.hyperpar, "parameter")
  out$effect_type <- "hyperparameter"
  out
}

joint_inla_extract_random_effects <- function(fit_artifact, component = NULL) {
  fit <- joint_inla_extract_fit(fit_artifact)
  components <- names(fit$summary.random)
  if (!is.null(component)) components <- intersect(as.character(component), components)
  if (!length(components)) stop("No requested random-effect components are present in the fit.")
  tables <- lapply(components, function(name) {
    x <- as.data.frame(fit$summary.random[[name]], stringsAsFactors = FALSE)
    model_index <- if ("ID" %in% names(x)) x$ID else seq_len(nrow(x))
    x$component <- name
    x$model_index <- model_index
    x$row_index <- seq_len(nrow(x))
    x
  })
  columns <- unique(unlist(lapply(tables, names)))
  tables <- lapply(tables, function(x) { missing <- setdiff(columns, names(x)); x[missing] <- NA; x[, columns, drop = FALSE] })
  do.call(rbind, tables)
}

joint_inla_extract_temporal_effects <- function(build, fit_artifact, stage2) {
  if (is.null(stage2$temporal_mapping)) stop("Stage 2 temporal_mapping is required for temporal effect extraction.")
  mapping <- stage2$temporal_mapping
  if (!all(c("timestep", "epiyear", "epiweek") %in% names(mapping))) stop("Stage 2 temporal_mapping lacks timestep/year-week fields.")
  out <- joint_inla_extract_random_effects(fit_artifact, c("week_steps", "tier2_week"))
  out$timestep <- as.integer(out$model_index)
  join <- mapping[match(out$timestep, mapping$timestep), , drop = FALSE]
  out$epiyear <- join$epiyear
  out$epiweek <- join$epiweek
  for (column in setdiff(names(mapping), c("timestep", "epiyear", "epiweek"))) out[[column]] <- join[[column]]
  out
}

joint_inla_extract_admin_effects <- function(fit_artifact, stage2) {
  if (is.null(stage2$admin_mapping)) stop("Stage 2 admin_mapping is required for admin effect extraction.")
  full <- stage2$admin_mapping
  full$model_index <- as.integer(full$admin_f)
  random <- joint_inla_extract_random_effects(fit_artifact, "admin_f")
  random$model_index <- as.integer(random$model_index)
  summary_columns <- setdiff(names(random), c("component", "model_index", "row_index", "ID"))
  for (column in summary_columns) full[[column]] <- random[[column]][match(full$model_index, random$model_index)]
  full$fitted_level <- full$model_index %in% random$model_index
  full$unused_level <- !full$fitted_level
  full
}

joint_inla_extract_cattle_effects <- function(fit_artifact, stage2) {
  required <- c("cattle_q", "cattle_mid_log1p", "cattle_mid", "response_training", "response_observed")
  if (!all(required %in% names(stage2$tier2))) stop("Stage 2 Tier 2 lacks cattle support/count fields.")
  data <- stage2$tier2
  q <- as.integer(data$cattle_q)
  support <- sort(unique(q[is.finite(q)]))
  counts <- data.frame(
    model_index = support,
    cattle_q = support,
    cattle_mid_log1p = vapply(support, function(i) data$cattle_mid_log1p[match(i, q)], numeric(1L)),
    cattle_mid = vapply(support, function(i) data$cattle_mid[match(i, q)], numeric(1L)),
    full_count = vapply(support, function(i) sum(q == i, na.rm = TRUE), integer(1L)),
    active_count = vapply(support, function(i) sum(q == i & !is.na(data$response_training), na.rm = TRUE), integer(1L)),
    observed_positive_count = vapply(support, function(i) sum(q == i & !is.na(data$response_observed) & data$response_observed > 0, na.rm = TRUE), integer(1L))
  )
  random <- joint_inla_extract_random_effects(fit_artifact, "cattle_q")
  summary_columns <- setdiff(names(random), c("component", "model_index", "row_index", "ID"))
  for (column in summary_columns) counts[[column]] <- random[[column]][match(counts$model_index, random$model_index)]
  counts$fitted_level <- counts$model_index %in% random$model_index
  counts
}

joint_inla_extract_spde_fields <- function(build, fit_artifact) {
  specs <- list(
    tier1_field = list(scope = "tier1", index = "tier1_field"),
    tier2_field = list(scope = "tier2", index = "tier2_field"),
    tier2_copy_field = list(scope = "copy", index = "tier2_copy_field")
  )
  out <- lapply(names(specs), function(component) {
    spec <- specs[[component]]
    field <- build$fields[[spec$scope]]
    if (is.null(field) || is.null(field[[spec$index]])) stop("Build field index is missing ", component, ".")
    n <- length(field[[spec$index]])
    random <- joint_inla_extract_random_effects(fit_artifact, component)
    if (nrow(random) != n) stop(component, " summary length does not match its build field index length.")
    group_name <- paste0(spec$index, ".group")
    repl_name <- paste0(spec$index, ".repl")
    data.frame(
      component = component,
      latent_row = seq_len(n),
      model_index = random$model_index,
      mesh_node = as.integer(field[[spec$index]]),
      group_index = as.integer(field[[group_name]]),
      replicate_index = as.character(field[[repl_name]]),
      mean = random$mean,
      sd = random$sd,
      stringsAsFactors = FALSE
    )
  })
  names(out) <- names(specs)
  out
}

joint_inla_extract_criteria <- function(build, fit_artifact, tolerance = 1e-6) {
  fit <- joint_inla_extract_fit(fit_artifact)
  family_index <- as.integer(fit$dic$family)
  local_dic <- as.numeric(fit$dic$local.dic)
  local_waic <- as.numeric(fit$waic$local.waic)
  if (!identical(length(family_index), length(local_dic)) || !identical(length(family_index), length(local_waic))) stop("Local DIC/WAIC/family vectors have different lengths.")
  family_name <- rep(NA_character_, length(family_index))
  valid_family <- !is.na(family_index) & family_index >= 1L & family_index <= length(build$family)
  family_name[valid_family] <- as.character(build$family[family_index[valid_family]])
  local <- data.frame(output_index = seq_along(family_index), family_index = family_index, family = family_name,
                      local_dic = local_dic, local_waic = local_waic, stringsAsFactors = FALSE)
  levels <- sort(unique(family_index[valid_family]))
  by_family <- do.call(rbind, lapply(levels, function(i) data.frame(
    family_index = i, family = as.character(build$family[[i]]), n_rows = sum(family_index == i, na.rm = TRUE),
    dic = sum(local_dic[family_index == i], na.rm = TRUE), waic = sum(local_waic[family_index == i], na.rm = TRUE)
  )))
  global <- data.frame(metric = c("dic", "waic"), value = c(as.numeric(fit$dic$dic)[[1L]], as.numeric(fit$waic$waic)[[1L]]), stringsAsFactors = FALSE)
  local_totals <- c(dic = sum(by_family$dic), waic = sum(by_family$waic))
  differences <- c(
    dic = global$value[match("dic", global$metric)] - local_totals[["dic"]],
    waic = global$value[match("waic", global$metric)] - local_totals[["waic"]]
  )
  list(global = global, by_family = by_family, local = local, reconciliation = data.frame(metric = names(differences), local_sum = unname(local_totals), global = global$value, difference = unname(differences), pass = abs(differences) <= tolerance, stringsAsFactors = FALSE))
}

joint_inla_extract_marginal_log_likelihood <- function(fit_artifact) {
  value <- joint_inla_extract_fit(fit_artifact)$mlik
  if (is.null(value)) return(data.frame(method = character(), value = numeric(), stringsAsFactors = FALSE))
  matrix_value <- as.matrix(value)
  labels <- rownames(matrix_value)
  if (is.null(labels)) labels <- colnames(matrix_value)
  if (is.null(labels)) labels <- rep("unspecified", length(matrix_value))
  data.frame(method = as.character(labels), value = as.numeric(matrix_value), stringsAsFactors = FALSE)
}

joint_inla_extract_audit <- function(build, fit_artifact, stage2 = NULL, tolerance = 1e-6) {
  checks <- list()
  add <- function(section, check, status, observed, expected, details) checks[[length(checks) + 1L]] <<- data.frame(section = section, check = check, status = toupper(status), observed = as.character(observed), expected = as.character(expected), details = details, stringsAsFactors = FALSE)
  fit <- joint_inla_extract_fit(fit_artifact)
  info <- tryCatch(joint_inla_extract_stack_info(build), error = function(e) e)
  if (inherits(info, "error")) {
    add("artifact", "joint_stack_structure", "FAIL", conditionMessage(info), "named disjoint exhaustive indices", "Cannot construct an authoritative row map.")
    return(list(audit = do.call(rbind, checks), details = "Extraction stopped at joint stack validation."))
  }
  tags <- names(info$indices)
  add("stack", "named_tier_indices", if (identical(tags, c("tier1", "tier2"))) "PASS" else "FAIL", paste(tags, collapse = ","), "tier1,tier2", "The production stack stores tier indices in stack$data$index; top-level stack$tag is not required.")
  add("stack", "disjoint_exhaustive_indices", "PASS", info$n, info$n, "Tier indices are disjoint and cover every joint response row.")
  layout <- tryCatch(joint_inla_extract_predictor_layout(build, fit), error = function(e) e)
  if (inherits(layout, "error")) {
    add("fit", "predictor_layout", "FAIL", conditionMessage(layout), "APredictor plus Predictor blocks reconcile", "Fitted-value indexing is not safe.")
    return(list(audit = do.call(rbind, checks), details = "Extraction stopped at predictor-layout validation."))
  }
  add("fit", "predictor_layout", "PASS", paste(layout$n_observed, layout$n_latent, layout$n_total, sep = "/"), "2,624,383/2,815,201/5,439,584 for production", "Observed fitted values are the first APredictor block; latent Predictor rows are retained separately.")
  row_map <- tryCatch(joint_inla_extract_row_map(build, stage2), error = function(e) e)
  fitted <- tryCatch(joint_inla_extract_fitted_values(build, fit, stage2), error = function(e) e)
  if (inherits(row_map, "error") || inherits(fitted, "error")) {
    message <- if (inherits(row_map, "error")) conditionMessage(row_map) else conditionMessage(fitted)
    add("fit", "authoritative_observation_extraction", "FAIL", message, "fitted values mapped to stack rows", "The production audit cannot continue.")
    return(list(audit = do.call(rbind, checks), details = "Extraction stopped at row-map validation."))
  }
  counts <- table(row_map$tier)
  add("rows", "tier_row_counts", if (identical(as.integer(counts[c("tier1", "tier2")]), c(nrow(stage2$tier1), nrow(stage2$tier2)))) "PASS" else "FAIL", paste(as.integer(counts[c("tier1", "tier2")]), collapse = "/"), paste(nrow(stage2$tier1), nrow(stage2$tier2), sep = "/"), "Stack row counts match Stage 2 source rows.")
  link_counts <- table(row_map$link)
  add("rows", "likelihood_link_counts", if (identical(as.integer(link_counts[c(1, 2)]), c(sum(row_map$family_index == 1L), sum(row_map$family_index == 2L)))) "PASS" else "FAIL", paste(as.integer(link_counts[c(1, 2)]), collapse = "/"), "link 1/link 2", "Link values are preserved as output metadata.")
  active <- tapply(!is.na(row_map$response_training), row_map$tier, sum)
  source_active <- tapply(!is.na(unlist(lapply(stage2[c("tier1", "tier2")], function(x) x$response_training))), rep(c("tier1", "tier2"), c(nrow(stage2$tier1), nrow(stage2$tier2))), sum)
  add("rows", "active_training_counts", if (identical(as.integer(active[c("tier1", "tier2")]), as.integer(source_active[c("tier1", "tier2")])) ) "PASS" else "FAIL", paste(as.integer(active[c("tier1", "tier2")]), collapse = "/"), paste(as.integer(source_active[c("tier1", "tier2")]), collapse = "/"), "Training-response activity agrees with Stage 2.")
  holdout_counts <- tapply(row_map$source_is_test_point %in% TRUE, row_map$tier, sum)
  add("holdout", "holdout_rows", "PASS", paste(as.integer(holdout_counts[c("tier1", "tier2")]), collapse = "/"), "Stage 2 holdout indicators", "Holdout rows are retained as fitted predictions without computing validation metrics.")
  finite <- all(is.finite(fitted$fitted_mean))
  add("fit", "observed_fitted_values_finite", if (finite) "PASS" else "FAIL", sum(!is.finite(fitted$fitted_mean)), 0, "Observed APredictor fitted means are finite.")
  tier1_mean <- fitted$fitted_mean[fitted$link == 1L]
  tier2_mean <- fitted$fitted_mean[fitted$link == 2L]
  add("fit", "tier1_fitted_probability_range", if (all(tier1_mean >= 0 & tier1_mean <= 1)) "PASS" else "FAIL", paste(range(tier1_mean), collapse = "/"), "within 0/1", "Tier 1 fitted means are on the response probability scale.")
  add("fit", "tier2_fitted_positive", if (all(tier2_mean > 0)) "PASS" else "FAIL", paste(range(tier2_mean), collapse = "/"), "> 0", "Tier 2 fitted means are positive on the count response scale.")
  add("fit", "fixed_effect_count", if (nrow(fit$summary.fixed) == 16L) "PASS" else "FAIL", nrow(fit$summary.fixed), 16, "Fixed-effect summary count.")
  add("fit", "hyperparameter_count", if (nrow(fit$summary.hyperpar) == 10L) "PASS" else "FAIL", nrow(fit$summary.hyperpar), 10, "Hyperparameter summary count.")
  add("fit", "random_component_count", if (length(fit$summary.random) == 7L) "PASS" else "FAIL", length(fit$summary.random), 7, "Random-effect component count.")
  if (!is.null(stage2)) {
    temporal <- tryCatch(joint_inla_extract_temporal_effects(build, fit, stage2), error = function(e) e)
    add("temporal", "week_effect_support", if (!inherits(temporal, "error") && all(c("week_steps", "tier2_week") %in% unique(temporal$component)) && all(temporal$timestep %in% 1:105)) "PASS" else "FAIL", if (inherits(temporal, "error")) conditionMessage(temporal) else length(unique(temporal$timestep)), "105 timesteps for both week components", "Temporal effects are mapped to Stage 2 year/week metadata.")
    admin <- tryCatch(joint_inla_extract_admin_effects(fit, stage2), error = function(e) e)
    add("admin", "full_and_fitted_levels", if (!inherits(admin, "error") && nrow(admin) == 340L && sum(admin$fitted_level) == 319L) "PASS" else "FAIL", if (inherits(admin, "error")) conditionMessage(admin) else paste(nrow(admin), sum(admin$fitted_level), sep = "/"), "340/319 full/fitted admin levels", "Unused full-support admin levels remain explicit.")
    cattle <- tryCatch(joint_inla_extract_cattle_effects(fit, stage2), error = function(e) e)
    zero_bins <- if (inherits(cattle, "error")) character() else as.character(cattle$model_index[cattle$active_count == 0L])
    add("cattle", "full_rw2_support", if (!inherits(cattle, "error") && identical(cattle$model_index, 1:22)) "PASS" else "FAIL", if (inherits(cattle, "error")) conditionMessage(cattle) else paste(nrow(cattle), paste(zero_bins, collapse = ","), sep = "; zero_active_bins="), "22 bins retained; zero-active bins are allowed", "Cattle support is mapped to cattle_q and original/log1p midpoints.")
    spde <- tryCatch(joint_inla_extract_spde_fields(build, fit), error = function(e) e)
    spde_ok <- !inherits(spde, "error") && all(vapply(spde, nrow, integer(1L)) == 13449L * 8L)
    copy_ok <- spde_ok && identical(spde$tier1_field[c("mesh_node", "group_index")], spde$tier2_copy_field[c("mesh_node", "group_index")])
    add("spde", "field_dimensions", if (spde_ok) "PASS" else "FAIL", if (inherits(spde, "error")) conditionMessage(spde) else paste(vapply(spde, nrow, integer(1L)), collapse = "/"), "13,449 vertices x 8 groups for each field/copy", "SPDE rows retain mesh node, group, replicate, and latent row indices.")
    add("spde", "copy_field_mapping", if (copy_ok) "PASS" else "FAIL", if (spde_ok) "tier2_copy_field matches tier1 mesh/group support" else "unavailable", "copy uses the tier1 mesh/group support", "The copy field is mapped separately from its random-effect model IDs.")
  }
  criteria <- tryCatch(joint_inla_extract_criteria(build, fit, tolerance), error = function(e) e)
  criteria_ok <- !inherits(criteria, "error") && all(criteria$reconciliation$pass)
  add("criteria", "local_global_reconciliation", if (criteria_ok) "PASS" else "FAIL", if (inherits(criteria, "error")) conditionMessage(criteria) else paste(criteria$reconciliation$difference, collapse = "/"), paste0("absolute difference <= ", tolerance), "Local DIC/WAIC sums reconcile to global criteria by likelihood family.")
  mlik <- joint_inla_extract_marginal_log_likelihood(fit)
  integration <- mlik$value[grepl("integration", mlik$method, ignore.case = TRUE)]
  add("criteria", "marginal_log_likelihood", if (length(integration) == 1L && is.finite(integration)) "PASS" else "FAIL", if (length(integration)) integration[[1L]] else "missing", "finite integration marginal log likelihood", "The matrix row label is used; the Gaussian approximation is retained separately.")
  fit_warnings <- fit$misc$warnings
  add("provenance", "fit_internal_warnings", if (is.null(fit_warnings) || !length(fit_warnings)) "PASS" else "WARNING", if (is.null(fit_warnings)) "none" else paste(as.character(fit_warnings), collapse = " | "), "recorded context only", "Warnings are preserved as provenance and do not alter the production fit.")
  if (!is.null(stage2$prediction_grid)) add("prediction", "prediction_grid_in_fit_stack", "WARNING", nrow(stage2$prediction_grid), "prediction grid rows are not in the response stack", "The production fit contains observed/holdout response rows but no direct prediction-grid fitted block; prediction-grid metrics require a separate prediction step.")
  add("scope", "validation_readiness", "WARNING", "holdout predictions extractable; metrics not computed", "separate formal validation review", "Extraction is suitable for structural holdout review, not biological interpretation or final predictive-performance claims.")
  audit <- do.call(rbind, checks)
  details <- paste(c("Joint-INLA extraction audit", paste0("PASS=", sum(audit$status == "PASS"), "; WARNING=", sum(audit$status == "WARNING"), "; FAIL=", sum(audit$status == "FAIL")), "Production fit warnings are contextual and preserved; no model artifacts were modified.", capture.output(print(audit, row.names = FALSE))), collapse = "\n")
  list(audit = audit, details = details, row_map = row_map, fitted = fitted)
}

`%||%` <- if (exists("%||%", mode = "function")) get("%||%") else function(x, y) if (is.null(x)) y else x
