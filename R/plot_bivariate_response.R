#' plot_bivariate_response
#' @description Side-by-side visualization of Tier 1 (Detection) and Tier 2 (Aggregated Counts)
plot_bivariate_response <- function(
    tier1_sf, 
    tier2_sf, 
    states_sf,
    yr, 
    wk,
    point_color = "firebrick",
    fill_option = "turbo"
) {
  
  t1_subset <- tier1_sf %>% filter(year == yr, week == wk, Y1 == 1)
  t2_subset <- tier2_sf %>% filter(year == yr, week == wk)
  
  shared_theme <- theme_minimal(base_size = 14) +
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      legend.title     = element_text(size = 14, face = "bold"),
      axis.title       = element_text(size = 16, face = "bold"),
      axis.text        = element_text(size = 9, face = "bold"),
      plot.title       = element_text(size = 18, face = "bold", hjust = 0.5),
      plot.subtitle    = element_text(size = 12, face = "italic", hjust = 0.5)
    )
  
  # Tier 1 Point Detetcions
  p1 <- ggplot() +
    geom_sf(data = states_sf, fill = "gray95", color = "gray80", size = 0.2) +
    geom_sf(data = t1_subset, color = point_color, size = 0.7, alpha = 0.6) +
    labs(title = "Tier 1: Detections", subtitle = paste("Binary points (y1) | Week", wk, yr)) +
    shared_theme
  
  # Tier 2 Areal Counts
  p2 <- ggplot() +
    geom_sf(data = states_sf, fill = "gray95", color = "gray80", size = 0.2) +
    geom_sf(data = t2_subset, aes(fill = n_points), color = "gray60", size = 0.05) +
    scale_fill_viridis_c(option = fill_option, name = "Count", na.value = "gray95") +
    labs(title = "Tier 2: Abundance", subtitle = paste("Aggregated counts (y2) | Week", wk, yr)) +
    shared_theme +
    theme(
      legend.key.height = unit(2, "line"),
      legend.position = "right"
    )
  
  p1 + p2 + plot_layout(ncol = 2)
}
