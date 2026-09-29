#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)"

exec "$SCRIPT_DIR/run_pipeline_atlas.sh" --mode submit "$@"

