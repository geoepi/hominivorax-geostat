require_joint_inla <- function() {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("Stage 3A requires the INLA package; Stage 1 and Stage 2 do not.")
  invisible(TRUE)
}

joint_mesh_unit_to_m <- function(joint_inputs) {
  value <- joint_inputs$spatial_support$linear_unit_to_m
  if (is.null(value) || length(value) != 1L || !is.finite(as.numeric(value)) || as.numeric(value) <= 0) stop("Stage 2 spatial_support$linear_unit_to_m must be a positive finite scalar.")
  as.numeric(value)
}

make_joint_spde <- function(mesh, specification, unit_to_m, label) {
  require_joint_inla()
  range_coordinate_units <- as.numeric(specification$prior_range_km) * 1000 / unit_to_m
  object <- INLA::inla.spde2.pcmatern(
    mesh, alpha = as.numeric(specification$alpha),
    prior.range = c(range_coordinate_units, as.numeric(specification$prior_range_probability)),
    prior.sigma = c(as.numeric(specification$prior_sigma), as.numeric(specification$prior_sigma_probability)),
    constr = isTRUE(specification$constr)
  )
  list(
    object = object,
    label = label,
    n_spde = object$n.spde,
    parameters = list(
      alpha = specification$alpha,
      prior_range_km = specification$prior_range_km,
      prior_range_probability = specification$prior_range_probability,
      prior_sigma = specification$prior_sigma,
      prior_sigma_probability = specification$prior_sigma_probability,
      coordinate_unit_to_m = unit_to_m,
      prior_range_coordinate_units = range_coordinate_units,
      constr = specification$constr
    )
  )
}

make_joint_projection <- function(mesh, data, grouping_variable) {
  require_joint_inla()
  require_columns(data, c("x", "y", grouping_variable), "joint-INLA projection data")
  loc <- as.matrix(data[c("x", "y")])
  group <- as.integer(data[[grouping_variable]])
  if (any(!is.finite(loc)) || anyNA(group) || any(group < 1L)) stop("Projection coordinates and temporal groups must be finite and positive.")
  INLA::inla.spde.make.A(mesh, loc = loc, group = group)
}
