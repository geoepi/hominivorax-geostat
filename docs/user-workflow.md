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

This checkout-relative example is portable for local or other governed
environments. Atlas production uses the canonical checkout and the secure
absolute configuration path documented in the [Atlas deployment guide](developer/atlas-deployment.md);
do not copy the private Atlas configuration into Git.

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

## 7. Use a versioned refresh request

Production refreshes can be described by a schema-versioned YAML request. The
request separates the observation release from the scientific specification,
records source checksums and endpoints, identifies the configuration and
qualification evidence, selects `full`, `resume`, or `adopt`, and records the
required reporting contract. The archived
[W44 request](archive/original-refresh-w44-2026/original_refresh_w44_2026_refresh_request.yml)
is a planning-only example: `dispatch_authorized` is `false` and it must not be
edited to make W44 dispatchable. See the
[refresh and release framework](developer/refresh-release-framework.md) for
the field contract and operator sequence.

For an approved full run, save a reviewed request in the governed location and
run the standard submit wrapper with its matching candidate configuration:

```bash
./scripts/submit_full_pipeline.sh \
  --config /path/to/approved-candidate-production.yml \
  --refresh-request /path/to/reviewed-refresh-request.yml
```

The request hash is rechecked before dispatch. A full request must select
Prepare, Fit, and Post-fit in canonical order; job completion does not activate
the result. For an interrupted request, create a `resume` request containing
the run ID, run-manifest path and SHA-256, then submit it with the compatible
configuration. Only accepted stages with reverified input and output hashes
are reused.

## 8. Adopt an existing fit without refitting

An `adopt` request must enumerate the Stage 1, Stage 2, Stage 3A and fit
artifacts, the source fit job and commit, formula and source-data identities,
fit-health, extraction and predictive-validation evidence, and direct
artifact lineage. The adoption validator reads the small fit metadata file and
hashes the declared artifacts; it does not deserialize the multi-gigabyte fit
or call `INLA::inla()`.

First run the no-write plan:

```bash
./scripts/run_pipeline_atlas.sh \
  --mode dry-run \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --refresh-request docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_refresh_request.yml
```

An adoption dry-run reports the artifacts, registry destination and
configuration compatibility. It must show no Prepare or Fit jobs and zero
submitted jobs. If provenance is blocked, Post-fit remains blocked. An
authorized adoption requires a separately reviewed request with a
`candidate_execution` configuration and explicit dispatch authorization; the
same `submit_full_pipeline.sh` wrapper then submits Post-fit only. Do not use
the archived W44 planning request for dispatch.

## 9. Review, activate, verify, or roll back

After all required gates pass, review the generated `model-release.yml`,
configuration identity, run manifest, product manifest and product checksums.
The release manifest remains `READY_FOR_REVIEW`; neither scheduler completion
nor Git merge changes the active production release.

Use read-only deployment reconciliation and the active-release verifier before
activation. Activation requires the expected active-state generation and
SHA-256, writes an append-only event record, atomically updates the pointer,
and verifies the new pointer. Rollback is a new pointer generation and event;
it keeps both releases and all historical manifests intact. Exact commands
and secure Atlas paths are documented in the
[framework guide](developer/refresh-release-framework.md) and
[Atlas deployment guide](developer/atlas-deployment.md).

## Further reading

- [Documentation index](README.md)
- [Model architecture](developer/model-architecture.md)
- [Production validation contract](developer/production-validation.md)
- [Refresh and release framework](developer/refresh-release-framework.md)
- [Atlas deployment](developer/atlas-deployment.md)
- [Provenance and data residency](developer/provenance-and-data-residency.md)
- [Interpretation guide](interpretation-guide.md)
