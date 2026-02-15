# VoiceNote

macOS メニューバー常駐の音声入力アプリ。ショートカットキー（右⌘×2）で録音 → 書き起こし → アクティブアプリへ自動入力。

## 特徴

- **2つの認識エンジン**: Apple音声認識（高速）/ WhisperKit Large V3 Turbo（高精度）
- **音声コマンド**: 「見出し」「項目」「改行」等の音声でMarkdown記法を入力
- **完全オンデバイス処理**: 音声データは外部に送信されません
- **アプリ別プロファイル**: Slack, VSCode等に応じた出力最適化
- **Gemini API連携**: 長文のフィラー除去・整形（オプション）

## 動作環境

- macOS 14 (Sonoma) 以降
- Apple Silicon (M1/M2/M3/M4) 推奨
- Whisperモード使用時: 約3GBの空き容量（初回モデルダウンロード）

## インストール

DMGファイルを開き、VoiceNote.appをApplicationsフォルダにドラッグしてください。

初回起動時に以下の権限を許可する必要があります：
1. **アクセシビリティ**: システム設定 > プライバシーとセキュリティ > アクセシビリティ
2. **マイク**: 初回録音時に自動表示
3. **音声認識**: Apple音声認識使用時に自動表示

## ビルド（開発者向け）

```bash
# Xcode 15.4+ で開く
open VoiceNote/VoiceNote.xcodeproj

# DMG作成
./scripts/build_dmg.sh
```

### 依存パッケージ

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) v0.9.0+ — オンデバイス音声認識
- Swift Package Manager で自動解決

## プロジェクト構成

```
VoiceNote/
├── VoiceNoteApp.swift              # アプリエントリポイント
├── AppState.swift                  # アプリ状態管理・メイン処理パイプライン
├── Models/
│   ├── AppProfile.swift            # アプリ別プロファイル定義
│   └── VoiceCommand.swift          # 音声コマンド定義
├── Services/
│   ├── AppleSpeechService.swift    # Apple音声認識（SFSpeechRecognizer）
│   ├── WhisperService.swift        # WhisperKit音声認識
│   ├── AudioRecorderService.swift  # AVAudioEngine録音（16kHz mono）
│   ├── ClipboardService.swift      # クリップボード操作・Cmd+Vシミュレーション
│   ├── HotKeyService.swift         # 右⌘×2 ホットキー（CGEventTap）
│   ├── FormatterService.swift      # テキスト整形（Gemini API / オフライン）
│   ├── VoiceCommandService.swift   # 音声コマンド→Markdown変換
│   └── AppProfileService.swift     # アクティブアプリ検出・プロファイル適用
└── Views/
    ├── MenuBarView.swift           # メニューバーUI
    └── SettingsView.swift          # 設定画面（3タブ）
```

## 処理パイプライン

```
録音 → 音声認識(Apple/Whisper) → 音声コマンド処理 → テキスト整形 → 句読点正規化 → アプリプロファイル適用 → ペースト
```

## ライセンス

個人利用

---

開発: underbar.tokyo
