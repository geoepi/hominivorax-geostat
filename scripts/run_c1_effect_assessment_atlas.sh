#!/usr/bin/env bash
# Reporting-only analysis of saved C-1 marginals and Stage 2 predictor ranges.
#SBATCH --job-name=c1-effect-assessment
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=04:00:00
#SBATCH --output=c1-effect-assessment-%j.out
#SBATCH --error=c1-effect-assessment-%j.err

set -euo pipefail

PROJECT_ROOT=$(printenv ORIGINAL_REFRESH_REPO_ROOT 2>/dev/null || true)
if [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT=$SLURM_SUBMIT_DIR; fi
if [[ -z "$PROJECT_ROOT" ]]; then echo "Set ORIGINAL_REFRESH_REPO_ROOT or submit from the development checkout." >&2; exit 2; fi
C1_ROOT="/project/disease_ecology/hominivorax-geostat-c1-validation-20261121"
C1_OUTPUT="$C1_ROOT/outputs/configuration_c"
FIT="$C1_OUTPUT/c1-stage3b-20261122/fit/joint_model_fit.rds"
STAGE1="$C1_OUTPUT/c1-validation-20261121-stage2-index-repair/stage1/model_inputs.rds"
STAGE2="$C1_OUTPUT/c1-validation-20261121-stage2-index-repair/stage2/joint_model_inputs.rds"
STAGE3A="$C1_OUTPUT/c1-validation-20261121-stage2-index-repair/stage3a/joint_inla_build.rds"
HOLDOUT="$C1_OUTPUT/c1-stage3b-20261122/diagnostics/extraction/holdout_predictions_c1-stage3b-20261122.csv"
PREDICTIVE_DIR="$C1_OUTPUT/c1-predictive-validation-20261123/validation_presence_background_c1-predictive-qualification-20261123-r3"
PREDICTIVE_MANIFEST="$PREDICTIVE_DIR/c1_predictive_artifact_manifest_c1-predictive-qualification-20261123-r3.csv"
PREDICTIVE_REPORT="$PREDICTIVE_DIR/c1_predictive_qualification_report_c1-predictive-qualification-20261123-r3.md"
PREDICTIVE_METRICS="$PREDICTIVE_DIR/holdout_validation_metrics_c1-predictive-qualification-20261123-r3.csv"
TIER2_ROWS="$PREDICTIVE_DIR/tier2_holdout_diagnostics_c1-predictive-qualification-20261123-r3.csv"

cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/atlas_runtime.sh"
atlas_runtime_load
atlas_runtime_preflight
Rscript --vanilla scripts/assess_c1_effects.R \
  --fit="$FIT" --stage1="$STAGE1" --stage2="$STAGE2" --stage3a="$STAGE3A" \
  --holdout="$HOLDOUT" --tier2-rows="$TIER2_ROWS" --predictive-metrics="$PREDICTIVE_METRICS" \
  --predictive-manifest="$PREDICTIVE_MANIFEST" --predictive-report="$PREDICTIVE_REPORT" \
  --predictive-report-sha256=828d2384614cef5dc31088e862fd1b32ca397d061ad731e7d45d03937aa25f1d \
  --fit-job=21304948
echo "C-1 effect assessment end: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
