import SwiftUI

struct SettingsView: View {

    let appState: AppState

    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("saveMarkdown") private var saveMarkdown = true
    @AppStorage("voiceCommandsEnabled") private var voiceCommandsEnabled = true
    @AppStorage("appProfilesEnabled") private var appProfilesEnabled = true
    @AppStorage("outputDirectory") private var outputDirectory = NSString("~/Documents/VoiceNote").expandingTildeInPath
    @AppStorage("recognitionEngine") private var recognitionEngine = "whisper"

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("一般", systemImage: "gear")
                }

            BridgeSettingsView()
                .tabItem {
                    Label("Bridge", systemImage: "arrow.left.arrow.right")
                }

            GlossarySettingsView(glossaryService: appState.glossaryService)
                .tabItem {
                    Label("用語集", systemImage: "book")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("ショートカット", systemImage: "command")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("詳細", systemImage: "gearshape.2")
                }
        }
        .frame(width: 560, height: 460)
    }

    // MARK: - 一般タブ

    private var generalTab: some View {
        Form {
            Section("認識エンジン") {
                Picker("エンジン", selection: $recognitionEngine) {
                    Text("Apple（高速）").tag("apple")
                    Text("Whisper（高精度）").tag("whisper")
                }
                .pickerStyle(.radioGroup)

                Text(recognitionEngine == "apple"
                    ? "macOS内蔵の音声認識を使用します。高速ですが、専門用語や英単語混じりの認識はWhisperに劣る場合があります。"
                    : "WhisperKit (Large V3 Turbo) を使用します。高精度ですが、認識に時間がかかります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("出力") {
                HStack {
                    TextField("出力ディレクトリ", text: $outputDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button("選択...") {
                        selectOutputDirectory()
                    }
                }

                Toggle("Markdownファイルを保存", isOn: $saveMarkdown)
            }

            Section("入力") {
                Toggle("自動ペースト", isOn: $autoPaste)
                    .help("書き起こし完了後、アクティブなアプリに自動でペーストします")
            }

            Section("機能") {
                Toggle("音声コマンドを有効にする", isOn: $voiceCommandsEnabled)
                Toggle("アプリ別プロファイルを有効にする", isOn: $appProfilesEnabled)
            }

            Section("情報") {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text("2.1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "選択"

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url.path
        }
    }
}
