cds_upstream_provenance_required_products <- c(
  mintemp = "era5_mintemp",
  soilmoist = "era5_soilmoist",
  leafarea = "era5_lai_low",
  rhum = "agera5_relhum_min"
)

cds_upstream_provenance_require <- function(packages = c("digest", "jsonlite")) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) stop("CDS upstream provenance requires: ", paste(missing, collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

cds_upstream_provenance_scalar <- function(value) {
  if (is.null(value) || !length(value)) return(NA_character_)
  if (is.list(value)) value <- unlist(value, use.names = FALSE)
  if (!length(value) || is.na(value[[1L]])) return(NA_character_)
  value <- trimws(as.character(value[[1L]]))
  if (!nzchar(value)) NA_character_ else value
}

cds_upstream_provenance_values <- function(value) {
  if (is.null(value) || !length(value)) return(character())
  if (is.list(value)) value <- unlist(value, use.names = FALSE)
  value <- trimws(as.character(value))
  value[!is.na(value) & nzchar(value)]
}

cds_upstream_provenance_first <- function(object, fields) {
  for (field in fields) {
    if (!is.null(object[[field]])) {
      value <- cds_upstream_provenance_scalar(object[[field]])
      if (!is.na(value)) return(value)
    }
  }
  NA_character_
}

cds_upstream_provenance_field_values <- function(object, fields) {
  values <- unlist(lapply(fields, function(field) cds_upstream_provenance_values(object[[field]])), use.names = FALSE)
  sort(unique(values))
}

cds_upstream_provenance_json_vector <- function(values) {
  cds_upstream_provenance_require("jsonlite")
  values <- sort(unique(cds_upstream_provenance_values(values)))
  if (!length(values)) return("")
  as.character(jsonlite::toJSON(values, auto_unbox = FALSE, null = "null"))
}

cds_upstream_provenance_week_key <- function(label) {
  parsed <- production_orchestration_parse_week(label)
  paste(parsed$year, parsed$week, sep = "-")
}

cds_upstream_provenance_week_order <- function(label) {
  parsed <- production_orchestration_parse_week(label)
  parsed$year * 100L + parsed$week
}

cds_upstream_provenance_normalize_week <- function(value, object = NULL) {
  value <- cds_upstream_provenance_scalar(value)
  if (!is.na(value) && grepl("^20[0-9]{2}-W[0-9]{1,2}$", value, ignore.case = TRUE)) {
    return(production_orchestration_parse_week(value)$label)
  }
  if (!is.null(object)) {
    year <- cds_upstream_provenance_first(object, c("epiyear", "iso_year", "year"))
    week <- cds_upstream_provenance_first(object, c("epiweek", "iso_week", "week"))
    if (!is.na(year) && !is.na(week)) {
      return(production_orchestration_parse_week(sprintf("%s-W%s", year, week))$label)
    }
  }
  NA_character_
}

cds_upstream_provenance_json_read <- function(path) {
  cds_upstream_provenance_require("jsonlite")
  if (!file.exists(path)) stop("Required CDS provenance sidecar does not exist: ", path, call. = FALSE)
  value <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(error) stop("CDS provenance sidecar is not parseable JSON: ", path, " (", conditionMessage(error), ")", call. = FALSE)
  )
  if (!is.list(value) || is.null(names(value))) stop("CDS provenance sidecar must contain a JSON object: ", path, call. = FALSE)
  value
}

cds_upstream_provenance_configured <- function(contract) {
  cfg <- contract$settings$cfg %||% list()
  preprocessing <- contract$settings$stages$preprocessing %||% list()
  dynamic <- preprocessing$dynamic_covariates %||% list()
  paths <- unname(as.character(unlist(dynamic, use.names = FALSE)))
  supplied <- !is.null(cfg$upstream$cds_datagrab) || !is.null(preprocessing$upstream$cds_datagrab)
  supplied || any(grepl("cds-datagrab-output", paths, fixed = TRUE))
}

cds_upstream_provenance_dynamic_specs <- function(contract) {
  preprocessing <- contract$settings$stages$preprocessing %||% list()
  dynamic <- preprocessing$dynamic_covariates %||% list()
  if ((!is.list(dynamic) && !is.character(dynamic)) || is.null(names(dynamic))) stop("CDS provenance requires named preprocessing dynamic_covariates.", call. = FALSE)
  required <- names(cds_upstream_provenance_required_products)
  aliases <- c(mintemp = "minimum_temperature", soilmoist = "soil_moisture", leafarea = "leaf_area_low", rhum = "relative_humidity")
  source_names <- ifelse(required %in% names(dynamic), required, unname(aliases[required]))
  if (!all(source_names %in% names(dynamic))) {
    stop("CDS provenance is missing required model covariates: ", paste(required[!(source_names %in% names(dynamic))], collapse = ", "), call. = FALSE)
  }
  paths <- vapply(required, function(name) {
    value <- dynamic[[unname(source_names[required == name])]]
    if (length(value) != 1L || is.na(value) || !nzchar(as.character(value))) stop("CDS provenance dynamic covariate path is missing for ", name, ".", call. = FALSE)
    normalizePath(as.character(value), mustWork = FALSE)
  }, character(1L))
  names(paths) <- required
  paths
}

cds_upstream_provenance_portfolio_roots <- function(contract, dynamic_paths) {
  cfg <- contract$settings$cfg %||% list()
  preprocessing <- contract$settings$stages$preprocessing %||% list()
  supplied <- cfg$upstream$cds_datagrab %||% preprocessing$upstream$cds_datagrab %||% list()
  configured <- supplied$portfolio_manifest_root %||% supplied$portfolio_root %||% supplied$portfolio_manifest
  configured <- if (is.null(configured) || !length(configured)) character() else normalizePath(as.character(configured), mustWork = FALSE)
  inferred <- unique(vapply(dynamic_paths, function(path) {
    normalizePath(file.path(dirname(dirname(dirname(dirname(path)))), "runs", "production", "_portfolio"), mustWork = FALSE)
  }, character(1L)))
  unique(c(configured, inferred))
}

cds_upstream_provenance_manifest_candidates <- function(roots) {
  files <- character()
  for (root in roots) {
    if (file.exists(root) && !dir.exists(root)) {
      files <- c(files, root)
    } else if (dir.exists(root)) {
      files <- c(files, list.files(root, pattern = "portfolio_manifest\\.json$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE))
    }
  }
  sort(unique(normalizePath(files, mustWork = FALSE)))
}

cds_upstream_provenance_date <- function(value) {
  value <- cds_upstream_provenance_scalar(value)
  if (is.na(value)) return(as.Date(NA))
  parsed <- suppressWarnings(as.Date(value, tryFormats = c("%Y-%m-%d", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%OSZ")))
  if (is.na(parsed)) as.Date(NA) else parsed
}

cds_upstream_provenance_portfolio_product <- function(portfolio, product_id) {
  products <- portfolio$products %||% list()
  product <- products[[product_id]]
  if (is.null(product) || !is.list(product)) stop("CDS portfolio manifest lacks product record: ", product_id, call. = FALSE)
  product
}

cds_upstream_provenance_validate_portfolio <- function(portfolio, manifest_path, required_products, horizon_end) {
  if (!identical(tolower(cds_upstream_provenance_scalar(portfolio$status)), "success")) return(NULL)
  products <- portfolio$products %||% list()
  if (!all(required_products %in% names(products))) return(NULL)
  for (product_id in required_products) {
    product <- products[[product_id]]
    if (!is.list(product) || !identical(tolower(cds_upstream_provenance_scalar(product$status)), "success")) return(NULL)
    missing <- cds_upstream_provenance_values(product$weekly_missing)
    if (length(missing)) return(NULL)
    if (!isTRUE(as.numeric(product$weekly_present %||% NA_real_) >= as.numeric(product$weekly_expected %||% Inf))) return(NULL)
  }
  endpoint <- cds_upstream_provenance_date(portfolio$requested_through %||% portfolio$effective_requested_end %||% portfolio$portfolio_inventory_end %||% portfolio$known_observed_end)
  if (is.na(endpoint)) return(NULL)
  validated_through <- production_orchestration_week_label(endpoint)
  if (cds_upstream_provenance_week_order(validated_through) < cds_upstream_provenance_week_order(horizon_end)) return(NULL)
  list(
    portfolio = portfolio,
    manifest_path = normalizePath(manifest_path, mustWork = TRUE),
    validated_through = validated_through,
    endpoint_date = endpoint
  )
}

cds_upstream_provenance_select_portfolio <- function(contract, dynamic_paths) {
  required_products <- unname(cds_upstream_provenance_required_products)
  roots <- cds_upstream_provenance_portfolio_roots(contract, dynamic_paths)
  candidates <- cds_upstream_provenance_manifest_candidates(roots)
  if (!length(candidates)) stop("No CDS portfolio manifest was found in: ", paste(roots, collapse = "; "), call. = FALSE)
  horizon_end <- contract$horizon$resolved_final_complete_epiweek
  valid <- lapply(candidates, function(path) {
    portfolio <- tryCatch(cds_upstream_provenance_json_read(path), error = function(error) NULL)
    if (is.null(portfolio)) return(NULL)
    tryCatch(cds_upstream_provenance_validate_portfolio(portfolio, path, required_products, horizon_end), error = function(error) NULL)
  })
  valid <- Filter(Negate(is.null), valid)
  if (!length(valid)) stop("No successful CDS portfolio manifest provides complete coverage through ", horizon_end, ".", call. = FALSE)
  endpoint <- as.numeric(vapply(valid, function(x) x$endpoint_date, as.Date(NA)))
  completed <- vapply(valid, function(x) cds_upstream_provenance_scalar(x$portfolio$completed_at %||% x$portfolio$started_at), character(1L))
  paths <- vapply(valid, function(x) x$manifest_path, character(1L))
  selected <- valid[[order(endpoint, completed, paths, decreasing = TRUE)[[1L]]]]
  selected$manifest_sha256 <- production_orchestration_hash_file(selected$manifest_path)
  selected
}

cds_upstream_provenance_weekly_index <- function(path, expected_labels) {
  if (!dir.exists(path)) stop("CDS weekly raster directory does not exist: ", path, call. = FALSE)
  files <- list.files(path, pattern = "\\.(tif|grd)$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) stop("No CDS weekly rasters found in: ", path, call. = FALSE)
  match <- regexec("(?i)(?:^|[^0-9])(20[0-9]{2})[^0-9]+(?:w(?:eek)?[-_ ]*)?([0-9]{1,2})(?=[^0-9]|$)", basename(files), perl = TRUE)
  groups <- regmatches(basename(files), match)
  year <- vapply(groups, function(x) if (length(x) >= 3L) as.integer(x[[2L]]) else NA_integer_, integer(1L))
  week <- vapply(groups, function(x) if (length(x) >= 3L) as.integer(x[[3L]]) else NA_integer_, integer(1L))
  if (anyNA(year) || anyNA(week)) stop("Every CDS weekly raster must encode an ISO year and week: ", path, call. = FALSE)
  if (any(week < 1L | week > 53L)) stop("CDS weekly raster contains an invalid ISO week: ", path, call. = FALSE)
  keys <- paste(year, week, sep = "-")
  if (anyDuplicated(keys)) stop("Duplicate CDS weekly raster year-week keys: ", path, call. = FALSE)
  expected_keys <- vapply(expected_labels, cds_upstream_provenance_week_key, character(1L))
  missing <- setdiff(expected_keys, keys)
  if (length(missing)) stop("CDS weekly raster directory lacks required weeks in ", path, ": ", paste(missing, collapse = ", "), call. = FALSE)
  data.frame(file = normalizePath(files, mustWork = TRUE), key = keys, stringsAsFactors = FALSE)
}

cds_upstream_provenance_source_workflow_id <- function(portfolio, product_id) {
  ids <- portfolio$source_workflow_ids
  if (is.list(ids) && !is.null(names(ids)) && product_id %in% names(ids)) return(cds_upstream_provenance_scalar(ids[[product_id]]))
  ids <- cds_upstream_provenance_values(ids)
  product_ids <- cds_upstream_provenance_values(portfolio$product_ids)
  if (length(ids) && length(product_ids) == length(ids) && product_id %in% product_ids) return(ids[[match(product_id, product_ids)]])
  NA_character_
}

cds_upstream_provenance_row <- function(contract, product_id, model_covariate, workflow_id, epiweek, raster_path, sidecar_path, sidecar) {
  product_in_sidecar <- cds_upstream_provenance_first(sidecar, c("product_id", "variable_id", "product", "variable"))
  if (is.na(product_in_sidecar) || !identical(product_in_sidecar, product_id)) stop("CDS sidecar product does not match expected product for ", raster_path, call. = FALSE)
  week_in_sidecar <- cds_upstream_provenance_normalize_week(sidecar$week_id %||% sidecar$epiweek, sidecar)
  if (is.na(week_in_sidecar) || !identical(week_in_sidecar, epiweek)) stop("CDS sidecar week does not match expected week for ", raster_path, call. = FALSE)
  output_sha <- cds_upstream_provenance_first(sidecar, c("output_sha256", "output_sha", "sha256"))
  if (is.na(output_sha) || !grepl("^[A-Fa-f0-9]{64}$", output_sha)) stop("CDS sidecar lacks an authoritative 64-character output_sha256 for ", raster_path, call. = FALSE)
  input_fingerprint <- cds_upstream_provenance_first(sidecar, c("input_fingerprint", "reuse_input_fingerprint"))
  if (is.na(input_fingerprint)) stop("CDS sidecar lacks input_fingerprint for ", raster_path, call. = FALSE)
  request_hashes <- cds_upstream_provenance_field_values(sidecar, c("source_request_hashes", "source_request_hash", "request_hashes", "request_hash"))
  data.frame(
    workflow_id = if (is.na(workflow_id)) "" else workflow_id,
    product_id = product_id,
    model_covariate = model_covariate,
    epiweek = epiweek,
    input_raster_path = normalizePath(raster_path, mustWork = TRUE),
    sidecar_path = normalizePath(sidecar_path, mustWork = TRUE),
    sidecar_sha256 = production_orchestration_hash_file(sidecar_path),
    output_sha256 = tolower(output_sha),
    input_fingerprint = input_fingerprint,
    source_family_id = cds_upstream_provenance_first(sidecar, c("source_family_id", "source_family")) %||% "",
    source_request_hashes = cds_upstream_provenance_json_vector(request_hashes),
    variable_spec_hash = cds_upstream_provenance_first(sidecar, c("variable_spec_hash", "spec_hash")) %||% "",
    aggregation_algorithm_version = cds_upstream_provenance_first(sidecar, c("aggregation_algorithm_version", "aggregation_version")) %||% "",
    weekly_statistic = cds_upstream_provenance_first(sidecar, c("weekly_statistic", "statistic")) %||% "",
    template_sha256 = cds_upstream_provenance_first(sidecar, c("template_sha256", "template_checksum")) %||% "",
    intermediate_artifact_path = normalizePath(file.path(contract$paths$stage1, "model_inputs.rds"), mustWork = FALSE),
    stringsAsFactors = FALSE
  )
}

cds_upstream_provenance_canonical_text <- function(data) {
  cds_upstream_provenance_require("jsonlite")
  columns <- c("workflow_id", "product_id", "model_covariate", "epiweek", "input_raster_path", "sidecar_path", "sidecar_sha256", "output_sha256", "input_fingerprint", "source_family_id", "source_request_hashes", "variable_spec_hash", "aggregation_algorithm_version", "weekly_statistic", "template_sha256")
  data <- data[order(data$product_id, data$model_covariate, data$epiweek), columns, drop = FALSE]
  if (!nrow(data)) return("")
  paste(vapply(seq_len(nrow(data)), function(i) as.character(jsonlite::toJSON(as.list(data[i, columns, drop = FALSE]), auto_unbox = TRUE, null = "null", digits = NA)), character(1L)), collapse = "\n")
}

cds_upstream_provenance_fingerprint <- function(data) {
  cds_upstream_provenance_require("digest")
  digest::digest(cds_upstream_provenance_canonical_text(data), algo = "sha256", serialize = FALSE)
}

cds_upstream_provenance_product_summary <- function(rows, product_id, model_covariate, validated_through) {
  selected <- rows[rows$product_id == product_id, , drop = FALSE]
  list(
    product_id = product_id,
    model_covariate = model_covariate,
    weeks = nrow(selected),
    first_epiweek = selected$epiweek[[1L]],
    last_epiweek = selected$epiweek[[nrow(selected)]],
    fingerprint = cds_upstream_provenance_fingerprint(selected),
    validated_through = validated_through
  )
}

cds_upstream_provenance_build <- function(contract) {
  cds_upstream_provenance_require()
  dynamic_paths <- cds_upstream_provenance_dynamic_specs(contract)
  expected_labels <- contract$horizon$modeled_week_labels
  selected <- cds_upstream_provenance_select_portfolio(contract, dynamic_paths)
  rows <- list()
  index <- 0L
  for (model_covariate in names(cds_upstream_provenance_required_products)) {
    product_id <- unname(cds_upstream_provenance_required_products[[model_covariate]])
    weekly <- cds_upstream_provenance_weekly_index(dynamic_paths[[model_covariate]], expected_labels)
    workflow_id <- cds_upstream_provenance_source_workflow_id(selected$portfolio, product_id)
    for (epiweek in expected_labels) {
      raster_path <- weekly$file[weekly$key == cds_upstream_provenance_week_key(epiweek)]
      if (length(raster_path) != 1L) stop("CDS weekly raster selection is not unique for ", product_id, " ", epiweek, call. = FALSE)
      sidecar_path <- paste0(raster_path, ".json")
      sidecar <- cds_upstream_provenance_json_read(sidecar_path)
      index <- index + 1L
      rows[[index]] <- cds_upstream_provenance_row(contract, product_id, model_covariate, workflow_id, epiweek, raster_path, sidecar_path, sidecar)
    }
  }
  rows <- do.call(rbind, rows)
  rows <- rows[order(rows$product_id, rows$model_covariate, rows$epiweek), , drop = FALSE]
  rownames(rows) <- NULL
  product_summaries <- lapply(names(cds_upstream_provenance_required_products), function(model_covariate) {
    cds_upstream_provenance_product_summary(rows, unname(cds_upstream_provenance_required_products[[model_covariate]]), model_covariate, selected$validated_through)
  })
  names(product_summaries) <- unname(cds_upstream_provenance_required_products)
  list(
    rows = rows,
    selected = selected,
    product_summaries = product_summaries,
    overall_fingerprint = cds_upstream_provenance_fingerprint(rows),
    horizon_start = expected_labels[[1L]],
    horizon_end = expected_labels[[length(expected_labels)]],
    dynamic_paths = dynamic_paths
  )
}

production_orchestration_attach_cds_provenance <- function(contract, write_files = TRUE) {
  built <- cds_upstream_provenance_build(contract)
  metadata <- contract$paths$metadata
  artifact_path <- file.path(metadata, "upstream_cds_provenance.csv")
  certificate_path <- file.path(metadata, "cds_coverage_certificate.yml")
  certificate <- list(
    provider = "cds-datagrab",
    status = "PASS",
    portfolio_run_id = cds_upstream_provenance_scalar(built$selected$portfolio$run_id),
    portfolio_manifest_path = built$selected$manifest_path,
    portfolio_manifest_sha256 = built$selected$manifest_sha256,
    horizon_start = built$horizon_start,
    horizon_end = built$horizon_end,
    validated_through = built$selected$validated_through,
    required_products = lapply(built$product_summaries, function(summary) summary[c("product_id", "model_covariate", "weeks", "first_epiweek", "last_epiweek", "validated_through")]),
    coverage_result = "all required CDS products cover the geostat horizon"
  )
  if (isTRUE(write_files)) {
    dir.create(metadata, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(built$rows, artifact_path, row.names = FALSE, na = "", quote = TRUE)
    production_orchestration_write_yaml(certificate, certificate_path)
  }
  artifact_sha <- if (isTRUE(write_files)) production_orchestration_hash_file(artifact_path) else NA_character_
  certificate_sha <- if (isTRUE(write_files)) production_orchestration_hash_file(certificate_path) else NA_character_
  provenance <- list(
    provider = "cds-datagrab",
    model_covariates = as.list(cds_upstream_provenance_required_products),
    consumer = list(stage = "preprocessing", script = "scripts/run_preprocessing.R", intermediate_artifact = normalizePath(file.path(contract$paths$stage1, "model_inputs.rds"), mustWork = FALSE)),
    detail_artifact = list(path = normalizePath(artifact_path, mustWork = FALSE), sha256 = artifact_sha, rows = nrow(built$rows)),
    overall_fingerprint = built$overall_fingerprint,
    product_fingerprints = lapply(built$product_summaries, function(summary) summary[c("product_id", "model_covariate", "weeks", "first_epiweek", "last_epiweek", "fingerprint", "validated_through")]),
    coverage_certificate = list(path = normalizePath(certificate_path, mustWork = FALSE), sha256 = certificate_sha, portfolio_run_id = certificate$portfolio_run_id, portfolio_manifest_path = certificate$portfolio_manifest_path, portfolio_manifest_sha256 = certificate$portfolio_manifest_sha256, status = certificate$status, validated_through = certificate$validated_through, result = certificate$coverage_result)
  )
  contract$upstream_provenance <- list(cds_datagrab = provenance)
  contract
}
