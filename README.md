# hominivorax-geostat

`hominivorax-geostat` is a model-based ecological workflow for understanding
where New World screwworm (*Cochliomyia hominivorax*) is reported and how
modeled occurrence intensity changes across space and time.

The workflow is designed for surveillance and ecological analysis. It combines
cleaned observations with environmental, land-use, livestock, spatial, and
temporal information. Because surveillance is uneven, a missing report is not
treated as proof of biological absence.

## Purpose

The project characterizes spatial and temporal patterns in New World screwworm
occurrence and positive-count intensity. It keeps detection/reporting
opportunity distinct from the intensity of positive counts, then produces
model-derived surfaces that can be inspected, validated, mapped, and compared
across epidemiological weeks.

The broad workflow is:

```text
observations + environmental information
        ↓
spatiotemporal statistical model
        ↓
fitted and structural spatial predictions
        ↓
physiological temperature constraint
        ↓
persistence-oriented RPI classification
        ↓
validation summaries, maps, and reporting products
```

## What the model produces

- **Fitted/model-reconstruction outputs** retain the full modeled spatial and
  temporal structure. They support interpretation of the fitted model and
  reproducible reconstruction of predictions.
- **Structural ecological predictions** remove the fitted SPDE spatial
  contributions so that modeled environmental and temporal structure can be
  examined without the dataset-specific residual spatial surface.
- **Temperature-masked structural potential abundance** applies the current
  physiological rule based on weekly minimum temperature of at least 14.5 °C.
  It is a model-derived potential-abundance index, not a direct count of
  animals.
- **RPI** is a persistence-oriented index derived from the masked structural
  product. Its threshold is recalculated for each run from same-week
  observation/model pairs; the class boundaries are fixed. RPI is a derived
  ecological classification, not direct proof of biological persistence.

## How the workflow is used

The production workflow runs three connected stages:

```text
Prepare → Fit → Post-fit
```

Prepare builds the model inputs and model definition, Fit estimates the joint
model, and Post-fit creates validation, weekly prediction, raster, structural,
temperature-masked, RPI, and reporting products. The workflow records the
input and configuration checksums, resolved time horizon, artifact lineage,
stage status, and diagnostics for each run.

## Quick start

Create a private production configuration from the tracked template, add the
authorized observation and covariate paths, and keep the resulting file
untracked:

```bash
cp config/production.example.yml config/production.yml
./scripts/submit_full_pipeline.sh --config config/production.yml
```

The command submits the Prepare → Fit → Post-fit workflow. See the
[user workflow guide](docs/user-workflow.md) for what to check before and
after submission. Scheduler options, dry-runs, resumption, and resource
profiles are documented in the [production orchestration guide](docs/developer/production-orchestration.md).

## Where to find results

Each run receives its own output directory. Start with:

- the run manifest and final summary for provenance and stage status;
- validation and diagnostics for holdout checks, reconstruction, and model
  health;
- projection and raster directories for weekly surfaces;
- structural and masked directories for ecological prediction products; and
- reporting outputs for maps, RPI, summaries, and product metadata.

The run manifest is the best first point of reference because it records the
run ID, source and configuration checksums, dynamic dimensions, output paths,
gate outcomes, and scheduler IDs.

## Main scientific caveats

Presence/background validation evaluates ranking against the chosen support
design; it is not classification accuracy. Structural surfaces are
model-derived ecological predictions. Potential abundance combines modeled
Tier 2 intensity with nominal cell area and is an index rather than a direct
posterior count for every cell. RPI summarizes modeled persistence potential
under its calibration and temporal rules; it does not observe persistence
directly.

## Repository structure

```text
R/           reusable model, validation, and reporting functions
scripts/     runnable workflow entry points
config/      tracked configuration templates
docs/        user and technical documentation
tests/       automated implementation and contract tests
```

## Technical documentation

Use the [documentation index](docs/README.md) to navigate model architecture,
workflow operations, validation, provenance, reporting semantics, and release
procedures. The [model workflow overview](docs/model-workflow-overview.md)
provides the ecological model explanation; technical contracts are maintained
under [docs/developer](docs/developer/).

For the operator-facing workflow, start with the [user workflow guide](docs/user-workflow.md).
Atlas operators should also read the [Atlas deployment guide](docs/developer/atlas-deployment.md),
which records the canonical production checkout and secure configuration paths.

## Citation and status

Please cite the project and the associated scientific publication when the
citation details are finalized. The repository contains the accepted
full-horizon workflow, dynamic production validation, structural and
temperature-masked reporting products, and the documentation needed to run
and interpret the workflow. Future scientific recalibration and sensitivity
analyses remain intentionally separate from this release.
