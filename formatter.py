"""VoiceNote - テキスト整形モジュール (Gemini API)"""

import time
import threading

SYSTEM_PROMPT = """\
あなたは日本語の音声書き起こしテキストを整形する専門家です。
整形されたテキストはAIチャット（Claude等）への入力として使用されます。

## 最重要ルール
- **話者が述べた内容は一切省略・要約・削除しない**
- フィラー（えー、うーん等）と明らかな言い直しのみ除去する
- それ以外の情報はすべて残す

## フィラー除去対象
えー、えーと、えっと、あー、あのー、あの、うーん、うん、まぁ、まあ、
そのー、なんか、なんていうか、ほら、ね、さ、同じ言葉の繰り返し（言い直し）

## 文章の整形
- 話し言葉のままで問題ない部分はそのまま残す
- 過度に書き言葉に変換しない
- 話者の意図やニュアンスを維持する

## 内容に応じた整形レベル

**短い発話・会話・簡単な質問や依頼:**
- フィラー除去のみ
- Markdown記法は使わない

**要件定義・タスク指示（複数の条件、仕様、手順を含む内容）:**
- 見出し（##）で話題を区切る
- 条件や要件を箇条書き（-）で整理する
- 技術用語、ファイル名、コマンドは `バッククォート` で囲む

**複数話題の説明:**
- 話題ごとに段落を分ける
- 必要に応じて見出しや箇条書きを使う

## 出力形式
- 余計なメタ情報（「以下は整形結果です」等）は付けない
- 整形後のテキストのみを返す
"""


class Formatter:
    """Gemini APIによるテキスト整形"""

    def __init__(self, api_key: str, model: str = "gemini-2.0-flash-lite"):
        """
        Args:
            api_key: Gemini APIキー
            model: 使用するモデル名
        """
        self.api_key = api_key
        self.model = model
        self._client = None
        self._client_lock = threading.Lock()

    def _get_client(self):
        """Geminiクライアントを遅延初期化（スレッドセーフ）"""
        if self._client is None:
            with self._client_lock:
                if self._client is None:
                    from google import genai

                    self._client = genai.Client(api_key=self.api_key)
        return self._client

    def format_text(self, raw_text: str, on_progress=None) -> str:
        """
        生の書き起こしテキストを整形。

        Args:
            raw_text: Whisperが出力した生テキスト
            on_progress: 進捗コールバック

        Returns:
            整形済みMarkdownテキスト
        """
        if not raw_text.strip():
            return ""

        if on_progress:
            on_progress("テキストを整形中...")

        start = time.time()
        client = self._get_client()

        user_prompt = f"以下の音声書き起こしテキストを整形してください。\n\n{raw_text}"

        try:
            from google.genai import types

            response = client.models.generate_content(
                model=self.model,
                contents=user_prompt,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    temperature=0.3,
                    max_output_tokens=4096,
                ),
            )
            result = response.text.strip() if response.text else raw_text
        except ImportError:
            # google-genai SDKが古い場合のフォールバック
            try:
                response = client.models.generate_content(
                    model=self.model,
                    contents=f"{SYSTEM_PROMPT}\n\n{user_prompt}",
                )
                result = response.text.strip() if response.text else raw_text
            except Exception as e:
                if on_progress:
                    on_progress(f"Gemini API エラー: {e}")
                result = raw_text
        except Exception as e:
            if on_progress:
                on_progress(f"Gemini API エラー: {e}")
            # APIエラー時は生テキストをそのまま返す
            result = raw_text

        elapsed = time.time() - start
        if on_progress:
            on_progress(f"整形完了 ({elapsed:.1f}秒)")

        return result


class OfflineFormatter:
    """オフライン時のフォールバック: フィラー除去 + 基本的な句読点整形"""

    FILLERS = [
        "えーと", "えっと", "えー", "あのー", "あの",
        "うーん", "うん", "まぁ", "まあ", "そのー",
        "なんか", "なんていうか", "ほら",
        "あー", "んー", "んと",
    ]

    def format_text(self, raw_text: str, on_progress=None, format_mode="auto") -> str:
        """
        フィラー除去と基本的な整形（正規表現ベース）。

        Args:
            raw_text: 生テキスト
            on_progress: 進捗コールバック
            format_mode: 整形モード ("auto", "plain", "structured")
        """
        import re

        if on_progress:
            on_progress("テキストを整形中（オフライン）...")

        text = raw_text
        for filler in sorted(self.FILLERS, key=len, reverse=True):
            pattern = rf"(?:^|(?<=\s)){re.escape(filler)}(?:\s*|(?=、|。))"
            text = re.sub(pattern, "", text)

        # 連続するスペースを整理
        text = re.sub(r"[ 　]+", " ", text)
        # 空の文を除去
        text = re.sub(r"\n\s*\n\s*\n", "\n\n", text)

        if on_progress:
            on_progress("整形完了（オフライン）")

        return text.strip()
