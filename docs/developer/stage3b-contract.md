# Stage 3B contract

`scripts/run_joint_inla.R` performs preflight, version checks, and the fit. It writes the fit, audit, metadata, and `joint_model_theta_init.rds` from `fit$mode$theta`. Theta reuse is opt-in and fails closed when verified names/order, formula, family, SPDE, copy-field, effect/prior structure, hyperparameter count, or INLA compatibility metadata are missing or inconsistent. The source Stage 3A checksum is retained as provenance and is not itself a data-identity compatibility gate.
