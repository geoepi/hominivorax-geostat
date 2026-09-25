# Canonical post-fit reporting objects and deterministic renderers.
#
# This module consumes validated Stage 3B, Stage 2, Phase 2, and Phase 3
# artifacts.  It does not fit, validate, project, or rasterize a model.

`%||%` <- function(x, y) if (is.null(x)) y else x

postfit_reporting_require <- function(packages = character()) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) stop("Post-fit reporting requires missing package(s): ", paste(missing, collapse = ", "))
  invisible(TRUE)
}

postfit_reporting_iso_timestamp <- function(value = Sys.time()) {
  format(value, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

postfit_reporting_validate_run_id <- function(run_id) {
  if (length(run_id) != 1L || is.na(run_id) || !nzchar(as.character(run_id)) ||
      grepl("[/\\\\]", as.character(run_id)) || as.character(run_id) %in% c(".", "..")) {
    stop("run_id must be a single non-empty path-safe identifier.")
  }
  as.character(run_id)
}

postfit_reporting_output_paths <- function(output_root, run_id) {
  run_id <- postfit_reporting_validate_run_id(run_id)
  root <- normalizePath(file.path(output_root, run_id), mustWork = FALSE)
  list(
    root = root,
    objects = file.path(root, "objects"),
    tables = file.path(root, "tables"),
    figures = file.path(root, "figures"),
    spatial = file.path(root, "spatial"),
    metadata = file.path(root, "metadata"),
    qa = file.path(root, "qa"),
    manifest = file.path(root, "metadata", paste0("manifest_", run_id, ".csv")),
    metadata_rds = file.path(root, "metadata", paste0("reporting_metadata_", run_id, ".rds")),
    metadata_yml = file.path(root, "metadata", paste0("reporting_metadata_", run_id, ".yml"))
  )
}

postfit_reporting_assert_output_isolated <- function(output_root, run_id, overwrite = FALSE) {
  paths <- postfit_reporting_output_paths(output_root, run_id)
  if (dir.exists(paths$root) && length(list.files(paths$root, all.files = TRUE, recursive = TRUE, no.. = TRUE)) && !isTRUE(overwrite)) {
    stop("Refusing to write to non-empty reporting output root without explicit overwrite=TRUE: ", paths$root)
  }
  invisible(paths)
}

postfit_reporting_hash_file <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !file.exists(path)) return(NA_character_)
  if (!requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  tryCatch(digest::digest(file = path, algo = "sha256"), error = function(e) NA_character_)
}

postfit_reporting_file_format <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (!nzchar(ext)) "file" else ext
}

postfit_reporting_summary_column <- function(data, candidates, label, required = TRUE) {
  found <- candidates[candidates %in% names(data)]
  if (!length(found)) {
    if (required) stop(label, " is missing; expected one of: ", paste(candidates, collapse = ", "))
    return(NULL)
  }
  found[[1L]]
}

postfit_reporting_summary_value <- function(data, candidates, label, required = TRUE) {
  column <- postfit_reporting_summary_column(data, candidates, label, required)
  if (is.null(column)) return(rep(NA_real_, nrow(data)))
  as.numeric(data[[column]])
}

postfit_reporting_effect_label <- function(term) {
  labels <- c(
    intercept1 = "Intercept",
    north = "Northing",
    road_dens = "Road density",
    night_illum = "Night illumination",
    intercept2 = "Intercept",
    mintemp = "Minimum temperature",
    soilmoist = "Soil moisture",
    leafarea = "Leaf area",
    rhum = "Relative humidity",
    cattle = "Cattle linear term",
    horses = "Horses",
    pigs = "Pigs",
    goats = "Goats",
    sheep = "Sheep",
    `mintemp:soilmoist` = "Minimum temperature × soil moisture",
    `mintemp:leafarea` = "Minimum temperature × leaf area"
  )
  value <- unname(labels[term])
  if (length(value) != 1L || is.na(value)) term else value
}

postfit_reporting_effect_source <- function(term) {
  sources <- c(
    intercept1 = "intercept1", north = "northing_km_s|northing_z", road_dens = "road_dens_s|road_density_log1p",
    night_illum = "night_illum_s|night_illumination_log1p", intercept2 = "intercept2",
    mintemp = "mintemp_s|mintemp_z", soilmoist = "soilmoist_s|soilmoist_z",
    leafarea = "leafarea_s|leafarea_z", rhum = "rhum_s|rhum_z", cattle = "cattle_log1p",
    horses = "horses_log1p", pigs = "pigs_log1p", goats = "goats_log1p", sheep = "sheep_log1p",
    `mintemp:soilmoist` = "mintemp_s × soilmoist_s", `mintemp:leafarea` = "mintemp_s × leafarea_s"
  )
  value <- unname(sources[term])
  if (length(value) != 1L || is.na(value)) term else value
}

postfit_reporting_effect_note <- function(term) {
  if (grepl("intercept", term, fixed = TRUE)) return("Model intercept on the component linear-predictor scale.")
  if (term %in% c("cattle", "horses", "pigs", "goats", "sheep")) return("Stage 2 log1p livestock feature; see source artifact for transformation details.")
  if (grepl(":", term, fixed = TRUE)) return("Interaction of Stage 2 transformed covariates.")
  if (term %in% c("north", "road_dens", "night_illum", "mintemp", "soilmoist", "leafarea", "rhum")) return("Stage 2 transformed or standardized covariate; see source artifact for units.")
  NA_character_
}

