#!/bin/bash
# VoiceNote DMGビルドスクリプト
# 使い方: ./scripts/build_dmg.sh

set -e

APP_NAME="VoiceNote"
SCHEME="VoiceNote"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJECT="$PROJECT_DIR/VoiceNote/VoiceNote.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$DMG_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
VOLUME_NAME="$APP_NAME"

echo "================================================"
echo "  $APP_NAME DMG ビルド"
echo "================================================"
echo ""

# クリーンアップ
echo "[1/5] ビルドディレクトリをクリーンアップ..."
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_DIR"

# Xcodeビルド（Release）
echo "[2/5] Release ビルド中..."
xcodebuild archive \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# アーカイブからアプリを抽出
echo "[3/5] アプリを抽出中..."
if [ -d "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" ]; then
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"
elif [ -d "$ARCHIVE_PATH/Products/usr/local/bin" ]; then
    # フォールバック: 直接ビルド
    xcodebuild build \
        -project "$XCODE_PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/derived" \
        -quiet \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    BUILT_APP=$(find "$BUILD_DIR/derived" -name "$APP_NAME.app" -type d | head -1)
    if [ -n "$BUILT_APP" ]; then
        cp -R "$BUILT_APP" "$APP_PATH"
    else
        echo "エラー: ビルドされたアプリが見つかりません"
        exit 1
    fi
fi

# アプリの存在確認
if [ ! -d "$APP_PATH" ]; then
    echo "エラー: $APP_PATH が見つかりません"
    exit 1
fi

# Applicationsフォルダへのシンボリックリンク
ln -s /Applications "$DMG_DIR/Applications"

# DMG作成
echo "[4/5] DMG を作成中..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# サイズ確認
echo "[5/5] 完了!"
echo ""
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "  出力: $DMG_PATH"
echo "  サイズ: $DMG_SIZE"
echo ""
echo "================================================"
echo "  ビルド完了"
echo "================================================"
