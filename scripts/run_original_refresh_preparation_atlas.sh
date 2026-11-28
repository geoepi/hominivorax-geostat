#!/usr/bin/env bash
# Original-specification Stage 1 reuse gate, Stage 2/3A assembly, and dry-run.
# This job never calls INLA::inla() and writes only in the isolated W44 output tree.
#SBATCH --job-name=original-refresh-prepare
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=08:00:00
#SBATCH --output=original-refresh-prepare-%j.out
#SBATCH --error=original-refresh-prepare-%j.err

set -euo pipefail

PROJECT_ROOT=$(printenv ORIGINAL_REFRESH_REPO_ROOT 2>/dev/null || true)
if [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT=$SLURM_SUBMIT_DIR; fi
if [[ -z "$PROJECT_ROOT" ]]; then echo "Set ORIGINAL_REFRESH_REPO_ROOT or submit from the development checkout." >&2; exit 2; fi
C1_STAGE1_SOURCE="/project/disease_ecology/hominivorax-geostat-c1-validation-20261121/outputs/configuration_c/c1-validation-20261121-stage2-index-repair/stage1/model_inputs.rds"
STAGE1_DEST="$PROJECT_ROOT/outputs/original_refresh_w44_2026/stage1/model_inputs.rds"

cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/atlas_runtime.sh"
atlas_runtime_load
atlas_runtime_preflight

run_configured_tests() {
  FOCUSED_TEST=$(printenv ORIGINAL_REFRESH_FOCUSED_TEST 2>/dev/null || true)
  if [[ -n "$FOCUSED_TEST" ]]; then
    if [[ ! "$FOCUSED_TEST" =~ ^test_[A-Za-z0-9_.-]+\.R$ || ! -s "$PROJECT_ROOT/tests/$FOCUSED_TEST" ]]; then
      echo "ORIGINAL_REFRESH_FOCUSED_TEST must name an existing tests/test_*.R file." >&2
      exit 2
    fi
    TEST_SKIP=()
    for test_path in "$PROJECT_ROOT"/tests/test_*.R; do
      test_name=$(basename "$test_path")
      [[ "$test_name" == "$FOCUSED_TEST" ]] || TEST_SKIP+=("$test_name")
    done
    skip_csv=$(IFS=,; printf '%s' "${TEST_SKIP[*]}")
    echo "Running focused validation test after prior full-suite execution: $FOCUSED_TEST"
    Rscript tests/run_tests.R --log-dir outputs/original_refresh_w44_2026/validation/test-logs --skip "$skip_csv"
  else
    Rscript tests/run_tests.R --log-dir outputs/original_refresh_w44_2026/validation/test-logs
  fi
}

RESUME_STAGE3A_AUDIT=$(printenv ORIGINAL_REFRESH_RESUME_STAGE3A_AUDIT 2>/dev/null || true)
if [[ "$RESUME_STAGE3A_AUDIT" == "1" ]]; then
  RUN_ROOT="$PROJECT_ROOT/outputs/original_refresh_w44_2026"
  for required in \
    "$RUN_ROOT/stage1/stage1_reuse_audit.csv" \
    "$RUN_ROOT/stage2/joint_model_inputs.rds" \
    "$RUN_ROOT/stage2/joint_model_preparation_audit.csv" \
    "$RUN_ROOT/stage3a/joint_inla_build.rds" \
    "$RUN_ROOT/stage3a/joint_inla_build_audit.csv" \
    "$RUN_ROOT/validation/stage3b_dry_run/joint_inla_fit_preflight.csv"; do
    [[ -s "$required" ]] || { echo "Required completed preparation artifact is missing: $required" >&2; exit 2; }
  done
  FORMULA_AUDIT="$RUN_ROOT/validation/original_refresh_formula_audit.csv"
  [[ ! -e "$FORMULA_AUDIT" ]] || { echo "Refusing to overwrite an existing formula audit: $FORMULA_AUDIT" >&2; exit 2; }
  echo "Original refresh Stage 3A audit resumption: $SLURM_JOB_ID"
  echo "Repository: $(git rev-parse HEAD)"
  echo "Start UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  module list 2>&1 | cat
  run_configured_tests
  Rscript --vanilla scripts/check_original_refresh_stage3a.R
  echo "Stage 3A formula/row-map audit passed; no fit was run."
  echo "End UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
  exit 0
elif [[ -n "$RESUME_STAGE3A_AUDIT" && "$RESUME_STAGE3A_AUDIT" != "0" ]]; then
  echo "ORIGINAL_REFRESH_RESUME_STAGE3A_AUDIT must be 0 or 1." >&2
  exit 2
fi

for partial in \
  "$PROJECT_ROOT/outputs/original_refresh_w44_2026/stage2/joint_model_inputs.rds" \
  "$PROJECT_ROOT/outputs/original_refresh_w44_2026/stage2/joint_model_preparation_audit.csv" \
  "$PROJECT_ROOT/outputs/original_refresh_w44_2026/stage3a/joint_inla_build.rds" \
  "$PROJECT_ROOT/outputs/original_refresh_w44_2026/stage3a/joint_inla_build_audit.csv" \
  "$PROJECT_ROOT/outputs/original_refresh_w44_2026/validation/stage3b_dry_run"; do
  [[ ! -e "$partial" ]] || { echo "Refusing to overwrite a pre-existing or partial preparation output: $partial" >&2; exit 2; }
done

if [[ ! -s "$C1_STAGE1_SOURCE" ]]; then
  echo "Reusable C-1 Stage 1 artifact is missing: $C1_STAGE1_SOURCE" >&2
  exit 2
fi
if [[ -e "$STAGE1_DEST" ]]; then
  SOURCE_SHA=$(sha256sum "$C1_STAGE1_SOURCE" | awk '{print $1}')
  DEST_SHA=$(sha256sum "$STAGE1_DEST" | awk '{print $1}')
  if [[ "$SOURCE_SHA" != "$DEST_SHA" ]]; then
    echo "The existing isolated Stage 1 copy differs from its approved C-1 source; refusing to continue." >&2
    exit 2
  fi
  echo "Reusing byte-identical Stage 1 copy after a prior preparation attempt."
else
  mkdir -p "$(dirname "$STAGE1_DEST")"
  cp --preserve=mode,timestamps "$C1_STAGE1_SOURCE" "$STAGE1_DEST"
fi
echo "Stage 1 source and copied artifact checksums:"
sha256sum "$C1_STAGE1_SOURCE" "$STAGE1_DEST"

echo "Original refresh preparation job: $SLURM_JOB_ID"
echo "Repository: $(git rev-parse HEAD)"
echo "Start UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
module list 2>&1 | cat
run_configured_tests
Rscript --vanilla scripts/validate_original_refresh_stage1_reuse.R \
  --config config/original_refresh_w44_2026/stage1_reuse.yml
Rscript --vanilla scripts/prepare_joint_model.R \
  --config config/original_refresh_w44_2026/joint_model.yml
Rscript --vanilla scripts/build_joint_inla.R \
  --config config/original_refresh_w44_2026/joint_inla.yml
Rscript --vanilla scripts/run_joint_inla.R \
  --config config/original_refresh_w44_2026/joint_inla_fit.yml --dry-run \
  --output outputs/original_refresh_w44_2026/validation/stage3b_dry_run
Rscript --vanilla scripts/check_original_refresh_stage3a.R

echo "Stage 2 and Stage 3A checks passed; no fit was run."
echo "End UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
