# Model architecture and product semantics

This document is the technical map of the accepted production workflow. A
scheduler job is an operational wrapper around one or more model stages; the
two concepts should not be conflated.

## Stage map

| Model stage | Main purpose | Production job |
| --- | --- | --- |
| Stage 1 | Clean observations, establish spatial support, align covariates, and create model inputs | Prepare |
| Stage 2 | Build Tier 1/Tier 2 responses, exposure, holdouts, prediction grid, and dynamic indices | Prepare |
| Stage 3A | Assemble the joint INLA formula, stacks, meshes, priors, and group mappings | Prepare |
| Stage 3B | Fit the joint binomial/negative-binomial model | Fit |
| Post-fit extraction and validation | Reconcile fitted values, holdouts, finite predictions, and validation metrics | Post-fit |
| Projection | Reconstruct posterior-mean linear predictors on the supported grid | Post-fit |
| Rasterization | Map weekly values back to source cells without interpolation or geometry changes | Post-fit |
| Structural surface | Remove both fitted SPDE contributions and retain the environmental/temporal structure | Post-fit |
| Temperature mask | Apply weekly minimum temperature ≥ 14.5 °C to the structural product | Post-fit |
| Dynamic RPI and reporting | Calibrate the run-specific threshold, classify persistence potential, and write reports/maps | Post-fit |

## Fitted and structural products

The full Tier 2 fitted product includes the Tier 2 SPDE field and the copied
Tier 1 SPDE field. The structural Tier 2 product removes both SPDE
contributions. The structural product therefore emphasizes modeled covariate
and temporal structure rather than the dataset-specific residual spatial
surface; it remains a model-derived prediction, not an observation.

The temperature-masked structural product applies the current weekly minimum
temperature rule at 14.5 °C. It is the input to the current RPI reporting
product. The raw fitted and unmasked structural products remain distinct and
are not overwritten.

RPI is calculated from the masked structural product. Its threshold is derived
for each run from same-week observation/model pairs, and its class boundaries
are fixed by the RPI contract. RPI is a persistence-oriented index rather than
direct evidence that persistence occurred.

## Dynamic runtime contracts

The workflow derives, records, and reconciles the final complete epiweek,
modeled-week count, quarter and other temporal group counts, supported-cell
count, prediction-row count, RPI threshold, job IDs, and output paths from the
current inputs and artifacts. These values are not frozen production
constants. Historical runs may appear in diagnostics, tests, or provenance as
examples, but they do not define acceptance for a new run.

For the compact acceptance contract, see
[production validation](production-validation.md). For source lineage and
residency rules, see [provenance and data residency](provenance-and-data-residency.md).
