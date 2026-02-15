import SwiftUI

/// オーバーレイの SwiftUI コンテンツ
@MainActor
struct OverlayContentView: View {

    let appState: AppState

    private var overlayState: OverlayState { appState.overlayState }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerSection
            Divider()

            if overlayState.mode == .recording {
                // 録音中: リアルタイム書き起こし表示（表示専用）
                recordingSection
            } else {
                // ソーステキスト（上段・読み取り専用）
                sourceSection
                Divider()
                // 出力テキスト（下段・編集可能）
                outputSection
                Divider()
                // アクションボタン
                actionButtons
            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(.regularMaterial)
    }

    // MARK: - ヘッダー

    private var headerSection: some View {
        HStack {
            // モードアイコン + タイトル
            HStack(spacing: 6) {
                if overlayState.mode == .recording {
                    // 録音中: 赤い脈動ドット
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(pulseOpacity)
                    Text("録音中...")
                        .font(.headline)
                } else {
                    Image(systemName: overlayState.mode == .bridgeSend ? "globe" : "text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(overlayState.mode == .bridgeSend ? "Bridge Send" : "Quick Translate")
                        .font(.headline)
                }
            }

            Spacer()

            // Quick Translate: 言語方向バッジ
            if overlayState.mode == .quickTranslate && !overlayState.sourceText.isEmpty {
                languageDirectionBadge
            }

            // プリセット切替（Bridge Send モードのみ）
            if overlayState.mode == .bridgeSend {
                Picker("", selection: Bindable(overlayState).activePreset) {
                    ForEach(BridgePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            // 処理中インジケータ
            if overlayState.isTranslating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 録音中セクション

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("リアルタイム書き起こし")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView {
                Text(appState.liveTranscription.isEmpty ? "話してください..." : appState.liveTranscription)
                    .foregroundStyle(appState.liveTranscription.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }

            HStack {
                Spacer()
                Button("キャンセル") {
                    appState.hideOverlay()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(8)
    }

    // MARK: - ソーステキスト（上段）

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("入力")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView {
                Text(overlayState.sourceText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
        }
        .padding(8)
        .frame(maxHeight: 120)
    }

    // MARK: - 出力テキスト（下段・編集可能）

    /// カスタムBinding: ユーザー編集を検知
    private var outputBinding: Binding<String> {
        Binding(
            get: { overlayState.outputText },
            set: { newValue in
                overlayState.outputText = newValue
                overlayState.userHasEdited = true
            }
        )
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("出力")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // 処理段階表示
                if overlayState.isTranslating && !overlayState.processingStage.isEmpty {
                    Text(overlayState.processingStage)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            if overlayState.isTranslating {
                VStack(spacing: 8) {
                    ProgressView()
                    if !overlayState.processingStage.isEmpty {
                        Text(overlayState.processingStage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("翻訳中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: outputBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)

                // リファイン中（Gemini文体調整中）: 控えめなインジケータ
                if overlayState.isRefining {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("文体調整中...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(8)
    }

    // MARK: - アクションボタン

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // エラー表示 + 再試行
            if let error = overlayState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Button("再試行") {
                    if overlayState.mode == .bridgeSend {
                        appState.retryBridgeSend()
                    } else if overlayState.mode == .quickTranslate {
                        appState.retryQuickTranslate()
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("キャンセル") {
                appState.hideOverlay()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("コピー") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(overlayState.outputText, forType: .string)
            }

            Button("確定ペースト") {
                appState.confirmPaste()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 言語方向バッジ

    private var languageDirectionBadge: some View {
        HStack(spacing: 4) {
            Text(detectedSourceLanguage)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15))
                .cornerRadius(4)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(targetLanguage)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.15))
                .cornerRadius(4)
        }
    }

    // MARK: - ヘルパー

    /// 脈動アニメーション用の不透明度
    @State private var pulseOpacity: Double = 1.0

    /// 言語判定（簡易: 日本語文字があるかどうか）
    private var detectedSourceLanguage: String {
        let text = overlayState.sourceText
        let hasJapanese = text.range(of: "[\\p{Hiragana}\\p{Katakana}\\p{Han}]", options: .regularExpression) != nil
        return hasJapanese ? "JA" : "EN"
    }

    private var targetLanguage: String {
        return detectedSourceLanguage == "JA" ? "EN" : "JA"
    }
}
