import Foundation
import WhisperKit

@Observable
final class WhisperService {

    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress: String = ""

    private var whisperKit: WhisperKit?
    private(set) var modelName: String
    private var loadingTask: Task<Void, Error>?

    init(model: String = "openai_whisper-large-v3_turbo") {
        self.modelName = model
    }

    /// モデルを切り替える（次回のtranscribe時に自動ダウンロード・ロード）
    func switchModel(to newModel: String) {
        guard newModel != modelName else { return }
        modelName = newModel
        whisperKit = nil
        isModelLoaded = false
        isLoading = false
        loadingProgress = "モデル変更: \(newModel)"
        loadingTask = nil
    }

    func loadModel() async throws {
        // 既にロード済み
        if isModelLoaded { return }

        // 別のタスクがロード中なら、その完了を待つ
        if let existingTask = loadingTask {
            try await existingTask.value
            return
        }

        let task = Task {
            isLoading = true
            loadingProgress = "Whisperモデル (\(modelName)) を読み込み中..."

            do {
                let config = WhisperKitConfig(model: modelName)
                let kit = try await WhisperKit(config)
                whisperKit = kit
                isModelLoaded = true
                isLoading = false
                loadingProgress = "モデル読み込み完了"
            } catch {
                isLoading = false
                loadingProgress = "モデル読み込みエラー: \(error.localizedDescription)"
                loadingTask = nil
                throw error
            }
        }

        loadingTask = task
        try await task.value
    }

    func transcribe(audioURL: URL) async throws -> String {
        // モデルのロードを待つ
        try await loadModel()

        guard let whisperKit else {
            throw WhisperServiceError.modelNotLoaded
        }

        loadingProgress = "音声を認識中..."

        let start = Date()

        let options = DecodingOptions(
            language: "ja",
            temperature: 0.0,
            temperatureFallbackCount: 0,     // 温度フォールバック無効化（リトライ回避で高速化）
            usePrefillPrompt: true,
            usePrefillCache: true,            // プリフィルキャッシュで2回目以降を高速化
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            concurrentWorkerCount: 4          // 長い音声の並列チャンク処理
        )

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        let elapsed = Date().timeIntervalSince(start)

        let text = results.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        loadingProgress = "認識完了 (\(String(format: "%.1f", elapsed))秒, \(text.count)文字)"

        return text
    }
}

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisperモデルが読み込まれていません"
        }
    }
}
