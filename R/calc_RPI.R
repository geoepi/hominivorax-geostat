# Reproductive Persistence Index (RPI)

calc_RPI <- function(count_stk, nws_obs, gen_days = 21, 
                     days_per_layer = 7, cut_quant = 0.10) {
  
  obs_pts <- vect(nws_obs, geom=c("x", "y"), crs=crs(count_stk))
  extracted_vals <- terra::extract(count_stk, obs_pts)
  
  # ignore the lowest cut_quant of records
  bio_threshold <- quantile(unlist(extracted_vals[,-1]), cut_quant, na.rm = TRUE)
  message(paste("Data-driven suitability threshold set at:", round(bio_threshold, 3)))
  
  # consecutive runs
  calc_max_run <- function(x) {
    if (all(is.na(x))) return(NA)
    
    is_suitable <- x > bio_threshold
    is_suitable[is.na(is_suitable)] <- FALSE 
    
    runs <- rle(is_suitable) 
    
    if (!any(runs$values, na.rm = TRUE)) return(0)
    
    return(max(runs$lengths[runs$values], na.rm = TRUE))
  }
  
  max_run_weeks <- app(count_stk, fun = calc_max_run)
  
  # RPI cals (generations)
  rpi_rast <- (max_run_weeks * days_per_layer) / gen_days
  
  # ---------------------------------------------------------------------------
  # Class 0: < 3 generations (Transient/Sink) 
  #          Incapable of establishing a local population.
  # Class 1: 3 - 8 generations (Sustained Seasonal) 
  #          Meets 60-day threshold; local establishment likely during favorable seasons.
  # Class 2: 8 - 15 generations (Permanent/Multi-Season) 
  #          High stability across most of the year.
  # Class 3: > 15 generations (Endemic Core) 
  #          Year-round reproductive persistence; the primary population source.
  # ---------------------------------------------------------------------------
  
  stability_class <- classify(rpi_rast, 
                              rcl = matrix(c(-Inf, 3, 0,
                                             3,   8, 1,
                                             8,  15, 2,
                                             15, Inf, 3), 
                                           ncol=3, byrow=TRUE))
  
  return(list(
    rpi = rpi_rast,
    stability_class = stability_class,
    calibrated_threshold = bio_threshold
  ))
}