postfit_reporting_fixed_effects <- function(fit_artifact, tier_terms = NULL) {
  if (!exists("joint_inla_extract_fixed_effects", mode = "function")) stop("Source R/joint_inla_extract.R before extracting fixed effects.")
  raw <- joint_inla_extract_fixed_effects(fit_artifact)
  if (!nrow(raw)) stop("The fit contains no fixed-effect summary rows.")
  tier_terms <- tier_terms %||% list(
    tier1 = c("intercept1", "north", "road_dens", "night_illum"),
    tier2 = c("intercept2", "mintemp", "soilmoist", "leafarea", "rhum", "cattle", "horses", "pigs", "goats", "sheep", "mintemp:soilmoist", "mintemp:leafarea")
  )
  all_terms <- unlist(tier_terms, use.names = FALSE)
  if (anyDuplicated(all_terms)) stop("tier_terms contains duplicate fixed-effect terms.")
  raw$term <- as.character(raw$term)
  raw$tier <- unname(vapply(raw$term, function(term) {
    hits <- names(tier_terms)[vapply(tier_terms, function(terms) term %in% terms, logical(1L))]
    if (length(hits) != 1L) NA_character_ else hits[[1L]]
  }, character(1L)))
  unexpected <- raw$term[is.na(raw$tier)]
  if (length(unexpected)) stop("Fitted fixed effects could not be assigned to exactly one reporting tier: ", paste(unexpected, collapse = ", "))
  raw$term_order <- match(raw$term, all_terms)
  raw <- raw[order(raw$tier, raw$term_order, raw$term), , drop = FALSE]
  raw$posterior_mean <- postfit_reporting_summary_value(raw, c("mean", "Mean"), "fixed-effect mean")
  raw$posterior_sd <- postfit_reporting_summary_value(raw, c("sd", "SD"), "fixed-effect SD")
  raw$q025 <- postfit_reporting_summary_value(raw, c("0.025quant", "Q0.025", "q025"), "fixed-effect 2.5% quantile")
  raw$median <- postfit_reporting_summary_value(raw, c("0.5quant", "Q0.5", "median"), "fixed-effect median")
  raw$q975 <- postfit_reporting_summary_value(raw, c("0.975quant", "Q0.975", "q975"), "fixed-effect 97.5% quantile")
  out <- data.frame(
    tier = raw$tier,
    term = raw$term,
    label = vapply(raw$term, postfit_reporting_effect_label, character(1L)),
    posterior_mean = raw$posterior_mean,
    posterior_sd = raw$posterior_sd,
    q025 = raw$q025,
    median = raw$median,
    q975 = raw$q975,
    effect_scale = ifelse(raw$tier == "tier1", "latent logit-scale deviation", "latent log-intensity deviation"),
    source_model_variable = vapply(raw$term, postfit_reporting_effect_source, character(1L)),
    units_transformation_note = vapply(raw$term, postfit_reporting_effect_note, character(1L)),
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  split(out, out$tier)
}

postfit_reporting_weight_summary <- function(mean, sd, q025, median, q975, weight) {
  if (!is.finite(weight)) return(c(mean = NA_real_, sd = NA_real_, q025 = NA_real_, median = NA_real_, q975 = NA_real_))
  if (weight >= 0) {
    c(mean = mean * weight, sd = abs(weight) * sd, q025 = q025 * weight, median = median * weight, q975 = q975 * weight)
  } else {
    c(mean = mean * weight, sd = abs(weight) * sd, q025 = q975 * weight, median = median * weight, q975 = q025 * weight)
  }
}

postfit_reporting_cattle_effect <- function(fit_artifact, stage2) {
  if (!exists("joint_inla_extract_cattle_effects", mode = "function")) stop("Source R/joint_inla_extract.R before extracting cattle effects.")
  raw <- joint_inla_extract_cattle_effects(fit_artifact, stage2)
  raw$cattle_q <- as.integer(raw$cattle_q)
  latent_mean <- postfit_reporting_summary_value(raw, c("mean", "Mean"), "cattle RW2 posterior mean")
  latent_sd <- postfit_reporting_summary_value(raw, c("sd", "SD"), "cattle RW2 posterior SD")
  latent_q025 <- postfit_reporting_summary_value(raw, c("0.025quant", "Q0.025", "q025"), "cattle RW2 2.5% quantile")
  latent_median <- postfit_reporting_summary_value(raw, c("0.5quant", "Q0.5", "median"), "cattle RW2 median")
  latent_q975 <- postfit_reporting_summary_value(raw, c("0.975quant", "Q0.975", "q975"), "cattle RW2 97.5% quantile")
  weighted <- t(vapply(seq_len(nrow(raw)), function(i) postfit_reporting_weight_summary(
    latent_mean[[i]], latent_sd[[i]], latent_q025[[i]], latent_median[[i]], latent_q975[[i]], raw$cattle_mid_log1p[[i]]
  ), numeric(5L)))
  out <- data.frame(
    model_index = raw$model_index,
    cattle_q = raw$cattle_q,
    cattle_mid = as.numeric(raw$cattle_mid),
    cattle_mid_log1p = as.numeric(raw$cattle_mid_log1p),
    active_count = as.integer(raw$active_count),
    full_count = as.integer(raw$full_count),
    observed_positive_count = as.integer(raw$observed_positive_count),
    fitted_level = as.logical(raw$fitted_level),
    active_bin = as.integer(raw$active_count) > 0L,
    support_status = ifelse(as.integer(raw$active_count) > 0L, "active_training_support", "inactive_training_support"),
    rw2_latent_mean = latent_mean,
    rw2_latent_sd = latent_sd,
    rw2_latent_q025 = latent_q025,
    rw2_latent_median = latent_median,
    rw2_latent_q975 = latent_q975,
    posterior_mean = weighted[, "mean"],
    posterior_sd = weighted[, "sd"],
    q025 = weighted[, "q025"],
    median = weighted[, "median"],
    q975 = weighted[, "q975"],
    contribution_definition = "posterior cattle_q RW2 summary multiplied by cattle_mid_log1p, matching f(cattle_q, cattle_mid_log1p, model='rw2')",
    stringsAsFactors = FALSE
  )
  out[order(out$cattle_q), , drop = FALSE]
}

postfit_reporting_as_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, c("POSIXct", "POSIXlt"))) return(as.Date(x))
  suppressWarnings(as.Date(as.character(x)))
}

postfit_reporting_temporal_effects <- function(build, fit_artifact, stage2) {
  if (!exists("joint_inla_extract_temporal_effects", mode = "function")) stop("Source R/joint_inla_extract.R before extracting temporal effects.")
  raw <- joint_inla_extract_temporal_effects(build, fit_artifact, stage2)
  raw$timestep <- as.integer(raw$timestep)
  raw$component <- as.character(raw$component)
  raw$tier <- ifelse(raw$component == "week_steps", "tier1", ifelse(raw$component == "tier2_week", "tier2", NA_character_))
  if (anyNA(raw$tier)) stop("Temporal extraction returned an unsupported component.")
  raw$posterior_mean <- postfit_reporting_summary_value(raw, c("mean", "Mean"), "temporal posterior mean")
  raw$posterior_sd <- postfit_reporting_summary_value(raw, c("sd", "SD"), "temporal posterior SD")
  raw$q025 <- postfit_reporting_summary_value(raw, c("0.025quant", "Q0.025", "q025"), "temporal 2.5% quantile")
  raw$median <- postfit_reporting_summary_value(raw, c("0.5quant", "Q0.5", "median"), "temporal median")
  raw$q975 <- postfit_reporting_summary_value(raw, c("0.975quant", "Q0.975", "q975"), "temporal 97.5% quantile")
  mapping <- stage2$temporal_mapping
  date_column <- postfit_reporting_summary_column(mapping, c("week_start", "date", "calendar_date"), "Stage 2 calendar-date mapping", required = FALSE)
  calendar_date <- if (is.null(date_column)) as.Date(rep(NA_character_, nrow(raw))) else postfit_reporting_as_date(mapping[[date_column]][match(raw$timestep, mapping$timestep)])
  out <- data.frame(
    timestep = raw$timestep,
    epiyear = as.integer(raw$epiyear),
    epiweek = as.integer(raw$epiweek),
    calendar_date = calendar_date,
    posterior_mean = raw$posterior_mean,
    posterior_sd = raw$posterior_sd,
    q025 = raw$q025,
    median = raw$median,
    q975 = raw$q975,
    component = raw$component,
    tier = raw$tier,
    scale_semantics = ifelse(raw$tier == "tier1", "latent logit-scale deviation", "latent log-intensity deviation"),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$tier, out$timestep), , drop = FALSE]
  if (anyDuplicated(out[c("component", "timestep")])) stop("Temporal reporting object contains duplicate component/timestep rows.")
  out
}

