build_tier1 <- function(observations, integration, time_index) {
  q <- tidyr::crossing(integration, time_index)
  q$.row_id <- paste0("quad_", seq_len(nrow(q)))
  q$source_obs_id <- NA_integer_
  q$Yi <- 0
  q$sc_Exp <- ifelse(q$inside_domain, q$area_km2, 0.0001)
  p <- observations
  p$.row_id <- paste0("obs_", p$observation_id)
  p$source_obs_id <- p$observation_id
  p$Yi <- 1
  p$sc_Exp <- 0.0001
  dplyr::bind_rows(p, q)
}

thin_tier1 <- function(tier1, cfg, template = NULL) {
  tier1$.tier1_row_id <- seq_len(nrow(tier1))
  positives <- tier1[tier1$Yi == 1, , drop = FALSE]
  if (!isTRUE(cfg$tier1_thinning$enabled)) {
    positives$cell_id <- NA_integer_
    positives$selection_rank <- 1L
    return(list(retained = tier1, excluded = positives[0, , drop = FALSE], audit = data.frame(input_positive_count = nrow(positives), retained_positive_count = nrow(positives), excluded_positive_count = 0, seed = cfg$tier1_thinning$seed)))
  }
  if (is.null(template)) stop("Tier 1 thinning requires a template raster.")
  positives$cell_id <- terra::cellFromXY(template, as.matrix(positives[c("x", "y")]))
  positives$selection_rank <- ave(seq_len(nrow(positives)), interaction(positives$epiyear, positives$epiweek, positives$cell_id, drop = TRUE), FUN = seq_along)
  set.seed(cfg$tier1_thinning$seed)
  retained_positive <- positives |>
    dplyr::group_by(epiyear, epiweek, cell_id) |>
    dplyr::slice_sample(n = 1) |>
    dplyr::ungroup()
  excluded <- dplyr::anti_join(positives, retained_positive[c(".tier1_row_id")], by = ".tier1_row_id")
  retained <- dplyr::bind_rows(retained_positive, tier1[tier1$Yi == 0, , drop = FALSE]) |>
    dplyr::arrange(.tier1_row_id)
  audit <- data.frame(input_positive_count = nrow(positives), retained_positive_count = nrow(retained_positive), excluded_positive_count = nrow(excluded), seed = cfg$tier1_thinning$seed)
  if (audit$input_positive_count != audit$retained_positive_count + audit$excluded_positive_count) stop("Tier 1 thinning invariant failed.")
  list(retained = retained, excluded = excluded, audit = audit)
}

build_tier2 <- function(observations, support, time_index) {
  points <- sf::st_as_sf(observations, coords = c("x", "y"), crs = sf::st_crs(support$domain), remove = FALSE)
  hit <- sf::st_within(points, support$mesh_polygons)
  observations$poly_id <- vapply(hit, function(i) if (length(i)) support$mesh_polygons$poly_id[i[1]] else NA_integer_, integer(1))
  centroids <- sf::st_coordinates(sf::st_centroid(support$mesh_polygons))
  base <- data.frame(poly_id = support$mesh_polygons$poly_id, x = centroids[, 1], y = centroids[, 2], area_km2 = support$mesh_polygons$area_km2)
  counts <- observations |> dplyr::filter(!is.na(poly_id)) |> dplyr::count(poly_id, epiyear, epiweek, name = "n_points")
  out <- tidyr::crossing(base, time_index) |>
    dplyr::left_join(counts, by = c("poly_id", "epiyear", "epiweek"))
  out$n_points[is.na(out$n_points)] <- 0L
  out$Yi <- out$n_points
  out$sc_Exp <- out$area_km2
  out$.row_id <- paste0("poly_", out$poly_id, "_time_", out$time_index)
  out
}

build_prediction_grid <- function(support, time_index, template, target_crs) {
  raster <- validate_raster(template)
  points <- terra::as.points(raster, values = FALSE)
  xy <- terra::crds(points)
  cells <- data.frame(cell_id = terra::cellFromXY(raster, xy), x = xy[, 1], y = xy[, 2])
  sf_points <- sf::st_as_sf(cells, coords = c("x", "y"), crs = target_crs, remove = FALSE)
  keep <- lengths(sf::st_within(sf_points, support$simplified_domain)) > 0
  cells <- cells[keep, , drop = FALSE]
  tidyr::crossing(cells, time_index) |>
    dplyr::mutate(.row_id = paste0("cell_", cell_id, "_time_", time_index), space_time_id = .row_id)
}

apply_missing_policy <- function(data, audit, cfg) {
  dynamic <- c("mintemp", "soilmoist", "leafarea", "rhum")
  if (cfg$transformations$dynamic_missing_policy == "complete_case") {
    keep <- stats::complete.cases(data[dynamic])
    data <- data[keep, , drop = FALSE]
  } else if (cfg$transformations$dynamic_missing_policy == "fail" && any(audit$missing > 0)) {
    stop("Dynamic covariate missingness violates configured policy.")
  }
  data
}

assemble_model_inputs <- function(tier1, tier2, prediction_grid, support, time_index, transformations, audits, cfg, excluded_detections, thinning_exclusions) {
  list(
    tier1 = tier1, tier2 = tier2, prediction_grid = prediction_grid,
    mesh = support$mesh, mesh_polygons = support$mesh_polygons,
    time_index = time_index, transformations = transformations,
    excluded_detections = excluded_detections,
    excluded_tier1_positives = thinning_exclusions,
    observation_audit = audits$observation,
    covariate_audit = audits$covariate,
    thinning_audit = audits$thinning,
    configuration = cfg,
    provenance = list(timestamp = as.character(Sys.time()), git_commit = NA_character_, R = R.version.string, seed = cfg$project$seed)
  )
}
