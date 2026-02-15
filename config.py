"""VoiceNote - 設定管理モジュール"""

import json
import os
import sys

CONFIG_DIR = os.path.expanduser("~/.voicenote")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
DEFAULT_OUTPUT_DIR = os.path.expanduser("~/Documents/VoiceNote")

DEFAULT_CONFIG = {
    "gemini_api_key": "",
    "gemini_model": "gemini-2.0-flash",
    "whisper_model": "kotoba-tech/kotoba-whisper-v2.0-faster",
    "output_dir": DEFAULT_OUTPUT_DIR,
    "auto_copy_clipboard": True,
    "auto_paste": True,
    "save_markdown": True,
    "sample_rate": 16000,
    "silence_threshold": 0.01,
    "silence_duration": 3.0,
    "voice_commands_enabled": True,
    "app_profiles_enabled": True,
}


def ensure_dirs():
    """設定ディレクトリと出力ディレクトリを作成"""
    os.makedirs(CONFIG_DIR, exist_ok=True)


def load_config() -> dict:
    """設定ファイルを読み込む。存在しない場合やパースエラー時はデフォルト設定を返す"""
    ensure_dirs()
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
            config = DEFAULT_CONFIG.copy()
            config.update(saved)
            return config
        except (json.JSONDecodeError, ValueError) as e:
            print(f"  [警告] 設定ファイルの読み込みに失敗しました: {e}")
            print(f"         デフォルト設定を使用します。")
    return DEFAULT_CONFIG.copy()


def save_config(config: dict):
    """設定をファイルに保存"""
    ensure_dirs()
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def get_api_key() -> str:
    """Gemini APIキーを取得"""
    config = load_config()
    key = config.get("gemini_api_key", "")
    if not key:
        key = os.environ.get("GEMINI_API_KEY", "")
    return key


def setup_interactive():
    """対話的にAPIキーを設定"""
    config = load_config()

    print("=" * 50)
    print("  VoiceNote 初期設定")
    print("=" * 50)
    print()

    # Gemini APIキー
    current_key = config.get("gemini_api_key", "")
    if current_key:
        masked = current_key[:8] + "..." + current_key[-4:]
        print(f"  現在のAPIキー: {masked}")
    else:
        print("  APIキー: 未設定")

    new_key = input("\n  Gemini APIキーを入力 (スキップ: Enter): ").strip()
    if new_key:
        config["gemini_api_key"] = new_key

    # Whisperモデル
    print(f"\n  現在のWhisperモデル: {config.get('whisper_model', 'kotoba-tech/kotoba-whisper-v2.0-faster')}")
    print("  選択肢:")
    print("    1. kotoba-tech/kotoba-whisper-v2.0-faster  (推奨: 日本語最高精度、高速、~1.5GB)")
    print("    2. kotoba-tech/kotoba-whisper-v2.2-faster  (v2.0 + 話者分離・自動句読点)")
    print("    3. large-v3                                (汎用最高精度、~3GB)")
    print("    4. large-v3-turbo                          (large-v3の高速版、~2GB)")
    print("    5. small                                   (軽量、~462MB)")
    model_map = {
        "1": "kotoba-tech/kotoba-whisper-v2.0-faster",
        "2": "kotoba-tech/kotoba-whisper-v2.2-faster",
        "3": "large-v3",
        "4": "large-v3-turbo",
        "5": "small",
    }
    choice = input("  番号で選択 (スキップ: Enter): ").strip()
    if choice in model_map:
        config["whisper_model"] = model_map[choice]

    # 出力ディレクトリ
    print(f"\n  現在の出力先: {config.get('output_dir', DEFAULT_OUTPUT_DIR)}")
    out_dir = input("  出力ディレクトリ (スキップ: Enter): ").strip()
    if out_dir:
        config["output_dir"] = os.path.expanduser(out_dir)

    save_config(config)
    print(f"\n  設定を保存しました: {CONFIG_FILE}")
    print("  `python main.py` で起動できます。")


if __name__ == "__main__":
    setup_interactive()
