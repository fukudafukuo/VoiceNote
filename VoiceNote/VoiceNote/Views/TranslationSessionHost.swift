import SwiftUI

#if compiler(>=6.0) && canImport(Translation)
import Translation

/// Apple Translation セッションを保持・管理する不可視ビュー
/// MenuBarExtra 内に .background() で埋め込んで使用する
struct TranslationSessionHost: View {

    var translationService: TranslationService

    /// JA→EN セッション用コンフィグ
    @State private var jaToEnConfig: TranslationSession.Configuration?

    /// EN→JA セッション用コンフィグ
    @State private var enToJaConfig: TranslationSession.Configuration?

    /// 現在保持している JA→EN セッション
    @State private var jaToEnSession: TranslationSession?

    /// 現在保持している EN→JA セッション
    @State private var enToJaSession: TranslationSession?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(jaToEnConfig) { session in
                jaToEnSession = session
                updateHandler()
            }
            .translationTask(enToJaConfig) { session in
                enToJaSession = session
                updateHandler()
            }
            .onAppear {
                // 初回起動時にセッションを作成
                jaToEnConfig = .init(
                    source: Locale.Language(identifier: "ja"),
                    target: Locale.Language(identifier: "en")
                )
                enToJaConfig = .init(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ja")
                )
            }
    }

    /// TranslationService にハンドラを設定
    private func updateHandler() {
        translationService.translateHandler = { [jaToEnSession, enToJaSession] text, sourceLang, targetLang in
            let session: TranslationSession?
            if sourceLang == "ja" && targetLang == "en" {
                session = jaToEnSession
            } else if sourceLang == "en" && targetLang == "ja" {
                session = enToJaSession
            } else {
                session = nil
            }

            guard let session else {
                throw TranslationServiceError.sessionNotAvailable
            }

            let response = try await session.translate(text)
            return response.targetText
        }
    }
}

#else

/// Translation frameworkが利用できない場合のフォールバック
struct TranslationSessionHost: View {

    var translationService: TranslationService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                // Translation framework未対応 — ハンドラは未設定のまま
                // BYO APIフォールバックが使用される
            }
    }
}

#endif
