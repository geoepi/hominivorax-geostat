library(terra)

rescale_rasters <- function(in_dir, out_dir, max_value = 100, pattern = "\\.tif$") {
  files <- list.files(in_dir, pattern = pattern, full.names = TRUE)
  
  rlist <- lapply(files, rast)
  
  all_min <- min(sapply(rlist, function(r) global(r, "min", na.rm=TRUE)[[1]]))
  all_max <- max(sapply(rlist, function(r) global(r, "max", na.rm=TRUE)[[1]]))
  
  message("Global min: ", all_min, " | Global max: ", all_max)
  
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  
  for (i in seq_along(rlist)) {
    r <- (rlist[[i]] - all_min) / (all_max - all_min) * max_value
    out_file <- file.path(out_dir, basename(files[i]))
    writeRaster(r, out_file, overwrite = TRUE)
  }
}


