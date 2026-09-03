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

build_inla_mesh <- function(mesh_boundary, cfg, mesh_observations = NULL, use_observation_locations = !is.null(mesh_observations)) {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA is required for mesh construction.")
  boundary_sp <- methods::as(sf::st_as_sf(mesh_boundary), "Spatial")
  mesh_args <- list(
    boundary = INLA::inla.sp2segment(boundary_sp),
    cutoff = cfg$mesh$cutoff_km * 1000 / crs_linear_unit_to_m(sf::st_crs(mesh_boundary)),
    max.edge = cfg$mesh$max_edge_km * 1000 / crs_linear_unit_to_m(sf::st_crs(mesh_boundary)),
    offset = cfg$mesh$offset_km * 1000 / crs_linear_unit_to_m(sf::st_crs(mesh_boundary)),
    min.angle = cfg$mesh$minimum_angle_degrees
  )
  if (isTRUE(use_observation_locations)) {
    if (is.null(mesh_observations)) stop("Observation-dependent mesh construction requires observations.")
    loc <- mesh_observations[, c("x", "y"), drop = FALSE]
    loc <- as.matrix(loc[stats::complete.cases(loc), , drop = FALSE])
    if (!nrow(loc)) stop("At least one valid observation is required for observation-dependent mesh construction.")
    mesh_args$loc <- loc
  }
  set.seed(cfg$project$seed)
  mesh <- do.call(INLA::inla.mesh.2d, mesh_args)
  if (is.null(mesh) || mesh$n < 1) stop("INLA returned an empty mesh.")
  mesh
}

build_observation_independent_mesh <- function(boundary, cfg) {
  analysis_domain <- build_analysis_domain(boundary, cfg)
  domain <- analysis_domain$domain
  simplified_domain <- analysis_domain$simplified_domain
  unit_to_m <- analysis_domain$unit_to_m
  mesh_boundary <- sf::st_buffer(simplified_domain, cfg$mesh$boundary_buffer_km * 1000 / unit_to_m)
  list(
    mesh = build_inla_mesh(mesh_boundary, cfg, mesh_observations = NULL, use_observation_locations = FALSE),
    domain = domain,
    simplified_domain = simplified_domain,
    mesh_boundary = mesh_boundary,
    metadata = list(
      mesh_observation_dependent = FALSE,
      cutoff_supplied_without_observation_locations = TRUE,
      seed = cfg$project$seed,
      mesh_parameters = cfg$mesh
    )
  )
}

build_analysis_domain <- function(boundary, cfg) {
  domain <- validate_boundary(boundary, cfg$study$projected_crs)
  simplified_domain <- simplify_analysis_domain(domain, cfg$mesh$island_area_threshold_km2)
  if (length(sf::st_geometry(simplified_domain)) == 0L) stop("Configured island-area threshold removed the entire analysis domain.")
  list(
    domain = domain,
    simplified_domain = simplified_domain,
    unit_to_m = crs_linear_unit_to_m(sf::st_crs(simplified_domain)),
    island_area_threshold_km2 = cfg$mesh$island_area_threshold_km2
  )
}

classify_mesh_support <- function(mesh_polygons, mesh, domain) {
  if (nrow(mesh_polygons) != mesh$n) stop("Mesh polygon count does not equal mesh node count.")
  node_points <- sf::st_as_sf(
    data.frame(poly_id = seq_len(mesh$n), x = mesh$loc[, 1], y = mesh$loc[, 2]),
    coords = c("x", "y"), crs = sf::st_crs(domain)
  )
  polygon_intersects_domain <- lengths(sf::st_intersects(mesh_polygons, domain)) > 0
  node_inside_domain <- lengths(sf::st_covered_by(node_points, domain)) > 0
  category <- ifelse(
    node_inside_domain & polygon_intersects_domain, "A_node_inside_polygon_intersects",
    ifelse(!node_inside_domain & polygon_intersects_domain, "B_node_outside_polygon_intersects",
      ifelse(node_inside_domain & !polygon_intersects_domain, "C_node_inside_polygon_disjoint", "D_node_outside_polygon_disjoint")
    )
  )
  data.frame(
    poly_id = seq_len(mesh$n),
    node_inside_domain = node_inside_domain,
    polygon_intersects_domain = polygon_intersects_domain,
    category = category,
    stringsAsFactors = FALSE
  )
}

