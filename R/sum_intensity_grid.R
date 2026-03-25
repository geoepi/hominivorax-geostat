sum_intensity_grid <- function(raster_stack, min_est = 1) {
  
  stk_names <- names(raster_stack)
  
  results_list <- lapply(stk_names, function(layer_name) {
    
    lyr <- raster_stack[[layer_name]]

    eligible_lyr <- terra::ifel(lyr >= min_est, lyr, 0)
    raw_sum <- terra::global(eligible_lyr, "sum", na.rm = TRUE)[1, 1]
    
    yr_str <- regmatches(layer_name, regexpr("y\\d{4}", layer_name))
    wk_str <- regmatches(layer_name, regexpr("w\\d{2}", layer_name))
    
    yr <- as.numeric(gsub("y", "", yr_str))
    wk <- as.numeric(gsub("w", "", wk_str))
    
    data.frame(
      year     = yr,
      week     = wk,
      count      = floor(raw_sum),
      layer_id = layer_name,
      stringsAsFactors = FALSE
    )
  })
  
  final_df <- do.call(rbind, results_list)
  
  # formatting
  final_df <- final_df %>% 
    arrange(year, week) %>%
    mutate(
      date = lubridate::parse_date_time(paste(year, week, 1, sep = "-"), "Y-W-u"),
      date = as_date(date)
    )
  
  return(final_df)
}