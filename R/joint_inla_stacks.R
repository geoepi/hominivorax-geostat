make_joint_stack <- function(data, projection, effects, response, link, exposure, tag, joint = FALSE, column = NULL) {
  require_joint_inla()
  y <- if (isTRUE(joint)) {
    values <- matrix(NA_real_, nrow = nrow(data), ncol = 2L)
    values[, column] <- as.numeric(response)
    values
  } else as.numeric(response)
  INLA::inla.stack(
    data = list(Y = y, link = rep(as.integer(link), nrow(data)), e = as.numeric(exposure)),
    A = list(projection, 1), effects = list(effects$latent, effects$fixed), tag = tag
  )
}

build_joint_stacks <- function(tier1, tier2, projections, effects) {
  tier1_exposure <- rep(NA_real_, nrow(tier1))
  tier2_exposure <- if ("terrestrial_area_km2" %in% names(tier2)) tier2$terrestrial_area_km2 else tier2$area_km2
  list(
    tier1 = make_joint_stack(tier1, projections$tier1, effects$tier1, tier1$response_training, 1L, tier1_exposure, "tier1", FALSE),
    tier2 = make_joint_stack(tier2, projections$tier2, effects$tier2, tier2$response_training, 2L, tier2_exposure, "tier2", FALSE),
    joint_components = list(
      tier1 = make_joint_stack(tier1, projections$tier1, effects$tier1, tier1$response_training, 1L, tier1_exposure, "tier1", TRUE, 1L),
      tier2 = make_joint_stack(tier2, projections$tier2, effects$tier2, tier2$response_training, 2L, tier2_exposure, "tier2", TRUE, 2L)
    )
  ) |>
    (
      function(stacks) {
        stacks$joint <- INLA::inla.stack(stacks$joint_components$tier1, stacks$joint_components$tier2)
        stacks
      }
    )()
}
