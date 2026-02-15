import Foundation

final class VoiceCommandService {

    private let compiledPatterns: [(regex: NSRegularExpression, commandText: String, replacement: String)]
    private let enabled: Bool

    init(enabled: Bool = true, commands: [VoiceCommand]? = nil) {
        self.enabled = enabled

        let cmds = commands ?? VoiceCommands.all
        let sorted = cmds.sorted { $0.pattern.count > $1.pattern.count }

        var patterns: [(NSRegularExpression, String, String)] = []
        for cmd in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: cmd.pattern)
            // コマンド前後の句読点・スペースも一緒に消費する
            let pattern = "[\\s、。，．,.]*\(escaped)[\\s、。，．,.]*"

            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                patterns.append((regex, cmd.pattern, cmd.replacement))
            }
        }

        self.compiledPatterns = patterns
    }

    func process(_ text: String) -> String {
        guard enabled, !text.isEmpty else { return text }

        var result = text
        for (regex, _, replacement) in compiledPatterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }

        if let regex = try? NSRegularExpression(pattern: "\\n{3,}") {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "\n\n"
            )
        }

        while result.hasPrefix("\n") {
            result.removeFirst()
        }

        result = result.trimmingCharacters(in: .init(charactersIn: " \t"))
        while result.hasSuffix("\n") || result.hasSuffix(" ") {
            result = String(result.dropLast())
        }

        return result
    }

    func hasCommands(in text: String) -> Bool {
        guard enabled, !text.isEmpty else { return false }
        for (regex, _, _) in compiledPatterns {
            if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }
}
