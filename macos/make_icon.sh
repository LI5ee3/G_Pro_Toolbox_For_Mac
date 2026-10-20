#!/bin/bash
# 从独立的 PNG 源生成 macOS icns，不依赖其他桌面平台的图标格式。
# 用法：./make_icon.sh [输入 PNG] [输出 icns]
set -euo pipefail
cd "$(dirname "$0")"

SRC_PNG="${1:-assets/AppIcon.png}"
OUT="${2:-assets/AppIcon.icns}"
[ -f "$SRC_PNG" ] || { echo "❌ 找不到 $SRC_PNG"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$SRC_PNG" \
        --out "$SET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -s format png -z "$retina" "$retina" "$SRC_PNG" \
        --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$SET" -o "$OUT"
echo "✅ 已生成 ${OUT}（$(du -h "$OUT" | cut -f1)）"
