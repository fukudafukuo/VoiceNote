import AVFoundation
import Foundation
import Speech

@Observable
final class AppleSpeechService {

    private(set) var isAuthorized = false
    private(set) var loadingProgress: String = ""

    /// ストリーミング認識中のリアルタイム部分結果（@Observable で UI に自動反映）
    private(set) var partialResult: String = ""

    private let recognizer: SFSpeechRecognizer?

    // ストリーミング認識用
    private var bufferRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var hasResumed = false

    /// appendBuffer をスレッドセーフにするための専用キュー
    private let appendQueue = DispatchQueue(label: "jp.tokyo.underbar.voicenote.speechAppend")

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - 権限

    /// 音声認識の権限をリクエスト
    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        isAuthorized = (status == .authorized)
        return isAuthorized
    }

    // MARK: - バッチ認識（既存・WhisperKit用フォールバック）

    /// 録音済みの音声ファイルを書き起こし
    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        if !isAuthorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                throw AppleSpeechError.notAuthorized
            }
        }

        loadingProgress = "Apple音声認識中..."

        let start = Date()

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
        }

        let text: String = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        loadingProgress = "認識完了 (\(String(format: "%.1f", elapsed))秒, \(text.count)文字)"

        return text
    }

    // MARK: - ストリーミング認識

    /// ストリーミング認識を開始（録音開始時に呼ぶ）
    func startStreaming() async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        if !isAuthorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                throw AppleSpeechError.notAuthorized
            }
        }

        // 前回の状態をクリア
        partialResult = ""
        hasResumed = false
        loadingProgress = "ストリーミング認識中..."

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
        }

        self.bufferRequest = request

        // 認識タスク開始 — partialResult をリアルタイム更新
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                // MainActor で UI 更新
                Task { @MainActor in
                    self.partialResult = text
                }

                if result.isFinal {
                    // isFinal が来たら continuation を解決
                    if !self.hasResumed {
                        self.hasResumed = true
                        self.finalContinuation?.resume(returning: text)
                        self.finalContinuation = nil
                    }
                }
            }

            if let error, !self.hasResumed {
                self.hasResumed = true
                self.finalContinuation?.resume(throwing: error)
                self.finalContinuation = nil
            }
        }
    }

    /// 音声バッファを認識リクエストに追加（AVAudioEngine タップから呼ばれる・スレッドセーフ）
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        appendQueue.async { [weak self] in
            self?.bufferRequest?.append(buffer)
        }
    }

    /// ストリーミング認識を停止し最終結果を返す（録音停止時に呼ぶ）
    /// - 1.5秒タイムアウト: isFinal が来ない場合は partialResult をフォールバックで返す
    func stopStreaming() async throws -> String {
        let start = Date()

        // 音声入力の終了を通知
        bufferRequest?.endAudio()

        // isFinal がすでに来ている場合
        if hasResumed {
            let result = partialResult
            cleanup()
            let elapsed = Date().timeIntervalSince(start)
            loadingProgress = "認識完了 (\(String(format: "%.1f", elapsed))秒, \(result.count)文字)"
            return result
        }

        // isFinal を待つ（1.5秒タイムアウト付き）
        let finalText: String = try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: "")
                return
            }

            self.finalContinuation = continuation

            // タイムアウト: 1.5秒後に partialResult で返す
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                guard !self.hasResumed else { return }
                self.hasResumed = true
                let fallback = await MainActor.run { self.partialResult }
                self.finalContinuation?.resume(returning: fallback)
                self.finalContinuation = nil
                // finish が効かない場合に備えて cancel
                self.recognitionTask?.cancel()
            }
        }

        cleanup()

        let elapsed = Date().timeIntervalSince(start)
        loadingProgress = "認識完了 (\(String(format: "%.1f", elapsed))秒, \(finalText.count)文字)"

        return finalText
    }

    /// ストリーミング状態をクリーンアップ
    private func cleanup() {
        recognitionTask?.finish()
        recognitionTask = nil
        bufferRequest = nil
        finalContinuation = nil
    }
}

enum AppleSpeechError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Apple音声認識が利用できません。システム設定 > キーボード > 音声入力で日本語を有効にしてください。"
        case .notAuthorized:
            return "音声認識の許可がありません。システム設定 > プライバシーとセキュリティ > 音声認識で許可してください。"
        }
    }
}
