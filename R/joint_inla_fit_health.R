# Pure post-fit provenance checks for the Stage 3B fit-health audit.

joint_inla_fit_health_initialization <- function(configured_mode, recorded_mode,
                                                theta_evidence = NULL) {
  if (is.null(theta_evidence)) theta_evidence <- list()
  normalize_modes <- function(value) {
    value <- tolower(trimws(as.character(value)))
    value <- value[!is.na(value) & nzchar(value)]
    unique(value)
  }

  supported_modes <- c("default", "previous_theta", "historical")
  configured <- normalize_modes(configured_mode)
  recorded <- normalize_modes(recorded_mode)
  mode_status <- "PASS"
  mode_details <- "Recorded initialization mode agrees with the configured supported mode."

  if (length(configured) != 1L || length(recorded) != 1L) {
    mode_status <- "FAIL"
    mode_details <- "Initialization configuration or recorded provenance is missing or internally contradictory."
  } else if (!configured %in% supported_modes || !recorded %in% supported_modes) {
    mode_status <- "FAIL"
    mode_details <- paste0("Unsupported initialization mode; supported modes are ", paste(supported_modes, collapse = ", "), ".")
  } else if (!identical(configured, recorded)) {
    mode_status <- "FAIL"
    mode_details <- "Recorded initialization mode does not match the mode recorded in the runtime configuration."
  }

  theta_status <- "PASS"
  theta_details <- "Theta initialization evidence is not required for this initialization mode."
  if (identical(recorded, "previous_theta")) {
    required <- c("theta_supplied", "theta_length_valid", "theta_order_verified", "compatibility_passed", "restart")
    evidence <- theta_evidence[required]
    missing <- required[vapply(evidence, is.null, logical(1L))]
    if (length(missing) || !all(vapply(evidence, isTRUE, logical(1L)))) {
      theta_status <- "FAIL"
      theta_details <- if (length(missing)) {
        paste0("Previous-theta provenance is incomplete; missing: ", paste(missing, collapse = ", "), ".")
      } else {
        "Previous-theta provenance is internally inconsistent or records a failed compatibility/restart check."
      }
    } else {
      theta_details <- "Previous-theta source, length/order, compatibility, and restart provenance are internally consistent."
    }
  }

  list(
    configured_mode = if (length(configured) == 1L) configured else NA_character_,
    recorded_mode = if (length(recorded) == 1L) recorded else NA_character_,
    supported_modes = supported_modes,
    mode_status = mode_status,
    mode_details = mode_details,
    theta_status = theta_status,
    theta_details = theta_details,
    status = if (mode_status == "FAIL" || theta_status == "FAIL") "FAIL" else "PASS"
  )
}
