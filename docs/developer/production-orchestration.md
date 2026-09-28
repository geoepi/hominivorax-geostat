# Production orchestration

The production entry point is:

    ./scripts/submit_full_pipeline.sh --config config/production.yml

The command creates one run directory and submits three dependent SLURM jobs:

    Prepare (Stage 1 -> Stage 2 -> Stage 3A -> pre-fit gate)
      afterok -> Fit (Stage 3B -> fit-health gate)
                    afterok -> Post-fit (extraction -> validation -> projection
                                    -> rasterization -> structural products
                                    -> 14.5 C mask -> dynamic RPI -> reporting)

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

