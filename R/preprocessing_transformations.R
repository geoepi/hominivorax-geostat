estimate_transformations <- function(training, cfg) {
  dynamic <- c("mintemp", "soilmoist", "leafarea", "rhum")
  static <- c("cattle", "horses", "pigs", "sheep", "goats", "road_density", "night_illumination")
  if (!all(c(dynamic, static, "x", "y") %in% names(training))) stop("Training data lack covariates required for transformation estimation.")
  center_scale <- function(values) {
    c(center = mean(values, na.rm = TRUE), scale = max(sd(values, na.rm = TRUE), .Machine$double.eps))
  }
  static_spec <- lapply(static, function(nm) {
    values <- training[[nm]]
    impute <- if (nm %in% c("cattle", "horses", "pigs", "sheep", "goats")) 0 else mean(values, na.rm = TRUE)
    logged <- log1p(replace(values, is.na(values), impute))
    c(impute = impute, center = mean(logged, na.rm = TRUE), scale = max(sd(logged, na.rm = TRUE), .Machine$double.eps))
  })
  northing_values <- training$y
  list(
    dynamic = setNames(lapply(dynamic, function(nm) center_scale(training[[nm]])), dynamic),
    static = setNames(static_spec, static),
    northing = c(origin = min(northing_values, na.rm = TRUE), center = mean(northing_values, na.rm = TRUE), scale = max(sd(northing_values, na.rm = TRUE), .Machine$double.eps)),
    temperature_hinge = cfg$transformations$temperature_hinge,
    missing_policies = list(dynamic = cfg$transformations$dynamic_missing_policy, livestock = cfg$transformations$livestock_missing_policy),
    type = "training_only"
  )
}

apply_transformations <- function(data, spec, include_hinge = TRUE) {
  for (nm in names(spec$dynamic)) {
    values <- data[[nm]]
    values[is.na(values)] <- spec$dynamic[[nm]]["center"]
    data[[paste0(nm, "_z")]] <- (values - spec$dynamic[[nm]]["center"]) / spec$dynamic[[nm]]["scale"]
  }
  for (nm in names(spec$static)) {
    values <- data[[nm]]
    values[is.na(values)] <- spec$static[[nm]]["impute"]
    data[[paste0(nm, "_log1p")]] <- log1p(values)
  }
  data$northing_z <- (data$y - spec$northing["origin"] - spec$northing["center"]) / spec$northing["scale"]
  if (include_hinge && "mintemp" %in% names(data)) data$tmin_hinge <- pmax(0, data$mintemp - spec$temperature_hinge)
  data
}

add_legacy_model_fields <- function(data) {
  aliases <- c(mintemp_s = "mintemp_z", soilmoist_s = "soilmoist_z", leafarea_s = "leafarea_z", rhum_s = "rhum_z", road_dens_s = "road_density_log1p", night_illum_s = "night_illumination_log1p", northing_km_s = "northing_z")
  for (legacy in names(aliases)) data[[legacy]] <- data[[aliases[[legacy]]]]
  data
}
