import Foundation
import NaturalLanguage

/// 翻訳方向
enum TranslationDirection {
    case jaToEn
    case enToJa
    case auto
}

/// 翻訳リクエスト（TranslationSessionHost に渡すデータ）
struct TranslationRequest {
    let id: UUID
    let text: String
    let sourceLang: String
    let targetLang: String
    let continuation: CheckedContinuation<String, Error>
}

/// 翻訳サービス - 翻訳要求の窓口
/// TranslationSession はビュークロージャ内でのみ使用可能なため、
/// リクエストキュー方式で .translationTask に翻訳を委譲する。
/// タイムアウトは TranslationSessionHost 側で session.translate() を包む形で実装。
@MainActor
@Observable
final class TranslationService {

    private(set) var isTranslating = false

    /// 保留中の翻訳リクエスト（TranslationSessionHost が消費する）
    var pendingRequest: TranslationRequest?

    /// キャンセル済みリクエストID（二重 resume 防止用）
    var cancelledRequestIds = Set<UUID>()

    /// 翻訳リクエストが追加されたことを通知するコールバック
    var onRequestAdded: (() -> Void)?

    /// セッション再生成要求コールバック（TranslationSessionHost が設定）
    var onSessionInvalidate: (() -> Void)?

    /// セッションが利用可能か（TranslationSessionHost が設定）
    var isSessionAvailable: Bool = false

    /// テキストを翻訳
    func translate(_ text: String,
                   direction: TranslationDirection) async throws -> String {

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let (sourceLang, targetLang) = resolveLanguages(text: text, direction: direction)

        guard isSessionAvailable else {
            throw TranslationServiceError.sessionNotAvailable
        }

        isTranslating = true
        defer { isTranslating = false }

        let requestId = UUID()

        return try await withCheckedThrowingContinuation { continuation in
            let request = TranslationRequest(
                id: requestId,
                text: text,
                sourceLang: sourceLang,
                targetLang: targetLang,
                continuation: continuation
            )

            // 既存のリクエストがある場合はキャンセル扱い
            if let existing = pendingRequest {
                pendingRequest = nil
                cancelledRequestIds.insert(existing.id)
                existing.continuation.resume(throwing: CancellationError())
            }

            pendingRequest = request

            // TranslationSessionHost に通知 → .translationTask 再トリガー
            if let onRequestAdded {
                onRequestAdded()
            } else {
                // コールバック未設定（TranslationSessionHost 未初期化）→ エラーで返す
                pendingRequest = nil
                continuation.resume(throwing: TranslationServiceError.sessionNotAvailable)
            }
        }
    }

    /// 翻訳セッションをウォームアップ（起動時に呼ぶ）
    func warmUp() async {
        guard isSessionAvailable, onRequestAdded != nil else { return }
        _ = try? await translate("テスト", direction: .jaToEn)
    }

    /// 言語を自動検出
    func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "ja"
    }

    /// 翻訳方向から(source, target)言語コードを決定
    private func resolveLanguages(text: String, direction: TranslationDirection) -> (String, String) {
        switch direction {
        case .jaToEn:
            return ("ja", "en")
        case .enToJa:
            return ("en", "ja")
        case .auto:
            let detected = detectLanguage(text)
            if detected == "ja" {
                return ("ja", "en")
            } else {
                return ("en", "ja")
            }
        }
    }
}

enum TranslationServiceError: LocalizedError, Equatable {
    case sessionNotAvailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            return "翻訳セッションが利用できません。macOS 15以降が必要です。"
        case .timeout:
            return "翻訳がタイムアウトしました（10秒）。再試行してください。"
        }
    }
}
