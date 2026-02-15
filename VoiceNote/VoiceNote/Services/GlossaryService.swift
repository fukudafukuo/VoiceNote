import Foundation

/// 用語集サービス - プロジェクト別用語集の管理・適用
@MainActor
@Observable
final class GlossaryService {

    private(set) var projects: [GlossaryProject] = []

    /// 現在有効なプロジェクト
    var activeProject: GlossaryProject? {
        projects.first { $0.isActive }
    }

    /// 保存先ディレクトリ（bundleIdentifier ベース）
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "tokyo.underbar.VoiceNote"
        let dir = appSupport.appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("Glossaries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("glossaries.json")
        loadProjects()
    }

    // MARK: - CRUD

    func addProject(name: String) {
        let project = GlossaryProject(name: name)
        projects.append(project)
        saveProjects()
    }

    func removeProject(id: UUID) {
        projects.removeAll { $0.id == id }
        saveProjects()
    }

    func setActive(projectId: UUID) {
        for i in projects.indices {
            projects[i].isActive = (projects[i].id == projectId)
        }
        saveProjects()
    }

    /// アクティブプロジェクトを次へ循環
    func cycleActiveProject() {
        guard projects.count > 1 else { return }
        let activeIdx = projects.firstIndex { $0.isActive }
        // 全部OFFの場合は最初のものをアクティブに
        guard let idx = activeIdx else {
            projects[0].isActive = true
            saveProjects()
            return
        }
        projects[idx].isActive = false
        let nextIdx = (idx + 1) % projects.count
        projects[nextIdx].isActive = true
        saveProjects()
    }

    func addEntry(to projectId: UUID, entry: GlossaryEntry) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].entries.append(entry)
        saveProjects()
    }

    func removeEntry(from projectId: UUID, entryId: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].entries.removeAll { $0.id == entryId }
        saveProjects()
    }

    func updateEntry(in projectId: UUID, entry: GlossaryEntry) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectId }),
              let eIdx = projects[pIdx].entries.firstIndex(where: { $0.id == entry.id }) else { return }
        projects[pIdx].entries[eIdx] = entry
        saveProjects()
    }

    // MARK: - 翻訳前後の適用

    /// 翻訳前に noTranslate と fixed エントリをプレースホルダに置換
    /// - Returns: (処理済みテキスト, プレースホルダ→復元テキストのマッピング)
    func applyBeforeTranslation(_ text: String) -> (text: String, placeholders: [(placeholder: String, restoreText: String)]) {
        guard let project = activeProject else { return (text, []) }

        var result = text
        var placeholders: [(String, String)] = []

        // 長い語句から先に処理（部分一致を防ぐ）
        let sorted = project.entries
            .filter { $0.type == .noTranslate || $0.type == .fixed }
            .sorted { $0.source.count > $1.source.count }

        for entry in sorted {
            let source = entry.source
            guard result.contains(source) else { continue }

            let placeholder = ProtectedToken.makePlaceholder()
            // noTranslate: 復元時に元のテキストをそのまま使う
            // fixed: 復元時に指定訳を使う
            let restoreText = entry.type == .noTranslate ? source : entry.target

            result = result.replacingOccurrences(of: source, with: placeholder)
            placeholders.append((placeholder, restoreText))
        }

        return (result, placeholders)
    }

    /// 翻訳後に postReplace エントリを適用し、プレースホルダを復元
    func applyAfterTranslation(_ text: String, placeholders: [(placeholder: String, restoreText: String)]) -> String {
        var result = text

        // postReplace エントリを適用
        if let project = activeProject {
            for entry in project.entries where entry.type == .postReplace {
                result = result.replacingOccurrences(of: entry.source, with: entry.target)
            }
        }

        // プレースホルダを復元
        for (placeholder, restoreText) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: restoreText)
        }

        return result
    }

    // MARK: - 永続化

    func loadProjects() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            projects = try JSONDecoder().decode([GlossaryProject].self, from: data)
        } catch {
            print("  [警告] 用語集の読み込みに失敗: \(error.localizedDescription)")
        }
    }

    func saveProjects() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("  [警告] 用語集の保存に失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - インポート/エクスポート

    func exportProject(_ project: GlossaryProject, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
    }

    func importProject(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var project = try JSONDecoder().decode(GlossaryProject.self, from: data)
        // 既存IDとの衝突を避けるため新しいIDを割り当て
        project.id = UUID()
        project.isActive = false
        projects.append(project)
        saveProjects()
    }
}
