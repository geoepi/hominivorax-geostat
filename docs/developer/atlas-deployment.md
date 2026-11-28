# Atlas deployment

This guide records the canonical Atlas production topology and the commands
used by operators. It complements the private Atlas operator record at
`/project/disease_ecology/hominivorax-geostat-config/README-ATLAS.md`.

## Canonical paths

| Purpose | Canonical path |
| --- | --- |
| Code checkout | `/project/disease_ecology/hominivorax-geostat` |
| Secure configuration root | `/project/disease_ecology/hominivorax-geostat-config` |
| Production configuration | `/project/disease_ecology/hominivorax-geostat-config/production.yml` |
| Production execution history | `/project/disease_ecology/nws-geostat-output/production_runs` |
| Accepted product packages | `/project/disease_ecology/nws-geostat-output/postfit_acceptance` |
| Model artifact registry | `/project/disease_ecology/nws-geostat-output/production_runs/model_registry` |
| Reporting application source | `/project/disease_ecology/hominivorax-geostat-reporting` |
| Development worktrees | `/project/disease_ecology/worktrees` |

The production configuration is intentionally outside Git. It contains
governed input and stage-configuration paths and must not be copied into the
repository or committed. The tracked `config/production.example.yml` remains
the portable template for local or other governed environments.

## Operator commands

The production entry point self-bootstraps the validated Atlas runtime profile
`atlas-r44-spatial-v1`. The profile loads the UDUNITS, PROJ, GEOS, GDAL, MKL,
and R 4.4.3 modules and runs a bounded `units`/`sf`/`terra` preflight before
the production contract is created. Operators do not need to rely on an
interactive shell's module environment.

Manual or direct development execution still requires the validated runtime to
be loaded explicitly:

```bash
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3
```

Normal production submission:

```bash
cd /project/disease_ecology/hominivorax-geostat
./scripts/submit_full_pipeline.sh \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml
```

The same wrapper is used by every submitted Prepare, Fit, and Post-fit job, so
each allocation initializes and validates the runtime independently. If the
preflight fails, no production run directory or Slurm stage jobs are created.

Submission dry-run (no scheduler jobs are submitted):

```bash
cd /project/disease_ecology/hominivorax-geostat
./scripts/submit_full_pipeline.sh \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --dry-run
```

Resume an existing run using its run ID:

```bash
cd /project/disease_ecology/hominivorax-geostat
./scripts/submit_full_pipeline.sh \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --resume <run_id>
```

The run-specific manifest and stage status files are under
`<production_output_root>/<run_id>/metadata/`. Stage and scheduler logs are
under that run's `logs/` directory. The private configuration root also holds
the operator deployment manifest and historical audit records; accepted or
failed historical audits must not be rewritten to remove their original
provenance.

Run manifests record the runtime platform, stable module profile, requested
module set, resolved R version, and preflight status. The scheduler dependency
chain and stage resources are unchanged.

Historical or development worktrees, including paths with a suffix such as
`-prefit-20260926`, are not production checkouts. Use the canonical path above
for new runs and for resuming existing runs.

## Refresh requests and release controls

The versioned request is passed with `--refresh-request`; it does not replace
the secure configuration. Use a `candidate_execution` configuration for an
approved full or resumed run. An adoption dry-run may use the active secure
configuration with `dispatch_authorized: false` to compare the candidate with
the observed deployment.

```bash
cd /project/disease_ecology/hominivorax-geostat
./scripts/run_pipeline_atlas.sh \
  --mode dry-run \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --refresh-request docs/archive/original-refresh-w44-2026/original_refresh_w44_2026_refresh_request.yml
```

For an explicitly reviewed adoption request using a candidate execution
configuration, submit through the existing pipeline wrapper. It registers a
one-time, checksum-verified version under
`/project/disease_ecology/nws-geostat-output/production_runs/model_registry/`
before submitting Post-fit. The staging directory and final registry share a
filesystem, publication refuses to overwrite a version, and source files
remain unchanged. The W44 source is a development output tree, so its fit and
upstream stages must be copied once for stable production retention; no copy
or job is performed by the current planning-only W44 request. The copy is
limited to the inventoried artifacts and supporting records for that version.

Reconcile the observed production config and deployment record without
changing them:

```bash
./scripts/manage_model_release_atlas.sh \
  --action reconcile \
  --config /project/disease_ecology/hominivorax-geostat-config/production.yml \
  --deployment-manifest /project/disease_ecology/hominivorax-geostat-config/deployment-manifest.yml \
  --repo-root /project/disease_ecology/hominivorax-geostat
```

Verify the active release with:

```bash
./scripts/manage_model_release_atlas.sh \
  --action verify-active \
  --active-state /project/disease_ecology/hominivorax-geostat-config/active-release.yml
```

The active-state file is intentionally not initialized from the current W39
configuration: the previous active fit identity is not yet known. Therefore,
the verifier reports an absent pointer until that identity is reconciled and
an authorized initial state is supplied. Activation and rollback use explicit
compare-and-swap values and append-only events; details are in the
[refresh and release framework guide](refresh-release-framework.md).

## Optional CHIME execution correlation

An external orchestrator such as CHIME may set `CHIME_EXECUTION_ID` before
starting or resuming a run. Geostat records the trimmed, opaque value as
`chime_execution_id` in the run manifest and, after successful Post-fit, in the
production summary. The value has no scientific meaning and is not required
for standalone execution. A resume that supplies a different value from the
one already recorded in the manifest is rejected before resumed execution;
an uncorrelated existing run may be bound to a supplied value through the
normal resume path.

## Directory and release discovery contract

Execution history, accepted products, and reporting application source have
separate roles. Keep accepted packages under the existing
`postfit_acceptance` root. Keep the reporting Git checkout as source code;
do not use it as a product store or create another project-root reporting
directory. The model registry is beneath `production_runs`. Release records
use regular manifest paths and checksums; this contract does not use symlinks
or directory swaps.

A read-only active-release lookup returns the verified active manifest path and
SHA-256:

```bash
./scripts/manage_model_release_atlas.sh \
  --action discover-active \
  --active-state /project/disease_ecology/hominivorax-geostat-config/active-release.yml
```

This command reports an absent pointer when none exists. It does not initialize
one from the current W39 configuration. The accepted package is separately
identified by the release manifest under `postfit_acceptance`.
