#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)"
source "$SCRIPT_DIR/atlas_runtime.sh"

export ATLAS_RUNTIME_PROFILE="${ATLAS_RUNTIME_PROFILE:-$ATLAS_RUNTIME_PROFILE_DEFAULT}"
atlas_runtime_load "$ATLAS_RUNTIME_PROFILE"
export RSCRIPT_BIN="Rscript"
atlas_runtime_preflight "$RSCRIPT_BIN"
export ATLAS_RUNTIME_PREFLIGHT="PASS"

exec "$RSCRIPT_BIN" --vanilla "$SCRIPT_DIR/manage_model_release.R" "$@"
