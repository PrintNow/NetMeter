#!/usr/bin/env bash
# 使用最新 git 标签（v*）作为 MARKETING_VERSION，提交数作为 CURRENT_PROJECT_VERSION，Release 构建并打包 .zip

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="NetMeter"
PROJECT="NetMeter.xcodeproj"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
DERIVED="$BUILD_ROOT/DerivedData"
PRODUCT_NAME="NetMeter"

# 允许环境变量覆盖：VERSION_TAG=v1.2.3 ./scripts/package-release.sh
if [[ -n "${VERSION_TAG:-}" ]]; then
  LATEST_TAG="$VERSION_TAG"
else
  # 与当前提交关联的最近 v* 标签（若仅有轻量标签也可）
  if ! LATEST_TAG="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null)"; then
    echo "错误：仓库中没有任何 v* 形式的 tag（例如 v1.0.0）。" >&2
    echo "请先执行：git tag -a v1.0.0 -m 'Release v1.0.0' && git push origin v1.0.0" >&2
    exit 1
  fi
fi

# v1.0.0 -> 1.0.0（供 Xcode MARKETING_VERSION）
MARKETING_VERSION="${LATEST_TAG#v}"
if [[ "$MARKETING_VERSION" == "$LATEST_TAG" ]]; then
  echo "错误：标签应以 v 开头，例如 v1.0.0，当前为：$LATEST_TAG" >&2
  exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "警告：工作区或暂存区有未提交改动，打包结果可能与 tag 不一致。" >&2
fi

echo "==> 版本标签: $LATEST_TAG"
echo "==> MARKETING_VERSION=$MARKETING_VERSION  CURRENT_PROJECT_VERSION=$BUILD_NUMBER"

rm -rf "$DERIVED"
mkdir -p "$DIST_DIR"

if command -v xcpretty >/dev/null 2>&1; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build 2>&1 | xcpretty
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build
fi

# 产物目录：本工程 Release 主 target 未覆盖 SYMROOT 时多为 $BUILD_ROOT/Release（与 -derivedDataPath 并存）
APP_PATH="$DERIVED/Build/Products/Release/${PRODUCT_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$BUILD_ROOT/Release/${PRODUCT_NAME}.app"
fi
if [[ ! -d "$APP_PATH" ]]; then
  # ${APP_PATH} 与全角句号分开，避免 bash 3.2 把 $APP_PATH。 当成未定义变量名
  echo "错误：未找到 Release 产物（已尝试 DerivedData 与 BUILD_ROOT/Release）：${APP_PATH}" >&2
  exit 1
fi

ZIP_NAME="${PRODUCT_NAME}-${MARKETING_VERSION}-b${BUILD_NUMBER}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> 已生成: $ZIP_PATH"
/usr/bin/plutil -p "$APP_PATH/Contents/Info.plist" | grep -E 'CFBundleShortVersionString|CFBundleVersion' || true
