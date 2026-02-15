import SwiftUI

/// 用語集設定タブ
@MainActor
struct GlossarySettingsView: View {

    @Bindable var glossaryService: GlossaryService

    @State private var newProjectName = ""
    @State private var selectedProjectId: UUID?
    @State private var showingImport = false
    @State private var showingExport = false

    /// 選択中のプロジェクト
    private var selectedProject: GlossaryProject? {
        glossaryService.projects.first { $0.id == selectedProjectId }
    }

    var body: some View {
        HSplitView {
            // 左: プロジェクト一覧
            projectList
                .frame(minWidth: 160, maxWidth: 200)

            // 右: エントリ編集
            if let project = selectedProject {
                entryEditor(for: project)
            } else {
                Text("プロジェクトを選択してください")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    // MARK: - プロジェクト一覧

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プロジェクト")
                .font(.headline)

            List(glossaryService.projects, selection: $selectedProjectId) { project in
                HStack {
                    if project.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Text(project.name)
                    Spacer()
                    Text("\(project.entries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("有効にする") {
                        glossaryService.setActive(projectId: project.id)
                    }
                    Divider()
                    Button("削除", role: .destructive) {
                        if selectedProjectId == project.id {
                            selectedProjectId = nil
                        }
                        glossaryService.removeProject(id: project.id)
                    }
                }
            }

            HStack {
                TextField("新規プロジェクト", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addProject() }

                Button(action: addProject) {
                    Image(systemName: "plus")
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button("インポート") { showingImport = true }
                    .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
                        if case .success(let url) = result {
                            try? glossaryService.importProject(from: url)
                        }
                    }

                if let project = selectedProject {
                    Button("エクスポート") { showingExport = true }
                        .fileExporter(
                            isPresented: $showingExport,
                            document: GlossaryDocument(project: project),
                            contentType: .json,
                            defaultFilename: "\(project.name).json"
                        ) { _ in }
                }
            }
            .font(.caption)
        }
    }

    // MARK: - エントリ編集

    private func entryEditor(for project: GlossaryProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.headline)
                Spacer()
                if project.isActive {
                    Label("有効", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Table(of: GlossaryEntry.self) {
                TableColumn("種別") { entry in
                    Text(entryTypeLabel(entry.type))
                        .font(.caption)
                }
                .width(min: 60, max: 80)

                TableColumn("ソース") { entry in
                    Text(entry.source)
                }

                TableColumn("ターゲット") { entry in
                    Text(entry.target)
                        .foregroundStyle(entry.type == .noTranslate ? .secondary : .primary)
                }

                TableColumn("") { entry in
                    Button(role: .destructive) {
                        glossaryService.removeEntry(from: project.id, entryId: entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .width(30)
            } rows: {
                ForEach(project.entries) { entry in
                    TableRow(entry)
                }
            }

            AddEntryRow(projectId: project.id, glossaryService: glossaryService)
        }
    }

    // MARK: - Helpers

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        glossaryService.addProject(name: name)
        newProjectName = ""
    }

    private func entryTypeLabel(_ type: GlossaryEntryType) -> String {
        switch type {
        case .noTranslate: return "非翻訳"
        case .fixed:       return "指定訳"
        case .postReplace: return "後置換"
        }
    }
}

// MARK: - 新規エントリ追加行

@MainActor
private struct AddEntryRow: View {
    let projectId: UUID
    let glossaryService: GlossaryService

    @State private var source = ""
    @State private var target = ""
    @State private var type: GlossaryEntryType = .noTranslate

    var body: some View {
        HStack {
            Picker("", selection: $type) {
                Text("非翻訳").tag(GlossaryEntryType.noTranslate)
                Text("指定訳").tag(GlossaryEntryType.fixed)
                Text("後置換").tag(GlossaryEntryType.postReplace)
            }
            .frame(width: 80)

            TextField("ソース", text: $source)
                .textFieldStyle(.roundedBorder)

            TextField("ターゲット", text: $target)
                .textFieldStyle(.roundedBorder)
                .disabled(type == .noTranslate)

            Button("追加") {
                let entry = GlossaryEntry(source: source, target: target, type: type)
                glossaryService.addEntry(to: projectId, entry: entry)
                source = ""
                target = ""
            }
            .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - エクスポート用 FileDocument

import UniformTypeIdentifiers

struct GlossaryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(project: GlossaryProject) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.data = (try? encoder.encode(project)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
