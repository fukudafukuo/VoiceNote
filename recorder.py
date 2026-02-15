"""VoiceNote - 音声録音モジュール"""

import numpy as np
import sounddevice as sd
import scipy.io.wavfile as wav
import tempfile
import threading
import time
import os


class AudioRecorder:
    """マイクからの音声録音を管理するクラス"""

    def __init__(self, sample_rate=16000, channels=1):
        self.sample_rate = sample_rate
        self.channels = channels
        self._recording = False
        self._frames = []
        self._stream = None
        self._lock = threading.Lock()

    @property
    def is_recording(self) -> bool:
        return self._recording

    def _audio_callback(self, indata, frames, time_info, status):
        """sounddeviceのコールバック。録音中のオーディオデータを蓄積"""
        if status:
            print(f"  [録音] ステータス: {status}")
        if self._recording:
            self._frames.append(indata.copy())

    def start(self):
        """録音を開始"""
        with self._lock:
            if self._recording:
                return
            self._frames = []
            self._recording = True
            self._stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=self.channels,
                dtype="float32",
                callback=self._audio_callback,
            )
            self._stream.start()

    def stop(self) -> str:
        """
        録音を停止し、WAVファイルとして保存。
        戻り値: WAVファイルのパス
        """
        with self._lock:
            if not self._recording:
                return ""
            self._recording = False
            if self._stream:
                self._stream.stop()
                self._stream.close()
                self._stream = None

        if not self._frames:
            return ""

        # numpy配列に結合
        audio_data = np.concatenate(self._frames, axis=0)

        # float32 → int16に変換（WAV保存用）
        audio_int16 = np.clip(audio_data * 32767, -32768, 32767).astype(np.int16)

        # 一時WAVファイルに保存
        tmp = tempfile.NamedTemporaryFile(
            suffix=".wav", prefix="voicenote_", delete=False
        )
        wav.write(tmp.name, self.sample_rate, audio_int16)
        tmp.close()

        duration = len(audio_data) / self.sample_rate
        print(f"  [録音] 完了: {duration:.1f}秒, {tmp.name}")

        return tmp.name

    def get_duration(self) -> float:
        """現在の録音時間（秒）を返す"""
        if not self._frames:
            return 0.0
        total_frames = sum(f.shape[0] for f in self._frames)
        return total_frames / self.sample_rate

    @staticmethod
    def list_devices():
        """利用可能なオーディオデバイスを表示"""
        print(sd.query_devices())

    @staticmethod
    def cleanup(filepath: str):
        """一時ファイルを削除"""
        try:
            if filepath and os.path.exists(filepath):
                os.unlink(filepath)
        except OSError:
            pass
