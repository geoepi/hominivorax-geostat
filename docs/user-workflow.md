# Running the production workflow

This guide is for scientists and operators running an authorized production
analysis. The workflow reads governed inputs by reference and writes a
run-specific output directory; it does not copy the authoritative observation
CSV into that directory.

## 1. Confirm the inputs

Confirm that the current observation source and required weekly covariates are
available in the governed environment. Confirm that the observations contain
the required date or epidemiological-week and coordinate fields, and that the
configured spatial and temporal coverage is intentional.

## 2. Prepare the production configuration

Copy the tracked template to the intentionally untracked deployment file and
fill in authorized paths:

```bash
cp config/production.example.yml config/production.yml
```

The real `config/production.yml` is a governed deployment input. Do not commit
private paths, credentials, observations, fitted objects, or production
rasters.

## 3. Submit the workflow

```bash
./scripts/submit_full_pipeline.sh --config config/production.yml
```

The orchestrator submits three dependent jobs:

```text
Prepare → Fit → Post-fit
```

Prepare builds Stages 1–3A and performs the pre-fit gate. Fit runs Stage 3B
and performs the fit-health gate. Post-fit performs extraction, validation,
projection, rasterization, structural reconstruction, temperature masking, RPI,
and reporting, followed by the post-fit gate.

## 4. Monitor the run

Use the scheduler status and the run directory recorded at submission. Each
stage writes a status file and the run metadata directory contains the primary
`run_manifest.yml` and final summary. The three gates use these outcomes:

- **PASS** — required correctness, provenance, and completeness checks passed.
- **PASS_WITH_WARNINGS** — required checks passed; non-blocking diagnostics or
  provenance items need operator awareness.
- **FAIL** — the workflow stopped because a blocking correctness, provenance,
  dimension, finite-value, or required-output condition failed.

Historical comparison differences are reported as diagnostics or warnings and
do not invalidate a run by themselves.

## 5. Locate results

Within the run-specific output directory, use these locations by purpose:

| Purpose | Directory or file |
| --- | --- |
| Provenance and stage status | `metadata/run_manifest.yml`, `metadata/production_summary.yml`, `metadata/status_*.yml` |
| Model diagnostics | `fit_health/`, `logs/`, and stage audit files |
| Holdout validation | `extraction/`, `validation/` |
| Weekly predictions and raster products | `projection/`, `raster/` |
| Structural ecological products | `structural/` |
| Temperature-masked structural products | `masked_structural_rpi/` |
| Maps, RPI, and summaries | `reporting/` |

Start with the final summary, then open the validation and reporting metadata
before using a map or derived index.

## 6. Resume an incomplete run

Provide the existing run ID:

```bash
./scripts/submit_full_pipeline.sh \
  --config config/production.yml \
  --resume <run_id>
```

Accepted stages are reused. The orchestrator resumes from the first incomplete
stage after checking the existing manifest and configuration/source checksums.
For dry-runs, partial-stage execution, and scheduler resource details, see
the [production orchestration guide](developer/production-orchestration.md).

## Further reading

- [Documentation index](README.md)
- [Model architecture](developer/model-architecture.md)
- [Production validation contract](developer/production-validation.md)
- [Provenance and data residency](developer/provenance-and-data-residency.md)
- [Interpretation guide](interpretation-guide.md)
