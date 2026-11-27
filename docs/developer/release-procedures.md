# Release procedures

This document describes the lightweight release check for a validated
workflow baseline. It does not authorize a new model fit or scientific
recalibration.

1. Confirm the release branch is clean and contains the accepted validation
   implementation.
2. Run `Rscript tests/run_tests.R`, relevant parse checks, and `git diff --check`.
   The canonical test runner records per-script status and separate stdout and
   stderr logs; see [test execution](testing.md).
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

Framework work that depends on an open qualification-review PR is delivered
through a separate draft PR with an explicit dependency; it does not change or
merge that qualification PR. A Git merge only integrates reviewed software.
Production model activation remains a separate operation through
`scripts/manage_model_release_atlas.sh --action activate` after the versioned
release manifest, configuration identity, model qualification, upstream
artifacts and post-fit products have all been independently verified. Never
infer model activation from branch synchronization, a successful fit job, or
creation of a release tag.

The release baseline deliberately leaves thermal-mask sensitivity analyses,
future Stage 1/2 data minimization, future model-input updates, and scientific
recalibration beyond the current dynamic rules for later work. Historical
comparison utilities may remain in the repository as clearly labeled
diagnostics; they are not required production stages.
