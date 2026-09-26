#!/usr/bin/env bash
# Supervised, one-shot post-fit acceptance pipeline.
# This wrapper intentionally does not submit a watcher or scheduler dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FIT_JOB_ID=""
STAGE2=""
BUILD=""
FIT=""
HOLDOUT=""
RUN_ID=""
OUTPUT_ROOT=""
TEMPLATE=""
SOURCE_PHASE2_COMMIT=""
ALLOW_UNSEEN_ADMIN_ZERO=0
OVERWRITE=0

usage() {
  cat <<'USAGE'
Usage: run_postfit_acceptance_atlas.sh \
  --fit-job-id JOBID --stage2 PATH --build PATH --fit PATH --holdout PATH \
  --run-id ID --output-root PATH [--template PATH] \
  [--source-phase2-commit COMMIT] [--allow-unseen-admin-zero] [--overwrite]

The pipeline is a one-shot post-fit run. It does not create a watcher or a
SLURM dependency and it refuses non-empty output roots unless --overwrite is
explicitly supplied.
USAGE
}

while (($#)); do
  case "$1" in
    --fit-job-id) FIT_JOB_ID="$2"; shift 2 ;;
    --stage2) STAGE2="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --fit) FIT="$2"; shift 2 ;;
    --holdout) HOLDOUT="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --output-root) OUTPUT_ROOT="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --source-phase2-commit) SOURCE_PHASE2_COMMIT="$2"; shift 2 ;;
    --allow-unseen-admin-zero) ALLOW_UNSEEN_ADMIN_ZERO=1; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for required in FIT_JOB_ID STAGE2 BUILD FIT HOLDOUT RUN_ID OUTPUT_ROOT; do
  if [[ -z "${!required}" ]]; then echo "Missing required argument for ${required}" >&2; usage >&2; exit 2; fi
done

case "$RUN_ID" in *[!A-Za-z0-9_.-]*) echo "RUN_ID contains unsupported characters" >&2; exit 2 ;; esac

# The production runtime is part of the provenance contract. Do not rely on
# the caller's login-shell module state.
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 intel-oneapi-mkl/2023.2.0 r/4.4.3

echo "Post-fit acceptance start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
hostname
module list
which R
R --version
Rscript --vanilla -e 'cat("R:", R.version.string, "\n"); print(.libPaths()); for (p in c("INLA", "Matrix", "terra", "sf")) { if (requireNamespace(p, quietly=TRUE)) cat(p, as.character(packageVersion(p)), find.package(p), "\n") else cat(p, "not available\n") }'

if [[ -e "$OUTPUT_ROOT" && -n "$(find "$OUTPUT_ROOT" -mindepth 1 -print -quit 2>/dev/null)" && "$OVERWRITE" -ne 1 ]]; then
  echo "Refusing non-empty output root without --overwrite: $OUTPUT_ROOT" >&2
  exit 1
fi
mkdir -p "$OUTPUT_ROOT"

echo "Gate 0: scheduler completion for job ${FIT_JOB_ID}"
SACCT_ROW="$(sacct -X -j "$FIT_JOB_ID" --format=JobIDRaw,State,ExitCode --noheader --parsable2 | awk -F'|' -v id="$FIT_JOB_ID" '$1 == id {print; exit}')"
if [[ -z "$SACCT_ROW" ]]; then
  echo "Gate 0 FAIL: no exact sacct record for job ${FIT_JOB_ID}" >&2
  exit 1
fi
IFS='|' read -r SACCT_ID SACCT_STATE SACCT_EXIT <<< "$SACCT_ROW"
echo "${SACCT_ID}|${SACCT_STATE}|${SACCT_EXIT}"
if [[ "$SACCT_STATE" != "COMPLETED" || "$SACCT_EXIT" != "0:0" ]]; then
  echo "Gate 0 FAIL: fit job did not complete successfully" >&2
  exit 1
fi

if [[ ! -s "$FIT" ]]; then echo "Gate 0 FAIL: fit artifact missing or empty: $FIT" >&2; exit 1; fi

FIT_HEALTH_DIR="$OUTPUT_ROOT/fit_health"
EXTRACTION_DIR="$OUTPUT_ROOT/extraction"
VALIDATION_PARENT="$OUTPUT_ROOT/validation"
PROJECTION_DIR="$OUTPUT_ROOT/projection"
RASTER_DIR="$OUTPUT_ROOT/raster_surfaces"
ACCEPTANCE_DIR="$OUTPUT_ROOT/acceptance"
OVERWRITE_ARG=()
if [[ "$OVERWRITE" -eq 1 ]]; then OVERWRITE_ARG=(--overwrite); fi

