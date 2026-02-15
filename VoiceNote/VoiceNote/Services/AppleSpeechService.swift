import Foundation
import Speech

@Observable
final class AppleSpeechService {

    private(set) var isAuthorized = false
    private(set) var loadingProgress: String = ""

    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

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

    /// 録音済みの音声ファイルを書き起こし
    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        // 権限確認
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

        // オンデバイス認識を優先（高速・オフライン対応）
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
