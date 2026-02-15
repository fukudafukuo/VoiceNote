#!/bin/bash
# ============================================================
#  VoiceNote ビルドスクリプト
#
#  使い方:
#    bash build.sh           # ビルド → 署名 → DMG作成
#    bash build.sh --clean   # クリーンビルド
#    bash build.sh --dev     # 開発モード（エイリアスビルド）
#
#  前提条件:
#    - Python 3.11+ と venv が設定済み
#    - pip install py2app 済み
#    - brew install portaudio 済み
# ============================================================

set -e

VERSION="1.0.0"
APP_NAME="VoiceNote"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
DIST_DIR="dist"
DMG_DIR="dmg_staging"

# --- カラー出力 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}==>${NC} $1"; }

echo
echo "======================================================"
echo "  VoiceNote ビルドスクリプト v${VERSION}"
echo "======================================================"
echo

# ============================================================
# 0. 引数解析
# ============================================================
CLEAN=false
DEV_MODE=false

for arg in "$@"; do
    case $arg in
        --clean) CLEAN=true ;;
        --dev)   DEV_MODE=true ;;
        --help|-h)
            echo "Usage: bash build.sh [--clean] [--dev]"
            echo "  --clean   クリーンビルド（build/, dist/ を削除してから）"
            echo "  --dev     開発モード（エイリアスビルド。高速だが配布不可）"
            exit 0
            ;;
    esac
done

# ============================================================
# 1. 前提条件チェック
# ============================================================
step "前提条件を確認しています..."

# macOS チェック
if [[ "$(uname)" != "Darwin" ]]; then
    error "このスクリプトはmacOS専用です。"
    exit 1
fi
info "macOS $(sw_vers -productVersion)"

# Python チェック
if ! command -v python3 &> /dev/null; then
    error "Python3 が見つかりません。"
    exit 1
fi
PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
info "Python ${PYTHON_VER}"

# py2app チェック
if ! python3 -c "import py2app" 2>/dev/null; then
    warn "py2app がインストールされていません。インストールします..."
    pip install py2app
fi
info "py2app 確認済み"

# PortAudio チェック
PA_PATH=""
for p in /opt/homebrew/lib/libportaudio.dylib /opt/homebrew/lib/libportaudio.2.dylib \
         /usr/local/lib/libportaudio.dylib /usr/local/lib/libportaudio.2.dylib; do
    if [ -f "$p" ]; then
        PA_PATH="$p"
        break
    fi
done
if [ -n "$PA_PATH" ]; then
    info "PortAudio: $PA_PATH"
else
    warn "PortAudio が見つかりません。brew install portaudio を実行してください。"
fi

# entitlements チェック
if [ ! -f "VoiceNote.entitlements" ]; then
    error "VoiceNote.entitlements が見つかりません。"
    exit 1
fi
info "VoiceNote.entitlements 確認済み"

# ============================================================
# 2. クリーンアップ（--clean時）
# ============================================================
if $CLEAN; then
    step "クリーンアップ中..."
    rm -rf "$BUILD_DIR" "$DIST_DIR" "$DMG_DIR" "${DMG_NAME}.dmg"
    info "build/, dist/, dmg_staging/ を削除しました"
fi

# ============================================================
# 3. py2app ビルド
# ============================================================
step "py2app でビルド中..."

if $DEV_MODE; then
    echo "  (開発モード: エイリアスビルド)"
    python3 setup.py py2app -A 2>&1 | tail -5
else
    python3 setup.py py2app 2>&1 | tail -20
fi

if [ ! -d "$DIST_DIR/${APP_NAME}.app" ]; then
    error "ビルドに失敗しました。dist/${APP_NAME}.app が見つかりません。"
    exit 1
fi
info "ビルド完了: $DIST_DIR/${APP_NAME}.app"

# ============================================================
# 4. PortAudio dylib の追加確認
# ============================================================
step "PortAudio dylib を確認中..."

FRAMEWORKS_DIR="$DIST_DIR/${APP_NAME}.app/Contents/Frameworks"
if [ -n "$PA_PATH" ]; then
    if [ ! -f "$FRAMEWORKS_DIR/libportaudio.dylib" ] && \
       [ ! -f "$FRAMEWORKS_DIR/libportaudio.2.dylib" ]; then
        mkdir -p "$FRAMEWORKS_DIR"
        cp "$PA_PATH" "$FRAMEWORKS_DIR/"
        info "PortAudio を Frameworks/ にコピーしました"
    else
        info "PortAudio は既に同梱されています"
    fi
fi

# ============================================================
# 5. コード署名
# ============================================================
step "コード署名中..."

