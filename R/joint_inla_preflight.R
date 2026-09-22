joint_inla_preflight_text <- function(value, missing = NA_character_) {
  if (is.null(value) || !length(value)) return(missing)
  if (length(value) == 1L && is.na(value)) return(missing)
  paste(as.character(value), collapse = ",")
}

joint_inla_preflight_class <- function(value) {
  classes <- class(value)
  if (is.null(classes) || !length(classes)) "<none>" else paste(classes, collapse = "|")
}

joint_inla_preflight_storage <- function(value) {
  tryCatch(storage.mode(value), error = function(e) "<unavailable>")
}

joint_inla_preflight_numeric_storage_ok <- function(value) {
  !is.null(value) && is.atomic(value) &&
    typeof(value) %in% c("integer", "double") &&
    is.numeric(value) && !is.factor(value) && !is.ordered(value) &&
    !is.character(value) && !is.logical(value) && !is.list(value)
}

joint_inla_preflight_integer_observed <- function(value, tolerance = sqrt(.Machine$double.eps)) {
  if (!joint_inla_preflight_numeric_storage_ok(value)) return(NA)
  finite <- value[is.finite(value)]
  if (!length(finite)) return(NA)
  all(abs(finite - round(finite)) <= tolerance)
}

joint_inla_preflight_covers_joint_rows <- function(value, n_rows) {
  !is.null(value) && length(n_rows) == 1L && !is.na(n_rows) && length(value) >= n_rows
}

joint_inla_preflight_active_rows <- function(Y, link, likelihood) {
  if (!is.matrix(Y) || ncol(Y) < likelihood || length(link) != nrow(Y)) {
    return(rep(FALSE, if (is.matrix(Y)) nrow(Y) else 0L))
  }
  !is.na(Y[, likelihood]) & link == likelihood
}

joint_inla_preflight_number <- function(value) {
  if (is.null(value) || !length(value)) return(NA_character_)
  if (any(!is.finite(value))) return(NA_character_)
  format(value, scientific = FALSE, trim = TRUE)
}

joint_inla_preflight_formula_fixed_names <- function(formula) {
  labels <- attr(stats::terms(formula), "term.labels")
  if (!length(labels)) return(character())
  is_random <- vapply(labels, function(label) {
    expression <- tryCatch(str2lang(label), error = function(e) NULL)
    is.call(expression) && identical(as.character(expression[[1L]]), "f")
  }, logical(1L))
  fixed_labels <- labels[!is_random]
  unique(unlist(lapply(fixed_labels, function(label) {
    expression <- tryCatch(str2lang(label), error = function(e) NULL)
    if (is.null(expression)) character() else all.vars(expression)
  }), use.names = FALSE))
}

joint_inla_preflight_theta_inventory <- function() {
  component_inventory <- paste(c(
    "tier1_field SPDE hyperparameters",
    "tier1_field group iid hyperparameter",
    "week_steps RW1 hyperparameter",
    "admin_f iid hyperparameter",
    "tier2_field SPDE hyperparameters",
    "tier2_field group iid hyperparameter",
    "tier2_copy_field copy coefficient",
    "tier2_week RW1 hyperparameter",
    "cattle_q RW2 hyperparameter",
    "any additional reference-model hyperparameter exposed by INLA"
  ), collapse = "; ")
  data.frame(
    position = seq_len(10L),
    assumed_label = paste0("historical_theta_", sprintf("%02d", seq_len(10L)), " (semantic label unverified)"),
    expected_model_components = component_inventory,
    assumed_order_note = "Retain historical INLA theta position; semantic order is not established from Stage 3A metadata.",
    order_verified = FALSE,
    stringsAsFactors = FALSE
  )
}

