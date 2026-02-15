"""
VoiceNote - py2app ビルド設定

使い方:
    # 開発テスト（エイリアスモード）
    python setup.py py2app -A

    # 配布用ビルド
    python setup.py py2app

    # クリーンビルド
    rm -rf build/ dist/ && python setup.py py2app
"""

import os
import sys
from setuptools import setup

# py2app の modulegraph が numpy/scipy 等の巨大パッケージで
# 再帰上限に達するため引き上げ
sys.setrecursionlimit(10000)

# バージョン管理
VERSION = "1.0.0"

# py2app の Info.plist 設定
plist_dict = {
    # アプリ基本情報
    "CFBundleName": "VoiceNote",
    "CFBundleDisplayName": "VoiceNote",
    "CFBundleIdentifier": "com.voicenote.app",
    "CFBundleVersion": VERSION,
    "CFBundleShortVersionString": VERSION,
    "NSHumanReadableCopyright": "Copyright 2025. All rights reserved.",

    # メニューバー専用（Dockに表示しない）
    "LSUIElement": True,
    "LSBackgroundOnly": False,

    # macOS 14 Sonoma 以降
    "LSMinimumSystemVersion": "14.0",

    # マイク権限（ユーザーにダイアログを表示）
    "NSMicrophoneUsageDescription":
        "VoiceNoteは音声を録音して文字起こしするためにマイクへのアクセスが必要です。",

    # カテゴリ
    "LSApplicationCategoryType": "public.app-category.productivity",
}

# py2app ビルドオプション
py2app_options = {
    "argv_emulation": False,
    "plist": plist_dict,
    "packages": [
        "rumps",
        "sounddevice",
        "numpy",
        "scipy",
        "faster_whisper",
        "ctranslate2",
        "huggingface_hub",
        "tokenizers",
        "pyperclip",
    ],
    "includes": [
        "config",
        "recorder",
        "transcriber",
        "formatter",
        "voice_commands",
        "app_profiles",
        "google.genai",
        "google.genai.types",
    ],
    "excludes": [
        "tkinter",
        "pip",
        "ensurepip",
    ],
    "resources": [],
    "iconfile": None,  # TODO: アイコンファイル (VoiceNote.icns) を追加
}

# PortAudio dylib の自動検出・同梱
def find_portaudio():
    """Homebrew の PortAudio dylib パスを探す"""
    candidates = [
        "/opt/homebrew/lib/libportaudio.dylib",       # Apple Silicon Homebrew
        "/opt/homebrew/lib/libportaudio.2.dylib",
        "/usr/local/lib/libportaudio.dylib",           # Intel Homebrew
        "/usr/local/lib/libportaudio.2.dylib",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None

portaudio = find_portaudio()
if portaudio:
    py2app_options["frameworks"] = [portaudio]
    print(f"  [PortAudio] {portaudio} を同梱します")
else:
    print("  [警告] PortAudio が見つかりません。sounddevice が動作しない可能性があります。")
    print("         brew install portaudio でインストールしてください。")

setup(
    name="VoiceNote",
    version=VERSION,
    description="macOS メニューバー音声認識メモアプリ",
    author="VoiceNote",
    app=["main.py"],
    data_files=[],
    options={"py2app": py2app_options},
    setup_requires=["py2app"],
)
