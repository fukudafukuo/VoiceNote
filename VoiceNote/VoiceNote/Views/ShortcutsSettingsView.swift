import SwiftUI
import KeyboardShortcuts

/// ショートカット設定タブ
struct ShortcutsSettingsView: View {

    @AppStorage("rightCmdDoubleTapEnabled") private var rightCmdDoubleTapEnabled = true

    var body: some View {
        Form {
            Section("ショートカット設定") {
                KeyboardShortcuts.Recorder("録音トグル", name: .toggleRecording)
                KeyboardShortcuts.Recorder("Bridge Send", name: .bridgeSend)
                KeyboardShortcuts.Recorder("Quick Translate", name: .quickTranslate)
                KeyboardShortcuts.Recorder("プリセット切替", name: .cyclePreset)
                KeyboardShortcuts.Recorder("オーバーレイ表示/非表示", name: .toggleOverlay)
                KeyboardShortcuts.Recorder("プロジェクト切替", name: .cycleProject)
            }

            Section("右⌘×2 ダブルタップ") {
                Toggle("右⌘ダブルタップで録音トグル", isOn: $rightCmdDoubleTapEnabled)
                Text("KeyboardShortcuts の設定と併用できます。競合する場合はどちらかを無効にしてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("すべてリセット") {
                    KeyboardShortcuts.reset([
                        .toggleRecording,
                        .bridgeSend,
                        .quickTranslate,
                        .cyclePreset,
                        .toggleOverlay,
                        .cycleProject,
                    ])
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