postfit_reporting_host_lookup <- function(mapping_version = "historical-host-normalization-v1") {
  data.frame(
    pattern = c(
      "bovin", "bufal", "suin|porc", "(?<!b)ovin", "caprin",
      "equin", "burro", "canin|carin", "felin", "human",
      "bird|ave|aviar|ardeid", "kinkaju", "sloth|perezos",
      "porcupin|porcuspin", "rabbit|lapine|leporid", "procyonlotor",
      "deer|crvido", "leon|lion", "leopard", "wildterrestrial|faunasilvestre",
      "other|unknown"
    ),
    common_name = c(
      "Cattle", "Water Buffalo", "Pig", "Sheep", "Goat", "Horse", "Donkey",
      "Dog", "Cat", "Human", "Birds", "Kinkajou", "Sloth", "Porcupine",
      "Rabbit/Hare", "Raccoon", "Deer", "Lion", "Leopard", "Unspecified Wildlife",
      "Unreported"
    ),
    broad_group = c(
      rep("Livestock", 5L), rep("Equids", 2L), rep("Companion Animals", 2L),
      "Human", "Birds", rep("Wildlife", 9L), "Unreported"
    ),
    mapping_version = mapping_version,
    stringsAsFactors = FALSE
  )
}

postfit_reporting_clean_host <- function(value) {
  value <- tolower(as.character(value))
  value[is.na(value)] <- ""
  gsub("[^a-z]", "", value, perl = TRUE)
}

postfit_reporting_host_composition_table <- function(assignments, denominator, denominator_type,
                                                      source_file, mapping_version,
                                                      major_threshold_pct = 1) {
  if (!nrow(assignments)) {
    return(data.frame(
      common_name = character(), broad_group = character(), count = integer(), prop = numeric(),
      pct = numeric(), tier = character(), denominator = integer(), denominator_type = character(),
      source_file = character(), mapping_version = character(), stringsAsFactors = FALSE
    ))
  }
  counts <- stats::aggregate(
    assignments$submission_row,
    by = list(common_name = assignments$common_name, broad_group = assignments$broad_group),
    FUN = length
  )
  names(counts)[names(counts) == "x"] <- "count"
  counts$prop <- counts$count / denominator
  counts$pct <- 100 * counts$prop
  counts$tier <- ifelse(counts$pct >= major_threshold_pct, "Major Hosts", "Minor Hosts (<1%)")
  counts$denominator <- denominator
  counts$denominator_type <- denominator_type
  counts$source_file <- source_file
  counts$mapping_version <- mapping_version
  broad_order <- c("Livestock", "Equids", "Companion Animals", "Human", "Wildlife", "Birds", "Unreported")
  counts$.broad_order <- match(counts$broad_group, broad_order)
  counts <- counts[order(counts$.broad_order, -counts$pct, counts$common_name), , drop = FALSE]
  counts$.broad_order <- NULL
  rownames(counts) <- NULL
  counts[, c("common_name", "broad_group", "count", "prop", "pct", "tier", "denominator", "denominator_type", "source_file", "mapping_version"), drop = FALSE]
}

postfit_reporting_host_composition <- function(data, host_column = "host", source_file = NA_character_,
                                               mapping_version = "historical-host-normalization-v1",
                                               major_threshold_pct = 1) {
  if (!is.data.frame(data)) stop("Host-composition source must be a data frame.")
  if (length(host_column) != 1L || !host_column %in% names(data)) stop("Host-composition source is missing host column: ", host_column)
  if (length(mapping_version) != 1L || is.na(mapping_version) || !nzchar(mapping_version)) stop("mapping_version must be a non-empty string.")
  if (length(major_threshold_pct) != 1L || !is.finite(major_threshold_pct) || major_threshold_pct <= 0) stop("major_threshold_pct must be positive.")

  lookup <- postfit_reporting_host_lookup(mapping_version)
  raw_host <- as.character(data[[host_column]])
  cleaned_host <- postfit_reporting_clean_host(raw_host)
  matched_patterns <- lapply(cleaned_host, function(value) {
    if (!nzchar(value)) return(integer())
    which(vapply(lookup$pattern, function(pattern) grepl(pattern, value, perl = TRUE), logical(1L)))
  })
  n_matches <- lengths(matched_patterns)
  assignment_rows <- vector("list", length(raw_host))
  for (i in seq_along(raw_host)) {
    matches <- matched_patterns[[i]]
    if (!length(matches)) {
      assignment_rows[[i]] <- data.frame(
        submission_row = i, raw_host = raw_host[[i]], cleaned_host = cleaned_host[[i]],
        pattern = "unmatched", common_name = "Unreported", broad_group = "Unreported",
        match_count = 0L, matched = FALSE, stringsAsFactors = FALSE
      )
    } else {
      assignment_rows[[i]] <- data.frame(
        submission_row = rep.int(i, length(matches)), raw_host = rep.int(raw_host[[i]], length(matches)),
        cleaned_host = rep.int(cleaned_host[[i]], length(matches)), pattern = lookup$pattern[matches],
        common_name = lookup$common_name[matches], broad_group = lookup$broad_group[matches],
        match_count = rep.int(length(matches), length(matches)), matched = TRUE,
        stringsAsFactors = FALSE
      )
    }
  }
  assignments <- if (length(assignment_rows)) do.call(rbind, assignment_rows) else data.frame()
  rownames(assignments) <- NULL
  denominator <- nrow(assignments)
  primary <- postfit_reporting_host_composition_table(
    assignments, denominator, "expanded_host_assignments", source_file, mapping_version,
    major_threshold_pct = major_threshold_pct
  )

  first_rows <- lapply(seq_along(raw_host), function(i) {
    matches <- matched_patterns[[i]]
    if (!length(matches)) matches <- NA_integer_ else matches <- matches[[1L]]
    data.frame(
      submission_row = i, raw_host = raw_host[[i]], cleaned_host = cleaned_host[[i]],
      pattern = if (is.na(matches)) "unmatched" else lookup$pattern[[matches]],
      common_name = if (is.na(matches)) "Unreported" else lookup$common_name[[matches]],
      broad_group = if (is.na(matches)) "Unreported" else lookup$broad_group[[matches]],
      match_count = n_matches[[i]], matched = !is.na(matches), stringsAsFactors = FALSE
    )
  })
  first_assignments <- if (length(first_rows)) do.call(rbind, first_rows) else data.frame()
  first_table <- postfit_reporting_host_composition_table(
    first_assignments, nrow(data), "submission_rows_first_host", source_file, mapping_version,
    major_threshold_pct = major_threshold_pct
  )
  sensitivity <- merge(
    primary[, c("common_name", "broad_group", "count", "pct"), drop = FALSE],
    first_table[, c("common_name", "broad_group", "count", "pct"), drop = FALSE],
    by = c("common_name", "broad_group"), all = TRUE, suffixes = c("_expanded", "_first_host")
  )
  for (column in c("count_expanded", "pct_expanded", "count_first_host", "pct_first_host")) {
    sensitivity[[column]][is.na(sensitivity[[column]])] <- 0
  }
  sensitivity$pct_difference <- sensitivity$pct_expanded - sensitivity$pct_first_host
  sensitivity <- sensitivity[order(-sensitivity$pct_expanded, sensitivity$common_name), , drop = FALSE]
  rownames(sensitivity) <- NULL

  raw_trimmed <- trimws(raw_host)
  source_path <- if (length(source_file) == 1L && !is.na(source_file)) as.character(source_file) else NA_character_
  audit <- list(
    status = "PASS",
    source_role = "authoritative descriptive observation source; separate from fit provenance and RPI observations",
    source_file = source_path,
    source_sha256 = postfit_reporting_hash_file(source_path),
    source_row_count = nrow(data),
    source_column_names = paste(names(data), collapse = "|"),
    host_column = host_column,
    n_missing_or_blank_host = sum(is.na(raw_host) | !nzchar(raw_trimmed)),
    n_unique_raw_host = length(unique(raw_host)),
    n_submission_rows = nrow(data),
    n_expanded_host_assignments = denominator,
    n_compound_submission_rows = sum(n_matches > 1L),
    n_unmatched_submission_rows = sum(n_matches == 0L),
    n_assignments_unreported = sum(assignments$broad_group == "Unreported"),
    denominator_type = "expanded_host_assignments",
    denominator_discrepancy = denominator != nrow(data),
    mapping_version = mapping_version,
    major_threshold_pct = major_threshold_pct
  )
  list(
    table = primary,
    audit = audit,
    lookup = lookup,
    assignment_table = assignments,
    first_host_assignment_table = first_assignments,
    first_host_table = first_table,
    first_host_sensitivity = sensitivity
  )
}

