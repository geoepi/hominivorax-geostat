repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "joint_inla_fit_health.R"))

previous_theta_evidence <- list(
  theta_supplied = TRUE,
  theta_length_valid = TRUE,
  theta_order_verified = TRUE,
  compatibility_passed = TRUE,
  restart = TRUE
)

default_result <- joint_inla_fit_health_initialization("default", "default")
stopifnot(identical(default_result$status, "PASS"),
          identical(default_result$mode_status, "PASS"))

previous_theta_result <- joint_inla_fit_health_initialization(
  "previous_theta", "previous_theta", previous_theta_evidence
)
stopifnot(identical(previous_theta_result$status, "PASS"),
          identical(previous_theta_result$theta_status, "PASS"))

recorded_default_result <- joint_inla_fit_health_initialization(
  "previous_theta", "default", previous_theta_evidence
)
stopifnot(identical(recorded_default_result$status, "FAIL"),
          identical(recorded_default_result$mode_status, "FAIL"))

recorded_previous_theta_result <- joint_inla_fit_health_initialization(
  "default", "previous_theta", previous_theta_evidence
)
stopifnot(identical(recorded_previous_theta_result$status, "FAIL"),
          identical(recorded_previous_theta_result$mode_status, "FAIL"))

missing_theta_evidence_result <- joint_inla_fit_health_initialization(
  "previous_theta", "previous_theta", list()
)
stopifnot(identical(missing_theta_evidence_result$status, "FAIL"),
          identical(missing_theta_evidence_result$theta_status, "FAIL"))

failed_theta_compatibility_result <- joint_inla_fit_health_initialization(
  "previous_theta", "previous_theta", modifyList(previous_theta_evidence, list(compatibility_passed = FALSE))
)
stopifnot(identical(failed_theta_compatibility_result$status, "FAIL"))

cat("Stage 3B fit-health initialization contract tests passed\n")
