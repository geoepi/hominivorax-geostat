validate_boundary <- function(boundary, projected_crs) { if (is.na(sf::st_crs(boundary))) stop("Study boundary has no CRS"); sf::st_transform(sf::st_union(sf::st_make_valid(boundary)), projected_crs) }
build_spatial_support <- function(boundary, observations, cfg, mesh = NULL) {
  domain <- validate_boundary(boundary, cfg$study$projected_crs)
  if (!is.null(mesh)) { polys <- sf::st_transform(sf::st_read(mesh, quiet = TRUE), sf::st_crs(domain)); polys$poly_id <- seq_len(nrow(polys)); polys$area <- as.numeric(sf::st_area(polys)) } else { polys <- sf::st_as_sf(sf::st_make_grid(domain, n = c(7, 7))); polys <- polys[sf::st_intersects(polys, domain, sparse = FALSE)[,1], ]; polys$poly_id <- seq_len(nrow(polys)); polys$area <- as.numeric(sf::st_area(polys)) }
  nodes <- sf::st_coordinates(sf::st_centroid(polys)); list(mesh = mesh, mesh_polygons = polys, integration_points = data.frame(x = nodes[,1], y = nodes[,2], poly_id = polys$poly_id, area = polys$area), domain = domain, metadata = list(crs = sf::st_crs(domain)$input, units = sf::st_crs(domain)$units_gdal))
}
