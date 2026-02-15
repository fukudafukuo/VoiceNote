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

            // ソーステキスト（上段・読み取り専用）
            sourceSection

            Divider()

            // 出力テキスト（下段・編集可能）
            outputSection

            Divider()

            // アクションボタン
            actionButtons
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(.regularMaterial)
    }

    // MARK: - ヘッダー

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: overlayState.mode == .bridgeSend ? "globe" : "text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(overlayState.mode == .bridgeSend ? "Bridge Send" : "Quick Translate")
                    .font(.headline)
            }

            Spacer()

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

            // 翻訳中インジケータ
            if overlayState.isTranslating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("出力")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if overlayState.isTranslating {
                ProgressView("翻訳中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: Bindable(overlayState).outputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(8)
    }

    // MARK: - アクションボタン

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let error = overlayState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
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
}
