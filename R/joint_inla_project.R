# Phase 2 post-fit projection helpers.
#
# This file deliberately contains no call to INLA::inla().  It reconstructs
# posterior-mean linear predictors from the saved Stage 3B summaries and
# projects the same components to the Stage 2 prediction grid.

`%||%` <- function(x, y) if (is.null(x)) y else x

joint_inla_project_require_extract <- function() {
  required <- c(
    "joint_inla_extract_fit", "joint_inla_extract_row_map",
    "joint_inla_extract_fitted_values", "joint_inla_extract_spde_fields"
  )
  missing <- required[!vapply(required, exists, logical(1L), mode = "function", inherits = TRUE)]
  if (length(missing)) {
    stop("Source R/joint_inla_extract.R before using projection helpers; missing: ", paste(missing, collapse = ", "))
  }
  invisible(TRUE)
}

joint_inla_project_fixed_means <- function(fit_artifact) {
  fit <- joint_inla_extract_fit(fit_artifact)
  summary <- fit$summary.fixed
  if (is.null(summary) || is.null(rownames(summary)) || !"mean" %in% names(summary)) {
    stop("The saved fit is missing a named summary.fixed$mean table.")
  }
  terms <- as.character(rownames(summary))
  if (any(!nzchar(terms)) || anyDuplicated(terms)) stop("summary.fixed must have unique non-empty term names.")
  means <- as.numeric(summary[, "mean"])
  if (any(!is.finite(means))) stop("summary.fixed$mean contains non-finite values.")
  stats::setNames(means, terms)
}

joint_inla_project_fixed_lookup <- function(fixed_means, term, label = term) {
  if (!term %in% names(fixed_means)) stop("Fitted fixed effect is missing ", label, " ('", term, "').")
  value <- as.numeric(fixed_means[[term]])
  if (length(value) != 1L || !is.finite(value)) stop("Fitted fixed effect is not finite for ", label, ".")
  value
}

joint_inla_project_random_table <- function(fit_artifact, component) {
  fit <- joint_inla_extract_fit(fit_artifact)
  if (is.null(fit$summary.random) || !component %in% names(fit$summary.random)) {
    stop("The saved fit is missing summary.random$", component, ".")
  }
  table <- as.data.frame(fit$summary.random[[component]], stringsAsFactors = FALSE)
  if (!"mean" %in% names(table)) stop("summary.random$", component, " is missing its mean column.")
  index <- if ("ID" %in% names(table)) table$ID else seq_len(nrow(table))
  if (anyNA(index) || any(!nzchar(as.character(index))) || anyDuplicated(as.character(index))) {
    stop("summary.random$", component, " has invalid or duplicated model indices.")
  }
  means <- as.numeric(table$mean)
  if (any(!is.finite(means))) stop("summary.random$", component, "$mean contains non-finite values.")
  data.frame(model_index = index, mean = means, stringsAsFactors = FALSE)
}

joint_inla_project_random_lookup <- function(table, index, component, allow_missing = FALSE) {
  index_key <- as.character(index)
  fitted_key <- as.character(table$model_index)
  position <- match(index_key, fitted_key)
  missing <- is.na(position)
  if (any(missing) && !isTRUE(allow_missing)) {
    stop("", component, " has unsupported model indices: ", paste(unique(index_key[missing]), collapse = ", "))
  }
  out <- rep(0, length(index_key))
  out[!missing] <- table$mean[position[!missing]]
  out
}

joint_inla_project_safe_name <- function(term) {
  out <- gsub("[^A-Za-z0-9_]+", "_", term)
  out <- gsub("_+", "_", out)
  sub("^_|_$", "", out)
}

joint_inla_project_mapping <- function(build, tier) {
  if (is.null(build$effect_mapping) || is.null(build$effect_mapping[[tier]])) {
    stop("Stage 3A effect mapping is missing for ", tier, ".")
  }
  mapping <- build$effect_mapping[[tier]]
  if (is.null(names(mapping)) || any(!nzchar(names(mapping)))) stop("Effect mapping for ", tier, " is not named.")
  mapping
}

joint_inla_project_mapping_column <- function(mapping, term) {
  if (term %in% names(mapping)) unname(mapping[[term]]) else term
}

