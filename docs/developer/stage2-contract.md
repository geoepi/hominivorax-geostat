# Stage 2 contract

`scripts/prepare_joint_model.R` consumes Stage 1 only. It applies reporting censoring, deterministic holdouts, the configured Tier 2 zero policy, shared temporal indices, administrative mapping, livestock RW2 features, and carries temporal/thinning provenance into `joint_model_inputs.rds`.
