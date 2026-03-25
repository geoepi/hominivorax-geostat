library(spatstat)

simulate_detection_points <- function(raster_stack, obs_df, rseed=1976) {
  all_points_list <- list()
  stk_names <- names(raster_stack)
  
  # counter
  list_idx <- 1
  
  for (i in 1:nrow(obs_df)) {
    num_points <- obs_df$count[i]
    
    if (is.na(num_points) || num_points <= 0) next
    
    target_year <- obs_df$year[i]
    target_week <- obs_df$week[i]
    target_pattern <- sprintf("y%d_w%02d", target_year, target_week)
    
    match_idx <- grep(target_pattern, stk_names)
    if (length(match_idx) == 0) {
      warning(paste("No raster found for", target_pattern))
      next
    }
    
    lyr <- raster_stack[[match_idx[1]]]^1.5
    
    r_df <- as.data.frame(lyr, xy = TRUE, na.rm = TRUE)
    
    if (nrow(r_df) == 0 || sum(r_df[[3]], na.rm=TRUE) == 0) next
    
    # im for spatstat
    prob_im <- as.im(r_df)
    
    # generate points
    set.seed(rseed + target_week) 
    pts_ppp <- rpoint(n = num_points, f = prob_im)
    
    week_df <- data.frame(
      x = pts_ppp$x,
      y = pts_ppp$y,
      year = target_year,
      week = target_week 
    )
    
    all_points_list[[list_idx]] <- week_df
    list_idx <- list_idx + 1
  }
  
  if (length(all_points_list) == 0) return(NULL)
  
  final_df <- do.call(rbind, all_points_list)
  return(final_df)
}
