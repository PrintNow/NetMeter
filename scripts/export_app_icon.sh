#!/usr/bin/env bash
# 从 Design/AppIcon.svg 批量导出 macOS AppIcon PNG；依赖 rsvg-convert（brew install librsvg）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="${ROOT}/Design/AppIcon.svg"
OUT="${ROOT}/NetMeter/Assets.xcassets/AppIcon.appiconset"

RSVG="$(command -v rsvg-convert || true)"
if [[ -z "${RSVG}" && -x /opt/homebrew/bin/rsvg-convert ]]; then
  RSVG=/opt/homebrew/bin/rsvg-convert
fi
if [[ -z "${RSVG}" ]]; then
  echo "未找到 rsvg-convert，请安装: brew install librsvg" >&2
  exit 1
fi

[[ -f "${SVG}" ]] || { echo "缺少源文件: ${SVG}" >&2; exit 1; }
mkdir -p "${OUT}"

export_one() {
  local px="$1" name="$2"
  "${RSVG}" -w "${px}" -h "${px}" -o "${OUT}/${name}" "${SVG}"
}

# 与 Contents.json 中 mac 条目顺序一致：16/32/128/256/512 各 1x 与 2x
export_one 16  "icon_16x16.png"
export_one 32  "icon_16x16@2x.png"
export_one 32  "icon_32x32.png"
export_one 64  "icon_32x32@2x.png"
export_one 128 "icon_128x128.png"
export_one 256 "icon_128x128@2x.png"
export_one 256 "icon_256x256.png"
export_one 512 "icon_256x256@2x.png"
export_one 512 "icon_512x512.png"
export_one 1024 "icon_512x512@2x.png"

echo "已写入: ${OUT}"
