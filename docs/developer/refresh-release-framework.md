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

## Specification identity and release class

A release descriptor includes likelihood, fixed-effect formula and order,
random-effect structure, priors, spatial/temporal structure, transformations,
and product semantics. Its SHA-256 is computed from recursively sorted JSON,
so mapping key order does not change identity. Product semantics bind the
mask threshold, RPI calibration and quantile, and required product categories
to the same descriptor. Data release and analysis endpoint remain separate
fields.

`ROUTINE_REFRESH` is valid only when the candidate descriptor digest equals
the comparison digest and the specification ID is retained.
`MODEL_REVISION` requires a different digest and a new specification ID.
A matching model name alone does not select the routine class. The descriptor,
comparison identity, data-release identity, code commit, config checksum,
qualification state, fit identity, accepted package, product categories, and
previous release are recorded in schema v2 manifests.

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

## Canonical artifact storage and registration

An authorized adoption stages metadata and any required payload copies under
`<production-runs>/model_registry/<production-id>`. A core artifact already
inside canonical `production_runs` may be registered by a regular-file
reference with its path, source provenance, byte count, and SHA-256. A core
artifact outside that canonical root, including an artifact in a development
worktree, is copied once into registry staging and rehashed before atomic
publication. The implementation does not use hardlinks, reflinks, or
symlinks. An existing registry version is reused only when its declared
artifact identities match; it is never overwritten.

No artifact copy is performed by a planning-only request. W44's current source
is outside canonical `production_runs`, so a future separately authorized
adoption would need a verified canonical copy to avoid depending on a
development worktree. This task does not copy the W44 payload or remove its
source. A later source cleanup would require a separate owner-authorized
review after references and consumers are resolved.

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

The launch-record and runtime-metadata commits have been reconciled. The
`R`, `scripts`, `config`, and `tests` trees are identical; changes are
limited to archived documentation and evidence. The original launch identity,
fit metadata, and qualification records remain unchanged. The W44 request is
still planning-only with `dispatch_authorized: false`. This framework does not
copy W44 artifacts, submit Post-fit, create rasters, change private
configuration, initialize or update an active pointer, or activate W44.

## Read-only discovery and cleanup review

`discover-active` validates the existing active-state pointer and the
referenced manifest, then returns the stable manifest path and checksum. It
does not create the pointer. `register-accepted-package` validates the
accepted package and writes a separate immutable schema v2 manifest with
`QUALIFIED_NOT_ACTIVE` status; activation remains a distinct compare-and-swap
operation.

`cleanup-report` consumes an inventory of owner, size, source references,
consumers, retention dates/cycles, job references, replacement identity, and
preservation/duplicate flags. It reports review eligibility and estimated
recoverable storage only. Eligibility uses the later of the 90-day minimum and
two subsequent qualified refreshes, and the report requires explicit owner
and governance approval. No cleanup or automatic deletion is implemented.

## Artifact-only adoption registration

Artifact registration can be performed before Post-fit as a separate, audited
operation. Its versioned adoption request must set
`artifact_registration_authorized: true`, keep
`dispatch_authorized: false`, and leave `requested_stages` empty. The request
must use a `candidate_execution` configuration. The action runs the full
adoption evidence validator, stages artifacts under the canonical model
registry, verifies the staged checksums, and publishes the immutable registry
manifest atomically. An existing identical registry entry is reused; a
different entry is refused.

Invoke the action through the Atlas wrapper:

    ./scripts/manage_model_release_atlas.sh       --action register-adopted-artifacts       --request /project/disease_ecology/hominivorax-geostat-config/candidates/<candidate>/artifact-registration-request.yml       --repo-root /project/disease_ecology/hominivorax-geostat

This operation creates no execution run directory and submits no Prepare, Fit,
or Post-fit job. Keep the later Post-fit planning or dispatch request separate;
that request must not inherit artifact-registration authorization.
