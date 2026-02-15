import Foundation

/// トークン保護サービス - URL、コード、パス等を翻訳から保護する
final class TokenProtectionService {

    /// 保護パターン定義（優先順位順。先に定義されたものが優先される）
    private let patterns: [(TokenType, String)] = [
        // コードブロック（```...```）- 最優先
        (.codeBlock,  "```[\\s\\S]*?```"),
        // インラインコード（`...`）
        (.inlineCode, "`[^`]+`"),
        // メールアドレス
        (.email,      "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"),
        // URL（http/https）
        (.url,        "https?://[^\\s\\)\\]\\>「」（）]+"),
        // ファイルパス（/, ~/ で始まるもの）
        (.filePath,   "(?:~/|/(?:Users|Applications|Library|System|var|tmp|opt|usr|etc|home))[\\w./_-]+"),
        // コマンド（$ で始まる行）
        (.command,    "\\$\\s+[^\\n]+"),
        // Gitハッシュ（7-40文字の16進数）
        (.gitHash,    "\\b[0-9a-f]{7,40}\\b"),
        // バージョン番号（v1.2.3, v1.2.3-beta.1 など）
        (.version,    "\\bv\\d+(?:\\.\\d+)+(?:-[a-zA-Z0-9.]+)?\\b"),
        // 日時（ISO形式, スラッシュ区切り）
        (.dateTime,   "\\b\\d{4}[-/]\\d{2}[-/]\\d{2}(?:[T\\s]\\d{2}:\\d{2}(?::\\d{2})?)?\\b"),
        // 数値＋単位
        (.number,     "\\b\\d+(?:[,.]\\d+)*\\s*(?:GB|MB|KB|TB|ms|sec|min|px|em|rem|%|秒|分|時間|日|件|個|回|人|万|億)\\b"),
    ]

    /// テキスト内のトークンをプレースホルダに置換
    /// - Returns: (プレースホルダ化されたテキスト, 保護されたトークン一覧)
    func protect(_ text: String) -> (text: String, tokens: [ProtectedToken]) {
        var result = text
        var tokens: [ProtectedToken] = []
        // 既に保護済みの範囲を追跡（二重保護の防止）
        var protectedRanges: [Range<String.Index>] = []

        for (type, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange)

            // 後ろから置換（インデックスずれ防止）
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }

                // 既に保護済みの範囲と重複していないかチェック
                let overlaps = protectedRanges.contains { existing in
                    range.overlaps(existing)
                }
                if overlaps { continue }

                let original = String(result[range])
                let placeholder = ProtectedToken.makePlaceholder()
                let token = ProtectedToken(placeholder: placeholder, original: original, type: type)
                tokens.append(token)

                result.replaceSubrange(range, with: placeholder)

                // 保護済み範囲を更新（プレースホルダの範囲で）
                let newStart = range.lowerBound
                let newEnd = result.index(newStart, offsetBy: placeholder.count)
                protectedRanges.append(newStart..<newEnd)
            }
        }

        return (result, tokens)
    }

    /// プレースホルダを元のトークンに復元
    func restore(_ text: String, tokens: [ProtectedToken]) -> String {
        var result = text
        for token in tokens {
            result = result.replacingOccurrences(of: token.placeholder, with: token.original)
        }
        return result
    }
}
