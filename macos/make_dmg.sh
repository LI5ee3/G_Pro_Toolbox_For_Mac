#!/bin/bash
# Verified read-only DMG + ZIP; development names cannot become a formal release.
set -euo pipefail
exec python3 "$(dirname "$0")/scripts/dmg_pipeline.py" "$@"
