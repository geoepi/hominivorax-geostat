# Hominivorax-Geostat production workflow

This document freezes the computational workflow used for a production fit and
defines the provenance boundary around it. The workflow is intentionally
staged so that each artifact can be hashed, inspected, and accepted without
re-running an upstream stage.

## Artifact flow

```text
Stage 1 model_inputs.rds
        |
        v
Stage 2 joint_model_inputs.rds
        |
        v
Stage 3A joint_inla_build.rds
        |
        v
Stage 3B joint_model_fit.rds
        |
        +--> theta_init / joint_model_theta_init.rds
        +--> extraction / holdout_predictions.csv
        +--> Phase 1 validation
        +--> Phase 2 linear-predictor reconstruction and projection
        +--> Phase 3 rasterization and surface QA
```

Stage 3A is deterministic model preparation. Stage 3B fits the current model
contract; it does not change Stage 2 or Stage 3A. By default Stage 3B uses
INLA's default initialization. Reuse of a fitted `fit$mode$theta` is an
explicit, checksum- and model-signature-validated opt-in. The downstream products are
post-fit diagnostics and representations of the saved posterior means. They
do not refit, rescale, interpolate, threshold, or biologically interpret the
model.

## Frozen model contract

The current four-stage contract uses Tier 1 `binomial` and Tier 2 `nbinomial` likelihoods,
the two SPDE fields plus estimated shared copy field, Tier 1 and Tier 2 weekly
RW1 effects, administrative IID, and the cattle RW2 support. The fitting API
uses the joint stack data and A matrix through `control.predictor`, with the
row-specific `data$link` vector and `E = data$e`. Initialization mode and theta
provenance are recorded for reproducibility. Reuse of a theta vector is opt-in
and compatibility-checked; initialization mode by itself is not a fit-health
criterion.

The preprocessing contract resolves `end_week: auto_last_complete_observation_week`
from the observed temporal domain, excludes incomplete trailing weeks, and
records the raw/cleaned maximum dates plus the final epiweek. Tier 1 positive
cell-weeks are thinned to one deterministic representative per
`(epiyear, epiweek, cell_id)` by default, with the template checksum, seed,
eligible count, retained count, and exclusions recorded in the audit. If a
later production dataset intentionally differs from a historical reference,
its Stage 2 provenance must explain the difference and the acceptance record
must report the actual counts.

## Canonical Atlas runtime

The operational lessons, interactive compute-node validation workflow, package
paths, and GEOS ABI observation are maintained in
[docs/atlas-environment.md](atlas-environment.md). Read that document before
diagnosing Atlas package availability or changing a wrapper.

Atlas jobs establish the environment themselves:

```bash
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3
```

The expected runtime is R 4.4.3, INLA 25.9.19, terra 1.7.78, sf 1.0.21, and
Matrix 1.7.0. Site-specific library paths are supplied by the Atlas job
environment and are not committed to this repository. The existing GEOS ABI
warning is retained as provenance. It is not a reason to alter the working
environment. Jobs must print hostname, module list, R path, R version, and
library/package versions before substantive work.

## Reference lineage

The accepted historical run is `20742007` and its downstream outputs are
immutable regression references in the private production environment. Their
exact paths and checksums must be read from the saved launch, fit, and phase
metadata; they are deliberately not committed here. New code may preserve a
reference mode for regression tests, but must not overwrite those files or
silently use their paths for a new fit.

## New production runs

New-production downstream work requires explicit `--build`, `--fit`,
`--holdout`, `--stage2`, `--output-dir`, and `--run-id` arguments. Stage 2
holdout counts are derived from the supplied Stage 2 artifact and reconciled to
the extracted holdout table. Tier 2 metrics are required to be finite, but are
not compared with the reference fit's historical metric vector. Every new run
uses a run-specific sibling output root and records input paths, SHA-256
checksums, runtime, model mode, and actual dimensions.

No upstream artifact is regenerated during acceptance. A non-empty output
directory is a hard stop unless an explicit overwrite option is provided.
