# Model specification

This document records the accepted statistical structure. The workflow-closure task does not redesign it.

- Tier 1 uses a binomial likelihood for binary detection/report occurrence.
- Tier 2 uses a negative-binomial likelihood for polygon-week positive counts with terrestrial-area exposure.
- Tier 1 contains a broad SPDE spatial field, weekly RW1, administrative IID effect, and fixed detection/reporting covariates.
- Tier 2 contains an independent SPDE field, a copied Tier 1 field with estimated coefficient, weekly RW1, cattle RW2, environmental covariates/interactions, and livestock fixed effects.

The formula, priors, mesh, copy-field semantics, exposure, zero policy, holdout definitions, projection mathematics, rasterization, and RPI class rules are preserved by the production contracts.

The four artifacts are `model_inputs.rds`, `joint_model_inputs.rds`, `joint_inla_build.rds`, and `joint_model_fit.rds`. Stage 3B also writes `joint_model_theta_init.rds` from the exact fitted `fit$mode$theta` vector, with a verified canonical theta order, source checksums, formula/family/SPDE/effect/prior signatures, hyperparameter count, and runtime versions. Reuse is disabled by default, ignores Stage 3A data-identity checksums for compatibility, preserves those checksums as provenance, and fails closed when structural metadata are missing or inconsistent.

Potential abundance remains Tier 2 intensity multiplied by nominal cell area. Physiological temperature masking is not part of the raw statistical product.
