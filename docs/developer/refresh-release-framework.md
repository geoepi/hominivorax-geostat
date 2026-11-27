# Refresh, release, and activation framework

This guide describes the versioned request layer added to the established
Prepare → Fit → Post-fit orchestrator. It does not replace stage scripts,
scientific formulas, validation gates, or raster/reporting definitions.

## Existing-capabilities audit

| Capability | Existing support | Framework behavior |
| --- | --- | --- |
| New full run | Three dependent Prepare, Fit, and Post-fit jobs; run manifest and gates | `full` request pins inputs, configuration, model specification, endpoints, output root, and reporting requirements before using that pipeline. |
| Interrupted-run resume | Run manifest and stage status files; accepted stages are skipped | `resume` request pins the original run manifest by SHA and rehashes accepted input/output artifacts before reuse. |
| Reuse completed upstream stages | Native resume stage-status machinery | Resume uses it; `adopt` imports upstream identities as historical evidence and does not create fictitious Prepare/Fit statuses. |
| Register independently completed fit | No prior adoption mode | `adopt` validates metadata, checksums, audits, model/data identity, and the direct Stage 1 → Stage 2 → Stage 3A → fit chain. It never calls `INLA::inla()`. |
| Post-fit only | Post-fit exists as a stage, but no independent-fit dispatch contract | An accepted, explicitly authorized adoption schedules only Post-fit with no dependency on the historical fit job. |
| Production activation | No versioned active pointer | A verified release manifest and explicit compare-and-swap activation update an existing pointer atomically and append an event. |
| Rollback | No release rollback interface | Rollback creates a new pointer generation and event referencing the prior release; it does not rewrite or delete artifacts. |

## Refresh request schema v1

`--refresh-request PATH` accepts a strict YAML object with these top-level
fields:

| Field | Purpose |
| --- | --- |
| `schema_version`, `request_id` | Request schema and immutable run identity. |
| `operation` | `mode` (`full`, `resume`, or `adopt`), canonical requested stages, and explicit `dispatch_authorized`. |
| `configuration` | Configuration role (`candidate_execution` or read-only `active_deployment`), absolute or repository-relative path and SHA, model identity path and SHA. |
| `model` | Candidate ID, production ID, specification ID, and formula identity. |
| `data` | Observation release ID, source path/SHA, and availability endpoint. |
| `environmental_data` | Environmental availability endpoint and checksummed identity record. |
| `covariate_registry` | Registry identifier and mode; the original specification explicitly declares its manifest-free registry mode. |
| `analysis`, `output` | Requested epiweek window and versioned output root. |
| `qualification` | Scientific status, required gates, evidence path and SHA. |
| `reporting` | Exact 16.0 °C mask, same-week observation-paired RPI calibration, quantile, and required product names. |
| `resume` | Present only for resume; run ID, existing manifest path and SHA. |
| `adoption` | Present only for adopt; artifact inventory, fit SHA/job/commit, report-generation commit, and stage-lineage SHAs. |

The request SHA is captured at load and checked again before dispatch. The
request bytes are archived under run metadata for dispatched work. Full and
resume require the candidate-execution configuration and canonical stage set.
Adoption prohibits Prepare and Fit. A planning-only adoption (`false` dispatch)
cannot register artifacts or submit jobs.

The W44 request at
[`original_refresh_w44_2026_refresh_request.yml`](../archive/original-refresh-w44-2026/original_refresh_w44_2026_refresh_request.yml)
shows the full schema against actual evidence. Its active-deployment
configuration and `dispatch_authorized: false` make it a dry-run request, not a
production instruction.

## Fit adoption and provenance

Adoption validates inventory completeness, bytes and SHA-256 for each source,
the qualified 16-coefficient formula identity, observation release and
analysis window, configuration identity, source config links, fit-health,
extraction and predictive-validation audits, and the historical Slurm launch
record. It deserializes only the small fit metadata RDS. The large fit object
is verified by streaming checksum and is not loaded by R.

The run manifest distinguishes imported evidence from work performed by this
run: Prepare and Fit are `NOT_EXECUTED_BY_THIS_RUN`; adoption has its own
result. A legacy absent Stage 1 path in fit metadata is accepted only when the
checksummed Stage 2 configuration and Stage 1 audit prove the edge. Any
disagreement between launch-time source commit and metadata runtime commit
fails closed pending an explicit provenance decision.

## Stable artifact registry

An authorized adoption stages the declared inventory under
`<output-root>/model_registry/<production-id>` on the same filesystem as its
final destination. The directory is published by atomic rename only after
each copied file is rehashed. A lock prevents concurrent writers; an existing
version is accepted only if its artifact set, source identities, and copied
hashes match exactly. The source is never modified. In addition to the fit and
three upstream stages, the copy retains the small configs, audits, and
supporting records needed to verify the adopted evidence and release later.

The W44 source artifacts are under a development output tree, so they are not
permanent production dependencies. A one-time registry copy is required if
W44 adoption is ever authorized. That copy includes the multi-gigabyte model
artifacts because stable production retention and later lineage verification
require them; it is not performed by a dry-run and is never repeated for an
identical registry version. No production storage path is written during the
planning-only W44 check.

## Reconciliation and activation

Read-only deployment reconciliation is available through:

```bash
./scripts/manage_model_release_atlas.sh \
  --action reconcile \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --deployment-manifest /project/disease_ecology/hominivorax-geostat-config/deployment-manifest.yml \
  --repo-root /project/disease_ecology/hominivorax-geostat
```

Read-only verification of a configured active pointer is:

```bash
./scripts/manage_model_release_atlas.sh \
  --action verify-active \
  --active-state /project/disease_ecology/hominivorax-geostat-config/active-release.yml
```

Activation and rollback require the active-state path, the verified release
manifest or prior activation event, the expected pointer generation and SHA,
and the append-only event directory:

```bash
./scripts/manage_model_release_atlas.sh --action activate \
  --active-state /project/disease_ecology/hominivorax-geostat-config/active-release.yml \
  --release-manifest /project/disease_ecology/nws-geostat-output/production_runs/<run-id>/model-release.yml \
  --expected-generation <generation> \
  --expected-state-sha256 <active-state-sha256> \
  --event-root /project/disease_ecology/hominivorax-geostat-config/activation-events
```

```bash
./scripts/manage_model_release_atlas.sh --action rollback \
  --active-state /project/disease_ecology/hominivorax-geostat-config/active-release.yml \
  --activation-event /project/disease_ecology/hominivorax-geostat-config/activation-events/<activation-event>.yml \
  --expected-generation <generation> \
  --expected-state-sha256 <active-state-sha256> \
  --event-root /project/disease_ecology/hominivorax-geostat-config/activation-events
```

The implementation does not initialize an active pointer from `production.yml`
because that config alone does not identify the active W39 fit artifact. The
current deployment configuration and historical deployment manifest are
reported as observed; they are not modified by reconciliation.

## W44 review boundary

The current private configuration is tied to W39 and its recorded deployment
manifest references a different checkout commit and config SHA. The W44 fit
Slurm output records launch source `42f27497b251cdcd84d2b44b1844cd18292610a8`,
while its completion metadata records `5bf5e8d0f54de55e58f3a698daefb223ddc9d2e0`.
Adoption remains blocked until that launch/metadata discrepancy is resolved.
The current W44 request has no dispatch authorization. This framework change
does not copy the W44 fit, submit Post-fit, create production rasters, alter
the private configuration, merge PR #15, or activate W44.
