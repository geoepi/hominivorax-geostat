#!/usr/bin/env bash
# Atlas Phase 3 rasterization wrapper using the recovered Phase 2 runtime.
#
# The successful Phase 2 projection job used this exact module sequence.  Keep
# the environment self-contained here; do not rely on a login-shell module
# state or install packages into the project environment.
#SBATCH --job-name=phase3-rasterization
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/project/disease_ecology/nws-geostat-output/joint_inla_fit/phase3-rasterization-%j.out
#SBATCH --error=/project/disease_ecology/nws-geostat-output/joint_inla_fit/phase3-rasterization-%j.err

set -euo pipefail

module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 intel-oneapi-mkl/2023.2.0 r/4.4.3

PROJECT_ROOT=/project/disease_ecology/hominivorax-geostat
RUN_ID="${PHASE3_RUN_ID:-20725437}"
PHASE2_OUTPUT="${PHASE3_PHASE2_OUTPUT:-/project/disease_ecology/nws-geostat-output/joint_inla_fit/prediction_projection_${RUN_ID}}"
STAGE2_ARTIFACT="${PHASE3_STAGE2_ARTIFACT:-/project/disease_ecology/nws-geostat-output/joint_model/joint_model_inputs.rds}"
OUTPUT_DIR="${PHASE3_OUTPUT_DIR:-/project/disease_ecology/nws-geostat-output/joint_inla_fit/raster_surfaces_${RUN_ID}}"

cd "${PROJECT_ROOT}"

echo "Phase 3 Atlas job: ${SLURM_JOB_ID:-not-under-slurm}"
echo "Phase 3 hostname: $(hostname)"
echo "Phase 3 git SHA: $(git rev-parse HEAD)"
echo "Phase 3 start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
module list 2>&1
which R
R --version | head -2
Rscript --vanilla -e 'cat("R=", R.version.string, "\n", sep = ""); for (p in c("INLA", "terra", "sf", "Matrix")) cat(p, "=", if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "unavailable", "\n", sep = ""); if (requireNamespace("sf", quietly = TRUE)) print(sf::sf_extSoftVersion())'

R_ARGS=(
  --phase2-output "${PHASE2_OUTPUT}"
  --stage2-artifact "${STAGE2_ARTIFACT}"
  --output "${OUTPUT_DIR}"
  --run-id "${RUN_ID}"
)
if [[ -n "${PHASE3_TEMPLATE:-}" ]]; then R_ARGS+=(--template "${PHASE3_TEMPLATE}"); fi
if [[ -n "${PHASE3_SOURCE_COMMIT:-}" ]]; then R_ARGS+=(--source-phase2-commit "${PHASE3_SOURCE_COMMIT}"); fi

Rscript --vanilla scripts/run_joint_inla_rasterization.R "${R_ARGS[@]}"

echo "Phase 3 end: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
