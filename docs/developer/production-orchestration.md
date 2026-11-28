# Production orchestration

The production entry point is:

    ./scripts/submit_full_pipeline.sh --config config/production.yml

The command creates one run directory and submits three dependent SLURM jobs:

    Prepare (Stage 1 -> Stage 2 -> Stage 3A -> pre-fit gate)
      afterok -> Fit (Stage 3B -> fit-health gate)
                    afterok -> Post-fit (extraction -> validation -> projection
                                    -> rasterization -> structural products
                                    -> 16.0 C mask -> dynamic RPI -> reporting)

The fit profile is 12 CPUs, 280 GB, and 36 hours. Prepare and Post-fit use
smaller configurable profiles. Scheduler IDs are recorded in
metadata/run_manifest.yml.

## Runtime contracts

The orchestrator reads the authoritative observation CSV by reference, records
its SHA-256, and derives the final modeled epiweek from the last complete week
represented by current observations. It records the raw maximum date, resolved
week, observations after that endpoint, modeled weeks, temporal group counts,
supported cells, and expected prediction rows.

Stage 2 and Stage 3A artifacts are authoritative for downstream dimensions.
The production config stores rules only: it contains no week counts, group
counts, supported-cell counts, job IDs, output paths, or numeric RPI threshold.
The RPI config stores the calibration quantile (0.10); the computed threshold
is written to run metadata and final reporting outputs.

## Run and resume controls

    ./scripts/submit_full_pipeline.sh --config config/production.yml --dry-run
    ./scripts/submit_full_pipeline.sh --config config/production.yml --through prepare
    ./scripts/submit_full_pipeline.sh --config config/production.yml --from postfit --resume RUN_ID

Resume reads stage statuses and the run manifest, skips accepted stages, and
resumes at the first incomplete stage. Direct development execution uses the
same contract:

    Rscript scripts/run_pipeline.R --mode direct --config config/production.yml --through prepare

## Data residency and artifacts

The authoritative observation file is never copied, archived, bundled, or
rsynced into a run directory. Generated stage configs contain paths and rules,
not source rows. Existing Stage 1/2 model-ready representations remain intact
for backward compatibility; their future minimization is tracked separately.

Each major stage writes metadata/status_<stage>.yml. The run manifest is the
primary provenance entry point and records source/config hashes, dynamic
dimensions, scheduler IDs, artifact paths, and final status.

## Versioned refresh operations

The optional `--refresh-request PATH` argument adds a schema-versioned request
contract without replacing this Prepare → Fit → Post-fit scheduler pipeline.
It supports three operation modes:

- `full` requests Prepare, Fit, and Post-fit in canonical order.
- `resume` binds a compatible existing run ID and run-manifest SHA-256; accepted
  stages are reused only after their inputs and outputs are rehashed.
- `adopt` validates a separately completed fit, imports it as historical
  provenance, and plans Post-fit with no dependency on the historical Slurm
  job ID. Prepare and Fit are prohibited for this mode.

Run planning with `--mode dry-run`. For an adoption request, the dry-run
prints the source artifacts and checksums, deployment-configuration
compatibility, intended stable registry destination, and Post-fit output root.
It submits no jobs, registers no artifacts, and writes no production run
directory. A blocked provenance check yields no Post-fit job. The request
document is archived by hash with an actual run; the request is rehashed before
dispatch. See [refresh and release framework](refresh-release-framework.md)
for the request schema, adoption rules, and release controls.

The `scripts/manage_model_release_atlas.sh` interface exposes read-only
`reconcile` and `verify-active` actions, plus separately invoked `activate` and
`rollback` actions. Activation is independent of Git merge and scheduler
completion. It requires a complete, checksummed release manifest, an existing
active-state pointer, and caller-supplied compare-and-swap generation and
state SHA-256. No active-state pointer is bootstrapped from the current config
alone because the current W39 fit identity has not been established.

## Canonical storage and release operations

Production execution directories remain under
`/project/disease_ecology/nws-geostat-output/production_runs`; accepted
reporting packages remain under its sibling
`/project/disease_ecology/nws-geostat-output/postfit_acceptance`. The registry
is `production_runs/model_registry`. Applications should follow a validated
release manifest and its product manifest, not a worktree name or Slurm job
ID. Existing run and CHIME package naming conventions remain in place.

An accepted package can be recorded in a new immutable release manifest after
its acceptance summary, source run, historical Fit job, and product manifest
pass validation:

```bash
./scripts/manage_model_release_atlas.sh \
  --action register-accepted-package \
  --release-manifest /project/disease_ecology/nws-geostat-output/production_runs/<run-id>/model-release.yml \
  --accepted-package /project/disease_ecology/nws-geostat-output/postfit_acceptance/<package> \
  --acceptance-summary /project/disease_ecology/nws-geostat-output/postfit_acceptance/<package>/<summary.yml> \
  --product-manifest /project/disease_ecology/nws-geostat-output/postfit_acceptance/<package>/<manifest.csv>
```

The command writes `model-release-accepted.yml` beside the run manifest. It
does not activate the release or change the active pointer.

Cleanup review is metadata-only. The input CSV must include `path`,
`classification`, `bytes`, `owner`, `known_source_references`,
`downstream_consumers`, `retention_start_date`,
`subsequent_qualified_refreshes`, `active_job_references`,
`replacement_path`, `replacement_sha256`, `replacement_verified`,
`scientific_preservation_required`, and `duplicate_finding` columns:

```bash
./scripts/manage_model_release_atlas.sh \
  --action cleanup-report \
  --candidate-inventory /path/to/reviewed-candidates.csv \
  --report-output /path/to/cleanup-eligibility.csv \
  --as-of 2026-11-27
```

Eligibility requires both 90 days and two subsequent qualified refreshes, plus
resolved references, a verified replacement, and no scientific preservation
or duplicate-finding blocker. The report records estimated recoverable bytes
and required owner/governance approval. There is no deletion action.
