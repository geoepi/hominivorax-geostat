#' quick_map_plot
#'
#' @description Utility function for geostatistical workflows used in this repository.
#'
#' @return Object produced by quick_map_plot() based on provided inputs.
quick_map_plot <- function(grid_stk, target_year, target_week, boundary_polys) {
  
  year_pat <- paste0("y", target_year)
  week_pat <- sprintf("w%02d", target_week)
  
  all_names <- names(grid_stk)
  match_idx <- grep(year_pat, all_names) %>% 
    intersect(grep(week_pat, all_names))
  
  if (length(match_idx) == 0) {
    stop(paste("No layer found matching Year:", target_year, "and Week:", target_week))
  }

  target_layer_name <- all_names[match_idx[1]]
  
  single_layer <- grid_stk[[target_layer_name]]
  
  plot_df <- as.data.frame(single_layer, xy = TRUE, na.rm = TRUE)
  
  names(plot_df)[3] <- "value"
  
  plt_map <- ggplot(plot_df, aes(x = x, y = y, fill = value)) +
    geom_tile() +
    coord_sf(expand = FALSE) +
    scale_fill_viridis_c(
      option = "turbo",
      direction = 1,
      limits = c(0, 6.1),
      na.value = "white",
      name = expression("Detections per 625 km"^2),
      guide = guide_colorbar(
        title.position = "top",
        title.hjust = 0.5,
        barwidth = unit(10, "lines"),
        barheight = unit(1, "lines")
      )
    ) +
    geom_sf(data = boundary_polys, fill = NA, 
            color = "gray60", linewidth = 0.1, inherit.aes = FALSE) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      legend.title = element_text(size = 14, face = "bold"),
      axis.title = element_text(size = 16, face = "bold"),
      plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
    ) +
    labs(
      x = "Longitude", 
      y = "Latitude", 
      title = paste("Layer:", target_layer_name)
    )
  
  return(plt_map)
}
