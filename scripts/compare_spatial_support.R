parse_argument <- function(args, flag, default = NULL) {
  inline <- grep(paste0("^", flag, "="), args)
  if (length(inline)) return(sub(paste0("^", flag, "="), "", args[inline[1]]))
  separate <- which(args == flag)
  if (length(separate) && length(args) >= separate[1] + 1L) return(args[separate[1] + 1L])
  default
}

args <- commandArgs(trailingOnly = TRUE)
config_path <- parse_argument(args, "--config", file.path("config", "preprocessing.atlas.yml"))
output_directory <- parse_argument(args, "--output")
include_dynamic <- "--include-dynamic" %in% args
repo_root <- normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

cfg <- read_preprocessing_config(config_path, repo_root)
validate_preprocessing_config(cfg)
if (is.null(output_directory)) output_directory <- file.path(cfg$project$output_directory, "spatial_support_comparison")
output_directory <- resolve_preprocessing_path(output_directory, repo_root)
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)

boundary <- sf::st_read(cfg$inputs$study_boundary, quiet = TRUE)
observations <- read_observations(cfg$inputs$observations)
if (identical(cfg$inputs$observation_mode, "standardized")) {
  cleaned <- preprocess_standardized_observations(observations, boundary, cfg)
} else {
  host_lookup <- read_host_lookup(file.path(repo_root, "config", "host_lookup.csv"))
  cleaned <- preprocess_observations(observations, boundary, cfg, host_lookup)
}
if (!nrow(cleaned$data)) stop("No observations remain for the legacy/current mesh comparison.")

current <- build_spatial_support(boundary, cleaned$data, cfg)
mesh_boundary <- current$mesh_boundary
domain <- current$simplified_domain
unit_to_m <- crs_linear_unit_to_m(sf::st_crs(domain))

mesh_polygons_from_mesh <- function(mesh, crs) {
  polygons <- sf::st_as_sf(convert_mesh_poly(mesh))
  sf::st_crs(polygons) <- crs
  polygons$poly_id <- seq_len(nrow(polygons))
  polygons$area_km2 <- as.numeric(sf::st_area(polygons)) * unit_to_m^2 / 1e6
  polygons
}

legacy_mesh <- build_inla_mesh(mesh_boundary, cfg, mesh_observations = cleaned$data)
fixed_mesh <- build_inla_mesh(mesh_boundary, cfg, use_observation_locations = FALSE)
variants <- list(
  legacy = list(mesh = legacy_mesh, polygons = mesh_polygons_from_mesh(legacy_mesh, sf::st_crs(domain))),
  current = list(mesh = current$mesh, polygons = current$mesh_polygons),
  fixed = list(mesh = fixed_mesh, polygons = mesh_polygons_from_mesh(fixed_mesh, sf::st_crs(domain)))
)

for (variant in names(variants)) {
  classes <- classify_mesh_support(variants[[variant]]$polygons, variants[[variant]]$mesh, domain)
  variants[[variant]]$classes <- classes
  variants[[variant]]$polygons$intersects_domain <- classes$polygon_intersects_domain
  variants[[variant]]$polygons$inside_domain <- classes$node_inside_domain
}

rule_keep <- function(classes, rule) {
  if (identical(rule, "legacy_intersection")) classes$polygon_intersects_domain else classes$node_inside_domain & classes$polygon_intersects_domain
}

