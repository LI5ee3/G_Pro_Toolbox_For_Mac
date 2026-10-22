#!/bin/bash
# Production target only; Preview has no runtime phase and never downloads assets.
set -euo pipefail
exec python3 "${SRCROOT}/scripts/runtime_assets.py" copy "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
