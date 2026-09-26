`%||%` <- function(x, y) if (is.null(x)) y else x

build_tier1 <- function(observations, integration, time_index) {
  q <- tidyr::crossing(integration, time_index)
  q$.row_id <- paste0("quad_", seq_len(nrow(q)))
  q$source_obs_id <- NA_integer_
  q$Yi <- 0L
  q$sc_Exp <- ifelse(q$inside_domain, q$area_km2, 0.0001)
  p <- observations
  p$.row_id <- paste0("obs_", p$observation_id)
  p$source_obs_id <- p$observation_id
  p$Yi <- 1L
  p$sc_Exp <- 0.0001
  dplyr::bind_rows(p, q)
}

preprocessing_tier1_thinning_config <- function(cfg) {
  value <- if (!is.null(cfg$tier1) && !is.null(cfg$tier1$positive_cellweek_thinning)) cfg$tier1$positive_cellweek_thinning else cfg$tier1_thinning
  if (is.null(value)) value <- list(enabled = TRUE, seed = 1976L)
  value$enabled <- isTRUE(value$enabled)
  value$seed <- as.integer(if (is.null(value$seed)) 1976L else value$seed)
  value
}

preprocessing_hash_file <- function(path) {
  if (is.null(path) || !length(path) || is.na(path) || !file.exists(path) || !requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  tryCatch(digest::digest(file = path, algo = "sha256"), error = function(e) NA_character_)
}

thin_tier1 <- function(tier1, cfg, template = NULL, template_path = NULL) {
  thinning_cfg <- preprocessing_tier1_thinning_config(cfg)
  tier1$.tier1_row_id <- seq_len(nrow(tier1))
  positives <- tier1[tier1$Yi == 1, , drop = FALSE]
  template_checksum <- preprocessing_hash_file(template_path)
  cell_id <- rep(NA_integer_, nrow(positives))
  if (!is.null(template)) {
    points <- terra::vect(positives, geom = c("x", "y"), crs = cfg$study$projected_crs)
    if (!terra::same.crs(points, template)) points <- terra::project(points, terra::crs(template))
    cell_id <- terra::cellFromXY(template, terra::crds(points))
  }
  positives$cell_id <- cell_id
  positives$selection_rank <- ave(seq_len(nrow(positives)), interaction(positives$epiyear, positives$epiweek, positives$cell_id, drop = TRUE), FUN = seq_along)
  eligible <- positives[!is.na(positives$cell_id), , drop = FALSE]
  group_key <- if (nrow(eligible)) paste(eligible$epiyear, eligible$epiweek, eligible$cell_id, sep = "|") else character()
  counts <- if (length(group_key)) table(group_key) else integer()
  duplicate_groups <- if (length(counts)) sum(counts > 1L) else 0L
  duplicate_rows <- if (length(counts)) sum(pmax(as.integer(counts) - 1L, 0L)) else 0L
  if (isTRUE(thinning_cfg$enabled)) {
    if (is.null(template)) stop("Tier 1 thinning requires a template raster when enabled.")
    set.seed(thinning_cfg$seed)
    retained_positive <- eligible |>
      dplyr::group_by(epiyear, epiweek, cell_id) |>
      dplyr::slice_sample(n = 1) |>
      dplyr::ungroup()
    excluded <- dplyr::anti_join(positives, retained_positive[c(".tier1_row_id")], by = ".tier1_row_id")
  } else {
    retained_positive <- positives
    excluded <- positives[0, , drop = FALSE]
  }
  retained <- dplyr::bind_rows(retained_positive, tier1[tier1$Yi == 0, , drop = FALSE]) |>
    dplyr::arrange(.tier1_row_id)
  audit <- data.frame(
    enabled = isTRUE(thinning_cfg$enabled), seed = thinning_cfg$seed,
    template_path = if (is.null(template_path)) NA_character_ else normalizePath(template_path, mustWork = FALSE),
    template_sha256 = template_checksum,
    input_positive_count = nrow(positives), eligible_positive_count = nrow(eligible),
    retained_positive_count = nrow(retained_positive), excluded_positive_count = nrow(excluded),
    positive_outside_template_count = sum(is.na(positives$cell_id)),
    duplicate_positive_cellweek_groups = duplicate_groups,
    duplicate_positive_cellweek_rows = duplicate_rows,
    final_tier1_response_active_count = nrow(retained),
    stringsAsFactors = FALSE
  )
  if (audit$input_positive_count != audit$retained_positive_count + audit$excluded_positive_count) stop("Tier 1 thinning invariant failed.")
  list(retained = retained, excluded = excluded, audit = audit)
}

build_tier2 <- function(observations, support, time_index) {
  polygons <- support$tier2_polygons
  points <- sf::st_as_sf(observations, coords = c("x", "y"), crs = sf::st_crs(support$domain), remove = FALSE)
  hit <- sf::st_covered_by(points, polygons)
  hit_count <- lengths(hit)
  if (any(hit_count != 1L)) {
    stop("Every retained model observation must map to exactly one Tier 2 polygon; invalid assignments: ", sum(hit_count != 1L), ".")
  }
  observations$poly_id <- vapply(hit, function(i) polygons$poly_id[i[[1L]]], integer(1))
  representatives <- sf::st_point_on_surface(polygons)
  coordinates <- sf::st_coordinates(representatives)
  base <- data.frame(
    poly_id = polygons$poly_id,
    x = coordinates[, 1],
    y = coordinates[, 2],
    full_area_km2 = polygons$full_area_km2,
    terrestrial_area_km2 = polygons$terrestrial_area_km2,
    area_km2 = polygons$terrestrial_area_km2
  )
  counts <- observations |> dplyr::count(poly_id, epiyear, epiweek, name = "count")
  out <- tidyr::crossing(base, time_index) |>
    dplyr::left_join(counts, by = c("poly_id", "epiyear", "epiweek"))
  out$count[is.na(out$count)] <- 0L
  out$n_points <- out$count
  out$sc_Exp <- out$area_km2
  out$.row_id <- paste0("poly_", out$poly_id, "_time_", out$time_index)
  out
}

validate_detection_conservation <- function(tier1, tier2, model_eligible_detections, thinning_enabled = FALSE) {
  require_columns(tier1, "Yi", "Tier 1 conservation check")
  require_columns(tier2, "count", "Tier 2 conservation check")
  tier1_positive <- sum(tier1$Yi == 1L, na.rm = TRUE)
  tier2_count <- sum(tier2$count, na.rm = TRUE)
  if (tier2_count != model_eligible_detections) stop("Detection conservation failed: Tier 2 count sum (", tier2_count, ") does not equal model-eligible detections (", model_eligible_detections, ").")
  if (!isTRUE(thinning_enabled) && tier1_positive != tier2_count) stop("Detection conservation failed: Tier 1 positives (", tier1_positive, ") do not equal Tier 2 count sum (", tier2_count, ") with thinning disabled.")
  list(model_eligible_detections = model_eligible_detections, tier1_positive = tier1_positive, tier2_count = tier2_count, thinning_enabled = isTRUE(thinning_enabled))
}

build_prediction_grid <- function(support, time_index, template, target_crs) {
  raster <- validate_raster(template)
  points <- terra::as.points(raster, values = FALSE)
  xy <- terra::crds(points)
  cells <- data.frame(cell_id = terra::cellFromXY(raster, xy), x = xy[, 1], y = xy[, 2])
  template_values <- terra::extract(raster, xy)[[1L]]
  sf_points <- sf::st_as_sf(cells, coords = c("x", "y"), crs = terra::crs(raster), remove = FALSE)
  sf_points <- sf::st_transform(sf_points, target_crs)
  transformed_xy <- sf::st_coordinates(sf_points)
  cells$x <- transformed_xy[, 1]
  cells$y <- transformed_xy[, 2]
  keep <- !is.na(template_values) & lengths(sf::st_within(sf_points, support$simplified_domain)) > 0
  cells <- cells[keep, , drop = FALSE]
  tidyr::crossing(cells, time_index) |>
    dplyr::mutate(.row_id = paste0("cell_", cell_id, "_time_", time_index), space_time_id = .row_id)
}

infer_admin_column <- function(admin_geometry, configured = NULL) {
  if (!is.null(configured) && length(configured) && nzchar(as.character(configured))) {
    if (!configured %in% names(admin_geometry)) stop("Configured administrative column is absent from the boundary: ", configured)
    return(configured)
  }
  candidates <- c("admin_u", "admin_unit", "admin_name", "name", "NAME_0", "GID_0", "country", "COUNTRY")
  found <- candidates[candidates %in% names(admin_geometry)]
  if (length(found)) found[[1L]] else NULL
}

annotate_admin_units <- function(data, admin_geometry, configured_column = NULL, scope = "data") {
  require_columns(data, c("x", "y"), paste0(scope, " administrative annotation target"))
  if (!inherits(admin_geometry, "sf")) stop("Administrative geometry must be an sf object.")
  if (is.na(sf::st_crs(admin_geometry))) stop("Administrative geometry has no CRS.")
  column <- infer_admin_column(admin_geometry, configured_column)
  geometry <- sf::st_make_valid(admin_geometry)
  values <- if (is.null(column)) rep("Unk", nrow(geometry)) else as.character(geometry[[column]])
  values[is.na(values) | !nzchar(trimws(values))] <- "Unk"
  polygon_order <- order(values, seq_along(values), na.last = TRUE)
  geometry <- geometry[polygon_order, , drop = FALSE]
  values <- values[polygon_order]
  points <- sf::st_as_sf(data, coords = c("x", "y"), crs = sf::st_crs(geometry), remove = FALSE)
  hits <- sf::st_intersects(points, geometry)
  assigned <- vapply(hits, function(i) if (length(i)) values[[i[[1L]]]] else "Unk", character(1))
  assigned[is.na(assigned) | !nzchar(assigned)] <- "Unk"
  out <- data
  out$admin_u <- assigned
  audit <- data.frame(
    scope = scope,
    rows = nrow(out),
    assigned = sum(out$admin_u != "Unk"),
    unknown = sum(out$admin_u == "Unk"),
    stringsAsFactors = FALSE
  )
  list(data = out, audit = audit, admin_column = column %||% "Unk", geometry_features = nrow(geometry))
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
    spatial_support = support$metadata,
    preprocessing_metadata = list(
      stage = "geostatistical_preprocessing",
      admin_annotation = audits$admin,
      detection_conservation = audits$conservation,
      temporal_domain = audits$temporal,
      thinning = audits$thinning,
      admin_column = cfg$inputs$admin_column %||% "inferred"
    ),
    excluded_detections = excluded_detections,
    excluded_tier1_positives = thinning_exclusions,
    observation_audit = audits$observation,
    covariate_audit = audits$covariate,
    thinning_audit = audits$thinning,
    temporal_provenance = audits$temporal,
    configuration = cfg,
    provenance = list(timestamp = as.character(Sys.time()), git_commit = NA_character_, R = R.version.string, seed = cfg$project$seed)
  )
}