postfit_reporting_host_audit_table <- function(host_object) {
  audit <- host_object$audit
  data.frame(
    metric = names(audit),
    value = vapply(audit, function(value) paste(as.character(value), collapse = "|"), character(1L)),
    stringsAsFactors = FALSE
  )
}

postfit_reporting_species_composition <- function(data, species_column, cohort_definition,
                                                   category_column = NULL, major_threshold = 0.01,
                                                   standardize = NULL) {
  if (!is.data.frame(data)) stop("Species source must be a data frame.")
  if (!species_column %in% names(data)) stop("Species source is missing species column: ", species_column)
  if (length(cohort_definition) != 1L || !nzchar(as.character(cohort_definition))) stop("cohort_definition must explicitly identify the denominator cohort.")
  if (length(major_threshold) != 1L || !is.finite(major_threshold) || major_threshold <= 0 || major_threshold >= 1) stop("major_threshold must be between 0 and 1.")
  species <- as.character(data[[species_column]])
  species[is.na(species) | !nzchar(trimws(species))] <- "unreported"
  if (!is.null(standardize)) species <- as.character(standardize(species))
  if (is.null(category_column)) {
    category <- rep("unreported", length(species))
  } else {
    if (!category_column %in% names(data)) stop("Species source is missing category column: ", category_column)
    category <- as.character(data[[category_column]])
    category[is.na(category) | !nzchar(trimws(category))] <- "unreported"
  }
  counts <- as.data.frame(table(species), stringsAsFactors = FALSE)
  names(counts) <- c("host_species", "count")
  category_map <- data.frame(host_species = species, broad_category = category, stringsAsFactors = FALSE)
  category_map <- category_map[!duplicated(category_map$host_species), , drop = FALSE]
  counts <- merge(counts, category_map, by = "host_species", all.x = TRUE, sort = FALSE)
  counts <- counts[order(-counts$count, counts$host_species), , drop = FALSE]
  counts$percentage <- counts$count / sum(counts$count)
  counts$major_minor <- ifelse(counts$percentage >= major_threshold, "Major Hosts", "Minor Hosts (<1%)")
  counts$major_threshold <- major_threshold
  counts$denominator_n <- sum(counts$count)
  counts$cohort_definition <- as.character(cohort_definition)
  counts <- counts[, c("host_species", "count", "percentage", "broad_category", "major_minor", "major_threshold", "denominator_n", "cohort_definition"), drop = FALSE]
  rownames(counts) <- NULL
  list(table = counts, audit = list(status = "PASS", cohort_definition = cohort_definition, denominator_n = sum(counts$count), species_column = species_column, category_column = category_column, major_threshold = major_threshold))
}

theme_hominivorax_report <- function(base_size = 11, base_family = "sans") {
  postfit_reporting_require("ggplot2")
  ggplot2::`%+replace%`(ggplot2::theme_minimal(base_size = base_size, base_family = base_family),
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(linewidth = 0.25, colour = "grey85"),
      plot.title = ggplot2::element_text(face = "bold", colour = "grey15"),
      plot.subtitle = ggplot2::element_text(colour = "grey30"),
      axis.title = ggplot2::element_text(colour = "grey15"),
      legend.position = "bottom",
      plot.margin = ggplot2::margin(8, 10, 8, 10)
    ))
}

