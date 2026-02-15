import Foundation
import SwiftUI
import KeyboardShortcuts

// MARK: - 録音モード

/// 通常（書き起こしのみ）と Bridge（書き起こし→英語翻訳）を永続トグルで切り替え
enum RecordingMode: String {
    case normal
    case bridge
}

@MainActor
@Observable
final class AppState {

    // MARK: - 状態

    var isRecording = false
    var isProcessing = false
    var isModelLoaded = false
    var statusMessage = "待機中"

    /// 現在の録音モード（UserDefaults で永続化）
    var recordingMode: RecordingMode {
        get {
            RecordingMode(rawValue: UserDefaults.standard.string(forKey: "recordingMode") ?? "normal") ?? .normal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "recordingMode")
        }
    }

    /// 現在のBridgeプリセット
    var currentPreset: BridgePreset {
        get {
            BridgePreset(rawValue: UserDefaults.standard.string(forKey: "defaultPreset") ?? BridgePreset.enChat.rawValue) ?? .enChat
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "defaultPreset")
        }
    }

    /// ストリーミング認識のリアルタイムテキスト（メニューバー・オーバーレイで表示）
    var liveTranscription: String {
        appleSpeechService.partialResult
    }

    /// 現在ストリーミング認識中かどうか（録音開始時に決定、停止時はこれを参照）
    private var isStreaming = false

    /// 直近の Bridge 翻訳タスク（キャンセル伝播用）
    private var currentBridgeTask: Task<Void, Never>?

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
    var useGeminiStyleAdjust: Bool {
        get { UserDefaults.standard.object(forKey: "useGeminiStyleAdjust") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "useGeminiStyleAdjust") }
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
        if recordingMode == .bridge { return "globe" }
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

    // MARK: - モード切替

    /// 通常 ⇔ Bridge モードをトグル
    func toggleBridgeMode() {
        guard !isRecording, !isProcessing else { return }
        recordingMode = (recordingMode == .normal) ? .bridge : .normal
        updateStatus(recordingMode == .bridge
            ? "Bridgeモード: 録音 → 英語翻訳 (\(currentPreset.displayName))"
            : "通常モード: 録音 → 書き起こし")
    }

    // MARK: - 録音トグル

    func toggleRecording() {
        print("[VN] toggleRecording: isRecording=\(isRecording), isProcessing=\(isProcessing)")
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
        // 二重起動ガード
        guard !isRecording, !isProcessing else {
            print("[VN] startRecording: guarded out (isRecording=\(isRecording), isProcessing=\(isProcessing))")
            return
        }

        do {
            let engine = UserDefaults.standard.string(forKey: "recognitionEngine") ?? "whisper"
            print("[VN] startRecording: engine=\(engine)")

            if engine == "apple" {
                // ストリーミングモード: WAVファイル不要
                audioRecorder.writeToFile = false
                audioRecorder.onAudioBuffer = { [weak self] buffer in
                    self?.appleSpeechService.appendBuffer(buffer)
                }
                isStreaming = true

                // ストリーミング認識を開始
                Task {
                    do {
                        try await appleSpeechService.startStreaming()
                    } catch {
                        updateStatus("ストリーミング開始エラー: \(error.localizedDescription)")
                    }
                }
            } else {
                // ファイルベースモード（WhisperKit）
                audioRecorder.writeToFile = true
                audioRecorder.onAudioBuffer = nil
                isStreaming = false
            }

            try audioRecorder.start()
            isRecording = true
            print("[VN] startRecording: success, isRecording=\(isRecording)")
            updateStatus("録音中...")

            // Bridge + ストリーミング時: オーバーレイを録音中モードで即表示
            if recordingMode == .bridge && isStreaming {
                overlayState.liveText = ""
                overlayState.mode = .recording
                showOverlay()
            }

        } catch {
            updateStatus("録音開始エラー: \(error.localizedDescription)")
            isStreaming = false
        }
    }

    private func stopRecording() {
        print("[VN] stopRecording: isStreaming=\(isStreaming), mode=\(recordingMode)")
        isRecording = false
        isProcessing = true
        updateStatus("録音停止、処理開始...")

        let audioURL = audioRecorder.stop()
        let isBridge = (recordingMode == .bridge)

        if isStreaming {
            // ストリーミング: stopStreaming() で最終テキスト取得（audioURL は nil）
            Task {
                do {
                    updateStatus("認識確定中...")
                    let finalText = try await appleSpeechService.stopStreaming()
                    print("[VN] stopRecording: finalText='\(finalText.prefix(50))', isBridge=\(isBridge)")
                    updateStatus(appleSpeechService.loadingProgress)

                    if isBridge {
                        processTextBridge(text: finalText)
                    } else {
                        await processText(text: finalText)
                    }
                } catch {
                    print("[VN] stopRecording: streaming error: \(error)")
                    updateStatus("認識エラー: \(error.localizedDescription)")
                    isProcessing = false
                }
            }
        } else {
            // ファイルベース: audioURL を使って書き起こし
            guard let audioURL else {
                updateStatus("録音データがありません")
                isProcessing = false
                return
            }

            Task {
                if isBridge {
                    await processAudioBridge(audioURL: audioURL)
                } else {
                    await processAudio(audioURL: audioURL)
                }
            }
        }
    }

    // MARK: - 書き起こし共通（ファイルベース用）

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

    // MARK: - v1.0 通常パイプライン（ファイルベース入口）

    private func processAudio(audioURL: URL) async {
        defer {
            isProcessing = false
            AudioRecorderService.cleanup(audioURL)
        }

        do {
            let rawText = try await transcribe(audioURL: audioURL)
            await processTextCommon(text: rawText)
        } catch {
            updateStatus("エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - 通常パイプライン（テキスト入口 — ストリーミング/ファイルベース共通）

    /// ストリーミングまたはファイルベースから書き起こされたテキストを通常パイプラインで処理
    private func processText(text: String) async {
        defer { isProcessing = false }
        await processTextCommon(text: text)
    }

    /// 通常パイプラインの共通処理（voice commands → format → paste → save）
    private func processTextCommon(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateStatus("音声が検出されませんでした")
            return
        }

        // 1. 音声コマンド処理
        let processedText = voiceCommandService.process(text)

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
    }

    // MARK: - Bridge Send パイプライン（ファイルベース入口）

    private func processAudioBridge(audioURL: URL) async {
        defer {
            AudioRecorderService.cleanup(audioURL)
        }

        do {
            updateStatus("書き起こし中...")
            let rawText = try await transcribe(audioURL: audioURL)
            // processTextBridgeCommon 内部のTaskが isProcessing を管理する
            processTextBridgeCommon(text: rawText)
        } catch {
            overlayState.errorMessage = error.localizedDescription
            updateStatus("Bridge Sendエラー: \(error.localizedDescription)")
            isProcessing = false
        }
    }

    // MARK: - Bridge Send パイプライン（テキスト入口 — ストリーミング/ファイルベース共通）

    /// ストリーミングまたはファイルベースから書き起こされたテキストを Bridge パイプラインで処理
    private func processTextBridge(text: String) {
        processTextBridgeCommon(text: text)
    }

    /// Bridge パイプラインの共通処理（format → overlay → bridge send）
    /// Taskを生成して非同期で翻訳を実行。isProcessing の解除はTask内で行う。
    private func processTextBridgeCommon(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateStatus("音声が検出されませんでした")
            isProcessing = false
            return
        }

        // 前の翻訳タスクをキャンセル
        currentBridgeTask?.cancel()

        // 1. 整形（オフラインでフィラー除去のみ）
        let cleaned = offlineFormatter.format(text)

        // 2. オーバーレイにソーステキストを表示
        overlayState.sourceText = cleaned
        overlayState.outputText = ""
        overlayState.errorMessage = nil
        overlayState.mode = .bridgeSend
        overlayState.isTranslating = true
        overlayState.isRefining = false
        overlayState.userHasEdited = false
        showOverlay()

        // 3. Bridge Sendパイプライン実行（2フェーズ: 中間結果→文体調整）
        let preset = currentPreset
        let skipStyle = !useGeminiStyleAdjust

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            do {
                let result = try await self.bridgeSendService.process(
                    cleaned,
                    preset: preset,
                    skipStyleAdjust: skipStyle,
                    onProgress: { [weak self] stage in
                        self?.overlayState.processingStage = stage
                        self?.updateStatus(stage)
                    },
                    onIntermediateResult: { [weak self] intermediateText in
                        guard let self else { return }
                        self.overlayState.outputText = intermediateText
                        self.overlayState.isTranslating = false
                        self.overlayState.processingStage = ""
                        if !skipStyle && self.geminiFormatter != nil {
                            self.overlayState.isRefining = true
                        }
                    }
                )

                // Gemini完了後: ユーザーが編集していなければ差し替え
                if !self.overlayState.userHasEdited {
                    self.overlayState.outputText = result
                }
                self.overlayState.isTranslating = false
                self.overlayState.isRefining = false
                self.overlayState.processingStage = ""
                self.updateStatus("翻訳完了 — オーバーレイで確認してください")

            } catch is CancellationError {
                // キャンセルされた場合は何もしない
            } catch {
                self.overlayState.errorMessage = error.localizedDescription
                self.overlayState.isTranslating = false
                self.overlayState.isRefining = false
                self.overlayState.processingStage = ""
                self.updateStatus("Bridge Sendエラー: \(error.localizedDescription)")
            }
        }

        currentBridgeTask = task
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
                overlayState.errorMessage = nil
                overlayState.mode = .quickTranslate
                overlayState.isTranslating = true
                showOverlay()

                // 3. 翻訳実行
                updateStatus("翻訳中...")
                overlayState.processingStage = "翻訳中..."
                let translated = try await quickTranslateService.translate(selectedText)

                // 4. オーバーレイに結果を表示
                overlayState.outputText = translated
                overlayState.isTranslating = false
                overlayState.processingStage = ""
                updateStatus("翻訳完了")

            } catch {
                overlayState.errorMessage = error.localizedDescription
                overlayState.isTranslating = false
                overlayState.processingStage = ""
                updateStatus("Quick Translate エラー: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 再試行

    /// Bridge Send の再試行（前回のソーステキストから再翻訳）
    func retryBridgeSend() {
        let text = overlayState.sourceText
        guard !text.isEmpty, !isProcessing else { return }
        isProcessing = true
        overlayState.errorMessage = nil
        overlayState.isTranslating = true
        overlayState.isRefining = false
        overlayState.userHasEdited = false
        overlayState.processingStage = ""

        // 前の翻訳タスクをキャンセル
        currentBridgeTask?.cancel()

        let preset = currentPreset
        let skipStyle = !useGeminiStyleAdjust

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            do {
                let result = try await self.bridgeSendService.process(
                    text,
                    preset: preset,
                    skipStyleAdjust: skipStyle,
                    onProgress: { [weak self] stage in
                        self?.overlayState.processingStage = stage
                        self?.updateStatus(stage)
                    },
                    onIntermediateResult: { [weak self] intermediateText in
                        guard let self else { return }
                        self.overlayState.outputText = intermediateText
                        self.overlayState.isTranslating = false
                        self.overlayState.processingStage = ""
                        if !skipStyle && self.geminiFormatter != nil {
                            self.overlayState.isRefining = true
                        }
                    }
                )

                if !self.overlayState.userHasEdited {
                    self.overlayState.outputText = result
                }
                self.overlayState.isTranslating = false
                self.overlayState.isRefining = false
                self.overlayState.processingStage = ""
                self.updateStatus("翻訳完了 — オーバーレイで確認してください")
            } catch is CancellationError {
                // キャンセル
            } catch {
                self.overlayState.errorMessage = error.localizedDescription
                self.overlayState.isTranslating = false
                self.overlayState.isRefining = false
                self.overlayState.processingStage = ""
                self.updateStatus("再試行エラー: \(error.localizedDescription)")
            }
        }

        currentBridgeTask = task
    }

    /// Quick Translate の再試行（前回のソーステキストから再翻訳）
    func retryQuickTranslate() {
        let text = overlayState.sourceText
        guard !text.isEmpty, !isProcessing else { return }
        isProcessing = true
        overlayState.errorMessage = nil
        overlayState.isTranslating = true
        overlayState.processingStage = "翻訳中..."

        Task {
            defer { isProcessing = false }

            do {
                let translated = try await quickTranslateService.translate(text)
                overlayState.outputText = translated
                overlayState.isTranslating = false
                overlayState.processingStage = ""
                updateStatus("翻訳完了")
            } catch {
                overlayState.errorMessage = error.localizedDescription
                overlayState.isTranslating = false
                overlayState.processingStage = ""
                updateStatus("再試行エラー: \(error.localizedDescription)")
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

        KeyboardShortcuts.onKeyUp(for: .toggleBridgeMode) { [weak self] in
            Task { @MainActor in
                self?.toggleBridgeMode()
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
        print("[VN] preloadModel: engine=\(engine)")

        Task {
            if engine == "apple" {
                let authorized = await appleSpeechService.requestAuthorization()
                isModelLoaded = authorized
                print("[VN] preloadModel: apple auth=\(authorized)")
                updateStatus(authorized ? "待機中（Apple音声認識）" : "音声認識の権限がありません")
            } else {
                do {
                    try await whisperService.loadModel()
                    isModelLoaded = true
                    print("[VN] preloadModel: whisper loaded")
                    updateStatus("待機中")
                } catch {
                    print("[VN] preloadModel: whisper error: \(error)")
                    updateStatus("モデル読み込みエラー: \(error.localizedDescription)")
                }
            }

            // 翻訳セッションのウォームアップ（バックグラウンドで）
            print("[VN] preloadModel: starting warmUp (isSessionAvailable=\(translationService.isSessionAvailable), onRequestAdded=\(translationService.onRequestAdded != nil))")
            await translationService.warmUp()
            print("[VN] preloadModel: warmUp done")
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
