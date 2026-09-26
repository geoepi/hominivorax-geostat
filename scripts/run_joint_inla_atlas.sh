#!/usr/bin/env bash
# Atlas allocation; revise near the top after reviewing each sacct profile.
#SBATCH --job-name=hominivorax-stage3b
#SBATCH --account=disease_ecology
#SBATCH --cpus-per-task=12
#SBATCH --mem=280G
#SBATCH --time=36:00:00
#SBATCH --output=/project/disease_ecology/nws-geostat-output/joint_inla_fit/slurm-%x-%j.out
#SBATCH --error=/project/disease_ecology/nws-geostat-output/joint_inla_fit/slurm-%x-%j.err

set -euo pipefail

PROJECT_ROOT=/project/disease_ecology/hominivorax-geostat
CONFIG_PATH="${STAGE3B_CONFIG_PATH:-/project/disease_ecology/nws-geostat-output/config/joint_inla_fit.atlas.default.yml}"
OUTPUT_ROOT="${STAGE3B_OUTPUT_ROOT:-/project/disease_ecology/nws-geostat-output/joint_inla_fit}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"

module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 \
  intel-oneapi-mkl/2023.2.0 r/4.4.3

mkdir -p "${OUTPUT_ROOT}"
cd "${PROJECT_ROOT}"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-12}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK:-12}"

START_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
JOB_ID="${SLURM_JOB_ID:-not-under-slurm}"
HOSTNAME_VALUE="$(hostname)"
GIT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse HEAD)"

trap 'status=$?; echo "Stage 3B end: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=${status}"; exit "${status}"' EXIT

echo "Stage 3B Atlas job: ${JOB_ID}"
echo "Stage 3B hostname: ${HOSTNAME_VALUE}"
echo "Stage 3B git SHA: ${GIT_SHA}"
echo "Stage 3B start: ${START_TIMESTAMP}"
echo "OMP_NUM_THREADS=${OMP_NUM_THREADS}"
echo "OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS}"
echo "Stage 3B config: ${CONFIG_PATH}"
echo "Stage 3B output root: ${OUTPUT_ROOT}"
echo "Stage 3B module list:"
module list 2>&1 || true
echo "Stage 3B R executable:"
which R

"${RSCRIPT_BIN}" --version
"${RSCRIPT_BIN}" -e 'cat("R=", R.version.string, "\n", sep = ""); cat("libPaths=\n"); print(.libPaths()); for (p in c("INLA", "Matrix", "terra", "sf")) cat(p, "=", if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "unavailable", "\n", sep = "")'

# The runner performs production preflight and then Stage 3B. Existing outputs are never replaced by this wrapper.
"${RSCRIPT_BIN}" "${PROJECT_ROOT}/scripts/run_joint_inla.R" \
  --config "${CONFIG_PATH}" \
  --output "${OUTPUT_ROOT}"
