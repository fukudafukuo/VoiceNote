import SwiftUI

/// 詳細設定タブ
struct AdvancedSettingsView: View {

    @AppStorage("geminiAPIKey") private var apiKey = ""
    @AppStorage("protectURLs") private var protectURLs = true
    @AppStorage("protectCode") private var protectCode = true
    @AppStorage("protectPaths") private var protectPaths = true
    @AppStorage("protectVersions") private var protectVersions = true
    @AppStorage("protectEmails") private var protectEmails = true
    @AppStorage("protectCommands") private var protectCommands = true

    @State private var showingAPIKey = false
    @State private var apiTestResult = ""

    var body: some View {
        Form {
            Section("トークン保護") {
                Text("翻訳時に以下のトークンをプレースホルダで保護し、翻訳後に復元します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("URL", isOn: $protectURLs)
                Toggle("メールアドレス", isOn: $protectEmails)
                Toggle("コードブロック / インラインコード", isOn: $protectCode)
                Toggle("ファイルパス", isOn: $protectPaths)
                Toggle("コマンド（$で始まる行）", isOn: $protectCommands)
                Toggle("バージョン番号 / Gitハッシュ", isOn: $protectVersions)
            }

            Section("BYO API（Gemini — オプション）") {
                HStack {
                    if showingAPIKey {
                        TextField("APIキー", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("APIキー", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showingAPIKey.toggle()
                    } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    }
                }

                Text("Gemini APIキーを設定すると、長い文章の整形精度が向上し、Bridge Send のプリセット文体調整が利用できます。未設定でもオンデバイス翻訳は動作します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !apiKey.isEmpty {
                    HStack {
                        Button("APIキーをテスト") {
                            testAPIKey()
                        }
                        if !apiTestResult.isEmpty {
                            Text(apiTestResult)
                                .font(.caption)
                                .foregroundStyle(apiTestResult.contains("成功") ? .green : .red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func testAPIKey() {
        apiTestResult = "テスト中..."
        Task {
            let formatter = GeminiFormatter(apiKey: apiKey)
            do {
                _ = try await formatter.format("テスト")
                apiTestResult = "接続成功"
            } catch {
                apiTestResult = "接続失敗"
            }
        }
    }
}