joint_inla_project_require_columns <- function(data, columns, label) {
  missing <- setdiff(columns, names(data))
  if (length(missing)) stop(label, " is missing required columns: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}

joint_inla_project_fixed_terms <- function(fixed_means, mapping, intercept, data, tier) {
  index_terms <- c("admin_f", "week_steps", "tier2_week", "cattle_q", "cattle_mid_log1p")
  ordinary <- intersect(setdiff(names(mapping), index_terms), names(fixed_means))
  interactions <- names(fixed_means)[grepl(":", names(fixed_means), fixed = TRUE)]
  interactions <- interactions[vapply(interactions, function(term) {
    pieces <- strsplit(term, ":", fixed = TRUE)[[1L]]
    columns <- vapply(pieces, function(piece) joint_inla_project_mapping_column(mapping, piece), character(1L))
    all(columns %in% names(data))
  }, logical(1L))]
  terms <- unique(c(intersect(intercept, names(fixed_means)), ordinary, interactions))
  if (!length(terms)) stop("No fixed effects could be mapped for ", tier, ".")
  for (term in terms) {
    if (grepl(":", term, fixed = TRUE)) {
      pieces <- strsplit(term, ":", fixed = TRUE)[[1L]]
      columns <- vapply(pieces, function(piece) joint_inla_project_mapping_column(mapping, piece), character(1L))
      joint_inla_project_require_columns(data, columns, paste0(tier, " interaction ", term))
    } else if (term != intercept) {
      column <- joint_inla_project_mapping_column(mapping, term)
      joint_inla_project_require_columns(data, column, paste0(tier, " fixed effect ", term))
    }
  }
  terms
}

joint_inla_project_fixed_contributions <- function(data, fixed_means, mapping, intercept, tier) {
  terms <- joint_inla_project_fixed_terms(fixed_means, mapping, intercept, data, tier)
  out <- data.frame(row_index = seq_len(nrow(data)), stringsAsFactors = FALSE)
  for (term in terms) {
    coefficient <- joint_inla_project_fixed_lookup(fixed_means, term, paste0(tier, " fixed effect"))
    if (identical(term, intercept)) {
      value <- rep(coefficient, nrow(data))
    } else if (grepl(":", term, fixed = TRUE)) {
      pieces <- strsplit(term, ":", fixed = TRUE)[[1L]]
      columns <- vapply(pieces, function(piece) joint_inla_project_mapping_column(mapping, piece), character(1L))
      value <- coefficient * Reduce(`*`, lapply(data[columns], as.numeric))
    } else {
      column <- joint_inla_project_mapping_column(mapping, term)
      value <- coefficient * as.numeric(data[[column]])
    }
    if (any(!is.finite(value))) stop("Non-finite contribution for fitted fixed effect ", term, " in ", tier, ".")
    out[[paste0("fixed_", joint_inla_project_safe_name(term))]] <- value
  }
  contribution_columns <- setdiff(names(out), "row_index")
  out$fixed_total <- rowSums(out[contribution_columns])
  out
}

joint_inla_project_spatial_field_vector <- function(field_table, label) {
  if (!all(c("latent_row", "mean", "mesh_node", "group_index") %in% names(field_table))) {
    stop(label, " field table lacks latent-row, mean, mesh-node, or group metadata.")
  }
  order_index <- order(as.integer(field_table$latent_row))
  expected <- seq_len(nrow(field_table))
  if (!identical(as.integer(field_table$latent_row[order_index]), expected)) {
    stop(label, " field latent rows are not a complete one-based sequence.")
  }
  values <- as.numeric(field_table$mean[order_index])
  if (any(!is.finite(values))) stop(label, " field posterior means are non-finite.")
  values
}

joint_inla_project_field_matrix <- function(field_table, n_groups, label) {
  vector <- joint_inla_project_spatial_field_vector(field_table, label)
  mesh_node <- as.integer(field_table$mesh_node)
  group <- as.integer(field_table$group_index)
  if (anyNA(mesh_node) || anyNA(group) || any(mesh_node < 1L) || any(group < 1L | group > n_groups)) {
    stop(label, " field support contains invalid mesh-node/group indices.")
  }
  n_spde <- max(mesh_node)
  if (anyDuplicated(paste(mesh_node, group, sep = "|"))) stop(label, " field support has duplicate mesh-node/group rows.")
  if (length(mesh_node) != n_spde * n_groups || !identical(sort(unique(group)), seq_len(n_groups))) {
    stop(label, " field support does not cover every mesh-node/group combination.")
  }
  out <- matrix(NA_real_, nrow = n_spde, ncol = n_groups)
  out[cbind(mesh_node, group)] <- vector
  if (anyNA(out)) stop(label, " field support has missing mesh-node/group means.")
  out
}

joint_inla_project_spatial_contribution <- function(A, field_table, label = "SPDE field") {
  if (is.null(dim(A)) || ncol(A) != nrow(field_table)) {
    stop(label, " projection matrix has incompatible dimensions.")
  }
  as.numeric(A %*% joint_inla_project_spatial_field_vector(field_table, label))
}

joint_inla_project_admin_contribution <- function(data, admin_table, admin_f_column = "admin_f", allow_unseen_zero = FALSE) {
  joint_inla_project_require_columns(data, admin_f_column, "administrative prediction data")
  position <- match(as.character(data[[admin_f_column]]), as.character(admin_table$model_index))
  unseen <- is.na(position)
  if (any(unseen) && !isTRUE(allow_unseen_zero)) {
    stop("Prediction/response data contains administrative levels without fitted admin_f support: ",
         paste(unique(as.character(data[[admin_f_column]][unseen])), collapse = ", "),
         ". Explicitly authorize zero posterior-mean handling to continue.")
  }
  contribution <- rep(0, nrow(data))
  contribution[!unseen] <- admin_table$mean[position[!unseen]]
  list(
    contribution = contribution,
    fitted = !unseen,
    source = ifelse(unseen, "unseen_level_zero_mean", "fitted_summary_random")
  )
}

joint_inla_project_cattle_contribution <- function(data, mapping, cattle_table, support_data = NULL) {
  q_column <- unname(mapping[["cattle_q"]])
  weight_column <- unname(mapping[["cattle_mid_log1p"]])
  joint_inla_project_require_columns(data, c(q_column, weight_column), "cattle RW2 prediction data")
  q <- as.integer(data[[q_column]])
  weight <- as.numeric(data[[weight_column]])
  if (anyNA(q) || any(!is.finite(weight))) stop("Cattle RW2 indices or cattle_mid_log1p weights are non-finite.")
  if (!is.null(support_data)) {
    joint_inla_project_require_columns(support_data, c(q_column, weight_column), "cattle RW2 support data")
    support_q <- as.integer(support_data[[q_column]])
    support_weight <- as.numeric(support_data[[weight_column]])
    for (level in sort(unique(support_q))) {
      values <- support_weight[support_q == level]
      if (!length(values) || any(!is.finite(values)) || max(values) - min(values) > 1e-12) {
        stop("cattle_mid_log1p is not a unique finite support weight for cattle_q=", level, ".")
      }
    }
  }
  random_mean <- joint_inla_project_random_lookup(cattle_table, q, "cattle_q")
  contribution <- weight * random_mean
  if (any(!is.finite(contribution))) stop("Cattle RW2 contribution is non-finite.")
  data.frame(
    cattle_q = q,
    cattle_mid_log1p = weight,
    cattle_random_mean = random_mean,
    cattle_rw2_contribution = contribution,
    stringsAsFactors = FALSE
  )
}

joint_inla_project_assemble_tier1 <- function(data, components, spatial_contribution, allow_unseen_admin_zero = FALSE) {
  mapping <- components$mapping$tier1
  fixed <- joint_inla_project_fixed_contributions(data, components$fixed, mapping, "intercept1", "tier1")
  week_column <- unname(mapping[["week_steps"]])
  week <- joint_inla_project_random_lookup(components$random$week_steps, data[[week_column]], "week_steps")
  admin <- joint_inla_project_admin_contribution(data, components$random$admin_f, mapping[["admin_f"]], allow_unseen_admin_zero)
  out <- cbind(fixed, data.frame(
    week_contribution = week,
    admin_contribution = admin$contribution,
    admin_effect_fitted = admin$fitted,
    admin_effect_source = admin$source,
    spatial_contribution = as.numeric(spatial_contribution),
    stringsAsFactors = FALSE
  ))
  out$component_sum <- out$fixed_total + out$week_contribution + out$admin_contribution + out$spatial_contribution
  out
}

joint_inla_project_assemble_tier2 <- function(data, components, spatial_contribution, copy_contribution) {
  mapping <- components$mapping$tier2
  fixed <- joint_inla_project_fixed_contributions(data, components$fixed, mapping, "intercept2", "tier2")
  week_column <- unname(mapping[["tier2_week"]])
  week <- joint_inla_project_random_lookup(components$random$tier2_week, data[[week_column]], "tier2_week")
  cattle <- joint_inla_project_cattle_contribution(data, mapping, components$random$cattle_q, components$cattle_support)
  out <- cbind(fixed, data.frame(
    week_contribution = week,
    cattle_q = cattle$cattle_q,
    cattle_mid_log1p = cattle$cattle_mid_log1p,
    cattle_random_mean = cattle$cattle_random_mean,
    cattle_rw2_contribution = cattle$cattle_rw2_contribution,
    spatial_contribution = as.numeric(spatial_contribution),
    copy_spatial_contribution = as.numeric(copy_contribution),
    stringsAsFactors = FALSE
  ))
  out$component_sum <- out$fixed_total + out$week_contribution + out$cattle_rw2_contribution +
    out$spatial_contribution + out$copy_spatial_contribution
  out
}

joint_inla_project_prepare_components <- function(build, fit_artifact, stage2) {
  joint_inla_project_require_extract()
  fixed <- joint_inla_project_fixed_means(fit_artifact)
  mapping <- list(
    tier1 = joint_inla_project_mapping(build, "tier1"),
    tier2 = joint_inla_project_mapping(build, "tier2")
  )
  random <- list(
    week_steps = joint_inla_project_random_table(fit_artifact, "week_steps"),
    admin_f = joint_inla_project_random_table(fit_artifact, "admin_f"),
    tier2_week = joint_inla_project_random_table(fit_artifact, "tier2_week"),
    cattle_q = joint_inla_project_random_table(fit_artifact, "cattle_q")
  )
  fields <- joint_inla_extract_spde_fields(build, fit_artifact)
  n_groups <- max(c(fields$tier1_field$group_index, fields$tier2_field$group_index, fields$tier2_copy_field$group_index))
  if (!is.finite(n_groups) || n_groups < 1L || any(vapply(fields, function(x) max(x$group_index) != n_groups, logical(1L)))) {
    stop("SPDE field group supports are inconsistent.")
  }
  admin_mapping <- stage2$admin_mapping
  if (is.null(admin_mapping) || !is.data.frame(admin_mapping) || !all(c("admin_f", "admin_u") %in% names(admin_mapping))) {
    stop("Stage 2 admin_mapping must be a data frame containing admin_u and admin_f.")
  }
  if (is.null(stage2$tier2) || !is.data.frame(stage2$tier2)) stop("Stage 2 artifact must contain the Tier 2 table for cattle support validation.")
  list(
    fixed = fixed, mapping = mapping, random = random, fields = fields,
    cattle_support = stage2$tier2, admin_mapping = admin_mapping,
    n_groups = as.integer(n_groups), grouping_variable = "quarter_index",
    formula = if (!is.null(build$formula)) paste(deparse(build$formula), collapse = " ") else NA_character_
  )
}

joint_inla_project_reconstruct_response <- function(build, fit_artifact, stage2, components,
                                                    fitted_values = NULL, rows = NULL,
                                                    allow_unseen_admin_zero = FALSE) {
  if (is.null(fitted_values)) fitted_values <- joint_inla_extract_fitted_values(build, fit_artifact, stage2)
  stack_indices <- joint_inla_stack_indices(build)
  if (is.null(rows)) rows <- lapply(stack_indices, seq_along)
  if (!is.list(rows) || !all(c("tier1", "tier2") %in% names(rows))) stop("rows must be a named tier1/tier2 list.")
  results <- vector("list", 2L)
  names(results) <- c("tier1", "tier2")
  for (tier in names(results)) {
    source <- stage2[[tier]]
    selected <- as.integer(rows[[tier]])
    if (!length(selected) || anyNA(selected) || any(selected < 1L | selected > nrow(source))) stop("Invalid selected response rows for ", tier, ".")
    stack_rows <- stack_indices[[tier]][selected]
    data <- source[selected, , drop = FALSE]
    A <- build$A[[tier]][selected, , drop = FALSE]
    if (tier == "tier1") {
      spatial <- joint_inla_project_spatial_contribution(A, components$fields$tier1_field, "Tier 1")
      assembled <- joint_inla_project_assemble_tier1(data, components, spatial, allow_unseen_admin_zero)
    } else {
      spatial <- joint_inla_project_spatial_contribution(A, components$fields$tier2_field, "Tier 2")
      copy <- joint_inla_project_spatial_contribution(A, components$fields$tier2_copy_field, "Tier 2 copy")
      assembled <- joint_inla_project_assemble_tier2(data, components, spatial, copy)
    }
    target <- fitted_values[stack_rows, , drop = FALSE]
    assembled$tier <- tier
    assembled$stack_row <- stack_rows
    assembled$source_row <- selected
    assembled$output_id <- target$output_id
    assembled$linear_predictor_mean <- as.numeric(target$linear_predictor_mean)
    assembled$difference <- assembled$component_sum - assembled$linear_predictor_mean
    results[[tier]] <- assembled
  }
  columns <- unique(unlist(lapply(results, names), use.names = FALSE))
  results <- lapply(results, function(data) {
    missing <- setdiff(columns, names(data))
    for (column in missing) data[[column]] <- NA
    data[, columns, drop = FALSE]
  })
  do.call(rbind, results)
}

joint_inla_project_stratified_rows <- function(data, grouping_variable = "quarter_index", target = 10000L) {
  if (!is.data.frame(data) || !nrow(data)) return(integer())
  strata <- list(
    group = if (grouping_variable %in% names(data)) as.character(data[[grouping_variable]]) else rep("all", nrow(data)),
    timestep = if ("timestep" %in% names(data)) as.character(data$timestep) else rep("all", nrow(data)),
    training = if ("response_training" %in% names(data)) ifelse(is.na(data$response_training), "missing", "active") else rep("all", nrow(data)),
    holdout = if ("is_test_point" %in% names(data)) ifelse(data$is_test_point %in% TRUE, "holdout", "not_holdout") else rep("all", nrow(data)),
    admin = if ("admin_f" %in% names(data)) as.character(data$admin_f) else rep("all", nrow(data)),
    cattle = if ("cattle_q" %in% names(data)) as.character(data$cattle_q) else rep("all", nrow(data))
  )
  index <- seq_len(nrow(data))
  selected <- unique(unlist(lapply(strata, function(value) {
    split_index <- split(index, value, drop = TRUE)
    vapply(split_index, min, integer(1L))
  }), use.names = FALSE))
  remaining <- setdiff(index, selected)
  if (length(selected) < target && length(remaining)) {
    take <- min(length(remaining), as.integer(target) - length(selected))
    selected <- c(selected, remaining[seq_len(take)])
  }
  sort(unique(selected))
}

joint_inla_project_reconstruction_metrics <- function(manual, fitted_values, n_worst = 20L,
                                                     tolerances = c(rmse = 1e-8, median_abs = 1e-10, max_abs = 1e-6)) {
  if (!all(c("tier", "stack_row", "component_sum", "difference") %in% names(manual))) stop("Manual reconstruction lacks comparison columns.")
  tiers <- c("tier1", "tier2")
  audits <- vector("list", length(tiers))
  worst <- vector("list", length(tiers))
  for (i in seq_along(tiers)) {
    tier <- tiers[[i]]
    rows <- manual$tier == tier
    error <- manual$difference[rows]
    abs_error <- abs(error)
    finite <- is.finite(error)
    if (!all(finite)) stop("Non-finite reconstruction discrepancy in ", tier, ".")
    order_index <- order(abs_error, decreasing = TRUE)
    selected <- which(rows)[head(order_index, as.integer(n_worst))]
    worst[[i]] <- manual[selected, , drop = FALSE]
    audits[[i]] <- data.frame(
      tier = tier, n = sum(rows), mean_signed_error = mean(error), mean_absolute_error = mean(abs_error),
      rmse = sqrt(mean(error^2)), median_absolute_error = stats::median(abs_error),
      q95_absolute_error = as.numeric(stats::quantile(abs_error, 0.95, names = FALSE, type = 7)),
      q99_absolute_error = as.numeric(stats::quantile(abs_error, 0.99, names = FALSE, type = 7)),
      maximum_absolute_error = max(abs_error),
      pass_rmse = sqrt(mean(error^2)) <= tolerances[["rmse"]],
      pass_median_abs = stats::median(abs_error) <= tolerances[["median_abs"]],
      pass_max_abs = max(abs_error) <= tolerances[["max_abs"]],
      stringsAsFactors = FALSE
    )
  }
  audit <- do.call(rbind, audits)
  list(audit = audit, worst_rows = do.call(rbind, worst), pass = all(audit$pass_rmse & audit$pass_median_abs & audit$pass_max_abs))
}

joint_inla_project_prediction_grid_contract <- function(stage2, build, expected_rows = 1669395L, expected_weeks = 105L, components = NULL) {
  grid <- stage2$prediction_grid
  if (!is.data.frame(grid)) stop("Stage 2 prediction_grid must be a data frame.")
  if (!is.null(expected_rows) && nrow(grid) != as.integer(expected_rows)) stop("Prediction-grid row count is ", nrow(grid), "; expected ", expected_rows, ".")
  id_column <- c("space_time_id", ".row_id")[c("space_time_id", ".row_id") %in% names(grid)][1L]
  if (is.na(id_column) || anyDuplicated(as.character(grid[[id_column]]))) stop("Prediction grid must contain a unique stable space-time row ID.")
  mapping <- list(tier1 = joint_inla_project_mapping(build, "tier1"), tier2 = joint_inla_project_mapping(build, "tier2"))
  required <- unique(c(id_column, "cell_id", "x", "y", "epiyear", "epiweek", "time_index", "timestep", "quarter_index", "admin_u", "admin_f", unname(mapping$tier1), unname(mapping$tier2)))
  required <- required[nzchar(required)]
  joint_inla_project_require_columns(grid, required, "Stage 2 prediction_grid")
  numeric_required <- setdiff(required, c(id_column, "admin_u"))
  nonfinite <- vapply(grid[numeric_required], function(x) sum(!is.finite(as.numeric(x))), integer(1L))
  if (any(nonfinite > 0L)) stop("Prediction grid contains non-finite required predictors: ", paste(names(nonfinite)[nonfinite > 0L], collapse = ", "))
  groups <- as.integer(grid$quarter_index)
  n_groups <- max(as.integer(build$fields$tier1$tier1_field.group))
  if (any(groups < 1L | groups > n_groups)) stop("Prediction-grid spatial groups exceed fitted field support.")
  times <- as.integer(grid$timestep)
  if (!is.null(components)) {
    supported_tier1 <- as.character(components$random$week_steps$model_index)
    supported_tier2 <- as.character(components$random$tier2_week$model_index)
    if (any(!as.character(times) %in% supported_tier1) || any(!as.character(times) %in% supported_tier2)) {
      stop("Prediction-grid timestep is outside fitted week_steps/tier2_week support.")
    }
  }
  weeks <- unique(paste(grid$epiyear, grid$epiweek, sep = "-W"))
  if (length(weeks) != as.integer(expected_weeks)) stop("Prediction grid has ", length(weeks), " weeks; expected ", expected_weeks, ".")
  cell_coordinate <- unique(grid[c("cell_id", "x", "y")])
  if (anyDuplicated(cell_coordinate$cell_id)) stop("Each cell_id must map to one prediction coordinate.")
  list(
    id_column = id_column, required_columns = required, nonfinite_counts = nonfinite,
    n_rows = nrow(grid), n_weeks = length(weeks), n_cells = nrow(cell_coordinate),
    weeks = weeks, spatial_groups = sort(unique(groups)), temporal_support = sort(unique(times)),
    cells = cell_coordinate
  )
}

joint_inla_project_mesh <- function(build) {
  candidates <- list(build$mesh, build$spde$tier1$mesh, build$spde$tier2$mesh)
  candidates <- candidates[!vapply(candidates, is.null, logical(1L))]
  if (!length(candidates)) stop("The Stage 3A artifact does not expose a mesh for prediction projection.")
  candidates[[1L]]
}

joint_inla_project_validate_spatial_projector <- function(build, stage2, components, tolerance = 1e-10) {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required to construct the validated spatial projector.")
  mesh <- joint_inla_project_mesh(build)
  checks <- list()
  for (tier in c("tier1", "tier2")) {
    source <- stage2[[tier]]
    coords <- unique(source[c("x", "y")])
    key <- paste(source$x, source$y, sep = "|")
    coord_key <- paste(coords$x, coords$y, sep = "|")
    A_cell <- INLA::inla.spde.make.A(mesh, loc = as.matrix(coords))
    group <- as.integer(source$quarter_index)
    cell <- match(key, coord_key)
    field_names <- if (tier == "tier1") c("tier1_field") else c("tier2_field", "tier2_copy_field")
    for (field_name in field_names) {
      field_table <- components$fields[[field_name]]
      matrix_mean <- joint_inla_project_field_matrix(field_table, components$n_groups, field_name)
      projected_cells <- as.matrix(A_cell %*% matrix_mean)
      projected <- projected_cells[cbind(cell, group)]
      A_direct <- build$A[[tier]]
      direct <- joint_inla_project_spatial_contribution(A_direct, field_table, field_name)
      difference <- projected - direct
      checks[[length(checks) + 1L]] <- data.frame(
        tier = tier, field = field_name, n = nrow(source), unique_coordinates = nrow(coords),
        max_absolute_difference = max(abs(difference)), pass = max(abs(difference)) <= tolerance,
        stringsAsFactors = FALSE
      )
    }
  }
  audit <- do.call(rbind, checks)
  list(audit = audit, pass = all(audit$pass), mesh = mesh)
}

joint_inla_project_prediction <- function(stage2, build, components, spatial_validation,
                                          allow_unseen_admin_zero = FALSE,
                                          expected_rows = 1669395L, expected_weeks = 105L) {
  if (!isTRUE(spatial_validation$pass)) stop("Spatial projection validation failed; dense-grid prediction is forbidden.")
  contract <- joint_inla_project_prediction_grid_contract(stage2, build, expected_rows, expected_weeks, components)
  grid <- stage2$prediction_grid
  A_cell <- INLA::inla.spde.make.A(spatial_validation$mesh, loc = as.matrix(contract$cells[c("x", "y")]))
  cell <- match(as.character(grid$cell_id), as.character(contract$cells$cell_id))
  group <- as.integer(grid$quarter_index)
  if (anyNA(cell) || anyNA(group)) stop("Prediction grid cell/group mapping is incomplete.")
  fields <- list(
    tier1_field = as.matrix(A_cell %*% joint_inla_project_field_matrix(components$fields$tier1_field, components$n_groups, "tier1_field")),
    tier2_field = as.matrix(A_cell %*% joint_inla_project_field_matrix(components$fields$tier2_field, components$n_groups, "tier2_field")),
    tier2_copy_field = as.matrix(A_cell %*% joint_inla_project_field_matrix(components$fields$tier2_copy_field, components$n_groups, "tier2_copy_field"))
  )
  spatial1 <- fields$tier1_field[cbind(cell, group)]
  spatial2 <- fields$tier2_field[cbind(cell, group)]
  copy <- fields$tier2_copy_field[cbind(cell, group)]
  tier1 <- joint_inla_project_assemble_tier1(grid, components, spatial1, allow_unseen_admin_zero)
  tier2 <- joint_inla_project_assemble_tier2(grid, components, spatial2, copy)
  id_column <- contract$id_column
  out <- grid[c(id_column, intersect(c(".row_id", "space_time_id", "cell_id", "x", "y", "epiyear", "epiweek", "week_start", "time_index", "timestep", "quarter_index", "admin_u", "admin_f"), names(grid))), drop = FALSE]
  out$spatial_group_index <- group
  out$admin_effect_source <- tier1$admin_effect_source
  out$admin_effect_fitted <- tier1$admin_effect_fitted
  out$eta1_mean <- tier1$component_sum
  out$tier1_probability_plugin <- stats::plogis(out$eta1_mean)
  out$eta2_mean <- tier2$component_sum
  out$tier2_intensity_plugin <- exp(out$eta2_mean)
  if ("terrestrial_area_km2" %in% names(grid)) {
    exposure <- as.numeric(grid$terrestrial_area_km2)
    if (any(!is.finite(exposure) | exposure < 0)) stop("Canonical terrestrial prediction-cell exposure is non-finite or negative.")
    out$expected_count_plugin <- out$tier2_intensity_plugin * exposure
    if (any(!is.finite(out$expected_count_plugin))) stop("expected_count_plugin is non-finite.")
  }
  if (any(!is.finite(out$eta1_mean)) || any(!is.finite(out$eta2_mean))) stop("Projected linear predictors contain non-finite values.")
  if (any(!is.finite(out$tier1_probability_plugin) | out$tier1_probability_plugin < 0 | out$tier1_probability_plugin > 1)) stop("Tier 1 plug-in probabilities are invalid.")
  if (any(!is.finite(out$tier2_intensity_plugin) | out$tier2_intensity_plugin <= 0)) stop("Tier 2 plug-in intensities are invalid.")
  output_validation <- joint_inla_project_validate_prediction_output(out, grid, contract)
  if (!isTRUE(output_validation$pass)) stop("Projected prediction-grid output failed its row/key/weekly invariants.")
  list(predictions = out, contract = contract, fields = fields, output_validation = output_validation,
       expected_count_generated = "expected_count_plugin" %in% names(out))
}

joint_inla_project_validate_prediction_output <- function(output, source_grid, contract) {
  id_column <- contract$id_column
  checks <- list()
  add <- function(check, status, observed, expected, details) {
    checks[[length(checks) + 1L]] <<- data.frame(section = "prediction", check = check, status = status,
                                                 observed = as.character(observed), expected = as.character(expected),
                                                 details = details, stringsAsFactors = FALSE)
  }
  add("row_count", if (nrow(output) == nrow(source_grid)) "PASS" else "FAIL", nrow(output), nrow(source_grid), "Projected rows equal the Stage 2 prediction-grid rows.")
  add("stable_key_set", if (setequal(as.character(output[[id_column]]), as.character(source_grid[[id_column]]))) "PASS" else "FAIL", length(unique(output[[id_column]])), length(unique(source_grid[[id_column]])), "No prediction row was lost or duplicated.")
  output_week <- paste(output$epiyear, output$epiweek, sep = "-W")
  source_week <- paste(source_grid$epiyear, source_grid$epiweek, sep = "-W")
  add("week_count", if (length(unique(output_week)) == contract$n_weeks) "PASS" else "FAIL", length(unique(output_week)), contract$n_weeks, "All Stage 2 weeks are represented.")
  add("global_duplicate_row_id", if (!anyDuplicated(output[[id_column]])) "PASS" else "FAIL", anyDuplicated(output[[id_column]]), 0L, "Stable space-time row IDs are unique.")
  add("finite_coordinates", if (all(is.finite(output$x) & is.finite(output$y))) "PASS" else "FAIL", sum(!is.finite(output$x) | !is.finite(output$y)), 0L, "All projected coordinates are finite.")
  add("finite_eta1", if (all(is.finite(output$eta1_mean))) "PASS" else "FAIL", sum(!is.finite(output$eta1_mean)), 0L, "Tier 1 posterior-mean linear predictors are finite.")
  add("finite_eta2", if (all(is.finite(output$eta2_mean))) "PASS" else "FAIL", sum(!is.finite(output$eta2_mean)), 0L, "Tier 2 posterior-mean linear predictors are finite.")
  add("probability_range", if (all(is.finite(output$tier1_probability_plugin) & output$tier1_probability_plugin >= 0 & output$tier1_probability_plugin <= 1)) "PASS" else "FAIL", sum(!is.finite(output$tier1_probability_plugin) | output$tier1_probability_plugin < 0 | output$tier1_probability_plugin > 1), 0L, "Tier 1 plug-in probabilities are in [0, 1].")
  add("intensity_positive", if (all(is.finite(output$tier2_intensity_plugin) & output$tier2_intensity_plugin > 0)) "PASS" else "FAIL", sum(!is.finite(output$tier2_intensity_plugin) | output$tier2_intensity_plugin <= 0), 0L, "Tier 2 plug-in intensities are finite and positive.")
  group <- as.integer(output$spatial_group_index)
  add("spatial_group_support", if (all(is.finite(group) & group >= 1L & group <= max(contract$spatial_groups))) "PASS" else "FAIL", paste(sort(unique(group)), collapse = ","), paste(contract$spatial_groups, collapse = ","), "Spatial-group mapping remains within fitted support.")
  expected_counts <- table(source_week)
  output_counts <- table(output_week)
  if (!identical(sort(names(expected_counts)), sort(names(output_counts)))) {
    add("weekly_key_support", "FAIL", paste(sort(names(output_counts)), collapse = ","), paste(sort(names(expected_counts)), collapse = ","), "Weekly output support equals Stage 2 support.")
  } else {
    weekly <- lapply(sort(names(expected_counts)), function(key) {
      rows <- output_week == key
      source_rows <- source_week == key
      data.frame(
        section = "weekly", check = c("weekly_row_count", "weekly_cell_id_unique", "weekly_row_id_unique", "weekly_coordinates_finite", "weekly_eta1_finite", "weekly_eta2_finite"),
        status = c(
          if (sum(rows) == sum(source_rows)) "PASS" else "FAIL",
          if (!anyDuplicated(output$cell_id[rows])) "PASS" else "FAIL",
          if (!anyDuplicated(output[[id_column]][rows])) "PASS" else "FAIL",
          if (all(is.finite(output$x[rows]) & is.finite(output$y[rows]))) "PASS" else "FAIL",
          if (all(is.finite(output$eta1_mean[rows]))) "PASS" else "FAIL",
          if (all(is.finite(output$eta2_mean[rows]))) "PASS" else "FAIL"
        ),
        observed = c(sum(rows), anyDuplicated(output$cell_id[rows]), anyDuplicated(output[[id_column]][rows]), sum(!is.finite(output$x[rows]) | !is.finite(output$y[rows])), sum(!is.finite(output$eta1_mean[rows])), sum(!is.finite(output$eta2_mean[rows]))),
        expected = c(sum(source_rows), 0L, 0L, 0L, 0L, 0L),
        details = paste0("week=", key), stringsAsFactors = FALSE
      )
    })
    checks <- c(checks, weekly)
  }
  audit <- do.call(rbind, checks)
  list(audit = audit, pass = all(audit$status == "PASS"))
}

joint_inla_project_admin_audit <- function(grid, admin_table, admin_f_column = "admin_f", id_column = NULL, admin_mapping = NULL) {
  if (is.null(id_column)) id_column <- c("space_time_id", ".row_id")[c("space_time_id", ".row_id") %in% names(grid)][1L]
  fitted <- as.character(admin_table$model_index)
  grid_levels <- unique(as.character(grid[[admin_f_column]]))
  unseen <- setdiff(grid_levels, fitted)
  rows <- as.character(grid[[admin_f_column]]) %in% unseen
  mapping_levels <- if (!is.null(admin_mapping) && "admin_f" %in% names(admin_mapping)) unique(as.character(admin_mapping$admin_f)) else grid_levels
  labels <- unseen
  if (!is.null(admin_mapping) && all(c("admin_f", "admin_u") %in% names(admin_mapping)) && length(unseen)) {
    labels <- paste0("admin_f=", unseen, ";admin_u=", as.character(admin_mapping$admin_u[match(unseen, as.character(admin_mapping$admin_f))]))
  }
  data.frame(
    check = c("total_mapping_levels", "fitted_levels", "prediction_only_levels", "prediction_rows_affected", "prediction_cells_affected", "prediction_weeks_affected", "prediction_only_admin_ids"),
    observed = c(length(mapping_levels), length(fitted), length(unseen), sum(rows), length(unique(grid$cell_id[rows])), length(unique(paste(grid$epiyear[rows], grid$epiweek[rows], sep = "-W"))), paste(labels, collapse = ",")),
    status = ifelse(c(TRUE, TRUE, length(unseen) == 0L, TRUE, TRUE, TRUE, TRUE), "PASS", "WARNING"),
    stringsAsFactors = FALSE
  )
}

joint_inla_project_distribution <- function(values, tier, measure, scope, week = NA_character_) {
  values <- as.numeric(values)
  finite <- is.finite(values)
  if (!any(finite)) {
    return(data.frame(tier = tier, measure = measure, scope = scope, week = week, n = length(values), minimum = NA_real_, Q01 = NA_real_, Q05 = NA_real_, Q25 = NA_real_, median = NA_real_, mean = NA_real_, Q75 = NA_real_, Q95 = NA_real_, Q99 = NA_real_, maximum = NA_real_, nonfinite = sum(!finite), stringsAsFactors = FALSE))
  }
  q <- stats::quantile(values[finite], c(.01, .05, .25, .5, .75, .95, .99), names = FALSE, type = 7)
  data.frame(tier = tier, measure = measure, scope = scope, week = week, n = length(values), minimum = min(values[finite]), Q01 = q[[1L]], Q05 = q[[2L]], Q25 = q[[3L]], median = q[[4L]], mean = mean(values[finite]), Q75 = q[[5L]], Q95 = q[[6L]], Q99 = q[[7L]], maximum = max(values[finite]), nonfinite = sum(!finite), stringsAsFactors = FALSE)
}

joint_inla_project_response_scale_diagnostic <- function(manual, fitted_values) {
  out <- manual[c("tier", "stack_row", "component_sum", "linear_predictor_mean")]
  fitted <- fitted_values[out$stack_row, , drop = FALSE]
  out$plugin <- ifelse(out$tier == "tier1", stats::plogis(out$component_sum), exp(out$component_sum))
  out$inla_fitted_mean <- as.numeric(fitted$fitted_mean)
  out$diagnostic_difference <- out$plugin - out$inla_fitted_mean
  out
}

joint_inla_project_hash_file <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE) || !file.exists(path)) return(NA_character_)
  digest::digest(file = path, algo = "sha256")
}