postfit_reporting_plot_species <- function(species_object) {
  postfit_reporting_require("ggplot2")
  data <- species_object$table %||% species_object
  if ("pct" %in% names(data)) {
    data$host_species <- data$common_name
    data$broad_category <- data$broad_group
    data$percentage <- data$pct / 100
    data$major_minor <- data$tier
    x_label <- "Percentage of expanded host assignments (%)"
    subtitle <- "Compound submissions contribute once per identified species; Unreported is retained"
  } else {
    x_label <- "Percentage of stated cohort"
    subtitle <- "Major hosts and hosts contributing less than 1% of the stated cohort"
  }
  data$host_species <- stats::reorder(data$host_species, data$count)
  ggplot2::ggplot(data, ggplot2::aes(x = percentage, y = host_species, fill = broad_category)) +
    ggplot2::geom_col(width = 0.75, colour = "white", linewidth = 0.15) +
    ggplot2::facet_wrap(~major_minor, scales = "free_y", ncol = 1, drop = FALSE) +
    ggplot2::scale_x_continuous(labels = function(x) paste0(round(100 * x), "%"), expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::scale_fill_viridis_d(option = "D", end = 0.9, name = "Broad host category") +
    ggplot2::labs(x = x_label, y = NULL, title = "Host composition", subtitle = subtitle) +
    theme_hominivorax_report()
}

postfit_reporting_plot_cattle <- function(cattle_object, cattle_units = NULL) {
  postfit_reporting_require("ggplot2")
  data <- cattle_object
  x_label <- if (is.null(cattle_units)) "Cattle density (Stage 2 units)" else paste0("Cattle density (", cattle_units, ")")
  ggplot2::ggplot(data, ggplot2::aes(x = cattle_mid, y = posterior_mean)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.35) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = q025, ymax = q975), alpha = 0.22, fill = "#2C7FB8", na.rm = TRUE) +
    ggplot2::geom_line(colour = "#225EA8", linewidth = 0.7, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(size = active_count), colour = "#225EA8", na.rm = TRUE) +
    ggplot2::scale_size_continuous(name = "Active support", guide = ggplot2::guide_legend(order = 2)) +
    ggplot2::labs(x = x_label, y = "Partial contribution to Tier 2 log-intensity", title = "Cattle nonlinear effect", subtitle = "RW2 posterior contribution weighted by cattle_mid_log1p") +
    theme_hominivorax_report()
}

postfit_reporting_compose_two <- function(first, second) {
  if (requireNamespace("patchwork", quietly = TRUE)) return(first / second)
  if (requireNamespace("cowplot", quietly = TRUE)) return(cowplot::plot_grid(first, second, ncol = 1, align = "v", axis = "l"))
  list(first = first, second = second, composition = "grid")
}

postfit_reporting_plot_temporal <- function(temporal_object) {
  postfit_reporting_require("ggplot2")
  data <- temporal_object
  make_plot <- function(tier, title, y_label) {
    x <- data[data$tier == tier, , drop = FALSE]
    x_axis <- if (all(is.na(x$calendar_date))) ggplot2::aes(x = timestep) else ggplot2::aes(x = calendar_date)
    ggplot2::ggplot(x, x_axis) +
      ggplot2::geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.35) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = q025, ymax = q975), alpha = 0.22, fill = "#2C7FB8") +
      ggplot2::geom_line(ggplot2::aes(y = posterior_mean), colour = "#225EA8", linewidth = 0.6) +
      ggplot2::labs(title = title, x = NULL, y = y_label) +
      theme_hominivorax_report()
  }
  postfit_reporting_compose_two(
    make_plot("tier1", "Tier 1 weekly temporal effect", "Latent logit-scale deviation"),
    make_plot("tier2", "Tier 2 weekly temporal effect", "Latent log-intensity deviation")
  )
}

postfit_reporting_map_manifest <- function(raster_root, manifest_path = NULL) {
  postfit_reporting_require(c("terra", "digest"))
  raster_root <- normalizePath(raster_root, mustWork = TRUE)
  manifest_path <- manifest_path %||% file.path(raster_root, "qa", "temporal_manifest.csv")
  if (file.exists(manifest_path)) {
    manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
    required <- c("epiyear", "epiweek")
    if (length(setdiff(required, names(manifest)))) stop("Phase 3 temporal manifest is missing: ", paste(setdiff(required, names(manifest)), collapse = ", "))
    find_path <- function(value, family) {
      candidates <- unique(c(as.character(value), file.path(raster_root, as.character(value)), file.path(raster_root, family, basename(as.character(value)))))
      candidates <- candidates[file.exists(candidates)]
      if (!length(candidates)) NA_character_ else normalizePath(candidates[[1L]], mustWork = TRUE)
    }
    tier1_col <- postfit_reporting_summary_column(manifest, c("tier1_probability", "tier1_probability_plugin"), "Tier 1 probability raster path", required = FALSE)
    tier2_col <- postfit_reporting_summary_column(manifest, c("tier2_intensity", "tier2_intensity_plugin"), "Tier 2 intensity raster path", required = FALSE)
    if (is.null(tier1_col) || is.null(tier2_col)) stop("Phase 3 temporal manifest must contain Tier 1 probability and Tier 2 intensity paths.")
    out <- data.frame(
      time_index = if ("time_index" %in% names(manifest)) as.integer(manifest$time_index) else seq_len(nrow(manifest)),
      epiyear = as.integer(manifest$epiyear), epiweek = as.integer(manifest$epiweek),
      tier1_probability_path = vapply(manifest[[tier1_col]], find_path, character(1L), family = "tier1_probability"),
      tier2_intensity_path = vapply(manifest[[tier2_col]], find_path, character(1L), family = "tier2_intensity"),
      stringsAsFactors = FALSE
    )
  } else {
    find <- function(family, prefix) {
      paths <- list.files(file.path(raster_root, family), pattern = paste0("^", prefix, "_y[0-9]{4}_w[0-9]{2}\\.tif$"), full.names = TRUE)
      parsed <- regexec("_y([0-9]{4})_w([0-9]{2})\\.tif$", basename(paths), ignore.case = TRUE)
      matches <- regmatches(basename(paths), parsed)
      data.frame(path = paths, epiyear = as.integer(vapply(matches, `[[`, character(1L), 2L)), epiweek = as.integer(vapply(matches, `[[`, character(1L), 3L)), stringsAsFactors = FALSE)
    }
    one <- find("tier1_probability", "tier1_prob"); two <- find("tier2_intensity", "tier2_intensity")
    out <- merge(one, two, by = c("epiyear", "epiweek"), suffixes = c("_tier1", "_tier2"), sort = FALSE)
    names(out)[names(out) == "path_tier1"] <- "tier1_probability_path"
    names(out)[names(out) == "path_tier2"] <- "tier2_intensity_path"
    out$time_index <- seq_len(nrow(out))
  }
  if (anyNA(out$tier1_probability_path) || anyNA(out$tier2_intensity_path)) stop("Phase 3 map manifest contains missing raster paths.")
  out$week <- paste(out$epiyear, sprintf("W%02d", out$epiweek), sep = "-")
  out <- out[order(out$time_index, out$epiyear, out$epiweek), , drop = FALSE]
  rownames(out) <- NULL
  out
}

postfit_reporting_select_map_weeks <- function(manifest, n = 4L) {
  if (!nrow(manifest)) stop("Cannot select map weeks from an empty Phase 3 manifest.")
  n <- min(as.integer(n), nrow(manifest))
  indices <- unique(round(seq(1, nrow(manifest), length.out = n)))
  selected <- manifest[indices, , drop = FALSE]
  selected$selection_rule <- "first, approximately one-third, approximately two-thirds, and final modeled week"
  selected$selection_position <- indices
  selected
}

