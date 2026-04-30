#' quick_point_map
#'
#' @description Utility function for geostatistical workflows used in this repository.
#'
#' @return Object produced by quick_point_map() based on provided inputs.
quick_point_map <- function(target_year, target_week, boundary_polys, point_data) {
  
  filtered_points <- point_data %>%
    filter(year == !!target_year, week == !!target_week)
  
  plt_map <- ggplot() +
    geom_sf(data = boundary_polys, fill = "gray95", 
            color = "gray70", linewidth = 0.2, inherit.aes = FALSE) +
    geom_point(data = filtered_points, aes(x = x, y = y), 
               color = "black", fill = "firebrick", 
               shape = 21, size = 1, stroke = 0.25, alpha=0.5) +
    coord_sf() +
    
    theme_minimal() +
    theme(
      panel.grid = element_blank(),
      plot.title = element_text(size = 20, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 14, hjust = 0.5, color = "gray40"),
      axis.title = element_text(size = 12, face = "bold"),
      axis.text = element_text(color = "gray50")
    ) +
    labs(
      x = "Longitude", 
      y = "Latitude", 
      title = paste("Simulated Detections: Week", target_week, "-", target_year),
      subtitle = paste("Total Points:", nrow(filtered_points))
    )
  
  return(plt_map)
}
