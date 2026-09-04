joint_first_present <- function(data, candidates, label) {
  found <- candidates[candidates %in% names(data)]
  if (!length(found)) stop(label, " is missing all supported columns: ", paste(candidates, collapse = ", "))
  found[[1L]]
}

joint_effect_mapping <- function(tier1, tier2) {
  list(
    tier1 = c(
      north = joint_first_present(tier1, c("northing_km_s", "northing_z"), "Tier 1 northing"),
      road_dens = joint_first_present(tier1, c("road_dens_s", "road_density_log1p"), "Tier 1 road density"),
      night_illum = joint_first_present(tier1, c("night_illum_s", "night_illumination_log1p"), "Tier 1 night illumination"),
      admin_f = "admin_f", week_steps = "timestep"
    ),
    tier2 = c(
      mintemp = joint_first_present(tier2, c("mintemp_s", "mintemp_z"), "Tier 2 minimum temperature"),
      soilmoist = joint_first_present(tier2, c("soilmoist_s", "soilmoist_z"), "Tier 2 soil moisture"),
      leafarea = joint_first_present(tier2, c("leafarea_s", "leafarea_z"), "Tier 2 leaf area"),
      rhum = joint_first_present(tier2, c("rhum_s", "rhum_z"), "Tier 2 relative humidity"),
      cattle = "cattle_log1p", horses = "horses_log1p", pigs = "pigs_log1p", goats = "goats_log1p", sheep = "sheep_log1p",
      cattle_q = "cattle_q", cattle_mid_log1p = "cattle_mid_log1p", tier2_week = "timestep"
    )
  )
}

validate_joint_effect_columns <- function(data, mapping, active, label) {
  missing <- setdiff(unname(mapping), names(data))
  if (length(missing)) stop(label, " is missing required effect columns: ", paste(missing, collapse = ", "))
  counts <- vapply(mapping, function(column) sum(!is.finite(as.numeric(data[[column]]))), integer(1L))
  active_counts <- vapply(mapping, function(column) sum(active & !is.finite(as.numeric(data[[column]]))), integer(1L))
  if (any(active_counts > 0L)) stop(label, " has missing or non-finite active predictors: ", paste(names(active_counts)[active_counts > 0L], collapse = ", "))
  list(all_rows_nonfinite = counts, active_rows_nonfinite = active_counts)
}

make_joint_field_indices <- function(spde_tier1, spde_tier2, n_groups) {
  require_joint_inla()
  list(
    tier1 = INLA::inla.spde.make.index("tier1_field", n.spde = spde_tier1$n.spde, n.group = n_groups),
    tier2 = INLA::inla.spde.make.index("tier2_field", n.spde = spde_tier2$n.spde, n.group = n_groups),
    copy = INLA::inla.spde.make.index("tier2_copy_field", n.spde = spde_tier1$n.spde, n.group = n_groups)
  )
}

make_joint_fixed_effects <- function(data, mapping, names_to_include) {
  values <- lapply(names_to_include, function(name) as.numeric(data[[unname(mapping[[name]])]]))
  names(values) <- names_to_include
  values
}

make_tier1_effects <- function(data, fields, mapping) {
  latent <- c(fields$tier1, list(intercept1 = 1))
  fixed <- make_joint_fixed_effects(data, mapping$tier1, c("north", "road_dens", "night_illum", "admin_f", "week_steps"))
  list(latent = latent, fixed = fixed)
}

make_tier2_effects <- function(data, fields, mapping) {
  latent <- c(fields$tier2, fields$copy, list(intercept2 = 1))
  fixed <- make_joint_fixed_effects(data, mapping$tier2, c("mintemp", "soilmoist", "leafarea", "rhum", "cattle", "horses", "pigs", "goats", "sheep", "cattle_q", "cattle_mid_log1p", "tier2_week"))
  list(latent = latent, fixed = fixed)
}
