#!/bin/bash
# Retired: security export -t identities exports all login private keys.
# Export only the selected Developer ID certificate + key in Keychain Access to a dedicated P12.
set -euo pipefail
printf '%s\n' '已停用整钥匙串导出。请按 R6-RELEASE.md 仅导出选定 Developer ID 身份；不要上传登录钥匙串或在聊天中发送私钥。' >&2
exit 1
