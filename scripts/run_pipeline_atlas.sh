#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)"
source "$SCRIPT_DIR/atlas_runtime.sh"

export ATLAS_RUNTIME_PROFILE="${ATLAS_RUNTIME_PROFILE:-$ATLAS_RUNTIME_PROFILE_DEFAULT}"
atlas_runtime_load "$ATLAS_RUNTIME_PROFILE"

# Do not inherit an arbitrary Rscript from the interactive submit shell after
# the validated module stack has been loaded.
export RSCRIPT_BIN="Rscript"

echo "Atlas runtime profile: ${ATLAS_RUNTIME_PROFILE}"
echo "Atlas runtime module list:"
module list 2>&1 || true
echo "Atlas runtime Rscript: $(command -v "$RSCRIPT_BIN")"
atlas_runtime_preflight "$RSCRIPT_BIN"
export ATLAS_RUNTIME_PREFLIGHT="PASS"

exec "$RSCRIPT_BIN" --vanilla "$SCRIPT_DIR/run_pipeline.R" "$@"
