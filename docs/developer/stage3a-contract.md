# Stage 3A contract

`scripts/build_joint_inla.R` deterministically assembles the accepted two-family model and writes SPDE objects, projections, stacks, formula, priors, model signature, fit reference, and provenance. It does not execute `INLA::inla()`.
