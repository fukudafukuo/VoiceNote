import Foundation

/// Bridge Send パイプライン - 日本語音声 → 英語出力
/// パイプライン順序: トークン保護 → 用語集(翻訳前) → 翻訳 → 用語集(翻訳後) → トークン復元 → 文体調整
@MainActor
final class BridgeSendService {

    private let tokenProtection = TokenProtectionService()
    private let translationService: TranslationService
    private let glossaryService: GlossaryService
    private let geminiFormatter: GeminiFormatter?

    init(
        translationService: TranslationService,
        glossaryService: GlossaryService,
        geminiFormatter: GeminiFormatter?
    ) {
        self.translationService = translationService
        self.glossaryService = glossaryService
        self.geminiFormatter = geminiFormatter
    }

    /// Bridge Send 実行（全パイプライン）
    /// - Parameters:
    ///   - jaText: 日本語テキスト（書き起こし結果）
    ///   - preset: 使用するプリセット
    ///   - skipStyleAdjust: Gemini文体調整をスキップする
    ///   - onProgress: 進捗コールバック
    ///   - onIntermediateResult: 翻訳完了時の中間結果コールバック（Gemini前）
    /// - Returns: 英語テキスト
    func process(
        _ jaText: String,
        preset: BridgePreset,
        skipStyleAdjust: Bool = false,
        onProgress: ((String) -> Void)? = nil,
        onIntermediateResult: ((String) -> Void)? = nil
    ) async throws -> String {
        // 1. トークン保護
        onProgress?("トークン保護中...")
        let (protectedText, tokens) = tokenProtection.protect(jaText)

        try Task.checkCancellation()

        // 2. 用語集（翻訳前）
        onProgress?("用語集を適用中...")
        let (glossaryText, glossaryPlaceholders) = glossaryService.applyBeforeTranslation(protectedText)

        try Task.checkCancellation()

        // 3. Apple Translation (JA→EN)
        onProgress?("翻訳中...")
        let translated = try await translationService.translate(glossaryText, direction: .jaToEn)

        try Task.checkCancellation()

        // 4. 用語集（翻訳後）+ プレースホルダ復元
        onProgress?("用語集を復元中...")
        let glossaryApplied = glossaryService.applyAfterTranslation(translated, placeholders: glossaryPlaceholders)

        // 5. トークン復元
        let tokensRestored = tokenProtection.restore(glossaryApplied, tokens: tokens)

        // 中間結果を通知（Geminiなしの翻訳結果）
        onIntermediateResult?(tokensRestored)

        // 6. プリセット文体調整（Gemini利用可能かつスキップでない場合のみ）
        let styled: String
        if !skipStyleAdjust, let gemini = geminiFormatter {
            try Task.checkCancellation()
            onProgress?("文体調整中（\(preset.displayName)）...")
            do {
                styled = try await gemini.adjustStyle(tokensRestored, preset: preset)
            } catch {
                // Gemini失敗時は文体調整なしで返す
                styled = tokensRestored
            }
        } else {
            styled = tokensRestored
        }

        onProgress?("完了")
        return styled
    }
}