clip_mesh_polygons_to_domain <- function(mesh_polygons, domain, unit_to_m, keep = seq_len(nrow(mesh_polygons))) {
  selected <- mesh_polygons[keep, , drop = FALSE]
  clipped_geometry <- lapply(sf::st_geometry(selected), function(g) {
    g <- sf::st_sfc(g, crs = sf::st_crs(domain))
    clipped <- sf::st_union(sf::st_intersection(g, domain))
    sf::st_geometry(clipped)[[1L]]
  })
  sf::st_geometry(selected) <- sf::st_sfc(clipped_geometry, crs = sf::st_crs(domain))
  selected <- sf::st_make_valid(selected)
  selected$terrestrial_area_km2 <- as.numeric(sf::st_area(selected)) * unit_to_m^2 / 1e6
  selected[selected$terrestrial_area_km2 > 0, , drop = FALSE]
}

build_spatial_support <- function(boundary, observations, cfg, use_observation_locations = NULL, analysis_domain = NULL) {
  if (is.null(use_observation_locations)) {
    use_observation_locations <- isTRUE(cfg$mesh$use_observation_locations)
  }
  if (is.null(analysis_domain)) analysis_domain <- build_analysis_domain(boundary, cfg)
  domain <- analysis_domain$domain
  simplified_domain <- analysis_domain$simplified_domain
  unit_to_m <- analysis_domain$unit_to_m
  buffer <- cfg$mesh$boundary_buffer_km * 1000 / unit_to_m
  mesh_boundary <- sf::st_buffer(simplified_domain, buffer)
  mesh <- build_inla_mesh(mesh_boundary, cfg, mesh_observations = if (isTRUE(use_observation_locations)) observations else NULL, use_observation_locations = use_observation_locations)
  mesh_sp <- convert_mesh_poly(mesh)
  mesh_polygons <- sf::st_as_sf(mesh_sp)
  sf::st_crs(mesh_polygons) <- sf::st_crs(simplified_domain)
  mesh_polygons$poly_id <- seq_len(nrow(mesh_polygons))
  mesh_polygons$area_km2 <- as.numeric(sf::st_area(mesh_polygons)) * unit_to_m^2 / 1e6
  mesh_polygons$full_area_km2 <- mesh_polygons$area_km2
  mesh_polygons$intersects_domain <- lengths(sf::st_intersects(mesh_polygons, simplified_domain)) > 0
  node_points <- sf::st_as_sf(sf::st_sfc(lapply(seq_len(mesh$n), function(i) sf::st_point(mesh$loc[i, 1:2])), crs = sf::st_crs(simplified_domain)))
  node_inside <- lengths(sf::st_covered_by(node_points, simplified_domain)) > 0
  mesh_polygons$inside_domain <- node_inside
  tier2_polygons <- clip_mesh_polygons_to_domain(
    mesh_polygons, simplified_domain, unit_to_m,
    keep = which(mesh_polygons$intersects_domain)
  )
  terrestrial_area <- numeric(mesh$n)
  terrestrial_area[match(tier2_polygons$poly_id, mesh_polygons$poly_id)] <- tier2_polygons$terrestrial_area_km2
  integration_points <- data.frame(
    point_id = seq_len(mesh$n), x = mesh$loc[, 1], y = mesh$loc[, 2],
    poly_id = mesh_polygons$poly_id, area_km2 = terrestrial_area,
    inside_domain = node_inside
  )
  list(
    mesh = mesh,
    mesh_boundary = mesh_boundary,
    mesh_polygons = mesh_polygons,
    tier2_polygons = tier2_polygons,
    integration_points = integration_points,
    domain = domain,
    simplified_domain = simplified_domain,
    metadata = list(
      crs = sf::st_crs(simplified_domain)$input,
      linear_unit_to_m = unit_to_m,
      distance_units = "configured kilometres converted to CRS units",
      tier2_support = "Voronoi polygons intersecting the simplified terrestrial domain; retained polygons clipped to that domain",
      tier2_representative = "st_point_on_surface of clipped terrestrial polygon",
      tier1_integration_points = "mesh nodes, retaining current outside-domain exposure semantics",
      mesh_observation_dependent = isTRUE(use_observation_locations),
      seed = cfg$project$seed,
      mesh_parameters = cfg$mesh
    )
  )
}