summary_rows <- list()
area_rows <- list()
representative_rows <- list()
template <- validate_raster(cfg$inputs$template_raster)
for (variant in names(variants)) {
  item <- variants[[variant]]
  for (rule in c("legacy_intersection", "refactor_node_inside_intersection")) {
    keep <- rule_keep(item$classes, rule)
    selected <- item$polygons[keep, , drop = FALSE]
    clipped <- clip_mesh_polygons_to_domain(item$polygons, domain, unit_to_m, which(keep))
    area <- data.frame(
      mesh_variant = variant, support_rule = rule,
      poly_id = selected$poly_id,
      full_area_km2 = selected$area_km2,
      stringsAsFactors = FALSE
    )
    clipped_area <- clipped[, c("poly_id", "terrestrial_area_km2"), drop = FALSE]
    names(clipped_area)[2] <- "clipped_area_km2"
    area <- dplyr::left_join(area, clipped_area, by = "poly_id")
    area$clipped_full_ratio <- area$clipped_area_km2 / area$full_area_km2
    area_rows[[length(area_rows) + 1L]] <- area
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      mesh_variant = variant,
      support_rule = rule,
      mesh_nodes = item$mesh$n,
      natural_neighborhoods = nrow(item$polygons),
      polygon_intersects_domain = sum(item$classes$polygon_intersects_domain),
      node_inside_domain = sum(item$classes$node_inside_domain),
      tier2_polygons = nrow(clipped),
      full_area_total_km2 = sum(area$full_area_km2, na.rm = TRUE),
      clipped_area_total_km2 = sum(area$clipped_area_km2, na.rm = TRUE),
      stringsAsFactors = FALSE
    )

    full <- selected[match(clipped$poly_id, selected$poly_id), , drop = FALSE]
    full_centroids <- sf::st_centroid(full)
    clipped_centroids <- sf::st_centroid(clipped)
    point_on_surface <- sf::st_point_on_surface(clipped)
    node_points <- sf::st_as_sf(
      data.frame(poly_id = clipped$poly_id, x = item$mesh$loc[clipped$poly_id, 1], y = item$mesh$loc[clipped$poly_id, 2]),
      coords = c("x", "y"), crs = sf::st_crs(domain)
    )
    point_sets <- list(
      legacy_centroid = full_centroids,
      clipped_centroid = clipped_centroids,
      point_on_surface = point_on_surface,
      mesh_node = node_points
    )
    for (method in names(point_sets)) {
      pts <- point_sets[[method]]
      coords <- sf::st_coordinates(pts)
      rep <- data.frame(
        mesh_variant = variant, support_rule = rule, method = method,
        poly_id = clipped$poly_id, x = coords[, 1], y = coords[, 2],
        stringsAsFactors = FALSE
      )
      full_geom <- full[match(rep$poly_id, full$poly_id), , drop = FALSE]
      clipped_geom <- clipped[match(rep$poly_id, clipped$poly_id), , drop = FALSE]
      rep_points <- sf::st_as_sf(rep, coords = c("x", "y"), crs = sf::st_crs(domain), remove = FALSE)
      full_hits <- sf::st_intersects(rep_points, full_geom)
      clipped_hits <- sf::st_intersects(rep_points, clipped_geom)
      rep$inside_own_full_polygon <- vapply(seq_len(nrow(rep)), function(i) i %in% full_hits[[i]], logical(1))
      rep$inside_own_clipped_polygon <- vapply(seq_len(nrow(rep)), function(i) i %in% clipped_hits[[i]], logical(1))
      rep$inside_terrestrial_domain <- lengths(sf::st_covered_by(rep_points, domain)) > 0
      template_points <- terra::vect(rep, geom = c("x", "y"), crs = cfg$study$projected_crs)
      if (!terra::same.crs(template_points, template)) template_points <- terra::project(template_points, terra::crs(template))
      rep$valid_template_support <- !is.na(terra::extract(template, template_points, method = "bilinear")[[2L]])
      rep$dynamic_unresolved_rows <- NA_integer_
      rep$dynamic_unresolved_any_week <- NA
      representative_rows[[length(representative_rows) + 1L]] <- rep
    }
  }
}

categories <- dplyr::bind_rows(lapply(names(variants), function(variant) {
  dplyr::count(variants[[variant]]$classes, category, name = "polygons") |>
    dplyr::mutate(mesh_variant = variant, .before = 1)
}))
areas <- dplyr::bind_rows(area_rows)
representatives <- dplyr::bind_rows(representative_rows)
summary <- dplyr::bind_rows(summary_rows)

if (isTRUE(include_dynamic)) {
  dynamic_specs <- cfg$dynamic_covariates
  dynamic_names <- c(minimum_temperature = "mintemp", soil_moisture = "soilmoist", leaf_area_low = "leafarea", relative_humidity = "rhum")
  names(dynamic_specs) <- unname(dynamic_names[names(dynamic_specs)])
  time_index <- make_week_index(cfg$study$start_date, cfg$study$end_date)
  representatives$comparison_id <- seq_len(nrow(representatives))
  group_keys <- unique(representatives[c("mesh_variant", "support_rule", "method")])
  for (g in seq_len(nrow(group_keys))) {
    group_rows <- which(
      representatives$mesh_variant == group_keys$mesh_variant[g] &
        representatives$support_rule == group_keys$support_rule[g] &
        representatives$method == group_keys$method[g]
    )
    locations <- representatives[group_rows, c("comparison_id", "poly_id", "x", "y"), drop = FALSE]
    target <- tidyr::crossing(locations, time_index)
    target$.row_id <- paste0("comparison_", target$comparison_id, "_", target$time_index)
    extracted <- extract_dynamic_covariates(
      target, dynamic_specs, cfg$study$projected_crs, time_index,
      missing_policy = "retain", search_radius_km = cfg$extraction$dynamic_search_radius_km,
      scope = "spatial_support_comparison"
    )
    dynamic_cols <- intersect(names(dynamic_specs), names(extracted$data))
    unresolved <- !stats::complete.cases(extracted$data[dynamic_cols])
    unresolved_by_location <- tapply(unresolved, extracted$data$comparison_id, sum)
    for (location_id in names(unresolved_by_location)) {
      row <- which(representatives$comparison_id == as.integer(location_id))
      representatives$dynamic_unresolved_rows[row] <- as.integer(unresolved_by_location[[location_id]])
      representatives$dynamic_unresolved_any_week[row] <- unresolved_by_location[[location_id]] > 0
    }
  }
}

write.csv(summary, file.path(output_directory, "spatial_support_summary.csv"), row.names = FALSE)
write.csv(categories, file.path(output_directory, "spatial_support_categories.csv"), row.names = FALSE)
write.csv(areas, file.path(output_directory, "spatial_support_area_comparison.csv"), row.names = FALSE)
write.csv(representatives, file.path(output_directory, "representative_location_comparison.csv"), row.names = FALSE)
writeLines(c(
  paste0("config=", normalizePath(config_path, mustWork = FALSE)),
  paste0("include_dynamic=", include_dynamic),
  paste0("cutoff_supplied_without_observation_locations=TRUE"),
  paste0("output_directory=", normalizePath(output_directory, mustWork = FALSE))
), file.path(output_directory, "comparison_metadata.txt"))
message("Spatial support comparison complete: ", output_directory)
