#' stack_rasters
#'
#' @description Utility function for geostatistical workflows used in this repository.
#'
#' @return Object produced by stack_rasters() based on provided inputs.
stack_rasters <- function(rast_dir) {
  
  library(terra)
  library(stringr)
  library(dplyr)
  
  count_paths <- list.files(rast_dir, pattern = "\\.tif$", full.names = TRUE)
  base_names  <- basename(count_paths)
  
  file_data <- data.frame(
    path = count_paths,
    filename = base_names,
    year = as.numeric(str_extract(base_names, "(?<=y)\\d{4}")),
    week = as.numeric(str_extract(base_names, "(?<=w)\\d{2}"))
  ) %>%
    arrange(year, week)
  
  clean_labels <- str_replace_all(file_data$filename, "count_|\\.tif", "")
  
  r_stack <- rast(file_data$path)
  names(r_stack) <- clean_labels
  
  return(r_stack)
}
