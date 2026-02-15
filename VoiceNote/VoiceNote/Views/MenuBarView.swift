import SwiftUI

@MainActor
struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // MARK: - 録音

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

            Divider()

            // MARK: - Bridge Send

            Button {
                appState.startBridgeSend()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle")
                    Text("Bridge Send")
                }
            }
            .disabled(appState.isProcessing)

            // MARK: - プリセット切替

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

    private var buttonTitle: String {
        if appState.isProcessing { return "処理中..." }
        if appState.isRecording { return "録音停止 (右⌘×2)" }
        return "録音開始 (右⌘×2)"
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
