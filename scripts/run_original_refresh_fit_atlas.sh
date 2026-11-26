#!/usr/bin/env bash
# Controlled single Stage 3B fit for ORIGINAL_REFRESH_W44_2026.
#SBATCH --job-name=original-refresh-fit
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=12
#SBATCH --mem=280G
#SBATCH --time=48:00:00
#SBATCH --output=original-refresh-fit-%j.out
#SBATCH --error=original-refresh-fit-%j.err

set -euo pipefail

PROJECT_ROOT=$(printenv ORIGINAL_REFRESH_REPO_ROOT 2>/dev/null || true)
if [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT=$SLURM_SUBMIT_DIR; fi
if [[ -z "$PROJECT_ROOT" ]]; then echo "Set ORIGINAL_REFRESH_REPO_ROOT or submit from the development checkout." >&2; exit 2; fi
RUN_ROOT="$PROJECT_ROOT/outputs/original_refresh_w44_2026"
FIT_CONFIG="$PROJECT_ROOT/config/original_refresh_w44_2026/joint_inla_fit.yml"
FIT_PATH="$RUN_ROOT/stage3b/joint_model_fit.rds"
HEALTH_ROOT="$RUN_ROOT/stage3b/fit_health"

cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/atlas_runtime.sh"
atlas_runtime_load
atlas_runtime_preflight

for required in \
  "$RUN_ROOT/stage1/stage1_reuse_audit.csv" \
  "$RUN_ROOT/stage2/joint_model_inputs.rds" \
  "$RUN_ROOT/stage2/joint_model_preparation_audit.csv" \
  "$RUN_ROOT/stage3a/joint_inla_build.rds" \
  "$RUN_ROOT/validation/original_refresh_formula_audit.csv" \
  "$RUN_ROOT/validation/stage3b_dry_run/joint_inla_fit_preflight.csv"; do
  [[ -s "$required" ]] || { echo "Required pre-fit gate artifact is missing: $required" >&2; exit 2; }
done
[[ ! -e "$FIT_PATH" ]] || { echo "Refusing to replace an existing Stage 3B fit: $FIT_PATH" >&2; exit 2; }
[[ ! -e "$RUN_ROOT/stage3b" ]] || { echo "Refusing to reuse a pre-existing or partial Stage 3B output directory: $RUN_ROOT/stage3b" >&2; exit 2; }
if grep -q ',FAIL,' "$RUN_ROOT/stage1/stage1_reuse_audit.csv" \
  "$RUN_ROOT/validation/original_refresh_formula_audit.csv" \
  "$RUN_ROOT/validation/stage3b_dry_run/joint_inla_fit_preflight.csv"; then
  echo "A Stage 1, Stage 3A, or production preflight check is not clear; fit stopped." >&2
  exit 2
fi

echo "Original refresh Stage 3B job: $SLURM_JOB_ID"
echo "Repository: $(git rev-parse HEAD)"
echo "Fit config SHA-256: $(sha256sum "$FIT_CONFIG" | awk '{print $1}')"
echo "Input artifact checksums:"
sha256sum "$RUN_ROOT/stage1/model_inputs.rds" \
  "$RUN_ROOT/stage2/joint_model_inputs.rds" \
  "$RUN_ROOT/stage3a/joint_inla_build.rds"
echo "Allocation: CPUs=$SLURM_CPUS_PER_TASK; memory=$SLURM_MEM_PER_NODE; start UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
module list 2>&1 | cat
Rscript --vanilla scripts/run_joint_inla.R --config config/original_refresh_w44_2026/joint_inla_fit.yml
Rscript --vanilla scripts/check_joint_inla_fit_health.R \
  --repo-root="$PROJECT_ROOT" \
  --fit="$FIT_PATH" \
  --build="$RUN_ROOT/stage3a/joint_inla_build.rds" \
  --stage2="$RUN_ROOT/stage2/joint_model_inputs.rds" \
  --output-dir="$HEALTH_ROOT" \
  --run-id=ORIGINAL_REFRESH_W44_2026
echo "Fit SHA-256: $(sha256sum "$FIT_PATH" | awk '{print $1}')"
echo "End UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