joint_inla_project_write_outputs <- function(reconstruction, prediction, spatial_validation, components,
                                            output_dir, run_id = "20725437", overwrite = FALSE,
                                            input_paths = list(), response_scale = NULL) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  weekly_dir <- file.path(output_dir, "weekly")
  dir.create(weekly_dir, recursive = TRUE, showWarnings = FALSE)
  reconstruction_audit_path <- file.path(output_dir, paste0("linear_predictor_reconstruction_audit_", run_id, ".csv"))
  reconstruction_worst_path <- file.path(output_dir, paste0("linear_predictor_reconstruction_worst_rows_", run_id, ".csv"))
  prediction_audit_path <- file.path(output_dir, paste0("prediction_projection_audit_", run_id, ".csv"))
  manifest_path <- file.path(output_dir, paste0("prediction_projection_manifest_", run_id, ".csv"))
  metadata_path <- file.path(output_dir, paste0("prediction_projection_metadata_", run_id, ".rds"))
  distribution_path <- file.path(output_dir, paste0("prediction_projection_distributions_", run_id, ".csv"))
  paths <- c(reconstruction_audit = reconstruction_audit_path, reconstruction_worst = reconstruction_worst_path,
             prediction_audit = prediction_audit_path, manifest = manifest_path, metadata = metadata_path, distributions = distribution_path)
  if (!isTRUE(overwrite) && any(file.exists(paths))) stop("Refusing to overwrite existing Phase 2 output(s): ", paste(paths[file.exists(paths)], collapse = ", "))
  utils::write.csv(reconstruction$audit, reconstruction_audit_path, row.names = FALSE, na = "")
  utils::write.csv(reconstruction$worst_rows, reconstruction_worst_path, row.names = FALSE, na = "")
  utils::write.csv(spatial_validation$audit, prediction_audit_path, row.names = FALSE, na = "")
  predictions <- prediction$predictions
  week_key <- paste(predictions$epiyear, predictions$epiweek, sep = "-W")
  keys <- unique(week_key)
  manifest <- do.call(rbind, lapply(keys, function(key) {
    rows <- which(week_key == key)
    year <- as.integer(predictions$epiyear[rows[[1L]]]); week <- as.integer(predictions$epiweek[rows[[1L]]])
    filename <- sprintf("prediction_y%04d_w%02d.rds", year, week)
    target <- file.path(weekly_dir, filename)
    if (file.exists(target) && !isTRUE(overwrite)) stop("Refusing to overwrite existing weekly output: ", target)
    saveRDS(predictions[rows, , drop = FALSE], target)
    data.frame(week = key, epiyear = year, epiweek = week, rows = length(rows), path = normalizePath(target, mustWork = FALSE), sha256 = joint_inla_project_hash_file(target), stringsAsFactors = FALSE)
  }))
  utils::write.csv(manifest, manifest_path, row.names = FALSE, na = "")
  distributions <- do.call(rbind, c(
    lapply(c("eta1_mean", "tier1_probability_plugin"), function(column) joint_inla_project_distribution(predictions[[column]], "tier1", column, "overall")),
    lapply(c("eta2_mean", "tier2_intensity_plugin"), function(column) joint_inla_project_distribution(predictions[[column]], "tier2", column, "overall")),
    lapply(keys, function(key) {
      rows <- week_key == key
      rbind(
        joint_inla_project_distribution(predictions$eta1_mean[rows], "tier1", "eta1_mean", "weekly", key),
        joint_inla_project_distribution(predictions$tier1_probability_plugin[rows], "tier1", "tier1_probability_plugin", "weekly", key),
        joint_inla_project_distribution(predictions$eta2_mean[rows], "tier2", "eta2_mean", "weekly", key),
        joint_inla_project_distribution(predictions$tier2_intensity_plugin[rows], "tier2", "tier2_intensity_plugin", "weekly", key)
      )
    })
  ))
  utils::write.csv(distributions, distribution_path, row.names = FALSE, na = "")
  audit <- rbind(
    data.frame(section = "reconstruction", check = "linear_predictor_identity", status = if (reconstruction$pass) "PASS" else "FAIL", observed = if (reconstruction$pass) "all tolerances met" else "tolerance failure", expected = "RMSE<=1e-8; median_abs<=1e-10; max_abs<=1e-6", details = "Manual posterior-mean component sum compared with summary.linear.predictor$mean.", stringsAsFactors = FALSE),
    data.frame(section = "spatial", check = spatial_validation$audit$field, status = ifelse(spatial_validation$audit$pass, "PASS", "FAIL"), observed = spatial_validation$audit$max_absolute_difference, expected = "<=1e-10", details = "Unique-coordinate SPDE projector compared with response-row projection.", stringsAsFactors = FALSE),
    prediction$output_validation$audit
  )
  utils::write.csv(audit, prediction_audit_path, row.names = FALSE, na = "")
  metadata <- list(
    phase = "Phase 2 post-fit linear-predictor reconstruction and dense-grid projection",
    run_id = run_id, generated_utc = format(Sys.time(), tz = "UTC"), input_paths = input_paths,
    input_sha256 = lapply(input_paths, joint_inla_project_hash_file),
    reconstruction = list(audit = reconstruction$audit, pass = reconstruction$pass, method = "named fixed-effect means + mapped random-effect means + sparse SPDE projection", copy_field = "summary.random$tier2_copy_field posterior means projected independently", cattle_rw2 = "summary.random$cattle_q mean multiplied by row cattle_mid_log1p weight"),
    spatial_validation = spatial_validation$audit, prediction_output_validation = prediction$output_validation$audit,
    prediction = list(rows = nrow(predictions), weeks = length(keys), unique_cells = prediction$contract$n_cells, spatial_groups = prediction$contract$spatial_groups, expected_count_generated = prediction$expected_count_generated, fields_tier1 = c("eta1_mean", "tier1_probability_plugin"), fields_tier2 = c("eta2_mean", "tier2_intensity_plugin")),
    audit_summary = list(pass = sum(audit$status == "PASS"), warning = sum(audit$status == "WARNING"), fail = sum(audit$status == "FAIL")),
    response_scale_diagnostic = list(description = "Transform of posterior-mean eta compared descriptively with INLA fitted response means; not an identity gate.", generated = !is.null(response_scale)),
    scope = list(stage3b_refit = FALSE, inla_posterior_sample = FALSE, raster_surfaces = FALSE, biological_interpretation = FALSE),
    output_paths = paths
  )
  saveRDS(metadata, metadata_path)
  list(paths = paths, manifest = manifest, distributions = distributions, metadata = metadata)
}
