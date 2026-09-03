repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required for this regression test")

model_crs <- "EPSG:3857"
boundary <- sf::st_as_sf(
  sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(10000, 0), c(10000, 10000), c(0, 10000), c(0, 0)
  ))), crs = model_crs)
)
cfg <- list(
  project = list(seed = 1976),
  study = list(projected_crs = model_crs),
  mesh = list(
    boundary_buffer_km = 1, cutoff_km = 0.25,
    max_edge_km = c(0.5, 2), offset_km = c(1, 2),
    minimum_angle_degrees = 30, island_area_threshold_km2 = 0
  )
)
observations <- data.frame(
  x = c(2000, 8000), y = c(2000, 8000),
  epiyear = c(2024L, 2024L), epiweek = c(1L, 2L)
)

support <- build_spatial_support(boundary, observations, cfg)
stopifnot(
  support$mesh$n == nrow(support$mesh_polygons),
  all(support$mesh_polygons$poly_id == seq_len(support$mesh$n)),
  all(support$integration_points$poly_id == seq_len(support$mesh$n))
)

classification <- classify_mesh_support(support$mesh_polygons, support$mesh, support$simplified_domain)
stopifnot(
  nrow(classification) == support$mesh$n,
  all(classification$poly_id == seq_len(support$mesh$n)),
  sum(classification$category %in% c(
    "A_node_inside_polygon_intersects", "B_node_outside_polygon_intersects",
    "C_node_inside_polygon_disjoint", "D_node_outside_polygon_disjoint"
  )) == support$mesh$n
)
legacy_keep <- classification$polygon_intersects_domain
refactor_keep <- classification$node_inside_domain & classification$polygon_intersects_domain
stopifnot(sum(refactor_keep) <= sum(legacy_keep))
legacy_polygons <- clip_mesh_polygons_to_domain(
  support$mesh_polygons, support$simplified_domain,
  crs_linear_unit_to_m(sf::st_crs(support$simplified_domain)), which(legacy_keep)
)
stopifnot(nrow(legacy_polygons) == sum(legacy_keep))

time_index <- data.frame(
  epiyear = c(2024L, 2024L), epiweek = c(1L, 2L), time_index = 1:2
)
tier2 <- build_tier2(observations, support, time_index)
stopifnot(nrow(tier2) == nrow(support$tier2_polygons) * nrow(time_index))

fixed_1 <- build_observation_independent_mesh(boundary, cfg)
fixed_2 <- build_observation_independent_mesh(boundary, cfg)
fixed_subset <- build_inla_mesh(
  support$mesh_boundary, cfg, mesh_observations = observations[1, , drop = FALSE],
  use_observation_locations = FALSE
)
stopifnot(
  fixed_1$mesh$n == fixed_2$mesh$n,
  identical(fixed_1$mesh$loc, fixed_2$mesh$loc),
  identical(fixed_1$mesh$graph$tv, fixed_2$mesh$graph$tv),
  fixed_1$mesh$n == fixed_subset$n,
  identical(fixed_1$mesh$loc, fixed_subset$loc),
  identical(fixed_1$mesh$graph$tv, fixed_subset$graph$tv)
)

cat("Spatial support and observation-independent mesh regression test passed\n")
