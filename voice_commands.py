"""VoiceNote - 音声コマンド検出・変換モジュール"""

import re


class VoiceCommandProcessor:
    """Whisper出力テキスト内の音声コマンドを検出し、対応する記法に変換する"""

    # 音声コマンド定義: (検出パターン, 置換処理)
    # 優先度順（長いパターンから先にマッチ）
    COMMANDS = [
        # 段落・改行
        ("新しい段落", "\n\n"),
        ("段落変えて", "\n\n"),
        ("段落変え", "\n\n"),
        ("改行して", "\n"),
        ("改行", "\n"),

        # 見出し
        ("大見出し", "\n\n# "),
        ("見出し3", "\n\n### "),
        ("見出し2", "\n\n## "),
        ("見出し1", "\n\n# "),
        ("見出し", "\n\n## "),
        ("小見出し", "\n\n### "),

        # 箇条書き
        ("箇条書き開始", "\n\n"),
        ("次の項目", "\n- "),
        ("項目", "\n- "),
        ("リスト", "\n- "),

        # コードブロック
        ("コードブロック開始", "\n```\n"),
        ("コードブロック終了", "\n```\n"),
        ("コード開始", "\n```\n"),
        ("コード終了", "\n```\n"),
        ("インラインコード", "`"),

        # 強調
        ("太字開始", "**"),
        ("太字終了", "**"),
        ("太字", "**"),
        ("斜体開始", "*"),
        ("斜体終了", "*"),

        # 区切り
        ("水平線", "\n\n---\n\n"),
        ("区切り線", "\n\n---\n\n"),

        # 引用
        ("引用開始", "\n\n> "),
        ("引用", "\n> "),
    ]

    def __init__(self, enabled=True, custom_commands=None):
        """
        Args:
            enabled: 音声コマンド機能の有効/無効
            custom_commands: ユーザー定義の追加コマンド [(パターン, 置換), ...]
        """
        self.enabled = enabled
        self._commands = list(self.COMMANDS)
        if custom_commands:
            self._commands = custom_commands + self._commands
        # パターンの長さ順でソート（長い方を先にマッチ）
        self._commands.sort(key=lambda x: len(x[0]), reverse=True)
        # 正規表現パターンをコンパイル
        self._patterns = []
        for cmd_text, replacement in self._commands:
            # コマンドの前後に句読点・スペース・文頭文末を許容
            pattern = re.compile(
                rf"(?:^|(?<=[\s、。，．,.\n]))({re.escape(cmd_text)})(?:[\s、。，．,.\n]|$)",
                re.MULTILINE,
            )
            self._patterns.append((pattern, cmd_text, replacement))

    def process(self, text: str) -> str:
        """
        テキスト内の音声コマンドを検出し、対応する記法に変換する。

        Args:
            text: Whisperの出力テキスト

        Returns:
            音声コマンドが変換されたテキスト
        """
        if not self.enabled or not text:
            return text

        result = text
        for pattern, cmd_text, replacement in self._patterns:
            result = pattern.sub(replacement, result)

        # 整形: 連続する空行を最大2つに
        result = re.sub(r"\n{3,}", "\n\n", result)
        # 先頭の改行を除去
        result = result.lstrip("\n")
        # 末尾の余分な空白を除去
        result = result.rstrip()

        return result

    def has_commands(self, text: str) -> bool:
        """テキスト内に音声コマンドが含まれているかチェック"""
        if not self.enabled or not text:
            return False
        for pattern, _, _ in self._patterns:
            if pattern.search(text):
                return True
        return False

    def list_commands(self) -> list:
        """利用可能なコマンド一覧を返す"""
        seen = set()
        commands = []
        for cmd_text, replacement in self._commands:
            if cmd_text not in seen:
                seen.add(cmd_text)
                # 表示用にreplacementを説明テキストに変換
                desc = replacement.replace("\n\n", "段落区切り")
                desc = desc.replace("\n", "改行")
                desc = desc.replace("```", "コードブロック")
                desc = desc.replace("**", "太字")
                desc = desc.replace("*", "斜体")
                desc = desc.replace("# ", "見出し")
                desc = desc.replace("- ", "箇条書き")
                desc = desc.replace("> ", "引用")
                desc = desc.replace("---", "水平線")
                desc = desc.replace("`", "コード")
                commands.append({"command": cmd_text, "description": desc.strip()})
        return commands
