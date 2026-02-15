import Foundation

final class GeminiFormatter {

    private let apiKey: String
    private let model: String
    private let session: URLSession

    private let systemPrompt = """
    あなたは日本語の音声書き起こしテキストを整形する専門家です。
    整形されたテキストはAIチャット（Claude等）への入力として使用されます。

    ## 最重要ルール
    - **話者が述べた内容は一切省略・要約・削除しない**
    - フィラー（えー、うーん等）と明らかな言い直しのみ除去する
    - それ以外の情報はすべて残す

    ## フィラー除去対象
    えー、えーと、えっと、あー、あのー、あの、うーん、うん、まぁ、まあ、
    そのー、なんか、なんていうか、ほら、ね、さ、同じ言葉の繰り返し（言い直し）

    ## 文章の整形
    - 話し言葉のままで問題ない部分はそのまま残す
    - 過度に書き言葉に変換しない
    - 話者の意図やニュアンスを維持する

    ## 内容に応じた整形レベル

    **短い発話・会話・簡単な質問や依頼:**
    - フィラー除去のみ
    - Markdown記法は使わない

    **要件定義・タスク指示（複数の条件、仕様、手順を含む内容）:**
    - 見出し（##）で話題を区切る
    - 条件や要件を箇条書き（-）で整理する
    - 技術用語、ファイル名、コマンドは `バッククォート` で囲む

    **複数話題の説明:**
    - 話題ごとに段落を分ける
    - 必要に応じて見出しや箇条書きを使う

    ## 出力形式
    - 余計なメタ情報（「以下は整形結果です」等）は付けない
    - 整形後のテキストのみを返す
    """

    init(apiKey: String, model: String = "gemini-2.0-flash") {
        self.apiKey = apiKey
        self.model = model
        self.session = URLSession.shared
    }

    /// 音声書き起こしテキストを整形
    func format(_ rawText: String) async throws -> String {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let userPrompt = "以下の音声書き起こしテキストを整形してください。\n\n\(rawText)"
        return try await callGeminiAPI(systemInstruction: systemPrompt, userPrompt: userPrompt)
    }

    /// Bridge Send プリセットに基づく英語文体調整
    func adjustStyle(_ englishText: String, preset: BridgePreset) async throws -> String {
        guard !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let sysPrompt = """
        You are an English style editor. Do NOT translate. Only adjust the tone and style.
        Keep all technical terms, URLs, code, placeholders (<<tok_...>>), and proper nouns exactly as they are.
        Return ONLY the adjusted text without any explanation.
        """

        let userPrompt = """
        \(preset.styleInstruction)

        Text to adjust:
        \(englishText)
        """

        return try await callGeminiAPI(systemInstruction: sysPrompt, userPrompt: userPrompt, timeout: 10)
    }

    // MARK: - Private: Gemini API 共通呼び出し

