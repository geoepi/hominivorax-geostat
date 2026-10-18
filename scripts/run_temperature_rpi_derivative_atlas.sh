#!/usr/bin/env bash
set -euo pipefail

module purge
module load udunits proj geos/3.12.1 gdal/3.8.5 intel-oneapi-mkl/2023.2.0 r/4.4.3

echo "hostname=$(hostname)"
module list 2>&1
echo "R=$(command -v R)"
R --version | head -n 1
Rscript -e 'gdal <- tryCatch(as.character(terra::gdal()), error = function(e) paste0("unavailable:", conditionMessage(e))); proj <- tryCatch(as.character(terra::proj_info()[["version"]]), error = function(e) paste0("unavailable:", conditionMessage(e))); cat(".libPaths=", paste(.libPaths(), collapse=";"), "\n", sep=""); cat("INLA=", as.character(packageVersion("INLA")), "\n", sep=""); cat("Matrix=", as.character(packageVersion("Matrix")), "\n", sep=""); cat("terra=", as.character(packageVersion("terra")), "\n", sep=""); cat("sf=", as.character(packageVersion("sf")), "\n", sep=""); cat("sf_extsoft=", sf::sf_extSoftVersion()[["GDAL"]], "\n", sep=""); cat("terra_GDAL=", gdal, "\n", sep=""); cat("terra_PROJ=", proj, "\n", sep="")'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-/project/disease_ecology/worktrees/hominivorax-geostat-temp16}"
Rscript --vanilla "${SCRIPT_DIR}/run_temperature_rpi_derivative.R" \
  --run-id "${TEMP16_RUN_ID:?TEMP16_RUN_ID is required}" \
  --source-root "${TEMP16_SOURCE_ROOT:?TEMP16_SOURCE_ROOT is required}" \
  --temp15-root "${TEMP16_TEMP15_ROOT:?TEMP16_TEMP15_ROOT is required}" \
  --stage2 "${TEMP16_STAGE2:?TEMP16_STAGE2 is required}" \
  --observations "${TEMP16_OBSERVATIONS:?TEMP16_OBSERVATIONS is required}" \
  --output-root "${TEMP16_OUTPUT_ROOT:?TEMP16_OUTPUT_ROOT is required}" \
  --boundary-path "${TEMP16_BOUNDARY_PATH:?TEMP16_BOUNDARY_PATH is required}" \
  --reference-figure "${TEMP16_REFERENCE_FIGURE:-C:/Users/humph173/Downloads/rpi_class.pdf}" \
  --source-native-repo-sha "${TEMP16_NATIVE_REPO_SHA:-33098504df8bae18a10b5200db36ab7493ce9901}" \
  --source-chime-execution "${TEMP16_CHIME_EXECUTION_ID:-exec-20261017T230234-a4a51da4}" \
  --source-repository-sha "${TEMP16_SOURCE_REPOSITORY_SHA:-516dd51b57229aa22245f23eda0da276fda9b715}" \
  --source-config-sha "${TEMP16_CONFIG_SHA:-400ecd1b3ca7fa70eb073290c7e4389c2558aaea69daa22feb2a54676c1c69ee}" \
  --source-observation-sha "${TEMP16_OBSERVATION_SHA:-193245f75d9fe863de852801b8cdc405d4ceb39d25b512f9c52da4f8876f969c}" \
  --source-cds-portfolio "${TEMP16_CDS_PORTFOLIO:-20261015T163459Z_portfolio}" \
  --source-coverage-sha "${TEMP16_COVERAGE_SHA:-9148d1f92ae86b0974ce5c76e2fc7102eb74a98d79a8666a8ac6057f2ec7d56c}" \
  --source-horizon "${TEMP16_HORIZON:-2024-W01 -> 2026-W39}" \
  --overwrite

