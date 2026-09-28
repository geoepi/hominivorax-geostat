#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"

exec "$RSCRIPT_BIN" --vanilla "$REPO_ROOT/scripts/run_pipeline.R" --mode submit "$@"

