import Cocoa
import Foundation

final class AppProfileService {

    private let profiles: [String: AppProfile]
    private let enabled: Bool

    init(enabled: Bool = true, customProfiles: [String: AppProfile]? = nil) {
        self.enabled = enabled
        var allProfiles = AppProfiles.profiles
        if let custom = customProfiles {
            allProfiles.merge(custom) { _, new in new }
        }
        self.profiles = allProfiles
    }

    func getActiveApp() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    func getProfile(for appName: String? = nil) -> (profile: AppProfile, appName: String) {
        guard enabled else {
            return (AppProfiles.fallback, "")
        }

        let name = appName ?? getActiveApp()
        guard !name.isEmpty else {
            return (AppProfiles.fallback, "")
        }

        if let profile = profiles[name] {
            return (profile, name)
        }

        let nameLower = name.lowercased()
        for (key, profile) in profiles {
            let keyLower = key.lowercased()
            if keyLower.contains(nameLower) || nameLower.contains(keyLower) {
                return (profile, name)
            }
        }

        return (AppProfiles.fallback, name)
    }

    func applyProfile(_ text: String, profile: AppProfile) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        if profile.stripMarkdown {
            result = stripMarkdown(result)
        }

        if profile.addTrailingNewline && !result.hasSuffix("\n") {
            result += "\n"
        }

        return result
    }

    private func stripMarkdown(_ text: String) -> String {
        var result = text

        let replacements: [(pattern: String, template: String)] = [
            ("^#{1,6}\\s+", ""),
            ("\\*\\*(.+?)\\*\\*", "$1"),
            ("\\*(.+?)\\*", "$1"),
            ("__(.+?)__", "$1"),
            ("_(.+?)_", "$1"),
            ("`(.+?)`", "$1"),
            ("```[\\s\\S]*?```", ""),
            ("^[\\s]*[-*+]\\s+", ""),
            ("^[\\s]*\\d+\\.\\s+", ""),
            ("^>\\s+", ""),
            ("^---+$", ""),
            ("\\n{3,}", "\n\n"),
        ]

        for (pattern, template) in replacements {
            let options: NSRegularExpression.Options = pattern.hasPrefix("^") ? .anchorsMatchLines : []
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: template
                )
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
