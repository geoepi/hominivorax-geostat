parse_argument <- function(args, flag, default = NULL) {
  inline <- grep(paste0("^", flag, "="), args)
  if (length(inline)) return(sub(paste0("^", flag, "="), "", args[inline[1]]))
  separate <- which(args == flag)
  if (length(separate) && length(args) >= separate[1] + 1L) return(args[separate[1] + 1L])
  default
}

print_help <- function() {
  cat(paste(
    "Usage: Rscript scripts/compare_spatial_support.R [options]",
    "",
    "Compare legacy, observation-dependent, and observation-independent mesh support.",
    "",
    "Options:",
    "  --config PATH                 preprocessing YAML (default: config/preprocessing.atlas.yml)",
    "  --output PATH                 comparison output directory",
    "  --mesh-variant NAME           legacy, current, or fixed",
    "  --support-rule NAME           legacy_intersection or refactor_node_inside_intersection",
    "  --representative-method NAME  legacy_centroid, clipped_centroid, point_on_surface, or mesh_node",
    "  --include-dynamic             run the targeted dynamic diagnostic",
    "  --help                        show this help and exit",
    "",
    "--include-dynamic requires all three filter options so that the expensive",
    "diagnostic is run for one explicitly selected support combination.",
    sep = "\n"
  ), "\n")
}

args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args || "-h" %in% args) {
  print_help()
  quit(status = 0, save = "no")
}

config_path <- parse_argument(args, "--config", file.path("config", "preprocessing.atlas.yml"))
output_directory <- parse_argument(args, "--output")
include_dynamic <- "--include-dynamic" %in% args
mesh_variant_arg <- parse_argument(args, "--mesh-variant")
support_rule_arg <- parse_argument(args, "--support-rule")
representative_method_arg <- parse_argument(args, "--representative-method")
if (isTRUE(include_dynamic) && (is.null(mesh_variant_arg) || is.null(support_rule_arg) || is.null(representative_method_arg))) {
  stop("--include-dynamic requires --mesh-variant, --support-rule, and --representative-method.")
}

repo_root <- normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)

cfg <- read_preprocessing_config(config_path, repo_root)
validate_preprocessing_config(cfg)
if (is.null(output_directory)) output_directory <- file.path(cfg$project$output_directory, "spatial_support_comparison")
output_directory <- resolve_preprocessing_path(output_directory, repo_root)
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)

select_names <- function(value, available, flag) {
  selected <- if (is.null(value)) available else value
  unknown <- setdiff(selected, available)
  if (length(unknown)) stop(flag, " must be one of: ", paste(available, collapse = ", "))
  selected
}

variant_names <- select_names(mesh_variant_arg, c("legacy", "current", "fixed"), "--mesh-variant")
support_rules <- select_names(support_rule_arg, c("legacy_intersection", "refactor_node_inside_intersection"), "--support-rule")
representative_methods <- select_names(
  representative_method_arg,
  c("legacy_centroid", "clipped_centroid", "point_on_surface", "mesh_node"),
  "--representative-method"
)

boundary <- sf::st_read(cfg$inputs$study_boundary, quiet = TRUE)
observations <- read_observations(cfg$inputs$observations)
if (identical(cfg$inputs$observation_mode, "standardized")) {
  cleaned <- preprocess_standardized_observations(observations, boundary, cfg)
} else {
  host_lookup <- read_host_lookup(file.path(repo_root, "config", "host_lookup.csv"))
  cleaned <- preprocess_observations(observations, boundary, cfg, host_lookup)
}
if (!nrow(cleaned$data)) stop("No observations remain for the spatial support comparison.")

observation_dependent <- build_spatial_support(boundary, cleaned$data, cfg, use_observation_locations = TRUE)
mesh_boundary <- observation_dependent$mesh_boundary
domain <- observation_dependent$simplified_domain
unit_to_m <- crs_linear_unit_to_m(sf::st_crs(domain))

mesh_polygons_from_mesh <- function(mesh, crs) {
  polygons <- sf::st_as_sf(convert_mesh_poly(mesh))
  sf::st_crs(polygons) <- crs
  polygons$poly_id <- seq_len(nrow(polygons))
  polygons$area_km2 <- as.numeric(sf::st_area(polygons)) * unit_to_m^2 / 1e6
  polygons$full_area_km2 <- polygons$area_km2
  polygons
}