joint_inla_preflight_build <- function(build, build_path = NA_character_, expected_nspde = 13449L,
                                      expected_quarter_groups = 8L, expected_cattle_bins = 22L) {
  checks <- list()
  artifact_sha256 <- joint_inla_fit_hash_file(build_path)
  add_check <- function(section, check, status, observed, expected, details = "", metrics = list()) {
    metric_character <- function(name) {
      value <- metrics[[name]]
      if (is.null(value) || !length(value)) NA_character_ else as.character(value[[1L]])
    }
    metric_logical <- function(name) {
      value <- metrics[[name]]
      if (is.null(value) || !length(value)) NA else as.logical(value[[1L]])
    }
    metric_numeric <- function(name) {
      value <- metrics[[name]]
      if (is.null(value) || !length(value)) NA_real_ else as.numeric(value[[1L]])
    }
    checks[[length(checks) + 1L]] <<- data.frame(
      section = as.character(section), check = as.character(check), status = as.character(status),
      observed = joint_inla_preflight_text(observed), expected = joint_inla_preflight_text(expected),
      details = as.character(details), artifact_path = joint_inla_preflight_text(build_path),
      artifact_sha256 = artifact_sha256,
      source_column = metric_character("source_column"),
      class = metric_character("class"), typeof = metric_character("typeof"),
      storage_accepted = metric_logical("storage_accepted"),
      length_observed = metric_numeric("length_observed"),
      length_expected = metric_numeric("length_expected"),
      length_matches = metric_logical("length_matches"),
      integer_valued_required = metric_logical("integer_valued_required"),
      integer_valued_observed = metric_logical("integer_valued_observed"),
      minimum = metric_numeric("minimum"), maximum = metric_numeric("maximum"),
      unique_count = metric_numeric("unique_count"),
      range_contiguity = metric_character("range_contiguity"),
      active_finite_count = metric_numeric("active_finite_count"),
      active_nonfinite_count = metric_numeric("active_nonfinite_count"),
      stringsAsFactors = FALSE
    )
  }
  fail <- function(section, check, observed, expected, details, metrics = list()) add_check(section, check, "fail", observed, expected, details, metrics)
  pass <- function(section, check, observed, expected, details = "", metrics = list()) add_check(section, check, "pass", observed, expected, details, metrics)
  warn <- function(section, check, observed, expected, details, metrics = list()) add_check(section, check, "warning", observed, expected, details, metrics)

  if (!is.list(build)) {
    fail("artifact", "build_object", "not a list", "Stage 3A build list", "Cannot inspect the production artifact.")
    return(list(success = FALSE, audit = do.call(rbind, checks), theta_inventory = joint_inla_preflight_theta_inventory(),
                summary = list(failures = 1L, warnings = 0L)))
  }

  stack <- if (is.list(build$stacks)) build$stacks$joint else NULL
  data <- NULL
  A <- NULL
  stack_error <- NULL
  if (is.null(stack)) {
    fail("artifact", "stacks_joint", "missing", "stacks$joint", "The production joint stack is required.")
  } else {
    materialized <- tryCatch({
      joint_inla_fit_require_inla()
      list(data = INLA::inla.stack.data(stack), A = INLA::inla.stack.A(stack))
    }, error = function(error) {
      list(error = conditionMessage(error))
    })
    if (!is.null(materialized$error)) stack_error <- materialized$error
    else if (!is.null(materialized)) {
      data <- materialized$data
      A <- materialized$A
    }
    if (!is.null(stack_error)) fail("artifact", "joint_stack_materialization", stack_error, "materializable INLA stack", "Stage 3B cannot validate the production stack.")
    else pass("artifact", "joint_stack_materialization", "data and A materialized", "data and A materialized", "No model fit was called.")
  }

  Y <- if (is.list(data)) data$Y else NULL
  link <- if (is.list(data)) data$link else NULL
  E <- if (is.list(data)) data$e else NULL
  n_rows <- if (is.matrix(Y)) nrow(Y) else NA_integer_
  n_for_rep <- if (is.na(n_rows)) 0L else n_rows
  stack_row_count <- tryCatch({
    if (exists("inla.stack.nrow", envir = asNamespace("INLA"), inherits = FALSE)) INLA::inla.stack.nrow(stack) else NA_integer_
  }, error = function(error) NA_integer_)
  if (is.na(stack_row_count) && is.list(stack$data) && is.matrix(stack$data$Y)) stack_row_count <- nrow(stack$data$Y)
  if (is.na(stack_row_count) && is.matrix(Y)) stack_row_count <- nrow(Y)
  if (!is.na(n_rows) && !is.na(stack_row_count) && identical(as.integer(n_rows), as.integer(stack_row_count))) pass("response", "joint_stack_row_count", n_rows, stack_row_count, "Y has the same row count as the production joint stack.")
  else fail("response", "joint_stack_row_count", paste(n_rows, stack_row_count, sep = "/"), "Y rows equal joint stack rows", "Joint response row count does not match the underlying stack.")
  link_active <- if (!is.null(link) && length(link) == n_rows) link %in% c(1, 2) else rep(FALSE, n_for_rep)
  tier1_rows <- if (!is.null(link) && length(link) == n_rows) link == 1 else rep(FALSE, n_for_rep)
  tier2_rows <- if (!is.null(link) && length(link) == n_rows) link == 2 else rep(FALSE, n_for_rep)

  y_ok <- is.matrix(Y) && is.numeric(Y) && ncol(Y) == 2L
  if (y_ok) pass("response", "Y_shape_type", paste(typeof(Y), dim(Y), collapse = " x "), "numeric matrix with 2 columns", "Joint response matrix has the required shape.")
  else fail("response", "Y_shape_type", if (is.null(Y)) "missing" else paste(typeof(Y), dim(Y), collapse = " x "), "numeric matrix with 2 columns", "Y must be a numeric two-column matrix.")

  if (y_ok && !is.null(link)) {
    pass("response", "joint_row_count", nrow(Y), "nrow(Y) equals joint stack row count", "Y row count is defined by the materialized joint stack.")
  }
  y1 <- if (y_ok) Y[, 1L] else NULL
  y2 <- if (y_ok) Y[, 2L] else NULL
  y1_active <- if (y_ok) !is.na(y1) else logical()
  y2_active <- if (y_ok) !is.na(y2) else logical()
  tier1_active_rows <- if (y_ok) joint_inla_preflight_active_rows(Y, link, 1L) else rep(FALSE, n_for_rep)
  tier2_active_rows <- if (y_ok) joint_inla_preflight_active_rows(Y, link, 2L) else rep(FALSE, n_for_rep)
  observation_active <- y1_active | y2_active
  if (y_ok) {
    pass("response", "likelihood_1_non_na_count", sum(y1_active), "recorded", "Tier 1 response count.")
    pass("response", "likelihood_2_non_na_count", sum(y2_active), "recorded", "Tier 2 response count.")
    simultaneous <- sum(y1_active & y2_active)
    if (simultaneous == 0L) pass("response", "no_simultaneous_responses", simultaneous, 0L, "Likelihood responses are mutually exclusive by row.")
    else fail("response", "no_simultaneous_responses", simultaneous, 0L, "A joint row has both likelihood responses active.")
    invalid_y1 <- sum(y1_active & !(is.finite(y1) & y1 %in% c(0, 1)))
    if (invalid_y1 == 0L) pass("response", "tier1_binary_values", invalid_y1, 0L, "Tier 1 values are limited to 0/1/NA.")
    else fail("response", "tier1_binary_values", invalid_y1, 0L, "Tier 1 contains values outside 0/1/NA.")
    invalid_y2 <- sum(y2_active & !(is.finite(y2) & y2 > 0))
    if (invalid_y2 == 0L) pass("response", "tier2_positive_values", invalid_y2, 0L, "Active Tier 2 responses are finite and positive.")
    else fail("response", "tier2_positive_values", invalid_y2, 0L, "Active Tier 2 responses must be finite and > 0.")
  }

  link_ok <- is.numeric(link) && length(link) == n_rows && all(is.finite(link)) && all(link == as.integer(link)) && all(link %in% c(1, 2))
  if (link_ok) {
    pass("link_exposure", "link_type_values", paste(typeof(link), paste(sort(unique(link)), collapse = ",")), "integer-valued numeric with values 1/2", "Link values identify the two likelihood rows.")
    pass("link_exposure", "link_row_counts", paste(sum(tier1_rows), sum(tier2_rows), sep = "/"), "counts sum to joint row count", "Tier 1/Tier 2 link counts cover the joint stack.")
    wrong_link_active <- sum((y1_active & !tier1_rows) | (y2_active & !tier2_rows))
    if (wrong_link_active == 0L) pass("link_exposure", "link_response_alignment", wrong_link_active, 0L, "Active responses align with their likelihood link.")
    else fail("link_exposure", "link_response_alignment", wrong_link_active, 0L, "Active responses are assigned to the wrong likelihood link.")
  } else {
    fail("link_exposure", "link_type_values", if (is.null(link)) "missing" else paste(typeof(link), length(link)), "integer-valued numeric with values 1/2", "Link must be integer-valued and match Y rows.")
  }

  e_ok <- is.numeric(E) && length(E) == n_rows
  if (e_ok) pass("link_exposure", "exposure_length", length(E), n_rows, "Exposure vector matches joint response rows.")
  else fail("link_exposure", "exposure_length", if (is.null(E)) "missing" else length(E), n_rows, "E must have one value per joint response row.")
  if (e_ok && link_ok) {
    tier1_e_non_na <- sum(!is.na(E[tier1_rows]))
    if (tier1_e_non_na == 0L) pass("link_exposure", "tier1_exposure_semantics", "all NA", "all NA", "Tier 1 uses implicit binomial trials; E is explicitly all NA.")
    else fail("link_exposure", "tier1_exposure_semantics", tier1_e_non_na, 0L, "Tier 1 E values are not all NA; binomial exposure semantics are ambiguous.")
    invalid_e2 <- sum(tier2_rows & y2_active & !(is.finite(E) & E > 0))
    if (invalid_e2 == 0L) pass("link_exposure", "tier2_active_exposure", invalid_e2, 0L, "Active Tier 2 exposures are finite and positive.")
    else fail("link_exposure", "tier2_active_exposure", invalid_e2, 0L, "Active Tier 2 exposures must be finite and > 0.")
  }

  formula_env <- if (inherits(build$formula, "formula")) environment(build$formula) else NULL
  required_formula_objects <- c("spde_tier1", "spde_tier2", "pc_rw", "pc_rw_strong", "pc_rw_cat", "hyper_copy")
  if (is.null(formula_env)) {
    fail("formula_environment", "formula_environment_exists", "missing", "formula environment", "Cannot inspect required formula objects.")
  } else {
    pass("formula_environment", "formula_environment_exists", "present", "present", "Formula environment loaded.")
    for (name in required_formula_objects) {
      present <- exists(name, envir = formula_env, inherits = FALSE)
      if (present) pass("formula_environment", paste0("object_", name), joint_inla_preflight_class(get(name, envir = formula_env, inherits = FALSE)), "present", "Required formula-environment object.")
      else fail("formula_environment", paste0("object_", name), "missing", "present", "Required object is absent from the formula environment.")
    }
  }

  nspde_values <- c(
    tier1 = if (!is.null(build$spde$tier1$n.spde)) build$spde$tier1$n.spde else NA_integer_,
    tier2 = if (!is.null(build$spde$tier2$n.spde)) build$spde$tier2$n.spde else NA_integer_
  )
  for (tier in names(nspde_values)) {
    if (identical(as.integer(nspde_values[[tier]]), as.integer(expected_nspde))) pass("random_effects", paste0(tier, "_mesh_nspde"), nspde_values[[tier]], expected_nspde, "Production mesh vertex count.")
    else fail("random_effects", paste0(tier, "_mesh_nspde"), nspde_values[[tier]], expected_nspde, "Unexpected SPDE mesh vertex count.")
  }

  data_names <- if (is.list(data)) names(data) else character()
  tier1_fixed <- c("intercept1", "north", "road_dens", "night_illum")
  tier2_fixed <- c("intercept2", "mintemp", "soilmoist", "leafarea", "rhum", "cattle", "horses", "pigs", "goats", "sheep")
  fixed_names <- character()
  if (inherits(build$formula, "formula")) {
    fixed_names <- tryCatch(joint_inla_preflight_formula_fixed_names(build$formula), error = function(error) {
      fail("fixed_effects", "formula_fixed_term_extraction", conditionMessage(error), "extractable fixed terms", "Unable to identify fixed effects from the production formula.")
      character()
    })
    pass("fixed_effects", "formula_fixed_terms", paste(fixed_names, collapse = ","), "all fixed terms identified", "Random f() terms were excluded from fixed-column validation.")
  }
  for (name in fixed_names) {
    value <- if (name %in% data_names) data[[name]] else NULL
    expected_likelihood <- if (name %in% tier1_fixed) "tier1" else if (name %in% tier2_fixed) "tier2" else "both"
    active <- if (expected_likelihood == "tier1") tier1_active_rows else if (expected_likelihood == "tier2") tier2_active_rows else observation_active
    storage_ok <- joint_inla_preflight_numeric_storage_ok(value)
    length_ok <- joint_inla_preflight_covers_joint_rows(value, n_rows)
    type_metrics <- list(
      class = if (is.null(value)) NA_character_ else joint_inla_preflight_class(value),
      typeof = if (is.null(value)) NA_character_ else typeof(value),
      source_column = name,
      storage_accepted = storage_ok,
      length_observed = if (is.null(value)) NA_real_ else length(value),
      length_expected = n_rows,
      length_matches = length_ok
    )
    if (storage_ok) pass("fixed_effects", paste0(name, "_type"), paste0("class=", joint_inla_preflight_class(value), "; typeof=", typeof(value), "; storage.mode=", joint_inla_preflight_storage(value)), "integer/double numeric atomic vector", "Fixed-effect storage type is accepted.", type_metrics)
    else fail("fixed_effects", paste0(name, "_type"), if (is.null(value)) "missing" else paste0("class=", joint_inla_preflight_class(value), "; typeof=", typeof(value), "; storage.mode=", joint_inla_preflight_storage(value)), "integer/double numeric atomic vector; no factor/ordered/character/logical/list", "Fixed-effect columns must use accepted numeric storage.", type_metrics)
    if (storage_ok && length_ok) pass("fixed_effects", paste0(name, "_length"), length(value), paste0(">=", n_rows), "Fixed-effect column covers the joint rows; additional prediction rows are permitted.", type_metrics)
    else if (storage_ok) fail("fixed_effects", paste0(name, "_length"), length(value), paste0(">=", n_rows), "Fixed-effect column is shorter than the joint stack row count.", type_metrics)
    if (storage_ok && length_ok) {
      active_values <- value[seq_len(n_rows)][active]
      finite_mask <- is.finite(active_values)
      invalid <- sum(!finite_mask)
      finite <- active_values[finite_mask]
      value_metrics <- c(type_metrics, list(
        active_finite_count = sum(finite_mask), active_nonfinite_count = invalid,
        minimum = if (length(finite)) min(finite) else NA_real_,
        maximum = if (length(finite)) max(finite) else NA_real_,
        unique_count = length(unique(finite))
      ))
      if (invalid == 0L) pass("fixed_effects", paste0(name, "_active_finite"), invalid, 0L, paste0("Finite on ", expected_likelihood, " likelihood rows."), value_metrics)
      else fail("fixed_effects", paste0(name, "_active_finite"), invalid, 0L, "Active fixed-effect values must be finite.", value_metrics)
      pass("fixed_effects", paste0(name, "_summary"), paste0("source=", name, "; min=", joint_inla_preflight_number(if (length(finite)) min(finite) else NA_real_), "; max=", joint_inla_preflight_number(if (length(finite)) max(finite) else NA_real_), "; unique=", length(unique(finite))), "source column with min/max/unique recorded", "Fixed-effect distribution summary for the production model column.", value_metrics)
    }
  }

  check_index <- function(name, active, integer_valued = TRUE, expected_min = 1L, expected_max = NULL,
                          exact_levels = NULL, contiguous = FALSE) {
    value <- if (name %in% data_names) data[[name]] else NULL
    storage_ok <- joint_inla_preflight_numeric_storage_ok(value)
    length_ok <- joint_inla_preflight_covers_joint_rows(value, n_rows)
    type_metrics <- list(
      class = if (is.null(value)) NA_character_ else joint_inla_preflight_class(value),
      typeof = if (is.null(value)) NA_character_ else typeof(value),
      source_column = name,
      storage_accepted = storage_ok,
      length_observed = if (is.null(value)) NA_real_ else length(value),
      length_expected = n_rows,
      length_matches = length_ok,
      integer_valued_required = integer_valued
    )
    if (storage_ok) pass("random_effects", paste0(name, "_type"), paste0("class=", joint_inla_preflight_class(value), "; typeof=", typeof(value), "; storage.mode=", joint_inla_preflight_storage(value)), "integer/double numeric atomic vector", "Random-effect/index storage type is accepted.", type_metrics)
    else fail("random_effects", paste0(name, "_type"), if (is.null(value)) "missing" else paste0("class=", joint_inla_preflight_class(value), "; typeof=", typeof(value), "; storage.mode=", joint_inla_preflight_storage(value)), "integer/double numeric atomic vector; no factor/ordered/character/logical/list", "Random-effect/index variables must use accepted numeric storage.", type_metrics)
    if (storage_ok && !length_ok) {
      fail("random_effects", paste0(name, "_length"), length(value), paste0(">=", n_rows), "Random-effect/index variable is shorter than the joint stack row count.", type_metrics)
      return(invisible(FALSE))
    }
    if (storage_ok) pass("random_effects", paste0(name, "_length"), length(value), paste0(">=", n_rows), "Random-effect/index variable covers the joint rows; additional prediction rows are permitted.", type_metrics)
    if (!storage_ok) return(invisible(FALSE))
    active_values <- value[seq_len(n_rows)][active]
    finite_mask <- is.finite(active_values)
    invalid_finite <- sum(!finite_mask)
    finite <- active_values[finite_mask]
    integer_observed <- joint_inla_preflight_integer_observed(active_values)
    finite_metrics <- c(type_metrics, list(
      integer_valued_observed = integer_observed,
      active_finite_count = sum(finite_mask), active_nonfinite_count = invalid_finite,
      minimum = if (length(finite)) min(finite) else NA_real_,
      maximum = if (length(finite)) max(finite) else NA_real_,
      unique_count = if (length(finite)) length(unique(finite)) else 0L
    ))
    if (invalid_finite == 0L) pass("random_effects", paste0(name, "_active_finite"), invalid_finite, 0L, "Active random-effect/index values are finite.", finite_metrics)
    else fail("random_effects", paste0(name, "_active_finite"), invalid_finite, 0L, "Active random-effect/index values must be finite.", finite_metrics)
    if (!length(finite)) {
      fail("random_effects", paste0(name, "_active_values"), "none", "at least one active value", "No active values were available for validation.", finite_metrics)
      return(invisible(FALSE))
    }
    if (integer_valued) {
      non_integer <- sum(abs(finite - round(finite)) > sqrt(.Machine$double.eps))
      if (non_integer == 0L) pass("random_effects", paste0(name, "_integer_valued"), non_integer, 0L, "Index/group values are integer-valued within numerical tolerance.", finite_metrics)
      else fail("random_effects", paste0(name, "_integer_valued"), non_integer, 0L, "Index/group values must be integer-valued within numerical tolerance.", finite_metrics)
    }
    if (!is.null(expected_min)) {
      below_min <- sum(finite < expected_min)
      if (below_min == 0L) pass("random_effects", paste0(name, "_minimum"), min(finite), paste0(">=", expected_min), "Index/group minimum is valid.", finite_metrics)
      else fail("random_effects", paste0(name, "_minimum"), min(finite), paste0(">=", expected_min), "Index/group values below the valid minimum.", finite_metrics)
    }
    if (!is.null(expected_max)) {
      above_max <- sum(finite > expected_max)
      if (above_max == 0L) pass("random_effects", paste0(name, "_maximum"), max(finite), paste0("<=", expected_max), "Index/group maximum is within the expected range.", finite_metrics)
      else fail("random_effects", paste0(name, "_maximum"), max(finite), paste0("<=", expected_max), "Index/group values exceed the expected range.", finite_metrics)
    }
    levels <- if (isTRUE(integer_observed)) sort(unique(as.integer(round(finite)))) else sort(unique(finite))
    range_contiguity <- "not_required"
    if (!is.null(exact_levels)) {
      exact <- isTRUE(integer_observed) && identical(levels, as.integer(exact_levels))
      range_contiguity <- if (exact) "pass" else "fail"
      if (exact) pass("random_effects", paste0(name, "_levels"), paste(levels, collapse = ","), paste(as.integer(exact_levels), collapse = ","), "Expected levels are represented.", c(finite_metrics, list(range_contiguity = range_contiguity)))
      else fail("random_effects", paste0(name, "_levels"), paste(levels, collapse = ","), paste(as.integer(exact_levels), collapse = ","), "Expected levels are not represented exactly.", c(finite_metrics, list(range_contiguity = range_contiguity)))
    } else if (isTRUE(contiguous)) {
      expected_levels <- seq.int(min(levels), max(levels))
      contiguous_ok <- isTRUE(integer_observed) && identical(levels, expected_levels)
      range_contiguity <- if (contiguous_ok) "pass" else "fail"
      if (contiguous_ok) pass("random_effects", paste0(name, "_contiguous_levels"), paste(levels, collapse = ","), paste(expected_levels, collapse = ","), "Levels are contiguous.", c(finite_metrics, list(range_contiguity = range_contiguity)))
      else fail("random_effects", paste0(name, "_contiguous_levels"), paste(levels, collapse = ","), paste(expected_levels, collapse = ","), "Levels have gaps.", c(finite_metrics, list(range_contiguity = range_contiguity)))
    }
    pass("random_effects", paste0(name, "_summary"), paste0("class=", joint_inla_preflight_class(value), "; typeof=", typeof(value), "; storage_accepted=TRUE; integer_required=", integer_valued, "; integer_observed=", integer_observed, "; min=", min(finite), "; max=", max(finite), "; unique=", length(levels)), "class/typeof/storage/integer/range summary recorded", "Random-effect/index audit summary.", c(finite_metrics, list(range_contiguity = range_contiguity)))
    invisible(TRUE)
  }

  nspde <- as.integer(expected_nspde)
  check_index("tier1_field", tier1_active_rows, expected_max = nspde)
  check_index("tier1_field.group", tier1_active_rows, expected_max = expected_quarter_groups, exact_levels = seq_len(expected_quarter_groups))
  check_index("week_steps", tier1_active_rows, expected_max = NULL, contiguous = TRUE)
  check_index("admin_f", tier1_active_rows, expected_max = NULL)
  check_index("tier2_field", tier2_active_rows, expected_max = nspde)
  check_index("tier2_field.group", tier2_active_rows, expected_max = expected_quarter_groups, exact_levels = seq_len(expected_quarter_groups))
  check_index("tier2_copy_field", tier2_active_rows, expected_max = nspde)
  check_index("tier2_copy_field.group", tier2_active_rows, expected_max = expected_quarter_groups, exact_levels = seq_len(expected_quarter_groups))
  check_index("tier2_week", tier2_active_rows, expected_max = NULL, contiguous = TRUE)
  check_index("cattle_q", tier2_active_rows, expected_max = expected_cattle_bins, exact_levels = seq_len(expected_cattle_bins))
  check_index("cattle_mid_log1p", tier2_active_rows, integer_valued = FALSE, expected_min = NULL)

  if (link_ok) {
    observed_groups <- sort(unique(c(
      data[["tier1_field.group"]][tier1_active_rows],
      data[["tier2_field.group"]][tier2_active_rows],
      data[["tier2_copy_field.group"]][tier2_active_rows]
    )))
    if (identical(as.integer(observed_groups), seq_len(expected_quarter_groups))) pass("random_effects", "quarter_group_count", length(observed_groups), expected_quarter_groups, "Quarter groups are exactly 1:8.")
    else fail("random_effects", "quarter_group_count", paste(observed_groups, collapse = ","), paste(seq_len(expected_quarter_groups), collapse = ","), "Quarter groups must be exactly 1:8.")
  }

  if (!is.null(A) && !is.null(n_rows) && !is.na(n_rows)) {
    a_dim <- dim(A)
    if (length(a_dim) == 2L && a_dim[[2L]] > 0L) pass("projection", "A_dimensions", paste(a_dim, collapse = " x "), "two-dimensional matrix with positive latent width", "Projection dimensions are internally defined.")
    else fail("projection", "A_dimensions", paste(a_dim, collapse = " x "), "two-dimensional matrix with positive latent width", "Projection matrix dimensions are invalid.")
    if (length(a_dim) == 2L && identical(as.integer(a_dim[[1L]]), as.integer(n_rows))) pass("projection", "A_row_count", a_dim[[1L]], n_rows, "Projection rows match joint predictor rows.")
    else fail("projection", "A_row_count", paste(a_dim, collapse = " x "), n_rows, "A row count must equal the joint predictor count.")
    finite_entries <- tryCatch({
      if (inherits(A, "sparseMatrix")) all(is.finite(A@x)) else all(is.finite(as.numeric(A)))
    }, error = function(error) FALSE)
    if (finite_entries) pass("projection", "A_finite_entries", "finite", "finite", "All sparse/dense projection entries are finite.")
    else fail("projection", "A_finite_entries", "non-finite or unavailable", "finite", "Projection matrix contains invalid entries.")
    row_sums <- tryCatch({
      if (inherits(A, "sparseMatrix") && requireNamespace("Matrix", quietly = TRUE)) as.numeric(Matrix::rowSums(A)) else rowSums(A)
    }, error = function(error) numeric())
    if (length(row_sums) == n_rows && all(observation_active)) {
      zero_rows <- sum(observation_active & row_sums == 0)
      if (zero_rows == 0L) pass("projection", "active_nonzero_rows", zero_rows, 0L, "No active observation has a zero-sum projection row.")
      else fail("projection", "active_nonzero_rows", zero_rows, 0L, "Active observation has a zero-sum projection row.")
    } else fail("projection", "A_internal_dimensions", paste(length(row_sums), n_rows, sep = "/"), "row sums match joint rows", "Could not validate projection row sums.")
  }

  prediction <- build$prediction_compatibility
  if (is.list(prediction) && isTRUE(prediction$compatible)) pass("prediction", "prediction_compatibility", TRUE, TRUE, "Stage 3A prediction compatibility passed.")
  else fail("prediction", "prediction_compatibility", if (is.null(prediction)) "missing" else prediction$compatible, TRUE, "Stage 3A prediction compatibility must be TRUE.")
  if (is.list(prediction) && !is.null(prediction$nonfinite_counts)) {
    counts <- as.numeric(prediction$nonfinite_counts)
    if (length(counts) && all(counts == 0)) pass("prediction", "prediction_required_variables_finite", paste(names(prediction$nonfinite_counts), collapse = ","), "all nonfinite counts are 0", "All required prediction variables are finite.")
    else fail("prediction", "prediction_required_variables_finite", joint_inla_preflight_text(prediction$nonfinite_counts), "all nonfinite counts are 0", "Prediction compatibility reports non-finite required variables.")
  } else fail("prediction", "prediction_required_variables_finite", "missing", "nonfinite_counts all zero", "Prediction-variable finite-value audit is unavailable.")

  theta <- build$fit_reference$control_mode$theta
  theta_type_ok <- is.numeric(theta) && !is.factor(theta) && !is.character(theta) && !is.list(theta)
  theta_valid <- theta_type_ok && length(theta) == 10L && all(is.finite(theta))
  if (theta_valid) pass("theta", "historical_theta_shape", paste(typeof(theta), length(theta)), "numeric finite vector length 10", "Historical theta has the required production shape.")
  else fail("theta", "historical_theta_shape", if (is.null(theta)) "missing" else paste(typeof(theta), length(theta)), "numeric finite vector length 10", "Historical theta must be numeric, finite, and length 10.")
  theta_inventory <- joint_inla_preflight_theta_inventory()
  warn("theta", "historical_theta_order", "unverified", "explicit order equivalence", paste0("PROMINENT WARNING: historical theta order cannot be established from Stage 3A metadata. Prefer initialization mode 'default' for the first production fit; assumed inventory is retained without claiming equivalence. Artifact: ", build_path))
  warn("theta", "historical_fit_comparison", "not performed", "optional external comparison", "An external historical fit artifact was not required or supplied.")

  audit <- do.call(rbind, checks)
  failures <- sum(audit$status == "fail")
  warnings <- sum(audit$status == "warning")
  list(
    success = failures == 0L,
    audit = audit,
    theta_inventory = theta_inventory,
    summary = list(failures = failures, warnings = warnings, checks = nrow(audit)),
    build_path = build_path
  )
}

