# Helpers shared by post-fit acceptance orchestration and its tests.

postfit_acceptance_output_paths <- function(output_root, run_id) {
  if (length(output_root) != 1L || !nzchar(as.character(output_root))) stop("output_root must be a non-empty path.")
  if (length(run_id) != 1L || !nzchar(as.character(run_id))) stop("run_id must be a non-empty identifier.")
  root <- normalizePath(output_root, mustWork = FALSE)
  list(
    root = root,
    fit_health = file.path(root, "fit_health"),
    extraction = file.path(root, "extraction"),
    validation = file.path(root, "validation"),
    projection = file.path(root, "projection"),
    raster_surfaces = file.path(root, "raster_surfaces"),
    acceptance = file.path(root, "acceptance"),
    summary_rds = file.path(root, "acceptance", paste0("postfit_acceptance_summary_", run_id, ".rds")),
    summary_yaml = file.path(root, "acceptance", paste0("postfit_acceptance_summary_", run_id, ".yml"))
  )
}

postfit_acceptance_output_root_available <- function(output_root, overwrite = FALSE) {
  if (!dir.exists(output_root)) return(TRUE)
  contents <- list.files(output_root, all.files = TRUE, no.. = TRUE, recursive = TRUE)
  isTRUE(overwrite) || !length(contents)
}

postfit_acceptance_require_output_root <- function(output_root, overwrite = FALSE) {
  if (!postfit_acceptance_output_root_available(output_root, overwrite)) {
    stop("Refusing to use a non-empty post-fit output root without explicit overwrite authorization: ", output_root)
  }
  invisible(TRUE)
}

postfit_acceptance_gate <- function(name, status, details = "") {
  status <- toupper(as.character(status))
  if (!status %in% c("PASS", "WARNING", "FAIL")) stop("Invalid post-fit gate status: ", status)
  data.frame(gate = as.character(name), status = status, details = as.character(details), stringsAsFactors = FALSE)
}

postfit_acceptance_overall_status <- function(gates) {
  statuses <- toupper(as.character(gates$status))
  if (any(statuses == "FAIL")) return("FAIL")
  if (any(statuses == "WARNING")) return("PASS_WITH_NONBLOCKING_WARNINGS")
  "PASS"
}

postfit_acceptance_find_one <- function(directory, pattern, label = pattern) {
  paths <- if (dir.exists(directory)) list.files(directory, pattern = pattern, full.names = TRUE, recursive = TRUE) else character()
  if (length(paths) != 1L) stop("Expected exactly one ", label, " under ", directory, "; found ", length(paths), ".")
  normalizePath(paths[[1L]], mustWork = TRUE)
}
