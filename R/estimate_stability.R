#' estimate_stability
#'
#' @description Utility function for geostatistical workflows used in this repository.
#'
#' @return Object produced by estimate_stability() based on provided inputs.
estimate_stability <- function(count_stk) {

  mean_rast <- terra::app(count_stk, fun = mean, na.rm = TRUE)
  sd_rast   <- terra::app(count_stk, fun = sd, na.rm = TRUE)
  
  max_sd <- terra::global(sd_rast, "max", na.rm = TRUE)[1,1]
  rel_sd <- sd_rast / max_sd

  stability_index <- mean_rast * (1 - rel_sd)
  
  variability_index <- rel_sd
  
  return(list(
    stability = stability_index,
    variation = variability_index,
    mean_intensity = mean_rast
  ))
}