# Developer ID が環境変数に設定されている場合はそれを使用
# 設定がなければ Ad-hoc 署名
SIGN_IDENTITY="${VOICENOTE_SIGN_IDENTITY:--}"

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "  (Ad-hoc署名を使用。Developer IDで署名するには:"
    echo "   export VOICENOTE_SIGN_IDENTITY='Developer ID Application: Your Name (ABCD1234EF)'"
    echo "   を設定してください)"
fi

codesign --deep --force --verify --verbose \
    --sign "$SIGN_IDENTITY" \
    --entitlements VoiceNote.entitlements \
    "$DIST_DIR/${APP_NAME}.app" 2>&1 | grep -v "^$"

info "コード署名完了 (identity: $SIGN_IDENTITY)"

# 署名の検証
codesign --verify --verbose "$DIST_DIR/${APP_NAME}.app" 2>&1 | head -3
info "署名検証OK"

# ============================================================
# 6. DMG 作成
# ============================================================
if ! $DEV_MODE; then
    step "DMG を作成中..."

    # ステージングディレクトリ準備
    rm -rf "$DMG_DIR"
    mkdir -p "$DMG_DIR"

    # .app をコピー
    cp -R "$DIST_DIR/${APP_NAME}.app" "$DMG_DIR/"

    # Applications シンボリックリンク
    ln -s /Applications "$DMG_DIR/Applications"

    # README を同梱
    cat > "$DMG_DIR/はじめにお読みください.txt" << 'README_INNER'
╔══════════════════════════════════════════════╗
║  VoiceNote - macOS 音声認識メモアプリ          ║
╚══════════════════════════════════════════════╝

■ インストール方法
  VoiceNote.app を Applications フォルダにドラッグ＆ドロップしてください。

■ 初回起動時の設定

  1. マイク権限
     初回起動時にマイクへのアクセス許可を求めるダイアログが表示されます。
     「OK」を押してください。

  2. アクセシビリティ権限
     自動ペーストとキーボードショートカットに必要です。
     システム設定 → プライバシーとセキュリティ → アクセシビリティ
     → VoiceNote を許可してください。

  3. 音声入力ショートカットの無効化（推奨）
     右⌘キーのダブルタップとmacOSの音声入力が競合する場合があります。
     システム設定 → キーボード → 音声入力 → ショートカット → 「オフ」

■ 使い方
  右⌘キーを素早く2回タップ → 録音開始
  もう一度2回タップ → 録音停止 → 自動で文字起こし → ペースト

■ Gemini API（オプション）
  メニューバーの VoiceNote アイコン → 設定ファイルを開く
  → gemini_api_key にAPIキーを入力すると、より高精度な整形が使えます。

■ 自動起動
  システム設定 → 一般 → ログイン項目 → 「+」→ VoiceNote.app を追加
README_INNER

    # DMG 作成（hdiutil）
    rm -f "${DMG_NAME}.dmg"

    # 一時DMG作成
    hdiutil create \
        -volname "$DMG_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        "${DMG_NAME}.dmg"

    # クリーンアップ
    rm -rf "$DMG_DIR"

    if [ -f "${DMG_NAME}.dmg" ]; then
        DMG_SIZE=$(du -h "${DMG_NAME}.dmg" | cut -f1)
        info "DMG作成完了: ${DMG_NAME}.dmg (${DMG_SIZE})"
    else
        error "DMG作成に失敗しました。"
        exit 1
    fi

    # ============================================================
    # 7. Notarization（Developer ID がある場合のみ）
    # ============================================================
    if [ "$SIGN_IDENTITY" != "-" ] && [ -n "${VOICENOTE_APPLE_ID:-}" ]; then
        step "Apple Notarization を実行中..."
        echo "  (この処理には数分かかる場合があります)"

        xcrun notarytool submit "${DMG_NAME}.dmg" \
            --apple-id "$VOICENOTE_APPLE_ID" \
            --password "$VOICENOTE_APP_PASSWORD" \
            --team-id "$VOICENOTE_TEAM_ID" \
            --wait

        xcrun stapler staple "${DMG_NAME}.dmg"
        info "Notarization 完了"
    fi
fi

# ============================================================
# 完了
# ============================================================
echo
echo "======================================================"
echo "  ビルド完了！"
echo "======================================================"
echo

if $DEV_MODE; then
    info "開発ビルド: $DIST_DIR/${APP_NAME}.app"
    echo
    echo "  テスト起動:"
    echo "    open $DIST_DIR/${APP_NAME}.app"
else
    info "配布用DMG: ${DMG_NAME}.dmg"
    echo
    echo "  テスト手順:"
    echo "    1. open ${DMG_NAME}.dmg"
    echo "    2. VoiceNote.app を Applications にドラッグ"
    echo "    3. open /Applications/VoiceNote.app"
    echo
    echo "  BOOTH/Gumroad にアップロードして販売できます。"
fi
echo
