# Hominivorax-Geostat

Hominivorax-Geostat is a joint geostatistical workflow for studying the spatial and temporal dynamics of New World screwworm (*Cochliomyia hominivorax*). It separates detection/report occurrence from abundance intensity so that surveillance effort and ecological signal are not treated as the same process.

## What the model does

The workflow has two linked responses:

- Tier 1 models reported detections against spatial and temporal background support. Background locations are availability support, not confirmed absences.
- Tier 2 models polygon-level positive counts with terrestrial-area exposure and environmental, livestock, spatial, and temporal effects.

Tier 2 borrows a spatial signal from Tier 1 through the accepted copy-field structure while retaining its own spatial field. The [model workflow overview](docs/model-workflow-overview.md) explains the design for ecological readers; the [model specification](docs/model-specification.md) records the technical contract.

## Production workflow

```text
raw observations + covariates
        ↓
Stage 1  run_preprocessing.R       → model_inputs.rds
        ↓
Stage 2  prepare_joint_model.R     → joint_model_inputs.rds
        ↓
Stage 3A build_joint_inla.R       → joint_inla_build.rds
        ↓
Stage 3B run_joint_inla.R         → joint_model_fit.rds
        ↓
validation → projection → raster reconstruction → post-fit reporting → RPI
```

The default production temporal endpoint is the last complete epidemiological week represented by the cleaned observation data. Tier 1 positive cell-week thinning is configurable and defaults to the accepted seed `1976`. A successful Stage 3B fit writes a reusable `joint_model_theta_init.rds` artifact, but theta reuse is opt-in and compatibility-checked.

## Primary outputs

- Tier 1 detection probability surfaces and presence/background diagnostics.
- Tier 2 intensity and held-out positive-count diagnostics.
- Posterior component summaries, temporal effects, livestock effects, and standardized potential-abundance surfaces.
- Reproductive Persistence Index (RPI) products when the semantic and calibration gates pass.

Potential abundance is a standardized derived quantity: Tier 2 intensity multiplied by nominal raster-cell area. It is not a direct posterior expected count for every partial or coastal cell.

## Reproducibility

Tracked example configurations are portable. Copy the relevant example to an ignored local configuration, provide private inputs, and run the staged scripts. Dynamic covariate files are indexed by epidemiological week; missing required weeks fail explicitly.

```powershell
& 'C:\Program Files\R\R-4.5.0\bin\Rscript.exe' scripts/run_preprocessing.R --config config/preprocessing.yml
& 'C:\Program Files\R\R-4.5.0\bin\Rscript.exe' scripts/prepare_joint_model.R --config config/joint_model.yml
& 'C:\Program Files\R\R-4.5.0\bin\Rscript.exe' scripts/build_joint_inla.R --config config/joint_inla.yml
& 'C:\Program Files\R\R-4.5.0\bin\Rscript.exe' scripts/run_joint_inla.R --config config/joint_inla_fit.yml
```

Do not commit private observations, fitted objects, production rasters, credentials, or machine-specific configuration. GitHub is the canonical source for code, configuration templates, tests, and documentation; Atlas is an execution environment for private data and large outputs. See [Atlas environment notes](docs/atlas-environment.md) and [data and preprocessing](docs/data-and-preprocessing.md).

## Documentation

- [Model workflow overview](docs/model-workflow-overview.md)
- [Model specification](docs/model-specification.md)
- [Interpretation guide](docs/interpretation-guide.md)
- [Data and preprocessing](docs/data-and-preprocessing.md)
- [Validation](docs/validation.md)
- [Post-fit reporting](docs/post-fit-reporting.md)
- [Production workflow and provenance](docs/production-workflow.md)
- [Deferred development roadmap](docs/deferred-development.md)
- [GitHub/local/Atlas synchronization](docs/synchronization.md)
- [Developer contracts](docs/developer/)

The rendered public site remains configured through `_quarto.yml` with output in `docs/`. Rendered pages are supporting documentation; the tracked R scripts and tests are the executable contract.

## Status

The repository contains the accepted staged workflow, validation and reporting interfaces, and a consolidation branch for production-workflow closure. New ecological interpretation and model-development experiments are intentionally deferred; see the roadmap.
