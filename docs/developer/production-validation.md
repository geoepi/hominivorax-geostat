# Production validation contract

The production orchestrator exposes three compact gates: Prepare, Fit, and Post-fit. Detailed CSV/RDS audits remain available under each run for debugging, but the scheduler path uses only the gate outcome.

## Prepare gate

The Prepare gate blocks on authoritative input/config readability and SHA lineage, the dynamically resolved horizon and required temporal coverage, required covariates and finite active design values, readable Stage 1/2/3A artifacts, direct Stage 1 → Stage 2 and Stage 2 → Stage 3A provenance, dynamic row/group dimensions, a contiguous current group structure, and `fit_executed = FALSE` in Stage 3A. Theta compatibility remains a pre-fit acceptance check.

Historical row counts, old horizon comparisons, old mesh summaries, runtime estimates, and old holdout counts are diagnostics or provenance only.

## Fit gate

The Fit gate blocks on a readable fit artifact whose direct Stage 3A SHA matches, `fit$ok = TRUE`, successful completion/convergence, the current family/link contract, required fixed/hyperparameter/random-effect summaries, finite posterior summaries and predictor values, and predictor/stack dimensions that reconcile with the Stage 3A design.

DIC, WAIC, marginal likelihood, parameter comparisons, runtime, MaxRSS, and initialization source are retained as nonblocking diagnostics/provenance. Initialization metadata are recorded and may warn when internally contradictory or incomplete, but `previous_theta` is not itself unhealthy.

## Post-fit gate

The Post-fit gate blocks on completed extraction and holdout alignment, finite predictions, valid Phase 2 reconstruction and dimensions, exact Phase 3 raster reconciliation, dynamic weekly support, structural reconstruction, temperature-mask alignment, authoritative coordinate provenance, same-week RPI matching, independently reproducible dynamic RPI threshold, dynamic class support, and required reporting artifacts/manifests.

Historical AUC/MAE/RMSE/correlation comparisons, old RPI thresholds/class counts, old northern extents, and canonical-versus-new product differences remain available as warnings or diagnostic reports. They do not determine production success unless a structural failure is found.

## Result schema and failure semantics

Every gate writes a CSV and RDS with:

`gate`, `check`, `severity`, `status`, `message`, `artifact`, `expected`, and `observed`.

Allowed severities are `BLOCKING`, `WARNING`, and `PROVENANCE`; allowed statuses are `PASS`, `WARN`, `FAIL`, and `INFO`.

The gate outcome is `PASS` when no warning or blocking failure is present, `PASS_WITH_WARNINGS` when warnings are present but no blocking failure occurs, and `FAIL` when any `BLOCKING` check fails. The orchestrator continues for the first two outcomes and stops only for `FAIL`.

The run manifest records `prepare_gate_status`, `fit_gate_status`, `postfit_gate_status`, `warning_count`, and `overall_status`, together with the artifact SHAs, horizon, dimensions, scheduler IDs, and dynamic threshold provenance.

## Private production configuration

Atlas production expects an intentionally untracked `config/production.yml` supplied by the governed deployment environment or copied into the checkout by the operator. It must reference authorized input and output locations and must never be committed. `config/production.example.yml` is tracked for parser and dry-run verification only; it is not a substitute for private production credentials or paths.

Historical comparisons belong in separate diagnostic reports and are not required acceptance criteria.

## Existing-fit adoption gate

The `adopt` operation adds an evidence gate before Post-fit. It verifies the
refresh-request SHA, fit and upstream byte counts and SHA-256 values, Stage 1
→ Stage 2 → Stage 3A → fit configuration links, formula/model identity,
source-data release, fit-health, extraction and predictive-validation audits,
and the historical Slurm launch record. It reads only the small fit metadata
RDS; it never loads the large fit object or calls `INLA::inla()`.

Imported Prepare and Fit stages are recorded as
`NOT_EXECUTED_BY_THIS_RUN`, with a separate adoption result. The historical
fit job ID is provenance only and is never a scheduler dependency. Legacy
partial metadata can pass only when the missing Stage 1 edge is independently
recoverable from the checksummed Stage 2 configuration and Stage 1 audit; that
limitation is retained in the run manifest.

Any mismatch between the Slurm launch commit and fit metadata runtime commit
blocks adoption. A completion-time Git revision does not replace the source
revision recorded at launch. A blocking validation result leaves Post-fit
unsubmitted, even if Slurm reports a successful historical fit.

## Release-product verification

Before a model release can be activated, its separate run and product
manifests are rehashed and every product path, byte count and SHA-256 is
verified. Required reporting products must be present, including the
`mintemp` mask at exactly 16.0 °C and the same-week observation-paired dynamic
RPI contract. This release gate preserves the existing Post-fit scientific
definitions and does not add a new acceptance cutoff to historical predictive
metrics.
