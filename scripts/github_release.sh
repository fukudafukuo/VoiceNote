#!/bin/bash
# VoiceNote GitHub Release スクリプト
# 使い方:
#   1. gh auth login でGitHubにログイン済みであること
#   2. ./scripts/github_release.sh

set -e

APP_NAME="VoiceNote"
VERSION="v1.0.0"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="$PROJECT_DIR/build/$APP_NAME.dmg"
REPO_NAME="VoiceNote"

echo "================================================"
echo "  $APP_NAME GitHub Release"
echo "================================================"
echo ""

# gh コマンドの確認
if ! command -v gh &> /dev/null; then
    echo "エラー: GitHub CLI (gh) がインストールされていません"
    echo "  brew install gh"
    echo "  gh auth login"
    exit 1
fi

# DMGの存在確認
if [ ! -f "$DMG_PATH" ]; then
    echo "エラー: DMGファイルが見つかりません: $DMG_PATH"
    echo "  先に ./scripts/build_dmg.sh を実行してください"
    exit 1
fi

cd "$PROJECT_DIR"

# Gitリポジトリの初期化（未初期化の場合）
if [ ! -d ".git" ]; then
    echo "[1/5] Gitリポジトリを初期化中..."
    git init -b main
else
    echo "[1/5] Gitリポジトリ確認OK"
fi

# 全ファイルをコミット
echo "[2/5] ファイルをコミット中..."
git add -A
git commit -m "VoiceNote v1.0.0 - Initial release" 2>/dev/null || echo "  (変更なし、スキップ)"

# GitHubリポジトリの作成（まだない場合）
echo "[3/5] GitHubリポジトリを確認中..."
if ! gh repo view "$REPO_NAME" &>/dev/null; then
    echo "  リポジトリを作成します..."
    gh repo create "$REPO_NAME" --public --source=. --push --description "macOS メニューバー音声入力アプリ - Voice-to-text with WhisperKit & Apple Speech"
else
    echo "  リポジトリ確認OK"
    # リモートが設定されていない場合追加
    if ! git remote get-url origin &>/dev/null; then
        GITHUB_USER=$(gh api user --jq '.login')
        git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
    fi
    git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || true
fi

# リリースを作成してDMGをアップロード
echo "[4/5] リリースを作成中..."
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

gh release create "$VERSION" "$DMG_PATH" \
    --title "$APP_NAME $VERSION" \
    --notes "$(cat <<'EOF'
# VoiceNote v1.0.0

macOS メニューバー音声入力アプリの初回リリースです。

## 主な機能
- **右⌘キー × 2回タップ**でどこからでも録音・書き起こし・自動ペースト
- **Apple音声認識（高速）** / **Whisper Large V3 Turbo（高精度）** の2エンジン搭載
- 音声コマンドでMarkdown入力（見出し、箇条書き、改行など）
- アプリ別プロファイルで出力フォーマットを自動調整
- Gemini API連携でフィラー除去・長文整形（オプション）

## 動作環境
- macOS 14 (Sonoma) 以降
- Apple Silicon (M1/M2/M3/M4) 推奨
- Whisperモード使用時は約3GBの空き容量が必要

## インストール
1. `VoiceNote.dmg` をダウンロード
2. DMGを開いてApplicationsフォルダにドラッグ
3. アプリを起動し、アクセシビリティ・マイクの許可を設定
4. 右⌘キーを2回タップで録音開始！

> ⚠️ コード署名なしのため、初回起動時にGatekeeperの警告が出ます。
> 「システム設定 > プライバシーとセキュリティ > このまま開く」で起動できます。
EOF
)"

# 完了
echo "[5/5] 完了!"
echo ""
RELEASE_URL=$(gh release view "$VERSION" --json url --jq '.url')
echo "  リリースURL: $RELEASE_URL"
echo "  DMGサイズ: $DMG_SIZE"
echo ""
echo "================================================"
echo "  リリース完了"
echo "================================================"