postfit_reporting_selected_map_values <- function(selected_manifest, raster_root = NULL, boundary = NULL) {
  postfit_reporting_require(c("terra", "digest"))
  if (!"week" %in% names(selected_manifest)) selected_manifest$week <- paste(selected_manifest$epiyear, sprintf("W%02d", selected_manifest$epiweek), sep = "-")
  rows <- vector("list", nrow(selected_manifest) * 2L)
  k <- 0L
  geometry <- NULL
  for (i in seq_len(nrow(selected_manifest))) {
    for (layer in c("tier1_probability", "tier2_intensity")) {
      path <- selected_manifest[[paste0(layer, "_path")]][[i]]
      if (!file.exists(path) && !is.null(raster_root)) path <- file.path(raster_root, layer, basename(path))
      if (!file.exists(path)) stop("Selected Phase 3 raster does not exist: ", path)
      raster <- terra::rast(path)
      if (terra::nlyr(raster) != 1L) stop("Selected raster is not a single layer: ", path)
      current_geometry <- list(extent = c(terra::xmin(raster), terra::xmax(raster), terra::ymin(raster), terra::ymax(raster)), resolution = as.numeric(terra::res(raster)), crs = terra::crs(raster, proj = TRUE), nrow = terra::nrow(raster), ncol = terra::ncol(raster))
      if (is.null(geometry)) geometry <- current_geometry else if (!isTRUE(all.equal(geometry, current_geometry, check.attributes = FALSE))) stop("Selected rasters do not share exact geometry.")
      cells <- which(!is.na(terra::values(raster, mat = FALSE)))
      if (!length(cells)) next
      xy <- terra::xyFromCell(raster, cells)
      k <- k + 1L
      rows[[k]] <- data.frame(
        time_index = selected_manifest$time_index[[i]], epiyear = selected_manifest$epiyear[[i]], epiweek = selected_manifest$epiweek[[i]], week = selected_manifest$week[[i]],
        layer = layer, cell_id = cells, x = xy[, 1L], y = xy[, 2L], value = terra::values(raster, mat = FALSE)[cells], source_path = normalizePath(path, mustWork = TRUE),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!k) stop("Selected Phase 3 rasters contain no non-NA cells.")
  values <- do.call(rbind, rows[seq_len(k)])
  if (!is.null(boundary)) {
    postfit_reporting_require("sf")
    if (!inherits(boundary, c("sf", "sfc"))) stop("boundary must be an sf or sfc object.")
    boundary_crs <- sf::st_crs(boundary)
    raster_crs <- sf::st_crs(geometry$crs)
    if (!is.na(boundary_crs) && !is.na(raster_crs)) boundary <- sf::st_transform(boundary, raster_crs)
  }
  list(values = values, selected_weeks = selected_manifest, geometry = geometry, boundary = boundary,
       scale_limits = lapply(split(values$value, values$layer), range, na.rm = TRUE),
       raster_value_semantics = "Values are direct Phase 3 cell assignments; no resampling or display rescaling was applied.")
}

postfit_reporting_plot_selected_maps <- function(map_object) {
  postfit_reporting_require("ggplot2")
  values <- map_object$values
  limits <- map_object$scale_limits
  plots <- lapply(seq_len(nrow(map_object$selected_weeks)), function(i) {
    week <- map_object$selected_weeks$week[[i]]
    data <- values[values$week == week, , drop = FALSE]
    add_context <- function(plot) {
      if (is.null(map_object$boundary)) return(plot + ggplot2::coord_equal(expand = FALSE))
      plot + ggplot2::geom_sf(data = map_object$boundary, inherit.aes = FALSE, fill = NA, colour = "grey25", linewidth = 0.2) + ggplot2::coord_sf(expand = FALSE)
    }
    p1 <- add_context(ggplot2::ggplot(data[data$layer == "tier1_probability", , drop = FALSE], ggplot2::aes(x = x, y = y, fill = value)) + ggplot2::geom_raster()) +
      ggplot2::scale_fill_viridis_c(limits = limits$tier1_probability, name = "Probability", na.value = "transparent") +
      ggplot2::labs(title = paste0(week, " — Tier 1"), x = NULL, y = NULL) + theme_hominivorax_report() + ggplot2::theme(axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank())
    p2 <- add_context(ggplot2::ggplot(data[data$layer == "tier2_intensity", , drop = FALSE], ggplot2::aes(x = x, y = y, fill = value)) + ggplot2::geom_raster()) +
      ggplot2::scale_fill_viridis_c(limits = limits$tier2_intensity, name = "Intensity", na.value = "transparent") +
      ggplot2::labs(title = paste0(week, " — Tier 2"), x = NULL, y = NULL) + theme_hominivorax_report() + ggplot2::theme(axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank())
    list(tier1 = p1, tier2 = p2)
  })
  structure(list(plots = plots, nrow = length(plots), ncol = 2L, composition = "grid", object = map_object), class = "postfit_reporting_map_grid")
}

postfit_reporting_trace_cell_area <- function(template_path = NULL, cell_area = NULL, units = NULL, source_document = "local/results_summary.qmdx") {
  if (!is.null(cell_area)) {
    value <- as.numeric(cell_area)
    if (length(value) != 1L || !is.finite(value) || value <= 0) stop("cell_area must be one positive finite number.")
    if (is.null(units) || !nzchar(as.character(units))) stop("Explicit cell_area requires explicit units.")
    return(list(status = "PASS", nominal_average_raster_cell_area = value, units = as.character(units), formula = "explicit audited input", template_path = template_path %||% NA_character_, source_document = source_document, provenance = "Caller supplied an audited conversion constant."))
  }
  if (is.null(template_path) || !file.exists(template_path)) return(list(status = "UNRESOLVED", reason = "No cell-area template or explicit audited constant was supplied.", source_document = source_document))
  postfit_reporting_require("terra")
  raster <- terra::rast(template_path)
  resolution <- terra::res(raster)
  value <- prod(resolution)
  crs_text <- tolower(terra::crs(raster, proj = TRUE))
  source_text <- if (file.exists(source_document)) paste(readLines(source_document, warn = FALSE), collapse = " ") else as.character(source_document)
  units_out <- if (grepl("units=km|units=kilomet", crs_text) || grepl("units\\s*=\\s*km|units\\s*=\\s*kilomet", source_text, ignore.case = TRUE)) "km^2" else if (grepl("units=m", crs_text)) "m^2" else NA_character_
  if (is.na(units_out)) return(list(status = "UNRESOLVED", reason = "Template resolution is known but coordinate units are not established.", resolution = resolution, template_path = normalizePath(template_path, mustWork = TRUE), source_document = source_document))
  if (identical(units_out, "m^2")) {
    value <- value / 1e6
    units_out <- "km^2"
  }
  list(status = "PASS", nominal_average_raster_cell_area = value, units = units_out, resolution = resolution, formula = "prod(terra::res(template_raster)) with m-to-km conversion when required", template_path = normalizePath(template_path, mustWork = TRUE), source_document = source_document, provenance = "Legacy reporting code defines cell_area <- prod(res(r_template)); template and resolution were recorded.")
}

postfit_reporting_potential_abundance <- function(tier2_paths, cell_area_info, output_dir, overwrite = FALSE) {
  if (!identical(cell_area_info$status, "PASS")) stop("Potential abundance is blocked until the cell-area audit passes.")
  postfit_reporting_require(c("terra", "digest"))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- vapply(tier2_paths, function(path) {
    raster <- terra::rast(path)
    output <- file.path(output_dir, paste0(tools::file_path_sans_ext(basename(path)), "_potential_abundance.tif"))
    if (file.exists(output) && !isTRUE(overwrite)) stop("Refusing to overwrite potential-abundance raster: ", output)
    terra::writeRaster(raster * cell_area_info$nominal_average_raster_cell_area, output, overwrite = TRUE, datatype = "FLT8S")
    normalizePath(output, mustWork = TRUE)
  }, character(1L))
  list(
    paths = unname(paths),
    definition = "potential_abundance = tier2_intensity_plugin × nominal_average_raster_cell_area",
    quantity_label = "standardized potential abundance for a nominal raster cell",
    cell_area = cell_area_info
  )
}

postfit_reporting_rpi_audit <- function(count_stack_semantics, observed_source = NULL, time_span_weeks = NULL,
                                        gen_days = 21, days_per_layer = 7, cut_quant = 0.10,
                                        class_boundaries = c(3, 8, 15)) {
  checks <- data.frame(
    check = c("count_stack_semantics", "observed_source", "continuous_time_span", "threshold_convention", "class_boundaries"),
    status = c(
      if (identical(count_stack_semantics, "standardized_potential_abundance")) "PASS" else "FAIL",
      if (!is.null(observed_source) && file.exists(observed_source)) "PASS" else "FAIL",
      if (!is.null(time_span_weeks) && as.integer(time_span_weeks) >= 1L) "PASS" else "UNRESOLVED",
      if (identical(as.numeric(cut_quant), 0.10)) "PASS" else "WARNING",
      if (identical(as.numeric(class_boundaries), c(3, 8, 15))) "PASS" else "WARNING"
    ),
    details = c(
      "RPI must receive the standardized potential-abundance stack, not raw Tier 2 intensity.",
      "Observation locations are required for threshold calibration.",
      "The supplied Phase 3 stack is evaluated as one ordered continuous stack.",
      "Threshold is the lower cut_quant quantile of values extracted at observation locations and suitability is value > threshold.",
      "Classes use <3, 3–8, 8–15, and >15 generations; boundary behavior is retained from R/calc_RPI.R."
    ), stringsAsFactors = FALSE
  )
  enabled <- all(checks$status == "PASS")
  list(status = if (enabled) "PASS" else "BLOCKED", enabled = enabled, checks = checks,
       parameters = list(gen_days = gen_days, days_per_layer = days_per_layer, cut_quant = cut_quant, class_boundaries = class_boundaries),
       source_function = "R/calc_RPI.R", semantic_note = "No RPI product is generated when the semantic gate is blocked.")
}

postfit_reporting_calc_rpi <- function(count_stk, nws_obs, gen_days = 21, days_per_layer = 7, cut_quant = 0.10) {
  postfit_reporting_require("terra")
  if (!inherits(count_stk, "SpatRaster")) stop("count_stk must be a terra SpatRaster.")
  required <- c("x", "y")
  if (!is.data.frame(nws_obs) || length(setdiff(required, names(nws_obs)))) stop("nws_obs must contain x and y columns.")
  obs_pts <- terra::vect(nws_obs, geom = c("x", "y"), crs = terra::crs(count_stk))
  extracted <- terra::extract(count_stk, obs_pts)
  values <- as.matrix(extracted[, setdiff(names(extracted), "ID"), drop = FALSE])
  threshold <- as.numeric(stats::quantile(as.numeric(values), cut_quant, na.rm = TRUE, names = FALSE))
  max_run <- function(x) {
    if (all(is.na(x))) return(NA_real_)
    suitable <- x > threshold; suitable[is.na(suitable)] <- FALSE
    runs <- rle(suitable)
    if (!any(runs$values)) return(0)
    max(runs$lengths[runs$values])
  }
  max_run_weeks <- terra::app(count_stk, fun = max_run)
  rpi <- (max_run_weeks * days_per_layer) / gen_days
  classes <- terra::classify(rpi, rcl = matrix(c(-Inf, 3, 0, 3, 8, 1, 8, 15, 2, 15, Inf, 3), ncol = 3, byrow = TRUE))
  names(classes) <- "rpi_class"
  list(rpi = rpi, stability_class = classes, calibrated_threshold = threshold,
       parameters = list(gen_days = gen_days, days_per_layer = days_per_layer, cut_quant = cut_quant),
       semantics = "Copied from R/calc_RPI.R with explicit terra namespace; class intervals retain the existing implementation's left-closed behavior.")
}

postfit_reporting_rpi_class_area <- function(stability_class, cell_area_info, labels = c("Transient/Sink", "Seasonal", "Multi-Season", "Endemic Core")) {
  if (!identical(cell_area_info$status, "PASS")) stop("RPI class area requires a passed cell-area audit.")
  postfit_reporting_require("terra")
  values <- terra::values(stability_class, mat = FALSE)
  values <- values[is.finite(values)]
  counts <- table(factor(as.integer(values), levels = 0:3))
  data.frame(class_code = 0:3, class_label = labels, cell_count = as.integer(counts), area = as.integer(counts) * cell_area_info$nominal_average_raster_cell_area, area_units = cell_area_info$units, stringsAsFactors = FALSE)
}

postfit_reporting_plot_rpi <- function(stability_class, labels = c("Transient/Sink", "Seasonal", "Multi-Season", "Endemic Core")) {
  postfit_reporting_require(c("terra", "ggplot2"))
  values <- terra::values(stability_class, mat = FALSE)
  cells <- which(!is.na(values))
  xy <- terra::xyFromCell(stability_class, cells)
  data <- data.frame(x = xy[, 1L], y = xy[, 2L], class_code = as.integer(values[cells]), class_label = factor(labels[as.integer(values[cells]) + 1L], levels = labels))
  ggplot2::ggplot(data, ggplot2::aes(x = x, y = y, fill = class_label)) + ggplot2::geom_raster() + ggplot2::coord_equal(expand = FALSE) +
    ggplot2::scale_fill_viridis_d(option = "C", name = "RPI class", drop = FALSE) + ggplot2::labs(title = "Reproductive Persistence Index classes", x = NULL, y = NULL) + theme_hominivorax_report() + ggplot2::theme(axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank())
}

postfit_reporting_model_summary <- function(build, fit_artifact, stage2) {
  fit <- if (is.list(fit_artifact) && !is.null(fit_artifact$fit)) fit_artifact$fit else fit_artifact
  mapping <- stage2$temporal_mapping
  rows <- c(tier1 = if (is.data.frame(stage2$tier1)) nrow(stage2$tier1) else NA_integer_, tier2 = if (is.data.frame(stage2$tier2)) nrow(stage2$tier2) else NA_integer_)
  holdouts <- c(tier1 = if (is.data.frame(stage2$tier1) && "is_test_point" %in% names(stage2$tier1)) sum(stage2$tier1$is_test_point %in% TRUE, na.rm = TRUE) else NA_integer_, tier2 = if (is.data.frame(stage2$tier2) && "is_test_point" %in% names(stage2$tier2)) sum(stage2$tier2$is_test_point %in% TRUE, na.rm = TRUE) else NA_integer_)
  groups <- unique(unlist(lapply(build$fields %||% list(), function(x) x[["tier1_field.group"]] %||% x[["tier2_field.group"]]), use.names = FALSE))
  groups <- groups[is.finite(as.numeric(groups))]
  marginal <- if (exists("joint_inla_extract_marginal_log_likelihood", mode = "function")) joint_inla_extract_marginal_log_likelihood(fit) else data.frame()
  list(
    likelihood_families = as.character(build$family %||% NA_character_),
    tier_rows = rows, holdout_counts = holdouts,
    mesh_vertices = c(tier1 = build$spde$tier1$n.spde %||% NA_integer_, tier2 = build$spde$tier2$n.spde %||% NA_integer_),
    temporal_weeks = if (is.data.frame(mapping)) nrow(mapping) else NA_integer_, spatial_groups = length(unique(groups)),
    fitted_fixed_effect_count = if (!is.null(fit$summary.fixed)) nrow(fit$summary.fixed) else NA_integer_,
    fitted_hyperparameter_count = if (!is.null(fit$summary.hyperpar)) nrow(fit$summary.hyperpar) else NA_integer_,
    DIC = fit$dic$dic %||% NA_real_, WAIC = fit$waic$waic %||% NA_real_,
    log_marginal_likelihood = if (nrow(marginal)) marginal$value[[1L]] else NA_real_
  )
}

postfit_reporting_write_table <- function(object, object_name, paths) {
  if (is.data.frame(object)) {
    data <- object
  } else if (is.list(object) && is.data.frame(object$table)) {
    data <- object$table
  } else stop("Canonical table object must be a data frame or list containing table.")
  rds <- file.path(paths$objects, paste0(object_name, ".rds")); csv <- file.path(paths$tables, paste0(object_name, ".csv"))
  saveRDS(object, rds); utils::write.csv(data, csv, row.names = FALSE, na = "")
  list(rds = rds, csv = csv, rows = nrow(data))
}

postfit_reporting_metadata_table <- function(object) {
  if (!is.list(object)) stop("Metadata object must be a list.")
  data.frame(field = names(object), value = vapply(object, function(value) {
    if (is.null(value)) return(NA_character_)
    if (length(value) == 1L && (is.atomic(value) || is.factor(value))) return(as.character(value))
    paste(as.character(unlist(value, use.names = FALSE)), collapse = "|")
  }, character(1L)), stringsAsFactors = FALSE)
}

postfit_reporting_save_plot <- function(plot, object_name, paths, width = 8, height = 5) {
  postfit_reporting_require("ggplot2")
  rds <- file.path(paths$objects, paste0("plot_", object_name, ".rds")); pdf <- file.path(paths$figures, paste0(object_name, ".pdf")); png <- file.path(paths$figures, paste0(object_name, ".png"))
  saveRDS(plot, rds)
  if (inherits(plot, "postfit_reporting_map_grid")) {
    draw <- function(device_path, device_fun) {
      if (identical(device_fun, grDevices::pdf)) device_fun(device_path, width = width, height = height) else device_fun(device_path, width = width, height = height, units = "in", res = 160)
      on.exit(grDevices::dev.off(), add = TRUE)
      grid::grid.newpage(); grid::pushViewport(grid::viewport(layout = grid::grid.layout(plot$nrow, plot$ncol)))
      for (i in seq_len(plot$nrow)) for (j in seq_len(plot$ncol)) {
        grid::pushViewport(grid::viewport(layout.pos.row = i, layout.pos.col = j)); grid::grid.draw(ggplot2::ggplotGrob(plot$plots[[i]][[j]])); grid::popViewport()
      }
      grid::popViewport()
    }
    draw(pdf, grDevices::pdf); draw(png, grDevices::png)
  } else {
    ggplot2::ggsave(pdf, plot = plot, width = width, height = height, units = "in", device = grDevices::pdf)
    ggplot2::ggsave(png, plot = plot, width = width, height = height, units = "in", dpi = 160)
  }
  list(rds = rds, pdf = pdf, png = png)
}

postfit_reporting_write_manifest <- function(paths, source_run, generated_at = postfit_reporting_iso_timestamp()) {
  files <- list.files(paths$root, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  files <- files[!dir.exists(files)]
  files <- files[normalizePath(files, mustWork = FALSE) != normalizePath(paths$manifest, mustWork = FALSE)]
  manifest <- do.call(rbind, lapply(files, function(path) {
    relative <- gsub("\\\\", "/", substring(normalizePath(path, mustWork = FALSE), nchar(paths$root) + 2L))
    info <- file.info(path)
    type <- if (grepl("^tables/", relative)) "table" else if (grepl("^figures/", relative)) "figure" else if (grepl("^spatial/", relative)) "spatial" else if (grepl("^metadata/", relative)) "metadata" else if (grepl("^qa/", relative)) "qa" else "object"
    stem <- tools::file_path_sans_ext(basename(relative))
    object <- if (type == "table") file.path("objects", paste0(stem, ".rds")) else if (type == "figure") file.path("objects", paste0("plot_", stem, ".rds")) else if (type == "object") relative else NA_character_
    data.frame(artifact_type = type, logical_product_name = stem, path = relative, file_format = postfit_reporting_file_format(path), source_object = gsub("\\\\", "/", object), source_run = source_run, checksum_sha256 = postfit_reporting_hash_file(path), generated_at_utc = generated_at, bytes = as.numeric(info$size), stringsAsFactors = FALSE)
  }))
  if (is.null(manifest)) manifest <- data.frame()
  utils::write.csv(manifest, paths$manifest, row.names = FALSE, na = "")
  manifest
}

postfit_reporting_write_metadata <- function(paths, metadata) {
  saveRDS(metadata, paths$metadata_rds)
  if (requireNamespace("yaml", quietly = TRUE)) try(yaml::write_yaml(metadata, paths$metadata_yml), silent = TRUE)
  invisible(metadata)
}
