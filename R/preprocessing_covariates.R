join_covariates <- function(data, covariates, keys, missing_policy = "fail") { master <- data[keys]; assert_unique_keys(master, keys, "master covariate keys"); audit <- data.frame(variable = character(), missing = integer(), rows = integer()); for (nm in names(covariates)) { z <- covariates[[nm]]; require_columns(z, c(keys, nm), nm); assert_unique_keys(z, keys, nm); k1 <- do.call(paste, c(master[keys], sep = "|")); k2 <- do.call(paste, c(z[keys], sep = "|")); master[[nm]] <- z[[nm]][match(k1, k2)]; audit <- rbind(audit, data.frame(variable = nm, missing = sum(is.na(master[[nm]])), rows = nrow(master))) }; if (missing_policy == "fail" && any(audit$missing > 0)) stop("Missing covariates detected"); list(data = dplyr::left_join(data, master, by = keys, suffix = c("", ".joined")), audit = audit) }
extract_dynamic_covariates <- function(target, specifications, keys = c("epiyear", "epiweek"), missing_policy = "fail") {
  out <- target[keys]; audit <- data.frame(variable = character(), missing = integer(), layers = integer())
  for (nm in names(specifications)) {
    files <- list.files(specifications[[nm]], pattern = "\\.(tif|grd)$", full.names = TRUE, ignore.case = TRUE)
    if (!length(files)) stop("No raster layers found for dynamic covariate: ", nm)
    key <- stringr::str_match(basename(files), "(?:y|year)?(20[0-9]{2})[^0-9]+(?:w|week)?([0-9]{1,2})"); keys_r <- data.frame(epiyear = as.integer(key[,2]), epiweek = as.integer(key[,3])); if (anyNA(keys_r) || anyDuplicated(keys_r)) stop("Dynamic raster keys are missing or duplicated: ", nm)
    if (!requireNamespace("terra", quietly = TRUE)) stop("terra is required for dynamic extraction")
    vals <- lapply(seq_along(files), function(i) { r <- terra::rast(files[i]); p <- terra::vect(target, geom = c("x", "y"), crs = terra::crs(r)); data.frame(epiyear = keys_r$epiyear[i], epiweek = keys_r$epiweek[i], value = terra::extract(r, p, method = "bilinear")[,2]) }); z <- dplyr::bind_rows(vals); names(z)[3] <- nm; out <- dplyr::left_join(out, z, by = keys); audit <- rbind(audit, data.frame(variable = nm, missing = sum(is.na(out[[nm]])), layers = length(files)))
  }
  if (missing_policy == "fail" && any(audit$missing > 0)) stop("Missing dynamic covariates detected"); list(data = out, audit = audit)
}
extract_static_covariates <- function(data, specs, crs = NULL) { out <- data.frame(.row_id = seq_len(nrow(data))); for (nm in names(specs)) { r <- terra::rast(specs[[nm]]); if (is.na(terra::crs(r))) stop("Raster has no CRS: ", nm); p <- terra::vect(data, geom = c("x", "y"), crs = crs %||% terra::crs(r)); out[[nm]] <- terra::extract(r, p, method = "bilinear")[,2] }; out }
`%||%` <- function(x, y) if (is.null(x)) y else x
