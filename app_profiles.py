"""VoiceNote - アプリ別プロファイルモジュール"""

import subprocess
import re


# デフォルトのアプリ別プロファイル定義
DEFAULT_PROFILES = {
    # ブラウザ系（Claude, ChatGPT等のAIチャットを想定）
    "Google Chrome": {
        "name": "ブラウザ",
        "format_mode": "auto",  # auto: 内容に応じて自動判定
        "strip_markdown": False,
        "add_trailing_newline": False,
    },
    "Safari": {
        "name": "Safari",
        "format_mode": "auto",
        "strip_markdown": False,
        "add_trailing_newline": False,
    },
    "Arc": {
        "name": "Arc",
        "format_mode": "auto",
        "strip_markdown": False,
        "add_trailing_newline": False,
    },
    "Firefox": {
        "name": "Firefox",
        "format_mode": "auto",
        "strip_markdown": False,
        "add_trailing_newline": False,
    },

    # チャット系（短文・プレーンテキスト向き）
    "Slack": {
        "name": "Slack",
        "format_mode": "plain",  # plain: Markdown記法を使わない
        "strip_markdown": True,  # Markdown記号を除去
        "add_trailing_newline": False,
    },
    "LINE": {
        "name": "LINE",
        "format_mode": "plain",
        "strip_markdown": True,
        "add_trailing_newline": False,
    },
    "Discord": {
        "name": "Discord",
        "format_mode": "auto",  # DiscordはMarkdown対応
        "strip_markdown": False,
        "add_trailing_newline": False,
    },
    "Messages": {
        "name": "メッセージ",
        "format_mode": "plain",
        "strip_markdown": True,
        "add_trailing_newline": False,
    },

    # メール
    "Mail": {
        "name": "メール",
        "format_mode": "plain",
        "strip_markdown": True,
        "add_trailing_newline": True,
    },

    # ノート系（Markdown構造化向き）
    "Notes": {
        "name": "メモ",
        "format_mode": "structured",  # structured: 積極的にMarkdown構造化
        "strip_markdown": False,
        "add_trailing_newline": True,
    },
    "Notion": {
        "name": "Notion",
        "format_mode": "structured",
        "strip_markdown": False,
        "add_trailing_newline": False,
    },
    "Obsidian": {
        "name": "Obsidian",
        "format_mode": "structured",
        "strip_markdown": False,
        "add_trailing_newline": True,
    },

    # エディタ系
    "Code": {
        "name": "VS Code",
        "format_mode": "auto",
        "strip_markdown": False,
        "add_trailing_newline": True,
    },
    "Cursor": {
        "name": "Cursor",
        "format_mode": "auto",
        "strip_markdown": False,
        "add_trailing_newline": True,
    },

    # ターミナル
    "Terminal": {
        "name": "ターミナル",
        "format_mode": "plain",
        "strip_markdown": True,
        "add_trailing_newline": False,
    },
    "iTerm2": {
        "name": "iTerm2",
        "format_mode": "plain",
        "strip_markdown": True,
        "add_trailing_newline": False,
    },
}

# デフォルトプロファイル（未知のアプリ用）
FALLBACK_PROFILE = {
    "name": "デフォルト",
    "format_mode": "auto",
    "strip_markdown": False,
    "add_trailing_newline": False,
}


class AppProfileManager:
    """アクティブアプリの検出とプロファイル管理"""

    def __init__(self, profiles=None, enabled=True):
        """
        Args:
            profiles: カスタムプロファイル辞書（Noneならデフォルト使用）
            enabled: プロファイル機能の有効/無効
        """
        self.enabled = enabled
        self._profiles = dict(DEFAULT_PROFILES)
        if profiles:
            self._profiles.update(profiles)

    def get_active_app(self) -> str:
        """
        現在アクティブな（最前面の）アプリケーション名を取得する。

        Returns:
            アプリ名（例: "Google Chrome", "Slack"）。取得失敗時は空文字列。
        """
        try:
            result = subprocess.run(
                [
                    "osascript", "-e",
                    'tell application "System Events" to get name of first '
                    'application process whose frontmost is true',
                ],
                capture_output=True,
                text=True,
                timeout=2,
            )
            return result.stdout.strip()
        except Exception:
            return ""

    def get_profile(self, app_name: str = None) -> dict:
        """
        指定アプリ（またはアクティブアプリ）のプロファイルを取得する。

        Args:
            app_name: アプリ名。Noneなら自動検出。

        Returns:
            プロファイル辞書
        """
        if not self.enabled:
            return FALLBACK_PROFILE

        if app_name is None:
            app_name = self.get_active_app()

        if not app_name:
            return FALLBACK_PROFILE

        # 完全一致
        if app_name in self._profiles:
            profile = self._profiles[app_name]
            profile["_app_name"] = app_name
            return profile

        # 部分一致（アプリ名にキーワードが含まれる場合）
        app_lower = app_name.lower()
        for key, profile in self._profiles.items():
            if key.lower() in app_lower or app_lower in key.lower():
                profile["_app_name"] = app_name
                return profile

        fallback = dict(FALLBACK_PROFILE)
        fallback["_app_name"] = app_name
        return fallback

    def apply_profile(self, text: str, profile: dict) -> str:
        """
        プロファイルに基づいてテキストを後処理する。

        Args:
            text: 整形済みテキスト
            profile: プロファイル辞書

        Returns:
            プロファイル適用後のテキスト
        """
        if not text:
            return text

        result = text

        # Markdown記号の除去（plain系アプリ向け）
        if profile.get("strip_markdown", False):
            result = self._strip_markdown(result)

        # 末尾改行の追加
        if profile.get("add_trailing_newline", False):
            if not result.endswith("\n"):
                result += "\n"

        return result

    def _strip_markdown(self, text: str) -> str:
        """Markdown記号を除去してプレーンテキストにする"""
        result = text

        # 見出し記号を除去（行頭の#）
        result = re.sub(r"^#{1,6}\s+", "", result, flags=re.MULTILINE)

        # 太字・斜体
        result = re.sub(r"\*\*(.+?)\*\*", r"\1", result)
        result = re.sub(r"\*(.+?)\*", r"\1", result)
        result = re.sub(r"__(.+?)__", r"\1", result)
        result = re.sub(r"_(.+?)_", r"\1", result)

        # インラインコード
        result = re.sub(r"`(.+?)`", r"\1", result)

        # コードブロック
        result = re.sub(r"```[\s\S]*?```", "", result)

        # 箇条書きの記号を除去
        result = re.sub(r"^[\s]*[-*+]\s+", "", result, flags=re.MULTILINE)

        # 番号付きリスト
        result = re.sub(r"^[\s]*\d+\.\s+", "", result, flags=re.MULTILINE)

        # 引用記号
        result = re.sub(r"^>\s+", "", result, flags=re.MULTILINE)

        # 水平線
        result = re.sub(r"^---+$", "", result, flags=re.MULTILINE)

        # 連続する空行を整理
        result = re.sub(r"\n{3,}", "\n\n", result)

        return result.strip()

    def list_profiles(self) -> list:
        """登録済みプロファイル一覧を返す"""
        profiles = []
        for app_name, profile in self._profiles.items():
            profiles.append({
                "app": app_name,
                "name": profile.get("name", app_name),
                "mode": profile.get("format_mode", "auto"),
            })
        return profiles