joint_inla_preflight_audit_path <- function(path, overwrite = FALSE) {
  path <- normalizePath(path, mustWork = FALSE)
  if (!file.exists(path) || isTRUE(overwrite)) return(path)
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  stem <- sub("\\.csv$", "", basename(path), ignore.case = TRUE)
  file.path(dirname(path), paste0(stem, "_", stamp, ".csv"))
}

joint_inla_preflight_write_audit <- function(result, path, overwrite = FALSE) {
  target <- joint_inla_preflight_audit_path(path, overwrite)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  staged <- tempfile("joint-inla-preflight-", fileext = ".csv", tmpdir = dirname(target))
  on.exit(unlink(staged, force = TRUE), add = TRUE)
  utils::write.csv(result$audit, staged, row.names = FALSE, na = "NA")
  if (file.exists(target)) {
    if (!isTRUE(overwrite)) stop("Preflight audit target unexpectedly exists: ", target)
    if (!file.remove(target)) stop("Unable to replace preflight audit: ", target)
  }
  if (!file.rename(staged, target)) stop("Unable to write preflight audit: ", target)
  target
}

joint_inla_preflight_print <- function(result, audit_path = NULL) {
  status <- if (isTRUE(result$success)) "PASS" else "FAIL"
  cat("Stage 3B production-artifact preflight: ", status, "\n", sep = "")
  cat("  Checks: ", result$summary$checks, "\n", sep = "")
  cat("  Failures: ", result$summary$failures, "\n", sep = "")
  cat("  Warnings: ", result$summary$warnings, "\n", sep = "")
  if (!is.null(audit_path)) cat("  Audit: ", audit_path, "\n", sep = "")
  warning_rows <- result$audit[result$audit$status == "warning", , drop = FALSE]
  if (nrow(warning_rows)) {
    for (detail in warning_rows$details) cat("  WARNING: ", detail, "\n", sep = "")
  }
  invisible(result)
}
