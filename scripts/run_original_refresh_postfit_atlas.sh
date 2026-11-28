#!/usr/bin/env bash
# Extraction and predictive validation only. Does not make surfaces or rasters.
#SBATCH --job-name=original-refresh-postfit
#SBATCH --account=disease_ecology
#SBATCH --partition=bigmem
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=08:00:00
#SBATCH --output=original-refresh-postfit-%j.out
#SBATCH --error=original-refresh-postfit-%j.err

set -euo pipefail

PROJECT_ROOT=$(printenv ORIGINAL_REFRESH_REPO_ROOT 2>/dev/null || true)
if [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT=$SLURM_SUBMIT_DIR; fi
if [[ -z "$PROJECT_ROOT" ]]; then echo "Set ORIGINAL_REFRESH_REPO_ROOT or submit from the development checkout." >&2; exit 2; fi
RUN_ROOT="$PROJECT_ROOT/outputs/original_refresh_w44_2026"
RUN_ID="ORIGINAL_REFRESH_W44_2026"
BUILD_PATH="$RUN_ROOT/stage3a/joint_inla_build.rds"
FIT_PATH="$RUN_ROOT/stage3b/joint_model_fit.rds"
STAGE2_PATH="$RUN_ROOT/stage2/joint_model_inputs.rds"
EXTRACTION_ROOT="$RUN_ROOT/extraction"
VALIDATION_ROOT="$RUN_ROOT/validation"
HOLDOUT_PATH="$EXTRACTION_ROOT/holdout_predictions_$RUN_ID.csv"
C1_HOLDOUT=$(printenv C1_REFRESH_COMPARE_HOLDOUT 2>/dev/null || true)
C1_TIER2_ROWS=$(printenv C1_REFRESH_COMPARE_TIER2_ROWS 2>/dev/null || true)
C1_METRICS=$(printenv C1_REFRESH_COMPARE_METRICS 2>/dev/null || true)
FIT_JOB=$(printenv ORIGINAL_REFRESH_FIT_JOB 2>/dev/null || true)
if [[ -z "$C1_HOLDOUT" || -z "$C1_TIER2_ROWS" || -z "$C1_METRICS" || -z "$FIT_JOB" ]]; then
  echo "Set ORIGINAL_REFRESH_FIT_JOB and all C1_REFRESH_COMPARE_* paths to the exact outputs listed in the C-1 r3 predictive artifact manifest." >&2
  exit 2
fi

cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/atlas_runtime.sh"
atlas_runtime_load
atlas_runtime_preflight
[[ -s "$FIT_PATH" ]] || { echo "Completed fit is missing: $FIT_PATH" >&2; exit 2; }

echo "Original refresh post-fit job: $SLURM_JOB_ID"
echo "Repository: $(git rev-parse HEAD)"
echo "Start UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
module list 2>&1 | cat
Rscript --vanilla scripts/extract_joint_inla_results.R \
  --repo-root="$PROJECT_ROOT" --build="$BUILD_PATH" --fit="$FIT_PATH" \
  --stage2="$STAGE2_PATH" --output-dir="$EXTRACTION_ROOT" --run-id="$RUN_ID"
Rscript --vanilla scripts/extract_original_refresh_summaries.R \
  --fit="$FIT_PATH" --build="$BUILD_PATH" --stage2="$STAGE2_PATH" \
  --output-dir="$EXTRACTION_ROOT"
Rscript --vanilla scripts/run_joint_inla_validation.R \
  --repo-root="$PROJECT_ROOT" --acceptance-mode=production \
  --build="$BUILD_PATH" --fit="$FIT_PATH" --holdout="$HOLDOUT_PATH" \
  --stage2="$STAGE2_PATH" --output-dir="$VALIDATION_ROOT" \
  --run-id="$RUN_ID" --source-fit-job="$FIT_JOB"
VALIDATION_DIR="$VALIDATION_ROOT/validation_presence_background_$RUN_ID"
Rscript --vanilla scripts/summarize_original_refresh_predictive_groups.R \
  --holdout="$HOLDOUT_PATH" \
  --percentiles="$VALIDATION_DIR/tier1_presence_percentiles_$RUN_ID.csv" \
  --output-dir="$VALIDATION_DIR"
Rscript --vanilla scripts/compare_c1_original_refresh_holdouts.R \
  --c1-holdout="$C1_HOLDOUT" --refreshed-holdout="$HOLDOUT_PATH" \
  --c1-tier2-rows="$C1_TIER2_ROWS" --c1-metrics="$C1_METRICS" \
  --refreshed-metrics="$VALIDATION_DIR/holdout_validation_metrics_$RUN_ID.csv" \
  --output-dir="$RUN_ROOT/comparison"
sacct_row=$(sacct -j "$FIT_JOB" --format=Elapsed,MaxRSS,ExitCode --noheader --parsable2 | awk -F'|' 'NF >= 3 && $1 != "" && $2 != "" && $3 != "" {print; exit}')
if [[ -z "$sacct_row" ]]; then echo "Could not retrieve the completed fit job accounting row for $FIT_JOB." >&2; exit 2; fi
IFS='|' read -r FIT_ELAPSED FIT_MAX_RSS FIT_EXIT_CODE <<< "$sacct_row"
FIT_EXIT_STATUS="${FIT_EXIT_CODE%%:*}"
if [[ ! "$FIT_EXIT_STATUS" =~ ^[0-9]+$ || "$FIT_EXIT_STATUS" != "0" ]]; then
  echo "Completed fit job accounting reports nonzero or invalid exit status: $FIT_EXIT_CODE" >&2
  exit 2
fi
Rscript --vanilla scripts/write_original_refresh_report.R \
  --fit-job="$FIT_JOB" --elapsed="$FIT_ELAPSED" --max-rss="$FIT_MAX_RSS" \
  --exit-status="$FIT_EXIT_STATUS" --cpus=12 --memory=280G
echo "Post-fit outputs complete; no projection, surface, or raster run was requested."
echo "End UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ) status=0"
