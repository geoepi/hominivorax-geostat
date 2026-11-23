# Configuration C-1 predictive qualification protocol

**Pre-registration date:** 2026-11-23
**Configuration:** C-1
**Purpose:** Evaluate the already completed Stage 3B fit on its existing deterministic holdout without refitting or generating prediction surfaces.

## Frozen inputs and scope

Use only the existing Stage 3A build, Stage 2 inputs, completed C-1 Stage 3B fit, and extracted C-1 holdout predictions. The fit is identified as Slurm job `21304948`; the source holdout is `holdout_predictions_c1-stage3b-20261122.csv`. The holdout is aligned to the fitted stack by the existing `output_id` contract. No source records, model specification, fit, or production artifact may be changed.

The analysis window is 2022-W01 through 2026-W44, with final analysis date 2026-11-01. Every holdout record must retain source ISO year/week within that window.

Tier 1 scores use the existing Stage 2 withheld detection rows and the repository's already defined terrestrial integration/background rows. Background rows represent availability with unknown biological status; they must not be assigned confirmed-absence labels. Tier 2 point predictions are evaluated on the expected-count scale, using the validated terrestrial exposure × fitted-intensity contract. Reporting-censored counts are not treated as exact outcomes.

## Metrics and interpretation

Report the repository-standard Tier 1 area-weighted and unweighted presence-background AUC, Continuous Boyce Index, and exact same-week occurrence percentile summaries. Separately report the status of binary ROC-AUC, Brier score, log loss, and binary calibration on the actual held-out Tier 1 responses. If the holdout is positive-only, those binary metrics are `NOT_ESTIMABLE`; availability rows do not supply the missing negative labels.

Report Tier 2 MAE, RMSE, Pearson and Spearman correlation, mean calibration ratio, intercept/slope, equal-frequency calibration bins, and row-level residuals using the existing response-scale expected-count validation. Report subgroup summaries by administrative unit, ISO year, and ISO week. A subgroup's error metrics are displayed only at `n >= 30`; lower-support groups retain their row count and are marked `LOW_SUPPORT`.

Report genuine observation-level negative-binomial predictive intervals only if they are generated from saved posterior support with a documented method that respects the fitted likelihood and exposure. Conditional-mean marginal standard deviations or quantiles are not observation-level predictive intervals and must not be substituted. If no such draws are generated, record the interval assessment as unavailable/not produced and explain the limitation.

Include diagnostic figures for same-week Tier 1 availability ranks, Tier 2 observed versus expected counts, spatially located Tier 2 residuals, and temporal observed/expected means. Figures describe existing holdouts only; the spatial figure is not a prediction surface.

## Acceptance and reporting decision

The repository standards define metric families but no numeric predictive-performance cutoffs. No numeric cutoff is introduced for this qualification, and the report must not imply that descriptive metric values establish acceptable predictive skill. Technical completion requires exact holdout/extraction alignment, valid family/link and response fields, finite scale-valid predictions, auditable exclusions, unchanged source holdout checksum, and no failed blocking audit check.

Classify the result as `C1_PREDICTIVE_VALIDATION_SUPPORTED` only if technical gates pass and the requested validation measures are estimable and produced. Use `C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS` when technical gates pass but a requested assessment is not estimable or predictive uncertainty was not produced. Use `C1_PREDICTIVE_VALIDATION_NOT_SUPPORTED` for a technical gate failure that invalidates the validation. Use `C1_PREDICTIVE_VALIDATION_INCOMPLETE` if required artifacts or metric computations are missing. These labels qualify the validation record, not the scientific model.

## Fit warning

Retain the exact completed-fit warning text and classify it as `INLA_EXPERIMENTAL_VB_WARNING`. Per the project-owner instruction, do not treat it as a failed fit and do not investigate it by running additional fits.

## Prohibited work

Do not refit Stage 3B, regenerate Stages 1–3A, generate geographic prediction rasters/surfaces, refit Configuration B, replace frozen artifacts, reinterpret the response definition, or use quadrature/background rows as confirmed absences.