echo "Gate 1: structural fit health"
Rscript --vanilla "$SCRIPT_DIR/check_joint_inla_fit_health.R" \
  --repo-root="$REPO_ROOT" --fit="$FIT" --build="$BUILD" --stage2="$STAGE2" \
  --output-dir="$FIT_HEALTH_DIR" --run-id="$RUN_ID" "${OVERWRITE_ARG[@]}"

echo "Gate 2: fail-closed extraction"
Rscript --vanilla "$SCRIPT_DIR/extract_joint_inla_results.R" \
  --repo-root="$REPO_ROOT" --build="$BUILD" --fit="$FIT" --stage2="$STAGE2" \
  --output-dir="$EXTRACTION_DIR" --run-id="$RUN_ID" "${OVERWRITE_ARG[@]}"
if [[ ! -s "$HOLDOUT" ]]; then
  echo "Gate 2 FAIL: explicit holdout input is missing or empty: $HOLDOUT" >&2
  exit 1
fi

echo "Phase 1: new-production validation"
VALIDATION_ARGS=(
  --repo-root="$REPO_ROOT" --acceptance-mode=production --build="$BUILD" --fit="$FIT"
  --holdout="$HOLDOUT" --stage2="$STAGE2" --output-dir="$VALIDATION_PARENT" --run-id="$RUN_ID"
  --source-fit-job="$FIT_JOB_ID"
)
if [[ "$OVERWRITE" -eq 1 ]]; then VALIDATION_ARGS+=(--overwrite); fi
Rscript --vanilla "$SCRIPT_DIR/run_joint_inla_validation.R" "${VALIDATION_ARGS[@]}"

echo "Phase 2: reconstruction and dense-grid projection"
PROJECTION_ARGS=(
  --repo-root="$REPO_ROOT" --build="$BUILD" --fit="$FIT" --stage2="$STAGE2"
  --run-id="$RUN_ID" --output-dir="$PROJECTION_DIR"
)
if [[ "$ALLOW_UNSEEN_ADMIN_ZERO" -eq 1 ]]; then PROJECTION_ARGS+=(--allow-unseen-admin-zero); fi
if [[ "$OVERWRITE" -eq 1 ]]; then PROJECTION_ARGS+=(--overwrite); fi
Rscript --vanilla "$SCRIPT_DIR/run_joint_inla_projection.R" "${PROJECTION_ARGS[@]}"

PHASE2_METADATA="$PROJECTION_DIR/prediction_projection_metadata_${RUN_ID}.rds"
Rscript --vanilla -e 'p <- commandArgs(TRUE); m <- readRDS(p[[1L]]); if (!identical(as.character(m$run_id), as.character(p[[2L]]))) stop("Phase 2 metadata run_id mismatch."); cat("Phase 2 metadata run_id:", m$run_id, "\n")' "$PHASE2_METADATA" "$RUN_ID"

echo "Phase 3: rasterization and surface QA"
RASTER_ARGS=(
  --repo-root="$REPO_ROOT" --phase2-output="$PROJECTION_DIR" --stage2-artifact="$STAGE2"
  --output="$RASTER_DIR" --run-id="$RUN_ID" --no-diagnostics
)
if [[ -n "$TEMPLATE" ]]; then RASTER_ARGS+=(--template="$TEMPLATE"); fi
if [[ -n "$SOURCE_PHASE2_COMMIT" ]]; then RASTER_ARGS+=(--source-phase2-commit="$SOURCE_PHASE2_COMMIT"); fi
if [[ "$OVERWRITE" -eq 1 ]]; then RASTER_ARGS+=(--overwrite); fi
Rscript --vanilla "$SCRIPT_DIR/run_joint_inla_rasterization.R" "${RASTER_ARGS[@]}"

echo "Final acceptance summary"
mkdir -p "$ACCEPTANCE_DIR"
SUMMARY_ARGS=(
  --repo-root="$REPO_ROOT" --fit-job-id="$FIT_JOB_ID" --run-id="$RUN_ID"
  --output-root="$OUTPUT_ROOT" --fit="$FIT" --build="$BUILD" --stage2="$STAGE2" --holdout="$HOLDOUT"
)
Rscript --vanilla "$SCRIPT_DIR/write_postfit_acceptance_summary.R" "${SUMMARY_ARGS[@]}"
echo "Post-fit acceptance complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
