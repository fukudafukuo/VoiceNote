"""VoiceNote - 音声認識モジュール (faster-whisper)"""

import os
import sys
import time


class Transcriber:
    """faster-whisperによるローカル音声認識"""

    # HuggingFace モデルID → CTranslate2変換済みモデル
    KNOWN_MODELS = {
        "kotoba-tech/kotoba-whisper-v2.0-faster": {
            "desc": "日本語最高精度・高速（推奨）",
            "size": "~1.5GB",
        },
        "kotoba-tech/kotoba-whisper-v2.2-faster": {
            "desc": "v2.0 + 話者分離・自動句読点",
            "size": "~1.5GB",
        },
        "kotoba-tech/kotoba-whisper-v1.0-faster": {
            "desc": "日本語特化（初期版）",
            "size": "~1.5GB",
        },
        "large-v3": {
            "desc": "OpenAI汎用最高精度",
            "size": "~3GB",
        },
        "large-v3-turbo": {
            "desc": "large-v3の高速版",
            "size": "~2GB",
        },
    }

    def __init__(
        self,
        model_size="kotoba-tech/kotoba-whisper-v2.0-faster",
        device="cpu",
        compute_type="int8",
    ):
        """
        Args:
            model_size: Whisperモデル名またはHuggingFace ID
                - "kotoba-tech/kotoba-whisper-v2.0-faster" : 日本語最高精度・高速（推奨）
                - "kotoba-tech/kotoba-whisper-v2.2-faster" : 話者分離・自動句読点対応
                - "large-v3"       : OpenAI汎用最高精度（約3GB）
                - "large-v3-turbo" : large-v3の高速版（約2GB）
                - "small"          : 軽量（約462MB）
            device: "cpu" or "cuda" (Apple SiliconではCPU推奨)
            compute_type: "int8" (高速) or "float16" or "float32"
        """
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self._model = None

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def load_model(self, on_progress=None):
        """
        モデルをロード（初回はダウンロードが発生）。
        on_progress: 進捗通知用コールバック (message: str) -> None
        """
        from faster_whisper import WhisperModel

        if on_progress:
            on_progress(f"Whisperモデル ({self.model_size}) を読み込み中...")

        start = time.time()
        self._model = WhisperModel(
            self.model_size,
            device=self.device,
            compute_type=self.compute_type,
        )
        elapsed = time.time() - start

        if on_progress:
            on_progress(f"モデル読み込み完了 ({elapsed:.1f}秒)")

    def transcribe(self, audio_path: str, on_progress=None) -> str:
        """
        音声ファイルを書き起こし。

        Args:
            audio_path: WAVファイルのパス
            on_progress: 進捗通知用コールバック

        Returns:
            書き起こしテキスト（生テキスト、整形前）
        """
        if not self._model:
            self.load_model(on_progress)

        if on_progress:
            on_progress("音声を認識中...")

        start = time.time()

        segments, info = self._model.transcribe(
            audio_path,
            language="ja",
            vad_filter=True,
            vad_parameters=dict(
                min_silence_duration_ms=500,
                speech_pad_ms=200,
            ),
            beam_size=1,
            condition_on_previous_text=False,
        )

        # セグメントを結合
        texts = []
        for segment in segments:
            texts.append(segment.text.strip())

        elapsed = time.time() - start
        result = "\n".join(texts)

        if on_progress:
            on_progress(f"認識完了 ({elapsed:.1f}秒, {len(result)}文字)")

        return result

    def transcribe_streaming(self, audio_path: str):
        """
        セグメント単位でストリーミング的に結果を返すジェネレータ。
        リアルタイム表示用。
        """
        if not self._model:
            self.load_model()

        segments, info = self._model.transcribe(
            audio_path,
            language="ja",
            vad_filter=False,
            beam_size=5,
        )

        for segment in segments:
            yield {
                "start": segment.start,
                "end": segment.end,
                "text": segment.text.strip(),
            }
