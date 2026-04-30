#' plot_duel_mesh
#'
#' @description Utility function for geostatistical workflows used in this repository.
#'
#' @return Object produced by plot_duel_mesh() based on provided inputs.
plot_duel_mesh <- function(
    mesh_polys_sf,
    mesh,
    bbox = c(xmin = -2500, ymin = -2500, xmax = 1500, ymax = 1500),
    all_cols = c(
      evertices = "gray40",
      adata     = "darkred",
      bsegments = "gray60",
      cbinding  = "gray10",
      dinternal = "darkorange"
    ),
    edge_widths = c(bsegments = 0.5, cbinding = 1.2, dinternal = 1),
    node_sizes  = c(evertices = 0.8, adata = 2.0),
    node_shapes = c(evertices = 19, adata = 19),
    fill_option = "turbo",
    legend.position = "right",
    title = "Geographic Exposure (Cropped)"
) {
  require(sf)
  require(dplyr)
  require(ggplot2)
  require(viridis)
  
  mesh_df <- extract_mesh_network(mesh)
  
  bbox_sf <- st_as_sfc(st_bbox(bbox, crs = st_crs(mesh_polys_sf)))
  
  mesh_polys_crop <- st_crop(mesh_polys_sf, bbox_sf)
  
  nodes_crop <- mesh_df$nodes %>%
    filter(
      x >= bbox["xmin"], x <= bbox["xmax"],
      y >= bbox["ymin"], y <= bbox["ymax"]
    )
  
  # filter mesh edges to inside bbox
  edges_crop <- mesh_df$edges %>%
    filter(
      x1 >= bbox["xmin"], x1 <= bbox["xmax"], y1 >= bbox["ymin"], y1 <= bbox["ymax"],
      x2 >= bbox["xmin"], x2 <= bbox["xmax"], y2 >= bbox["ymin"], y2 <= bbox["ymax"]
    )
  
  ggplot(mesh_polys_crop) +
    geom_sf(aes(fill = area), color = "grey30", size = 0.1) +
    geom_segment(
      data = edges_crop,
      aes(x = x1, y = y1, xend = x2, yend = y2, colour = type, linewidth = type),
      inherit.aes = FALSE
    ) +
    geom_point(
      data = nodes_crop,
      aes(x = x, y = y, colour = type, size = type, shape = type),
      inherit.aes = FALSE
    ) +
    scale_colour_manual(values = all_cols, guide = "none")        +
    scale_linewidth_manual(values = edge_widths, guide = "none")  +
    scale_size_manual(values = node_sizes, guide = "none")        +
    scale_shape_manual(values = node_shapes, guide = "none")      +
    scale_fill_viridis_c(option = fill_option, name = "Area (km²)") +
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = legend.position,
      legend.title = element_text(size = 16, face = "bold"),
      legend.text = element_text(size = 10, face = "bold"),
      legend.key.width = unit(1, "line"),
      legend.key.height = unit(3, "line"),
      strip.text     = element_text(size = 18, face = "bold", color = "gray40"),
      axis.title.x   = element_text(size = 20, face = "bold"),
      axis.title.y   = element_text(size = 20, face = "bold"),
      axis.text.x    = element_text(size = 10, hjust = 0.5, angle = 45, face = "bold"),
      axis.text.y    = element_text(size = 10, face = "bold"),
      plot.title     = element_text(size = 22, face = "bold", hjust = 0.5)
    ) +
    labs(
      title = title,
      fill = "Area (km²)",
      x = "Longitude",
      y = "Latitude"
    )
}
