#!/usr/bin/env Rscript
test_file <- file.path("scripts", "run_temperature_rpi_derivative.R")
stopifnot(file.exists(test_file))
src <- paste(readLines(test_file, warn = FALSE), collapse = "\n")
required <- c(
  "temperature-threshold", "16.0", "structural_apply_temperature_mask",
  "rpi_dynamic_threshold_temp16.csv", "rpi_class_area_temp16.csv",
  "rpi_class_temp16.pdf", "rpi_class_temp15_v2.pdf",
  "study_states.gpkg", "geom_raster", "RPI Class",
  "annotation_north_arrow", "annotation_scale", "support16 & !support15",
  "stats::quantile(values, probs = probs, names = FALSE, type = 7)",
  "no_na_to_zero_conversion", "no_unmatched_to_zero_conversion",
  "rpi_class_transition_", "write_transition(temp15_class_raster, rpi16$stability_class, \"15_to_16\")"
)
missing <- required[!vapply(required, grepl, logical(1L), x = src, fixed = TRUE)]
if (length(missing)) stop("Missing required derivative contract text: ", paste(missing, collapse = ", "))
if (!grepl("output_root.*temp15_root|temp15_root.*output_root", src)) stop("Missing 15 C overwrite guard.")
if (!grepl("scale_fill_manual", src, fixed = TRUE)) stop("Missing explicit canonical palette.")
cat("TEMP16_SOURCE_CONTRACT_PASS\n")

