# Release procedures

This document describes the lightweight release check for a validated
workflow baseline. It does not authorize a new model fit or scientific
recalibration.

1. Confirm the release branch is clean and contains the accepted validation
   implementation.
2. Run the relevant R tests, parse checks, and `git diff --check`.
3. Check README and `docs/` links, command names, configuration templates, and
   the dynamic production hard-code scan.
4. Run the production dry-run with `config/production.example.yml`; confirm
   that Prepare, Fit, and Post-fit resolve without submitting jobs.
5. Confirm the authoritative source remains read by reference and that source
   and configuration SHAs remain in the run manifest.
6. Verify the accepted full-horizon artifacts remain unchanged.
7. Merge the release branch to `main` with a non-squashing merge, push `main`,
   synchronize Atlas, and verify clean checkouts.
8. Create and push the repository-consistent annotated release tag.

The release baseline deliberately leaves thermal-mask sensitivity analyses,
future Stage 1/2 data minimization, future model-input updates, and scientific
recalibration beyond the current dynamic rules for later work. Historical
comparison utilities may remain in the repository as clearly labeled
diagnostics; they are not required production stages.
