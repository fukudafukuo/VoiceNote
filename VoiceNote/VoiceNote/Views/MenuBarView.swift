import SwiftUI

@MainActor
struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // MARK: - モード表示（常時表示）

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.recordingMode == .bridge ? Color.blue : Color.green)
                    .frame(width: 8, height: 8)
                Text(modeDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            // MARK: - 録音ボタン

            Button {
                appState.toggleRecording()
            } label: {
                HStack {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(appState.isRecording ? .red : .primary)
                    Text(buttonTitle)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.isProcessing)

            // MARK: - リアルタイム書き起こし（録音中+ストリーミング時のみ）

            if appState.isRecording && !appState.liveTranscription.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(appState.liveTranscription)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(.vertical, 2)
            }

            Divider()

            // MARK: - モード切替

            Button {
                appState.toggleBridgeMode()
            } label: {
                HStack {
                    Image(systemName: appState.recordingMode == .bridge
                        ? "arrow.right.circle.fill" : "arrow.right.circle")
                    Text(appState.recordingMode == .bridge ? "通常モードに戻す" : "Bridgeモードに切替")
                }
            }
            .disabled(appState.isRecording || appState.isProcessing)

            // MARK: - プリセット（Bridgeモード時のみ）

            if appState.recordingMode == .bridge {
                Menu {
                    ForEach(BridgePreset.allCases) { preset in
                        Button {
                            appState.currentPreset = preset
                        } label: {
                            HStack {
                                Text(preset.displayName)
                                if preset == appState.currentPreset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("プリセット: \(appState.currentPreset.displayName)")
                    }
                }
            }

            Divider()

            // MARK: - Quick Translate

            Button {
                appState.performQuickTranslate()
            } label: {
                HStack {
                    Image(systemName: "translate")
                    Text("Quick Translate")
                }
            }
            .disabled(appState.isProcessing)

            Divider()

            // MARK: - オーバーレイ・用語集

            Button {
                appState.toggleOverlay()
            } label: {
                HStack {
                    Image(systemName: appState.overlayState.isVisible ? "eye.slash" : "eye")
                    Text(appState.overlayState.isVisible ? "オーバーレイを隠す" : "オーバーレイを表示")
                }
            }

            if let project = appState.glossaryService.activeProject {
                Menu {
                    ForEach(appState.glossaryService.projects) { p in
                        Button {
                            appState.glossaryService.setActive(projectId: p.id)
                        } label: {
                            HStack {
                                Text(p.name)
                                if p.isActive {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "book")
                        Text("用語集: \(project.name)")
                    }
                }
            }

            Divider()

            // MARK: - ステータス

            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if appState.isRecording {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                    Text(formattedDuration)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // MARK: - ユーティリティ

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: appState.outputDirectory))
            } label: {
                HStack {
                    Image(systemName: "folder")
                    Text("出力フォルダを開く")
                }
            }

            SettingsLink {
                HStack {
                    Image(systemName: "gear")
                    Text("設定...")
                }
            }

            if !appState.isModelLoaded {
                Button {
                    appState.preloadModel()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("モデルを事前読み込み")
                    }
                }
                .disabled(appState.whisperService.isLoading)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("終了")
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(4)
    }

    // MARK: - Computed Properties

    private var modeDisplayText: String {
        switch appState.recordingMode {
        case .normal:
            return "通常モード"
        case .bridge:
            return "Bridgeモード (\(appState.currentPreset.displayName))"
        }
    }

    private var buttonTitle: String {
        if appState.isProcessing { return "処理中..." }
        if appState.isRecording { return "録音停止 (右⌘×2)" }
        return appState.recordingMode == .bridge
            ? "録音開始 → 英語翻訳"
            : "録音開始 (右⌘×2)"
    }

    private var statusIcon: String {
        if appState.isRecording { return "circle.fill" }
        if appState.isProcessing { return "hourglass" }
        if appState.isModelLoaded { return "checkmark.circle.fill" }
        return "circle"
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isProcessing { return .orange }
        if appState.isModelLoaded { return .green }
        return .secondary
    }

    private var formattedDuration: String {
        let seconds = Int(appState.audioRecorder.duration)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
