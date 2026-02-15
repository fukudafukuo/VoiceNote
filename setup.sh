#!/bin/bash
# VoiceNote セットアップスクリプト

set -e

echo "=============================="
echo "  VoiceNote セットアップ"
echo "=============================="
echo

# Python 3 チェック
if ! command -v python3 &> /dev/null; then
    echo "エラー: Python 3 がインストールされていません。"
    echo "  brew install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Python: $PYTHON_VERSION"

# PortAudio チェック（sounddeviceに必要）
if ! brew list portaudio &> /dev/null 2>&1; then
    echo
    echo "PortAudio をインストールしています..."
    brew install portaudio
fi

# 仮想環境の作成
VENV_DIR="$HOME/.voicenote/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo
    echo "仮想環境を作成しています..."
    python3 -m venv "$VENV_DIR"
fi

# 仮想環境を有効化
source "$VENV_DIR/bin/activate"

# 依存パッケージのインストール
echo
echo "依存パッケージをインストールしています..."
pip install --upgrade pip
pip install -r requirements.txt

# 出力ディレクトリの作成
mkdir -p "$HOME/Documents/VoiceNote"

# 初期設定
echo
python main.py --setup

echo
echo "=============================="
echo "  セットアップ完了"
echo "=============================="
echo
echo "起動方法:"
echo "  source $VENV_DIR/bin/activate"
echo "  python main.py"
echo
echo "または以下のエイリアスを ~/.zshrc に追加:"
echo "  alias voicenote='source $VENV_DIR/bin/activate && python $(pwd)/main.py'"
