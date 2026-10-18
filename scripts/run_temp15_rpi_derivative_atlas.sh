#!/usr/bin/env bash
# One-shot post-fit 15.0 C derivative. Consumes accepted products only.
#SBATCH --job-name=geostat-temp15-rpi
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=08:00:00
#SBATCH --output=temp15-rpi-%j.out
#SBATCH --error=temp15-rpi-%j.err
set -euo pipefail
module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 intel-oneapi-mkl/2023.2.0 r/4.4.3
SCRIPT_DIR="/project/disease_ecology/worktrees/hominivorax-geostat-temp15-rpi/scripts"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-/project/disease_ecology/worktrees/hominivorax-geostat-temp15-rpi}"
: "${TEMP15_SOURCE_ROOT:?Set TEMP15_SOURCE_ROOT}"
: "${TEMP15_STAGE2:?Set TEMP15_STAGE2}"
: "${TEMP15_OBSERVATIONS:?Set TEMP15_OBSERVATIONS}"
: "${TEMP15_OUTPUT_ROOT:?Set TEMP15_OUTPUT_ROOT}"
: "${TEMP15_RUN_ID:?Set TEMP15_RUN_ID}"
cd "${PROJECT_ROOT}"
test -f "${SCRIPT_DIR}/run_temp15_rpi_derivative.R"
echo "temp15 derivative job ${SLURM_JOB_ID:-not-under-slurm}; git $(git rev-parse HEAD); start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
Rscript --vanilla scripts/run_temp15_rpi_derivative.R \
  --run-id "${TEMP15_RUN_ID}" \
  --source-root "${TEMP15_SOURCE_ROOT}" \
  --stage2 "${TEMP15_STAGE2}" \
  --observations "${TEMP15_OBSERVATIONS}" \
  --output-root "${TEMP15_OUTPUT_ROOT}" \
  --temperature-threshold 15.0 \
  --source-threshold 14.5 \
  --overwrite
echo "temp15 derivative end $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
