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
        +--> extraction / holdout_predictions.csv
        +--> Phase 1 validation
        +--> Phase 2 linear-predictor reconstruction and projection
        +--> Phase 3 rasterization and surface QA
```

Stage 3A is deterministic model preparation. Stage 3B fits the current model
contract; it does not change Stage 2 or Stage 3A. The downstream products are
post-fit diagnostics and representations of the saved posterior means. They
do not refit, rescale, interpolate, threshold, or biologically interpret the
model.

## Frozen model contract

The current contract uses Tier 1 `binomial` and Tier 2 `nbinomial` likelihoods,
the two SPDE fields plus estimated shared copy field, Tier 1 and Tier 2 weekly
RW1 effects, administrative IID, and the cattle RW2 support. The fitting API
uses the joint stack data and A matrix through `control.predictor`, with the
row-specific `data$link` vector and `E = data$e`. The validated initialization
mode is `default`; historical theta vectors are not restored.

Reference architectural counts are 1,478,518 Tier 1 rows, 1,145,865 Tier 2
rows, 13,449 mesh vertices, 8 spatial groups, 22 cattle bins with active bins
1–22 except the documented inactive bins 1 and 3, and 105 prediction weeks.
If a later production dataset intentionally differs, its Stage 2 provenance
must explain the difference and the acceptance record must report the actual
counts.

## Canonical Atlas runtime

Atlas jobs establish the environment themselves:

```bash
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3
```

The expected runtime is R 4.4.3, INLA 25.9.19, terra 1.7.78, sf 1.0.21, and
Matrix 1.7.0, with the user library
`/home/john.humphreys/R/x86_64-pc-linux-gnu-library/4.4`. The existing GEOS
ABI warning is retained as provenance. It is not a reason to alter the working
environment. Jobs must print hostname, module list, R path, R version, and
library/package versions before substantive work.

## Reference lineage

Fit job 20725437 and its downstream outputs are immutable regression references:

* fit: `/project/disease_ecology/nws-geostat-output/joint_inla_fit/joint_model_fit.rds`;
* Stage 2: the `joint_model_inputs.rds` path recorded in the Stage 3A/Stage 3B provenance;
* Stage 3A: the `joint_inla_build.rds` path recorded in the fit metadata;
* Phase 1: `validation_presence_background_20725437`;
* Phase 2: `prediction_projection_20725437`;
* Phase 3: `raster_surfaces_20725437`.

The authoritative reference checksums are those in the saved launch, fit, and
phase metadata. New code may preserve a reference mode for regression tests,
but must not overwrite these files or silently use their paths for a new fit.

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