legacy_mesh <- build_inla_mesh(mesh_boundary, cfg, mesh_observations = cleaned$data, use_observation_locations = TRUE)
fixed_mesh <- build_inla_mesh(mesh_boundary, cfg, use_observation_locations = FALSE)
variants <- list(
  legacy = list(mesh = legacy_mesh, polygons = mesh_polygons_from_mesh(legacy_mesh, sf::st_crs(domain))),
  current = list(mesh = observation_dependent$mesh, polygons = observation_dependent$mesh_polygons),
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
for (variant in variant_names) {
  item <- variants[[variant]]
  for (rule in support_rules) {
    keep <- rule_keep(item$classes, rule)
    selected <- item$polygons[keep, , drop = FALSE]
    clipped <- clip_mesh_polygons_to_domain(item$polygons, domain, unit_to_m, which(keep))
    clipped_area <- clipped |>
      dplyr::select(poly_id, terrestrial_area_km2) |>
      sf::st_drop_geometry()
    names(clipped_area)[2] <- "clipped_area_km2"
    area <- data.frame(
      mesh_variant = variant, support_rule = rule,
      poly_id = selected$poly_id,
      full_area_km2 = selected$area_km2,
      stringsAsFactors = FALSE
    ) |>
      dplyr::left_join(clipped_area, by = "poly_id")
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
    point_sets <- list(
      legacy_centroid = sf::st_centroid(full),
      clipped_centroid = sf::st_centroid(clipped),
      point_on_surface = sf::st_point_on_surface(clipped),
      mesh_node = sf::st_as_sf(
        data.frame(poly_id = clipped$poly_id, x = item$mesh$loc[clipped$poly_id, 1], y = item$mesh$loc[clipped$poly_id, 2]),
        coords = c("x", "y"), crs = sf::st_crs(domain)
      )
    )
    for (method in representative_methods) {
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

categories <- dplyr::bind_rows(lapply(variant_names, function(variant) {
  dplyr::count(variants[[variant]]$classes, category, name = "polygons") |>
    dplyr::mutate(mesh_variant = variant, .before = 1)
}))
areas <- dplyr::bind_rows(area_rows)
representatives <- dplyr::bind_rows(representative_rows)
summary <- dplyr::bind_rows(summary_rows)

dynamic_audit_rows <- list()
dynamic_location_rows <- list()
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
      scope = "spatial_support_comparison", return_details = TRUE
    )
    dynamic_audit_rows[[length(dynamic_audit_rows) + 1L]] <- extracted$audit |>
      dplyr::mutate(
        mesh_variant = group_keys$mesh_variant[g],
        support_rule = group_keys$support_rule[g],
        method = group_keys$method[g],
        .before = 1
      )
    details <- dplyr::left_join(extracted$details, target[c(".row_id", "comparison_id", "poly_id")], by = ".row_id")
    affected <- details |>
      dplyr::filter(!direct_extraction) |>
      dplyr::group_by(comparison_id, poly_id, variable) |>
      dplyr::summarise(
        weeks_affected = dplyr::n(),
        direct_missing_weeks = sum(!direct_extraction),
        fallback_success_weeks = sum(nearest_fallback),
        unresolved_weeks = sum(unresolved),
        nearest_valid_distance_min_km = if (any(is.finite(nearest_valid_distance_km))) min(nearest_valid_distance_km, na.rm = TRUE) else NA_real_,
        nearest_valid_distance_median_km = if (any(is.finite(nearest_valid_distance_km))) stats::median(nearest_valid_distance_km, na.rm = TRUE) else NA_real_,
        nearest_valid_distance_max_km = if (any(is.finite(nearest_valid_distance_km))) max(nearest_valid_distance_km, na.rm = TRUE) else NA_real_,
        nearest_distance_bins = paste(unique(nearest_distance_bin(nearest_valid_distance_km)), collapse = ";"),
        .groups = "drop"
      ) |>
      dplyr::left_join(locations[c("comparison_id", "poly_id", "x", "y")], by = c("comparison_id", "poly_id")) |>
      dplyr::mutate(
        mesh_variant = group_keys$mesh_variant[g],
        support_rule = group_keys$support_rule[g],
        method = group_keys$method[g],
        .before = 1
      )
    dynamic_location_rows[[length(dynamic_location_rows) + 1L]] <- affected
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
if (isTRUE(include_dynamic)) {
  write.csv(dplyr::bind_rows(dynamic_audit_rows), file.path(output_directory, "spatial_support_dynamic_audit.csv"), row.names = FALSE)
  write.csv(dplyr::bind_rows(dynamic_location_rows), file.path(output_directory, "spatial_support_dynamic_location_diagnostic.csv"), row.names = FALSE)
}
writeLines(c(
  paste0("config=", normalizePath(config_path, mustWork = FALSE)),
  paste0("include_dynamic=", include_dynamic),
  paste0("mesh_variants=", paste(variant_names, collapse = ",")),
  paste0("support_rules=", paste(support_rules, collapse = ",")),
  paste0("representative_methods=", paste(representative_methods, collapse = ",")),
  paste0("cutoff_supplied_without_observation_locations=TRUE"),
  paste0("output_directory=", normalizePath(output_directory, mustWork = FALSE))
), file.path(output_directory, "comparison_metadata.txt"))
message("Spatial support comparison complete: ", output_directory)
