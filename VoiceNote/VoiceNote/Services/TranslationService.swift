import Foundation
import NaturalLanguage

/// 翻訳方向
enum TranslationDirection {
    case jaToEn
    case enToJa
    case auto
}

/// 翻訳サービス - 翻訳要求の窓口（セッション自体は TranslationSessionHost が保持）
@MainActor
@Observable
final class TranslationService {

    private(set) var isTranslating = false

    /// TranslationSessionHost から設定される翻訳ハンドラ
    /// (sourceText, sourceLang, targetLang) -> translatedText
    var translateHandler: ((String, String, String) async throws -> String)?

    /// テキストを翻訳
    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        isTranslating = true
        defer { isTranslating = false }

        let (sourceLang, targetLang) = resolveLanguages(text: text, direction: direction)

        guard let handler = translateHandler else {
            throw TranslationServiceError.sessionNotAvailable
        }

        return try await handler(text, sourceLang, targetLang)
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

enum TranslationServiceError: LocalizedError {
    case sessionNotAvailable

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            return "翻訳セッションが利用できません。macOS 15以降が必要です。"
        }
    }
}
