import SwiftUI

/// Bridge設定タブ
struct BridgeSettingsView: View {

    @AppStorage("defaultPreset") private var defaultPreset = BridgePreset.enChat.rawValue
    @AppStorage("autoShowOverlay") private var autoShowOverlay = true
    @AppStorage("overlayAlwaysOnTop") private var overlayAlwaysOnTop = true

    var body: some View {
        Form {
            Section("Bridge Send") {
                Picker("デフォルトプリセット", selection: $defaultPreset) {
                    ForEach(BridgePreset.allCases) { preset in
                        Text("\(preset.displayName) — \(preset.description)").tag(preset.rawValue)
                    }
                }
                Text("Bridge Send 開始時の初期プリセット。ショートカットやオーバーレイから切替可能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("翻訳") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Apple Translation（オンデバイス）")
                }
                Text("macOS 15 の Apple Translation を使用します。データは端末外に送信されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("オーバーレイ") {
                Toggle("翻訳完了時に自動でオーバーレイを表示", isOn: $autoShowOverlay)
                Toggle("常に最前面に表示", isOn: $overlayAlwaysOnTop)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
