crs_linear_unit_to_m <- function(crs) {
  if (sf::st_is_longlat(sf::st_crs(crs))) {
    stop("Mesh construction requires a projected CRS with linear units.")
  }
  wkt <- tolower(sf::st_crs(crs)$wkt)
  if (grepl("kilometre|kilometer|\"km\"", wkt)) return(1000)
  if (grepl("centimetre|centimeter", wkt)) return(0.01)
  if (grepl("millimetre|millimeter", wkt)) return(0.001)
  if (grepl("foot|feet|\"ft\"", wkt)) return(0.3048)
  1
}

validate_boundary <- function(boundary, projected_crs) {
  if (is.na(sf::st_crs(boundary))) stop("Study boundary has no CRS.")
  if (sf::st_is_longlat(sf::st_crs(projected_crs))) stop("projected_crs must be projected, not longitude/latitude.")
  boundary <- sf::st_transform(sf::st_make_valid(boundary), projected_crs)
  sf::st_union(boundary)
}

simplify_analysis_domain <- function(boundary, island_area_threshold_km2) {
  pieces <- sf::st_cast(sf::st_union(boundary), "POLYGON", warn = FALSE)
  unit_to_m <- crs_linear_unit_to_m(sf::st_crs(boundary))
  area_km2 <- as.numeric(sf::st_area(pieces)) * unit_to_m^2 / 1e6
  pieces[area_km2 >= island_area_threshold_km2] |> sf::st_union()
}

build_spatial_support <- function(boundary, observations, cfg) {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required for mesh construction.")
  domain <- validate_boundary(boundary, cfg$study$projected_crs)
  simplified_domain <- simplify_analysis_domain(domain, cfg$mesh$island_area_threshold_km2)
  unit_to_m <- crs_linear_unit_to_m(sf::st_crs(simplified_domain))
  buffer <- cfg$mesh$boundary_buffer_km * 1000 / unit_to_m
  mesh_boundary <- sf::st_buffer(simplified_domain, buffer)
  loc <- observations[, c("x", "y"), drop = FALSE]
  loc <- as.matrix(loc[stats::complete.cases(loc), , drop = FALSE])
  if (!nrow(loc)) stop("At least one valid observation is required to construct the INLA mesh.")
  boundary_sp <- methods::as(sf::st_as_sf(mesh_boundary), "Spatial")
  set.seed(cfg$project$seed)
  mesh <- INLA::inla.mesh.2d(
    boundary = INLA::inla.sp2segment(boundary_sp),
    loc = loc,
    cutoff = cfg$mesh$cutoff_km * 1000 / unit_to_m,
    max.edge = cfg$mesh$max_edge_km * 1000 / unit_to_m,
    offset = cfg$mesh$offset_km * 1000 / unit_to_m,
    min.angle = cfg$mesh$minimum_angle_degrees
  )
  if (is.null(mesh) || mesh$n < 1) stop("INLA returned an empty mesh.")
  mesh_sp <- convert_mesh_poly(mesh)
  mesh_polygons <- sf::st_as_sf(mesh_sp)
  sf::st_crs(mesh_polygons) <- sf::st_crs(simplified_domain)
  mesh_polygons$poly_id <- seq_len(nrow(mesh_polygons))
  mesh_polygons$area_km2 <- as.numeric(sf::st_area(mesh_polygons)) * unit_to_m^2 / 1e6
  mesh_polygons$intersects_domain <- lengths(sf::st_intersects(mesh_polygons, simplified_domain)) > 0
  node_points <- sf::st_as_sf(sf::st_sfc(lapply(seq_len(mesh$n), function(i) sf::st_point(mesh$loc[i, 1:2])), crs = sf::st_crs(simplified_domain)))
  node_inside <- lengths(sf::st_covered_by(node_points, simplified_domain)) > 0
  mesh_polygons$inside_domain <- node_inside
  tier2_polygons <- mesh_polygons[node_inside & mesh_polygons$intersects_domain, , drop = FALSE]
  clipped_geometry <- lapply(sf::st_geometry(tier2_polygons), function(g) {
    g <- sf::st_sfc(g, crs = sf::st_crs(simplified_domain))
    clipped <- sf::st_union(sf::st_intersection(g, simplified_domain))
    sf::st_geometry(clipped)[[1L]]
  })
  sf::st_geometry(tier2_polygons) <- sf::st_sfc(clipped_geometry, crs = sf::st_crs(simplified_domain))
  tier2_polygons <- sf::st_make_valid(tier2_polygons)
  tier2_polygons$terrestrial_area_km2 <- as.numeric(sf::st_area(tier2_polygons)) * unit_to_m^2 / 1e6
  tier2_polygons <- tier2_polygons[tier2_polygons$terrestrial_area_km2 > 0, , drop = FALSE]
  terrestrial_area <- numeric(mesh$n)
  terrestrial_area[match(tier2_polygons$poly_id, mesh_polygons$poly_id)] <- tier2_polygons$terrestrial_area_km2
  integration_points <- data.frame(
    point_id = seq_len(mesh$n), x = mesh$loc[, 1], y = mesh$loc[, 2],
    poly_id = mesh_polygons$poly_id, area_km2 = terrestrial_area,
    inside_domain = node_inside
  )
  list(
    mesh = mesh,
    mesh_polygons = mesh_polygons,
    tier2_polygons = tier2_polygons,
    integration_points = integration_points,
    domain = domain,
    simplified_domain = simplified_domain,
    metadata = list(
      crs = sf::st_crs(simplified_domain)$input,
      linear_unit_to_m = unit_to_m,
      distance_units = "configured kilometres converted to CRS units",
      tier2_support = "mesh vertices covered by the simplified terrestrial domain; Voronoi polygons clipped to that domain",
      seed = cfg$project$seed,
      mesh_parameters = cfg$mesh
    )
  )
}
