#!/usr/bin/env bash
# Atlas wrapper for the reporting-only reference run.
#
# This wrapper establishes the validated compute-node runtime explicitly. It
# does not install packages, refit the model, or modify Phase 1--3 artifacts.
# Use an interactive allocation for spatial smoke tests before submitting this
# wrapper as a production job; see docs/atlas-environment.md.
#SBATCH --job-name=postfit-reporting
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=postfit-reporting-%x-%j.out
#SBATCH --error=postfit-reporting-%x-%j.err

set -euo pipefail

module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${POSTFIT_REPORTING_PROJECT_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
RUN_ID="${POSTFIT_REPORTING_RUN_ID:?Set POSTFIT_REPORTING_RUN_ID to the immutable run identifier}"
OUTPUT_ROOT="${POSTFIT_REPORTING_OUTPUT_ROOT:?Set POSTFIT_REPORTING_OUTPUT_ROOT to the private output directory}"
FIT_PATH="${POSTFIT_REPORTING_FIT:?Set POSTFIT_REPORTING_FIT to the private Stage 3B fit}"
BUILD_PATH="${POSTFIT_REPORTING_BUILD:?Set POSTFIT_REPORTING_BUILD to the private Stage 3A build}"
STAGE2_PATH="${POSTFIT_REPORTING_STAGE2:?Set POSTFIT_REPORTING_STAGE2 to the private Stage 2 artifact}"
PHASE2_ROOT="${POSTFIT_REPORTING_PHASE2:?Set POSTFIT_REPORTING_PHASE2 to the private Phase 2 directory}"
PHASE3_ROOT="${POSTFIT_REPORTING_PHASE3:?Set POSTFIT_REPORTING_PHASE3 to the private Phase 3 directory}"
OBSERVATION_INPUT="${POSTFIT_REPORTING_OBSERVATION_INPUT:?Set POSTFIT_REPORTING_OBSERVATION_INPUT to the private observation CSV}"
HOST_COLUMN="${POSTFIT_REPORTING_HOST_COLUMN:-host}"
CATTLE_UNITS="${POSTFIT_REPORTING_CATTLE_UNITS:-}"
MAPPING_VERSION="${POSTFIT_REPORTING_MAPPING_VERSION:-historical-host-normalization-v2}"

cd "${PROJECT_ROOT}"

echo "Post-fit reporting Atlas job: ${SLURM_JOB_ID:-not-under-slurm}"
echo "Post-fit reporting hostname: $(hostname)"
echo "Post-fit reporting git SHA: $(git rev-parse HEAD)"
echo "Post-fit reporting start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Post-fit reporting module list:"
module list 2>&1 | cat
echo "Post-fit reporting R executable:"
which R
R --version | head -2
Rscript --vanilla -e 'cat("R=", R.version.string, "\n", sep = ""); cat("libPaths=\n"); print(.libPaths()); for (p in c("INLA", "Matrix", "terra", "sf")) cat(p, "=", if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "unavailable", "\n", sep = ""); if (requireNamespace("sf", quietly = TRUE)) print(sf::sf_extSoftVersion()); if (requireNamespace("terra", quietly = TRUE)) print(terra::gdal())'

R_ARGS=(
  --run-id "${RUN_ID}"
  --output-root "${OUTPUT_ROOT}"
  --fit "${FIT_PATH}"
  --build "${BUILD_PATH}"
  --stage2 "${STAGE2_PATH}"
  --phase2 "${PHASE2_ROOT}"
  --phase3-root "${PHASE3_ROOT}"
  --observation-input "${OBSERVATION_INPUT}"
  --host-column "${HOST_COLUMN}"
  --mapping-version "${MAPPING_VERSION}"
)
if [[ -n "${CATTLE_UNITS}" ]]; then R_ARGS+=(--cattle-units "${CATTLE_UNITS}"); fi
if [[ -n "${POSTFIT_REPORTING_BOUNDARY:-}" ]]; then R_ARGS+=(--boundary "${POSTFIT_REPORTING_BOUNDARY}"); fi
if [[ -n "${POSTFIT_REPORTING_CELL_AREA_TEMPLATE:-}" ]]; then R_ARGS+=(--cell-area-template "${POSTFIT_REPORTING_CELL_AREA_TEMPLATE}"); fi
if [[ -n "${POSTFIT_REPORTING_CELL_AREA:-}" ]]; then R_ARGS+=(--cell-area "${POSTFIT_REPORTING_CELL_AREA}"); fi
if [[ -n "${POSTFIT_REPORTING_CELL_AREA_UNITS:-}" ]]; then R_ARGS+=(--cell-area-units "${POSTFIT_REPORTING_CELL_AREA_UNITS}"); fi
if [[ -n "${POSTFIT_REPORTING_OBSERVATIONS:-}" ]]; then R_ARGS+=(--observations "${POSTFIT_REPORTING_OBSERVATIONS}"); fi
if [[ -n "${POSTFIT_REPORTING_RPI_OBSERVATIONS:-}" ]]; then R_ARGS+=(--rpi-observations "${POSTFIT_REPORTING_RPI_OBSERVATIONS}"); fi
if [[ "${POSTFIT_REPORTING_NO_RPI:-0}" == "1" ]]; then R_ARGS+=(--no-rpi); fi
if [[ "${POSTFIT_REPORTING_OVERWRITE:-0}" == "1" ]]; then R_ARGS+=(--overwrite); fi

Rscript --vanilla scripts/run_postfit_reporting.R "${R_ARGS[@]}"
echo "Post-fit reporting end: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
