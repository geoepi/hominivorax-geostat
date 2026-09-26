# Stage 3B contract

`scripts/run_joint_inla.R` performs preflight, version checks, and the fit. It writes the fit, audit, metadata, and `joint_model_theta_init.rds` from `fit$mode$theta`. Theta reuse is opt-in and fails closed when compatibility metadata are missing or inconsistent.
