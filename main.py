"""
VoiceNote - macOS メニューバー音声認識メモアプリ

Usage:
    python main.py            # アプリ起動
    python main.py --setup    # 初期設定
    python main.py --devices  # オーディオデバイス一覧
"""

import rumps
import threading
import os
import sys
import time
from datetime import datetime

from config import load_config, save_config, get_api_key, setup_interactive
from recorder import AudioRecorder
from transcriber import Transcriber
from formatter import Formatter, OfflineFormatter
from voice_commands import VoiceCommandProcessor
from app_profiles import AppProfileManager


class VoiceNoteApp(rumps.App):
    """メニューバー常駐型の音声認識アプリ"""

    ICON_IDLE = "🎙"
    ICON_RECORDING = "🔴"
    ICON_PROCESSING = "⏳"

    def __init__(self):
        super().__init__("VoiceNote", title=self.ICON_IDLE)

        self.config = load_config()
        self.recorder = AudioRecorder(
            sample_rate=self.config.get("sample_rate", 16000)
        )
        self._recording = False
        self._processing = False

        # Whisper（遅延ロード）
        self._transcriber = None
        self._transcriber_loading = False

        # Gemini Formatter
        api_key = get_api_key()
        if api_key:
            self._formatter = Formatter(
                api_key=api_key,
                model=self.config.get("gemini_model", "gemini-2.0-flash"),
            )
        else:
            self._formatter = None
            print("  [注意] Gemini APIキーが未設定です。フィラー除去は簡易モードで動作します。")

        self._offline_formatter = OfflineFormatter()

        # 音声コマンドプロセッサ
        self._voice_cmd = VoiceCommandProcessor(
            enabled=self.config.get("voice_commands_enabled", True)
        )

        # アプリ別プロファイルマネージャ
        self._profile_mgr = AppProfileManager(
            enabled=self.config.get("app_profiles_enabled", True)
        )

        # 出力ディレクトリ準備
        self._output_dir = self.config.get(
            "output_dir", os.path.expanduser("~/Documents/VoiceNote")
        )
        os.makedirs(self._output_dir, exist_ok=True)

        # メニュー構成
        self.record_button = rumps.MenuItem("録音開始 (右⌘×2)", callback=self.toggle_recording)
        self.status_item = rumps.MenuItem("待機中")
        self.status_item.set_callback(None)

        self.menu = [
            self.record_button,
            None,
            self.status_item,
            None,
            rumps.MenuItem("出力フォルダを開く", callback=self.open_output_dir),
            rumps.MenuItem("設定ファイルを開く", callback=self.open_config),
            rumps.MenuItem("モデルを事前読み込み", callback=self.preload_model),
        ]

        # バックグラウンドでモデルを事前ロード
        self._preload_thread = threading.Thread(
            target=self._preload_model_async, daemon=True
        )
        self._preload_thread.start()

        # グローバルキーボードショートカット設定
        self._setup_hotkey()

    def _setup_hotkey(self):
        """右Commandキー2回タップで録音トグルを設定"""
        import time as _time

        self._rcmd_press_time = 0
        self._rcmd_last_tap = 0
        self._rcmd_was_pressed = False
        TAP_THRESHOLD = 0.25       # これより短い押下をタップと判定
        DOUBLE_TAP_INTERVAL = 0.5  # タップ間隔がこれ以内で2回タップ

        try:
            from Quartz import (
                CGEventTapCreate, CGEventGetFlags, CGEventMaskBit,
                CFMachPortCreateRunLoopSource, CFRunLoopGetCurrent,
                CFRunLoopAddSource, CFRunLoopRun, CGEventTapEnable,
                kCGSessionEventTap, kCGHeadInsertEventTap,
                kCGEventTapOptionListenOnly, kCGEventFlagsChanged,
                kCFRunLoopCommonModes,
            )

            CMD_FLAG = 0x00100000        # kCGEventFlagMaskCommand
            RIGHT_CMD_FLAG = 0x00000010  # NX_DEVICERCMDKEYMASK

            def flags_changed_callback(proxy, event_type, event, refcon):
                flags = CGEventGetFlags(event)
                rcmd_pressed = bool(flags & CMD_FLAG) and bool(flags & RIGHT_CMD_FLAG)

                if rcmd_pressed and not self._rcmd_was_pressed:
                    # 右Command押下
                    self._rcmd_press_time = _time.time()

                elif not rcmd_pressed and self._rcmd_was_pressed:
                    # 右Commandリリース
                    now = _time.time()
                    if now - self._rcmd_press_time < TAP_THRESHOLD:
                        # 短い押下 = タップとして判定
                        if now - self._rcmd_last_tap < DOUBLE_TAP_INTERVAL:
                            # ダブルタップ検出！
                            self._rcmd_last_tap = 0
                            self.toggle_recording(None)
                        else:
                            self._rcmd_last_tap = now

                self._rcmd_was_pressed = rcmd_pressed
                return event

            tap = CGEventTapCreate(
                kCGSessionEventTap,
                kCGHeadInsertEventTap,
                kCGEventTapOptionListenOnly,
                CGEventMaskBit(kCGEventFlagsChanged),
                flags_changed_callback,
                None,
            )

            if tap is None:
                print("  [注意] イベントタップを作成できませんでした。")
                print("         アクセシビリティ許可が必要です。")
                return

            run_loop_source = CFMachPortCreateRunLoopSource(None, tap, 0)

            def run_tap():
                loop = CFRunLoopGetCurrent()
                CFRunLoopAddSource(loop, run_loop_source, kCFRunLoopCommonModes)
                CGEventTapEnable(tap, True)
                CFRunLoopRun()

            thread = threading.Thread(target=run_tap, daemon=True)
            thread.start()
            print("  [ショートカット] 右⌘キー2回タップで録音トグル")

        except ImportError:
            print("  [注意] Quartzモジュールが利用できません。")
            print("         pip install pyobjc-framework-Quartz でインストールできます。")
        except Exception as e:
            print(f"  [注意] ショートカット設定エラー: {e}")

    def _preload_model_async(self):
        """バックグラウンドでWhisperモデルを事前ロード"""
        self._transcriber_loading = True
        self._update_status("Whisperモデル読み込み中...")
        try:
            self._transcriber = Transcriber(
                model_size=self.config.get("whisper_model", "large-v3")
            )
            self._transcriber.load_model(on_progress=self._update_status)
            self._update_status("待機中")
        except Exception as e:
            self._update_status(f"モデル読み込みエラー: {e}")
            print(f"  [エラー] Whisperモデル読み込み失敗: {e}")
        finally:
            self._transcriber_loading = False

    def _update_status(self, message: str):
        """ステータス表示を更新"""
        self.status_item.title = message
        print(f"  [{datetime.now().strftime('%H:%M:%S')}] {message}")

    def toggle_recording(self, sender):
        """録音の開始/停止をトグル"""
        if self._processing:
            rumps.notification(
                "VoiceNote", "", "処理中です。しばらくお待ちください。"
            )
            return

        if self._transcriber_loading:
            rumps.notification(
                "VoiceNote", "", "モデルを読み込み中です。しばらくお待ちください。"
            )
            return

        if not self._recording:
            self._start_recording()
        else:
            self._stop_recording()

    def _start_recording(self):
        """録音開始"""
        self._recording = True
        self.title = self.ICON_RECORDING
        self.record_button.title = "録音停止 (右⌘×2)"
        self._update_status("録音中...")
        self.recorder.start()

    def _stop_recording(self):
        """録音停止→処理開始"""
        self._recording = False
        self.title = self.ICON_PROCESSING
        self.record_button.title = "処理中..."
        self._update_status("録音停止、処理開始...")

        audio_path = self.recorder.stop()

        if not audio_path:
            self.title = self.ICON_IDLE
            self.record_button.title = "録音開始 (右⌘×2)"
            self._update_status("録音データがありません")
            return

        # バックグラウンドで処理
        self._processing = True
        thread = threading.Thread(
            target=self._process_audio, args=(audio_path,), daemon=True
        )
        thread.start()

    def _process_audio(self, audio_path: str):
        """音声ファイルを処理（バックグラウンドスレッド）"""
        try:
            # Step 1: Whisper音声認識
            if self._transcriber is None or not self._transcriber.is_loaded:
                self._update_status("Whisperモデルを読み込み中...")
                self._transcriber = Transcriber(
                    model_size=self.config.get("whisper_model", "large-v3")
                )
                self._transcriber.load_model(on_progress=self._update_status)

            raw_text = self._transcriber.transcribe(
                audio_path, on_progress=self._update_status
            )

            if not raw_text.strip():
                self._update_status("音声が検出されませんでした")
                rumps.notification("VoiceNote", "", "音声が検出されませんでした。")
                return

            # Step 1.5: 音声コマンド処理
            processed_text = self._voice_cmd.process(raw_text)

            # Step 2: アクティブアプリのプロファイル取得
            profile = self._profile_mgr.get_profile()
            app_name = profile.get("_app_name", "")
            format_mode = profile.get("format_mode", "auto")
            if app_name:
                self._update_status(f"出力先: {profile.get('name', app_name)}")

            # Step 3: テキスト整形
            # 短いテキスト（100文字未満）はGemini APIをスキップして高速処理
            use_gemini = self._formatter and len(processed_text) >= 100
            if use_gemini:
                formatted_text = self._formatter.format_text(
                    processed_text, on_progress=self._update_status
                )
            else:
                formatted_text = self._offline_formatter.format_text(
                    processed_text,
                    on_progress=self._update_status,
                    format_mode=format_mode,
                )

            # Step 4: プロファイルに基づく後処理
            formatted_text = self._profile_mgr.apply_profile(
                formatted_text, profile
            )

            # Step 5: 出力
            # クリップボードにコピー → アクティブなアプリにペースト
            self._copy_to_clipboard(formatted_text)
            if self.config.get("auto_paste", True):
                self._paste_to_active_app()
                self._update_status("テキストを入力しました")
            else:
                self._update_status("クリップボードにコピーしました")

            # Markdownファイル保存
            saved_path = ""
            if self.config.get("save_markdown", True):
                saved_path = self._save_markdown(formatted_text)

            # 通知
            preview = formatted_text[:80]
            if len(formatted_text) > 80:
                preview += "..."

            rumps.notification(
                "VoiceNote",
                "書き起こし完了",
                preview,
            )

            self._update_status("待機中")

        except Exception as e:
            self._update_status(f"エラー: {e}")
            rumps.notification("VoiceNote", "エラー", str(e)[:100])
            import traceback
            traceback.print_exc()

        finally:
            self._processing = False
            self.title = self.ICON_IDLE
            self.record_button.title = "録音開始 (右⌘×2)"
            # 一時ファイル削除
            AudioRecorder.cleanup(audio_path)

    def _copy_to_clipboard(self, text: str):
        """テキストをクリップボードにコピー"""
        try:
            import pyperclip
            pyperclip.copy(text)
        except ImportError:
            try:
                import subprocess
                process = subprocess.Popen(
                    ["pbcopy"], stdin=subprocess.PIPE,
                )
                process.communicate(text.encode("utf-8"), timeout=5)
            except Exception as e:
                print(f"  [警告] クリップボードコピー失敗: {e}")

    def _paste_to_active_app(self):
        """アクティブなアプリケーションに⌘Vでペースト"""
        import subprocess
        import time as _time

        _time.sleep(0.5)  # アプリにフォーカスが戻るのを待つ
        try:
            result = subprocess.run(
                [
                    "osascript", "-e",
                    'tell application "System Events" to keystroke "v" using command down',
                ],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0:
                print(f"  [警告] ペースト失敗 (code={result.returncode}): {result.stderr.strip()}")
                print("         アクセシビリティ権限を確認してください:")
                print("         システム設定 → プライバシーとセキュリティ → アクセシビリティ → VoiceNote を許可")
        except Exception as e:
            print(f"  [警告] 自動ペースト失敗: {e}")
            print("         クリップボードにはコピー済みです。⌘Vで手動ペーストできます。")

    def _save_markdown(self, text: str) -> str:
        """テキストをMarkdownファイルとして保存"""
        filename = datetime.now().strftime("%Y%m%d_%H%M%S") + ".md"
        filepath = os.path.join(self._output_dir, filename)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  [保存] {filepath}")
        return filepath

    def open_output_dir(self, sender):
        """出力フォルダをFinderで開く"""
        os.system(f'open "{self._output_dir}"')

    def open_config(self, sender):
        """設定ファイルをエディタで開く"""
        from config import CONFIG_FILE, ensure_dirs
        ensure_dirs()
        config = load_config()
        save_config(config)  # 未保存の場合にファイルを生成
        os.system(f'open "{CONFIG_FILE}"')

    def preload_model(self, sender):
        """手動でモデルを事前読み込み"""
        if self._transcriber and self._transcriber.is_loaded:
            rumps.notification("VoiceNote", "", "モデルは既に読み込み済みです。")
            return
        if self._transcriber_loading:
            rumps.notification("VoiceNote", "", "モデルを読み込み中です。")
            return
        thread = threading.Thread(
            target=self._preload_model_async, daemon=True
        )
        thread.start()


def main():
    if "--setup" in sys.argv:
        setup_interactive()
        return

    if "--devices" in sys.argv:
        AudioRecorder.list_devices()
        return

    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        return

    print("=" * 50)
    print("  VoiceNote を起動しています...")
    print("=" * 50)
    print()

    app = VoiceNoteApp()
    app.run()


if __name__ == "__main__":
    main()
