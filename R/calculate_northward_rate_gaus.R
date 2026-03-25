calculate_northward_rate_gaus <- function(
    nws_obs,
    date_col = "date",
    y_col = "y",
    prob = 0.95,
    w = 7,
    min_n = 5,
    prior_sigma = 0.5, # lower sigma = smoother
    return_quants = c(0.025, 0.25, 0.5, 0.75, 0.975)
) {
  library(dplyr)
  library(INLA)
  library(slider)
  
  # rolling front
  date_range <- range(nws_obs[[date_col]], na.rm = TRUE)
  all_dates <- data.frame(date = seq(date_range[1], date_range[2], by = "day"))
  colnames(all_dates) <- date_col
  
  daily_front <- all_dates %>%
    mutate(
      y_q = vapply(.data[[date_col]], function(d) {
        z <- nws_obs[[y_col]][nws_obs[[date_col]] <= d & nws_obs[[date_col]] > (d - w)]
        if (length(z) < min_n) NA_real_ else as.numeric(quantile(z, prob, na.rm = TRUE))
      }, numeric(1)),
      dy = y_q - lag(y_q),
      t_idx = row_number()
    ) %>%
    # if dy is negative
    mutate(dy_clean = ifelse(!is.na(dy) & dy >= 0, dy, 0))
  
  # INLA model
  n_total <- nrow(daily_front)
  formula_zig <- dy_clean ~ 1 +
    f(t_idx, model = "rw1", values = 1:n_total,
      hyper = list(prec = list(prior = "pc.prec", param = c(prior_sigma, 0.01))))
  
  fit <- inla(
    formula_zig,
    data = daily_front,
    family = "gaussian", # Standard Gaussian is most stable
    control.predictor = list(compute = TRUE), 
    control.compute = list(config = TRUE),
    quantiles = return_quants
  )
  
  # extraction
  res_raw <- as.data.frame(fit$summary.fitted.values)
  q_cols <- grep("quant", colnames(res_raw), value = TRUE)
  speed_results <- res_raw %>% select(mean, all_of(q_cols))
  
  colnames(speed_results) <- c("mean", paste0("Q", return_quants))
  
  final_data <- bind_cols(daily_front, speed_results)
  
  plt <- ggplot(final_data, aes(x = .data[[date_col]], y = mean)) +
    geom_point(aes(y = dy_clean), alpha = 0.1, size = 0.5, color = "gray50") +
    geom_ribbon(aes(ymin = Q0.025, ymax = Q0.975), fill = "firebrick", alpha = 0.2) +
    geom_ribbon(aes(ymin = Q0.25, ymax = Q0.75), fill = "firebrick", alpha = 0.4) +
    geom_line(color = "firebrick", linewidth = 1) +
    theme_minimal() +
    labs(title = "Northward Invasion Velocity (km/day)",
         subtitle = "Gaussian RW1 Model",
         y = "km / day", x = "Date")
  
  return(list(fit = fit, data = final_data, plot = plt))
}