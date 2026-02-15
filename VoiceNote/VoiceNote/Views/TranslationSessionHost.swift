import SwiftUI

/// Translation frameworkが利用できない / macOS 15未満 のフォールバック
struct TranslationSessionHostFallback: View {

    var translationService: TranslationService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                translationService.isSessionAvailable = false
            }
    }
}

#if canImport(Translation)
import Translation

/// Apple Translation セッションを管理する不可視ビュー
///
/// Apple の制約: TranslationSession は .translationTask クロージャ内でのみ使用可能。
/// 設計: TranslationService.pendingRequest を onChange で監視し、
/// config を nil → 再セットして .translationTask を確実に再トリガー。
/// クロージャ内で session.translate() → continuation.resume() で結果を返す。
/// タイムアウトも Host 側で session.translate() を包む形で実装。
@available(macOS 15.0, *)
struct TranslationSessionHost: View {

    var translationService: TranslationService

    /// JA→EN セッション用コンフィグ
    @State private var jaToEnConfig: TranslationSession.Configuration?

    /// EN→JA セッション用コンフィグ
    @State private var enToJaConfig: TranslationSession.Configuration?

    /// リクエスト発火用トリガー（値が変わるたびに onChange で検知）
    @State private var triggerCounter: Int = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(jaToEnConfig) { session in
                translationService.isSessionAvailable = true
                await processRequest(session: session, direction: "jaToEn")
            }
            .translationTask(enToJaConfig) { session in
                translationService.isSessionAvailable = true
                await processRequest(session: session, direction: "enToJa")
            }
            .onAppear {
                // 初期セッション作成
                jaToEnConfig = makeConfig(source: "ja", target: "en")
                enToJaConfig = makeConfig(source: "en", target: "ja")

                // TranslationService のコールバック設定
                translationService.onRequestAdded = {
                    triggerCounter += 1
                }
                translationService.onSessionInvalidate = {
                    // セッション再生成
                    jaToEnConfig = nil
                    enToJaConfig = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        jaToEnConfig = makeConfig(source: "ja", target: "en")
                        enToJaConfig = makeConfig(source: "en", target: "ja")
                    }
                }
            }
            .onChange(of: triggerCounter) {
                // リクエストが来たら対応する config を nil → 再セット で
                // .translationTask を確実に再トリガー
                guard let request = translationService.pendingRequest else { return }
                if request.sourceLang == "ja" && request.targetLang == "en" {
                    jaToEnConfig = nil
                    DispatchQueue.main.async {
                        jaToEnConfig = makeConfig(source: "ja", target: "en")
                    }
                } else if request.sourceLang == "en" && request.targetLang == "ja" {
                    enToJaConfig = nil
                    DispatchQueue.main.async {
                        enToJaConfig = makeConfig(source: "en", target: "ja")
                    }
                }
            }
    }

    /// .translationTask クロージャ内で pendingRequest を処理（タイムアウト付き）
    private func processRequest(session: TranslationSession, direction: String) async {
        guard let request = translationService.pendingRequest else { return }

        // 方向チェック
        let isMatch: Bool
        if direction == "jaToEn" {
            isMatch = request.sourceLang == "ja" && request.targetLang == "en"
        } else {
            isMatch = request.sourceLang == "en" && request.targetLang == "ja"
        }
        guard isMatch else { return }

        // リクエストを消費
        let requestId = request.id
        translationService.pendingRequest = nil

        // キャンセル済みなら skip
        if translationService.cancelledRequestIds.contains(requestId) {
            translationService.cancelledRequestIds.remove(requestId)
            return
        }

        // タイムアウト付き翻訳を実行
        do {
            let result = try await translateWithTimeout(session: session, text: request.text, timeout: 10)
            // 二重 resume ガード
            if !translationService.cancelledRequestIds.contains(requestId) {
                request.continuation.resume(returning: result)
            }
        } catch {
            if !translationService.cancelledRequestIds.contains(requestId) {
                request.continuation.resume(throwing: error)
            }
            // タイムアウト時はセッション再生成
            if let tsError = error as? TranslationServiceError, tsError == .timeout {
                translationService.onSessionInvalidate?()
            }
        }
    }

    /// session.translate() を10秒タイムアウトで race
    private func translateWithTimeout(session: TranslationSession, text: String, timeout: Int) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let response = try await session.translate(text)
                return response.targetText
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranslationServiceError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func makeConfig(source: String, target: String) -> TranslationSession.Configuration {
        .init(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target)
        )
    }
}
#endif