    private func callGeminiAPI(systemInstruction: String, userPrompt: String, timeout: TimeInterval = 30) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw FormatterError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": userPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 4096
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw FormatterError.apiError(statusCode: statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw FormatterError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class OfflineFormatter {

    private let fillers: [String] = [
        "なんていうか", "えーと", "えっと", "あのー", "そのー",
        "なんか", "うーん", "まぁ", "まあ", "あー",
        "えー", "あの", "うん", "んー", "んと", "ほら",
    ]

    func format(_ rawText: String, formatMode: FormatMode = .auto) -> String {
        guard !rawText.isEmpty else { return "" }

        var text = rawText

        // フィラー除去
        for filler in fillers {
            let pattern = "(?:^|(?<=[\\s]))(\(NSRegularExpression.escapedPattern(for: filler)))(?:[\\s、。，．,.]|$)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: ""
                )
            }
        }

        // 句読点の正規化
        text = normalizePunctuation(text)

        // 連続スペースを1つに
        if let spaceRegex = try? NSRegularExpression(pattern: "[ 　]+") {
            text = spaceRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        // 連続改行を2つに
        if let newlineRegex = try? NSRegularExpression(pattern: "\\n{3,}") {
            text = newlineRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 句読点・記号の音声表現をシンボルに変換
    func normalizePunctuation(_ text: String) -> String {
        var result = text

        let punctuationMap: [(pattern: String, replacement: String)] = [
            // 疑問符（ひらがな・カタカナ・漢字）
            ("はてな", "？"),
            ("ハテナ", "？"),
            ("クエスチョンマーク", "？"),
            ("クエスチョン", "？"),
            ("疑問符", "？"),
            // 感嘆符
            ("びっくりマーク", "！"),
            ("ビックリマーク", "！"),
            ("エクスクラメーションマーク", "！"),
            ("エクスクラメーション", "！"),
            ("感嘆符", "！"),
            // 句読点（ひらがな・カタカナ・漢字）
            ("句読点", "、"),
            ("句点", "。"),
            ("読点", "、"),
            // 括弧
            ("カッコ開き", "（"),
            ("かっこ開き", "（"),
            ("括弧開き", "（"),
            ("カッコ閉じ", "）"),
            ("かっこ閉じ", "）"),
            ("括弧閉じ", "）"),
            ("閉じカッコ", "）"),
            ("閉じかっこ", "）"),
            ("閉じ括弧", "）"),
            ("カッコ", "（"),
            ("かっこ", "（"),
            // その他
            ("コロン", "："),
            ("セミコロン", "；"),
            ("三点リーダー", "…"),
            ("三点リーダ", "…"),
            ("中黒", "・"),
            ("なかぐろ", "・"),
            ("ナカグロ", "・"),
        ]

        // 長いパターンから先に処理（部分一致を防ぐ）
        let sorted = punctuationMap.sorted { $0.pattern.count > $1.pattern.count }

        for (pattern, replacement) in sorted {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }

        // 疑問文パターンの自動検出（「〜か。」→「〜か？」）
        result = autoDetectQuestions(result)

        return result
    }

    /// 疑問文を検出して「。」を「？」に自動変換
    private func autoDetectQuestions(_ text: String) -> String {
        var result = text

        // 「〜ですか。」「〜ますか。」「〜るか。」「〜のか。」→「〜か？」
        let questionEndings = [
            "か。", "か\n",
        ]
        for ending in questionEndings {
            let replacement = ending == "か\n" ? "か？\n" : "か？"
            result = result.replacingOccurrences(of: ending, with: replacement)
        }

        // 文末が「か」で終わる場合
        if result.hasSuffix("か") || result.hasSuffix("か。") {
            if result.hasSuffix("か。") {
                result = String(result.dropLast()) + "？"
            } else if result.hasSuffix("か") {
                result = result + "？"
            }
        }

        // 疑問詞（なに、どう、なぜ等）を含む文の「。」→「？」
        let questionWords = ["どう", "なぜ", "なに", "何", "どこ", "いつ", "誰", "どれ", "どの", "どんな", "なんで", "どうして", "どちら"]

        let sentences = result.components(separatedBy: "。")
        var newSentences: [String] = []

        for (i, sentence) in sentences.enumerated() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                newSentences.append(sentence)
                continue
            }

            let hasQuestionWord = questionWords.contains { trimmed.contains($0) }

            if hasQuestionWord && i < sentences.count - 1 {
                newSentences.append(sentence + "？")
            } else if i < sentences.count - 1 {
                newSentences.append(sentence + "。")
            } else {
                newSentences.append(sentence)
            }
        }

        result = newSentences.joined()
        return result
    }
}

enum FormatterError: LocalizedError {
    case invalidURL
    case apiError(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なAPI URL"
        case .apiError(let statusCode):
            return "Gemini APIエラー (ステータス: \(statusCode))"
        case .invalidResponse:
            return "Gemini APIのレスポンスが不正です"
        }
    }
}
