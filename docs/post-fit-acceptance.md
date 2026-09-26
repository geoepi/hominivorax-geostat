# Post-fit acceptance protocol

Post-fit acceptance is a gated computational workflow for a completed Stage 3B
fit. It is not a watcher, SLURM dependency, validation claim, or biological
interpretation. The one-shot Atlas wrapper is
`scripts/run_postfit_acceptance_atlas.sh`.

## Gate order

0. **Scheduler completion.** `sacct` must report the exact fit job as
   `COMPLETED` with exit code `0:0`. A running, pending, cancelled, or failed
   job cannot enter downstream analysis.
1. **Fit health.** `scripts/check_joint_inla_fit_health.R` checks the saved fit
   artifact, summaries, random-effect components, predictor dimensions, finite
   DIC/WAIC when requested, marginal log likelihood, and recorded warnings.
2. **Extraction.** `scripts/extract_joint_inla_results.R` maps the saved fit to
   Stage 2 rows. Any extraction audit `FAIL` stops the pipeline before writing
   holdout predictions.
3. **Phase 1 validation.** New production mode reconciles dynamic Stage 2
   holdout counts and reports finite Tier 2 metrics without applying the
   historical reference vector. Reference mode is retained only for the
   20725437 numerical regression lineage.
4. **Phase 2 projection.** The reconstruction identity must pass before dense
   prediction-grid projection is attempted. Stage 2 provenance is reconciled
   to Stage 3A, and the Phase 2 metadata must carry the requested run ID.
5. **Phase 3 rasterization.** The template, cell IDs, weeks, manifest, and
   direct cell assignments must pass surface QA. Rasterization derives row/week
   expectations from the supplied Stage 2 artifact unless explicit values are
   provided.
6. **Acceptance summary.** The machine-readable summary combines all gate
   audits and returns exactly one of `PASS`,
   `PASS_WITH_NONBLOCKING_WARNINGS`, or `FAIL`.

## Output isolation

The wrapper requires explicit paths for the fit, Stage 2, Stage 3A, holdout
table, run ID, and a new output root. A typical root is:

```text
production_postfit_<run-id>/
  fit_health/
  extraction/
  validation/
  projection/
  raster_surfaces/
  acceptance/
```

The reference fit directory and its Phase 1–3 outputs are immutable. All
phase runners refuse non-empty output directories unless `--overwrite` is
explicitly supplied. The wrapper does not create a watcher and does not submit
automatic scheduler dependencies.

## Required provenance

The final summary records the run purpose, production/reference mode, job ID,
UTC time, git commit, absolute input paths, SHA-256 checksums, actual Tier 1
and Tier 2 rows, mesh vertices, SPDE groups, cattle support, R/module/runtime
details, initialization mode, model families, output paths, audit counts, and
the final gate status. It records computational QA only; biological conclusions
require a separate review.

## Safe execution boundary

The running production fit must not be opened, analyzed, or modified before
Gate 0. While a fit is running, local workflow changes may be frozen and pushed
for later use, but the Atlas checkout must not be pulled to a new commit. No
preprocessing, Stage 2 rebuild, Stage 3A rebuild, refit, projection, or
rasterization is part of the launch task.
