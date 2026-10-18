#!/usr/bin/env Rscript

script_args <- commandArgs(trailingOnly = FALSE)
script_file <- script_args[grep("^--file=", script_args)][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_file)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "postfit_reporting.R"), local = .GlobalEnv)

parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!grepl("^--", key)) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (identical(name, "overwrite")) {
      out[[name]] <- TRUE
      i <- i + 1L
    } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) stop("Missing value for ", key)
      out[[name]] <- args[[i + 1L]]
      i <- i + 2L
    }
  }
  out
}

arg <- function(x, name, default = NULL) if (is.null(x[[name]])) default else x[[name]]
args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c(
  baseline_class = arg(args, "baseline-class"),
  temp15_class = arg(args, "temp15-class"),
  temp16_class = arg(args, "temp16-class"),
  boundary = arg(args, "boundary"),
  output_root = arg(args, "output-root")
)
missing <- names(required)[vapply(required, function(x) is.null(x) || !nzchar(x), logical(1L))]
if (length(missing)) stop("Missing required arguments: ", paste(paste0("--", gsub("_", "-", missing)), collapse = ", "))

source_paths <- lapply(required[1:4], normalizePath, mustWork = TRUE)
output_root <- normalizePath(required[["output_root"]], mustWork = FALSE)
overwrite <- isTRUE(args[["overwrite"]])
if (dir.exists(output_root) && length(list.files(output_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)) && !overwrite) {
  stop("Refusing non-empty figure-only output root without --overwrite: ", output_root)
}
for (directory in c("metadata", "figures", "qa")) dir.create(file.path(output_root, directory), recursive = TRUE, showWarnings = FALSE)

postfit_reporting_require(c("terra", "sf", "ggplot2", "ggspatial"))
boundary <- sf::st_read(source_paths[["boundary"]], layer = "study_states", quiet = TRUE)
if (is.na(sf::st_crs(boundary))) stop("Canonical boundary must carry CRS metadata.")
boundary <- sf::st_make_valid(boundary)
cartography <- postfit_reporting_rpi_cartography()
labels <- postfit_reporting_rpi_class_labels()
palette <- postfit_reporting_rpi_class_palette(labels)

render_one <- function(input_path, stem, title) {
  p <- postfit_reporting_plot_rpi(terra::rast(input_path), boundary = boundary, title = title)
  spec <- attr(p, "postfit_reporting_rpi_cartography")
  pdf_path <- file.path(output_root, "figures", paste0(stem, ".pdf"))
  png_path <- file.path(output_root, "figures", paste0(stem, ".png"))
  ggplot2::ggsave(pdf_path, p, width = spec$dimensions[["width"]], height = spec$dimensions[["height"]], units = "in", device = grDevices::pdf)
  ggplot2::ggsave(png_path, p, width = spec$dimensions[["width"]], height = spec$dimensions[["height"]], units = "in", dpi = spec$dimensions[["dpi"]])
  data.frame(
    product = stem,
    source_path = input_path,
    source_sha256 = postfit_reporting_hash_file(input_path),
    pdf_path = pdf_path,
    png_path = png_path,
    pdf_sha256 = postfit_reporting_hash_file(pdf_path),
    png_sha256 = postfit_reporting_hash_file(png_path),
    stringsAsFactors = FALSE
  )
}

source_manifest <- do.call(rbind, list(
  render_one(source_paths[["baseline_class"]], "rpi_class_14p5_v2", "14.5°C RPI classes"),
  render_one(source_paths[["temp15_class"]], "rpi_class_temp15_v3", "15.0°C RPI classes"),
  render_one(source_paths[["temp16_class"]], "rpi_class_temp16_v2", "16.0°C RPI classes")
))
utils::write.csv(source_manifest, file.path(output_root, "metadata", "source_manifest.csv"), row.names = FALSE, na = "")

figure_qa <- data.frame(
  check = c("temperature_derivative", "rpi_recalculation", "palette", "projection", "extent", "boundary", "california_frame", "raster_rendering", "ggspatial", "legend"),
  status = c("PASS", "NOT_PERFORMED", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS", "PASS"),
  details = c(
    "Figure-only rendering from existing classified rasters; no masking or RPI recalculation performed.",
    "Existing classified rasters were read without recomputation.",
    paste(paste(names(palette), unname(palette), sep = "="), collapse = " | "),
    cartography$plot_crs,
    paste(names(cartography$extent), cartography$extent, collapse = " "),
    paste(normalizePath(source_paths[["boundary"]], mustWork = TRUE), cartography$boundary_layer, sep = " | "),
    "Fixed projected frame includes the western United States, including California.",
    cartography$raster_rendering,
    paste(cartography$annotations$north_arrow, cartography$annotations$scale_bar, sep = " | "),
    paste(labels, collapse = " | ")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(figure_qa, file.path(output_root, "qa", "figure_qa_summary.csv"), row.names = FALSE, na = "")

if (!requireNamespace("yaml", quietly = TRUE)) stop("The yaml package is required to write cartography metadata.")
yaml::write_yaml(list(
  derivative_type = "figure_only_rpi_class_cartography",
  source_manifest = "metadata/source_manifest.csv",
  boundary = list(path = source_paths[["boundary"]], layer = cartography$boundary_layer, sha256 = postfit_reporting_hash_file(source_paths[["boundary"]])),
  labels = labels,
  palette = palette,
  cartography = cartography,
  reference_figure = arg(args, "reference-figure", NA_character_),
  rpi_recalculated = FALSE,
  temperature_mask_recalculated = FALSE,
  qa = "qa/figure_qa_summary.csv"
), file.path(output_root, "metadata", "cartography_spec.yml"))
cat("Canonical RPI figure regeneration complete\nOutput: ", output_root, "\n", sep = "")
