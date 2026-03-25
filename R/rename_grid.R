# add prefix to tif file names
rename_grid <- function(dir, prefix) {
  files <- list.files(dir, pattern = "\\.tif$", full.names = TRUE)
  
  for (f in files) {
    base <- basename(f)
    new  <- file.path(dir, paste0(prefix, "_", base))
    file.rename(f, new)
  }
}
