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
| Production outputs | `/project/disease_ecology/nws-geostat-output/production_runs` |

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

## Optional CHIME execution correlation

An external orchestrator such as CHIME may set `CHIME_EXECUTION_ID` before
starting or resuming a run. Geostat records the trimmed, opaque value as
`chime_execution_id` in the run manifest and, after successful Post-fit, in the
production summary. The value has no scientific meaning and is not required
for standalone execution. A resume that supplies a different value from the
one already recorded in the manifest is rejected before resumed execution;
an uncorrelated existing run may be bound to a supplied value through the
normal resume path.
