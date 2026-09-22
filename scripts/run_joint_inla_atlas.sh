#!/usr/bin/env bash
# Initial Atlas allocation; revise near the top after reviewing the first sacct profile.
#SBATCH --job-name=hominivorax-stage3b
#SBATCH --cpus-per-task=12
#SBATCH --mem=280G
#SBATCH --time=12:00:00
#SBATCH --output=/project/disease_ecology/nws-geostat-output/joint_inla_fit/slurm-%x-%j.out
#SBATCH --error=/project/disease_ecology/nws-geostat-output/joint_inla_fit/slurm-%x-%j.err

set -euo pipefail

PROJECT_ROOT=/project/disease_ecology/hominivorax-geostat
CONFIG_PATH=/project/disease_ecology/nws-geostat-output/config/joint_inla_fit.atlas.default.yml
OUTPUT_ROOT=/project/disease_ecology/nws-geostat-output/joint_inla_fit
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"

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

"${RSCRIPT_BIN}" --version
"${RSCRIPT_BIN}" -e 'cat(R.version.string, "\n"); cat("INLA=", if (requireNamespace("INLA", quietly = TRUE)) as.character(utils::packageVersion("INLA")) else "unavailable", "\n", sep = "")'

# The runner performs production preflight and then Stage 3B. Existing outputs are never replaced by this wrapper.
"${RSCRIPT_BIN}" "${PROJECT_ROOT}/scripts/run_joint_inla.R" \
  --config "${CONFIG_PATH}" \
  --output "${OUTPUT_ROOT}"
