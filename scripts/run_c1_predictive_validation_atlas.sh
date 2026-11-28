#!/usr/bin/env bash
# C-1 reporting-only predictive validation. Consumes the completed fit and
# existing Stage 2/3A/holdout artifacts; this wrapper never runs a fit.
#SBATCH --job-name=c1-predictive-validation
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-c1-predictive-validation-%j.out
#SBATCH --error=slurm-c1-predictive-validation-%j.err

set -euo pipefail

PROJECT_ROOT="${C1_PREDICTIVE_REPO_ROOT:?Set C1_PREDICTIVE_REPO_ROOT to the synchronized private Atlas checkout}"
OUTPUT_ROOT="${C1_PREDICTIVE_OUTPUT_ROOT:?Set C1_PREDICTIVE_OUTPUT_ROOT to a new isolated Configuration C-1 output directory}"
BUILD_PATH="${C1_PREDICTIVE_BUILD:?Set C1_PREDICTIVE_BUILD to the completed Stage 3A build}"
FIT_PATH="${C1_PREDICTIVE_FIT:?Set C1_PREDICTIVE_FIT to the completed C-1 Stage 3B fit}"
HOLDOUT_PATH="${C1_PREDICTIVE_HOLDOUT:?Set C1_PREDICTIVE_HOLDOUT to the saved extracted holdout CSV}"
STAGE2_PATH="${C1_PREDICTIVE_STAGE2:?Set C1_PREDICTIVE_STAGE2 to the validated Stage 2 artifact}"
RUN_ID="${C1_PREDICTIVE_RUN_ID:?Set C1_PREDICTIVE_RUN_ID to a unique immutable run identifier}"
SOURCE_FIT_JOB="${C1_PREDICTIVE_SOURCE_FIT_JOB:?Set C1_PREDICTIVE_SOURCE_FIT_JOB to the completed Stage 3B Slurm job ID}"

cd "${PROJECT_ROOT}"
source "${PROJECT_ROOT}/scripts/atlas_runtime.sh"
atlas_runtime_load

echo "C-1 predictive validation job: ${SLURM_JOB_ID:-not-under-Slurm}"
echo "C-1 predictive validation host: $(hostname)"
echo "C-1 predictive validation git SHA: $(git rev-parse HEAD)"
echo "C-1 predictive validation start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
module list 2>&1 | cat
Rscript --version

Rscript --vanilla scripts/run_joint_inla_validation.R \
  --repo-root="${PROJECT_ROOT}" \
  --acceptance-mode=production \
  --qualification-mode=configuration-c1 \
  --qualification-protocol="${PROJECT_ROOT}/docs/validation/configuration-c1-predictive-qualification-protocol-2026-11-23.md" \
  --build="${BUILD_PATH}" \
  --fit="${FIT_PATH}" \
  --holdout="${HOLDOUT_PATH}" \
  --stage2="${STAGE2_PATH}" \
  --output-dir="${OUTPUT_ROOT}" \
  --run-id="${RUN_ID}" \
  --source-fit-job="${SOURCE_FIT_JOB}"

echo "C-1 predictive validation end: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
