import Foundation
import SwiftUI
import KeyboardShortcuts

@MainActor
@Observable
final class AppState {

    // MARK: - 状態

    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var statusMessage = "待機中"

    /// Bridge Sendのワンショットフラグ（録音停止後にBridgeパイプラインへ流す）
    var bridgeModeOneShot = false

    /// 現在のBridgeプリセット
    var currentPreset: BridgePreset {
        get {
            BridgePreset(rawValue: UserDefaults.standard.string(forKey: "defaultPreset") ?? BridgePreset.enChat.rawValue) ?? .enChat
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "defaultPreset")
        }
    }

    // MARK: - UserDefaults設定

    @ObservationIgnored
    var geminiAPIKey: String {
        get { UserDefaults.standard.string(forKey: "geminiAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "geminiAPIKey") }
    }

    @ObservationIgnored
    var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPaste") }
    }

    @ObservationIgnored
    var saveMarkdown: Bool {
        get { UserDefaults.standard.object(forKey: "saveMarkdown") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "saveMarkdown") }
    }

    @ObservationIgnored
    var voiceCommandsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "voiceCommandsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voiceCommandsEnabled") }
    }

    @ObservationIgnored
    var appProfilesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "appProfilesEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "appProfilesEnabled") }
    }

    @ObservationIgnored
    var outputDirectory: String {
        get {
            UserDefaults.standard.string(forKey: "outputDirectory")
                ?? NSString("~/Documents/VoiceNote").expandingTildeInPath
        }
        set { UserDefaults.standard.set(newValue, forKey: "outputDirectory") }
    }

    // MARK: - v1.0 サービス（既存）

    let audioRecorder = AudioRecorderService()
    let whisperService: WhisperService
    let appleSpeechService = AppleSpeechService()
    let clipboardService = ClipboardService()

    @ObservationIgnored
    lazy var voiceCommandService = VoiceCommandService(enabled: voiceCommandsEnabled)

    @ObservationIgnored
    lazy var appProfileService = AppProfileService(enabled: appProfilesEnabled)

    @ObservationIgnored
    lazy var geminiFormatter: GeminiFormatter? = {
        let key = geminiAPIKey
        guard !key.isEmpty else { return nil }
        return GeminiFormatter(apiKey: key)
    }()

    @ObservationIgnored
    let offlineFormatter = OfflineFormatter()

    @ObservationIgnored
    var hotKeyService: HotKeyService?

    // MARK: - v2.1 サービス（新規）

    let translationService = TranslationService()
    let glossaryService = GlossaryService()
    let overlayState = OverlayState()

    @ObservationIgnored
    lazy var tokenProtectionService = TokenProtectionService()

    @ObservationIgnored
    lazy var bridgeSendService: BridgeSendService = {
        BridgeSendService(
            translationService: translationService,
            glossaryService: glossaryService,
            geminiFormatter: geminiFormatter
        )
    }()

    @ObservationIgnored
    lazy var quickTranslateService: QuickTranslateService = {
        QuickTranslateService(translationService: translationService)
    }()

    /// オーバーレイパネル
    var overlayPanel: OverlayPanel?

    // MARK: - メニューバーアイコン

    var menuBarIcon: String {
        if isRecording { return "record.circle.fill" }
        if isProcessing { return "hourglass" }
        return "mic.fill"
    }

    // MARK: - 初期化

    init() {
        let savedModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "openai_whisper-large-v3_turbo"
        self.whisperService = WhisperService(model: savedModel)

        if saveMarkdown {
            try? FileManager.default.createDirectory(
                atPath: outputDirectory, withIntermediateDirectories: true
            )
        }
    }

    // MARK: - 録音トグル

    func toggleRecording() {
        if isProcessing {
            updateStatus("処理中です。しばらくお待ちください。")
            return
        }

        if !isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private func startRecording() {
        do {
            try audioRecorder.start()
            isRecording = true
            updateStatus("録音中...")
        } catch {
            updateStatus("録音開始エラー: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        isRecording = false
        updateStatus("録音停止、処理開始...")

        guard let audioURL = audioRecorder.stop() else {
            updateStatus("録音データがありません")
            return
        }

        isProcessing = true

        // Bridge Sendモードかどうかでパイプラインを分岐
        let isBridgeMode = bridgeModeOneShot
        bridgeModeOneShot = false

        Task {
            if isBridgeMode {
                await processAudioBridge(audioURL: audioURL)
            } else {
                await processAudio(audioURL: audioURL)
            }
        }
    }

    // MARK: - 書き起こし共通

    /// 音声ファイルを書き起こす（エンジン設定に応じて切り替え）
    private func transcribe(audioURL: URL) async throws -> String {
        let engine = UserDefaults.standard.string(forKey: "recognitionEngine") ?? "whisper"

        if engine == "apple" {
            updateStatus("Apple音声認識中...")
            let text = try await appleSpeechService.transcribe(audioURL: audioURL)
            updateStatus(appleSpeechService.loadingProgress)
            return text
        } else {
            let preferredModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "openai_whisper-large-v3_turbo"
            if preferredModel != whisperService.modelName {
                updateStatus("モデルを切り替え中...")
                whisperService.switchModel(to: preferredModel)
            }
            let text = try await whisperService.transcribe(audioURL: audioURL)
            updateStatus(whisperService.loadingProgress)
            return text
        }
    }

    // MARK: - v1.0 通常パイプライン

    private func processAudio(audioURL: URL) async {
        defer {
            isProcessing = false
            AudioRecorderService.cleanup(audioURL)
        }

        do {
            let rawText = try await transcribe(audioURL: audioURL)

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updateStatus("音声が検出されませんでした")
                return
            }

            // 1. 音声コマンド処理
            let processedText = voiceCommandService.process(rawText)

            // 2. アプリプロファイル取得
            let (profile, appName) = appProfileService.getProfile()
            if !appName.isEmpty {
                updateStatus("出力先: \(profile.name)")
            }

            // 3. テキスト整形（Geminiは長文のみ）
            let formatted: String
            let useGemini = geminiFormatter != nil && processedText.count >= 100

            if useGemini {
                updateStatus("テキストを整形中...")
                do {
                    formatted = try await geminiFormatter!.format(processedText)
                } catch {
                    formatted = offlineFormatter.format(processedText, formatMode: profile.formatMode)
                }
            } else {
                formatted = offlineFormatter.format(processedText, formatMode: profile.formatMode)
            }

            // 4. 句読点変換（常に最後に適用）
            let punctuated = offlineFormatter.normalizePunctuation(formatted)

            let finalText = appProfileService.applyProfile(punctuated, profile: profile)

            clipboardService.copyToClipboard(finalText)

            if autoPaste {
                clipboardService.pasteToActiveApp()
                updateStatus("テキストを入力しました")
            } else {
                updateStatus("クリップボードにコピーしました")
            }

            if saveMarkdown {
                saveMarkdownFile(finalText)
            }

            updateStatus("待機中")

        } catch {
            updateStatus("エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - Bridge Send パイプライン

    /// Bridge Send: 録音 → 書き起こし → 英語翻訳 → オーバーレイ表示
    private func processAudioBridge(audioURL: URL) async {
        defer {
            isProcessing = false
            AudioRecorderService.cleanup(audioURL)
        }

        do {
            // 1. 書き起こし
            updateStatus("書き起こし中...")
            let rawText = try await transcribe(audioURL: audioURL)

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updateStatus("音声が検出されませんでした")
                return
            }

            // 2. 整形（オフラインでフィラー除去のみ）
            let cleaned = offlineFormatter.format(rawText)

            // オーバーレイにソーステキストを表示
            overlayState.sourceText = cleaned
            overlayState.outputText = ""
            overlayState.mode = .bridgeSend
            showOverlay()

            // 3. Bridge Sendパイプライン実行
            updateStatus("翻訳中...")
            let preset = currentPreset
            let result = try await bridgeSendService.process(cleaned, preset: preset)

            // 4. オーバーレイに結果を表示
            overlayState.outputText = result
            updateStatus("翻訳完了 — オーバーレイで確認してください")

        } catch {
            overlayState.outputText = "エラー: \(error.localizedDescription)"
            updateStatus("Bridge Sendエラー: \(error.localizedDescription)")
        }
    }

    /// Bridge Send をワンショットで開始（ショートカットから呼ばれる）
    func startBridgeSend() {
        if isRecording {
            // 録音中ならフラグを立てて停止 → Bridgeパイプラインへ
            bridgeModeOneShot = true
            stopRecording()
        } else if !isProcessing {
            // 未録音なら録音開始 + Bridgeフラグ
            bridgeModeOneShot = true
            startRecording()
        }
    }

    // MARK: - Quick Translate

    /// 選択テキストを取得して翻訳 → オーバーレイ表示
    func performQuickTranslate() {
        guard !isProcessing else { return }
        isProcessing = true

        Task {
            defer { isProcessing = false }

            do {
                // 1. 選択テキスト取得
                updateStatus("テキスト取得中...")
                guard let selectedText = quickTranslateService.getSelectedText(),
                      !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    updateStatus("テキストが選択されていません")
                    return
                }

                // 2. オーバーレイにソーステキストを表示
                overlayState.sourceText = selectedText
                overlayState.outputText = ""
                overlayState.mode = .quickTranslate
                showOverlay()

                // 3. 翻訳実行
                updateStatus("翻訳中...")
                let translated = try await quickTranslateService.translate(selectedText)

                // 4. オーバーレイに結果を表示
                overlayState.outputText = translated
                updateStatus("翻訳完了")

            } catch {
                updateStatus("Quick Translate エラー: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - プリセット切替

    func cyclePreset() {
        currentPreset = currentPreset.next
        updateStatus("プリセット: \(currentPreset.displayName)")
    }

    // MARK: - オーバーレイ管理

    func showOverlay() {
        if overlayPanel == nil {
            let hostView = OverlayContentView(appState: self)
            let hostingView = NSHostingView(rootView: hostView)
            overlayPanel = OverlayPanel(contentView: hostingView)
        }

        let alwaysOnTop = UserDefaults.standard.object(forKey: "overlayAlwaysOnTop") as? Bool ?? true
        overlayPanel?.level = alwaysOnTop ? .floating : .normal

        overlayPanel?.center()
        overlayPanel?.orderFront(nil)
        overlayState.isVisible = true
    }

    func hideOverlay() {
        overlayPanel?.orderOut(nil)
        overlayState.isVisible = false
    }

    func toggleOverlay() {
        if overlayState.isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    /// オーバーレイから確定ペースト
    func confirmPaste() {
        let text = overlayState.outputText
        guard !text.isEmpty else { return }

        hideOverlay()

        // 少し遅延してからペースト（オーバーレイが閉じてからアクティブアプリにフォーカスが戻るのを待つ）
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            clipboardService.copyToClipboard(text)
            clipboardService.pasteToActiveApp()
            updateStatus("テキストを入力しました")
        }
    }

    // MARK: - ショートカット設定

    func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .bridgeSend) { [weak self] in
            Task { @MainActor in
                self?.startBridgeSend()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .quickTranslate) { [weak self] in
            Task { @MainActor in
                self?.performQuickTranslate()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .cyclePreset) { [weak self] in
            Task { @MainActor in
                self?.cyclePreset()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .cycleProject) { [weak self] in
            Task { @MainActor in
                self?.glossaryService.cycleActiveProject()
                let name = self?.glossaryService.activeProject?.name ?? "なし"
                self?.updateStatus("プロジェクト: \(name)")
            }
        }
    }

    // MARK: - ホットキー・モデルプリロード

    func setupHotKey() {
        hotKeyService = HotKeyService { [weak self] in
            self?.toggleRecording()
        }
        _ = hotKeyService?.start()
    }

    func preloadModel() {
        let engine = UserDefaults.standard.string(forKey: "recognitionEngine") ?? "whisper"

        Task {
            if engine == "apple" {
                let authorized = await appleSpeechService.requestAuthorization()
                isModelLoaded = authorized
                updateStatus(authorized ? "待機中（Apple音声認識）" : "音声認識の権限がありません")
            } else {
                do {
                    try await whisperService.loadModel()
                    isModelLoaded = true
                    updateStatus("待機中")
                } catch {
                    updateStatus("モデル読み込みエラー: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - ユーティリティ

    func updateStatus(_ message: String) {
        statusMessage = message
    }

    private func saveMarkdownFile(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = formatter.string(from: Date()) + ".md"
        let filepath = (outputDirectory as NSString).appendingPathComponent(filename)
        try? text.write(toFile: filepath, atomically: true, encoding: .utf8)
    }
}
