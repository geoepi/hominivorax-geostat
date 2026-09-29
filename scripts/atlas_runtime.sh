#!/usr/bin/env bash
set -euo pipefail

ATLAS_RUNTIME_PROFILE_DEFAULT="atlas-r44-spatial-v1"

atlas_runtime_load() {
  local profile="${1:-$ATLAS_RUNTIME_PROFILE_DEFAULT}"
  if [[ "$profile" != "$ATLAS_RUNTIME_PROFILE_DEFAULT" ]]; then
    echo "Unsupported Atlas runtime profile: ${profile}" >&2
    return 2
  fi
  if ! command -v module >/dev/null 2>&1; then
    echo "Atlas runtime requires the environment-modules 'module' command." >&2
    return 127
  fi
  module purge
  module load udunits proj geos/3.12.1 gdal/3.8.5 \
    intel-oneapi-mkl/2023.2.0 r/4.4.3
}

atlas_runtime_preflight() {
  local rscript="${1:-Rscript}"
  if ! command -v "$rscript" >/dev/null 2>&1; then
    echo "Atlas runtime preflight cannot find Rscript: ${rscript}" >&2
    return 127
  fi
  "$rscript" --version
  "$rscript" --vanilla -e 'required <- c("units", "sf", "terra"); missing <- required[!vapply(required, requireNamespace, logical(1L), quietly = TRUE)]; if (length(missing)) stop("Missing Atlas runtime packages: ", paste(missing, collapse = ", ")); invisible(lapply(required, library, character.only = TRUE)); cat("Atlas runtime spatial preflight: PASS\n")'
}
