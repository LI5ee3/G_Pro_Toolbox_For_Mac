#!/bin/bash
# Build the native Release App Target in an isolated output directory. Never installs.
# development = explicit ad-hoc; local/distribution require an exact identity; no fallback.
set -euo pipefail
exec python3 "$(dirname "$0")/scripts/release_pipeline.py" build "$@"
