import SwiftUI
import UniformTypeIdentifiers
import ScenarioWriterCore

/// シナリオ情報（タイトル・作者・分類・メモ・作品画像・複写・削除）
struct InfoView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = Scenario()
    @State private var saveTask: Task<Void, Never>?
    @State private var dropTarget = false

    var body: some View {
        Form {
            Section("作品") {
                TextField("タイトル", text: $draft.title)
                TextField("サブタイトル", text: $draft.subtitle)
                TextField("作者名", text: $draft.writerName)
                Picker("分類", selection: $draft.category) {
                    ForEach(ScenarioCategory.allCases) { c in Text(c.label).tag(c.rawValue) }
                }
                TextField("メモ（自分用。台本には出ません）", text: $draft.memo, axis: .vertical).lineLimit(3...10)
                LabeledContent("更新日時", value: draft.date)
                LabeledContent("作品ファイル") {
                    HStack {
                        Text(model.currentWorkURL?.path ?? "").font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                        Button("Finder で表示") { model.revealCurrent() }
                    }
                }
            }
            Section("作品画像") {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(dropTarget ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        if let d = model.thumbnail, let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(6)
                        } else {
                            VStack {
                                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                                Text("ここに画像をドロップ").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 200, height: 150)
                    .id(model.documentVersion)
                    .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
                        guard let p = providers.first else { return false }
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in model.setThumbnail(from: url) } }
                        }
                        return true
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("作品一覧のカードに出ます。作品ファイルの中に保存されます。").foregroundStyle(.secondary)
                        HStack {
                            Button("画像を選ぶ…") { chooseImage() }
                            Button("画像を外す") { model.removeThumbnail() }
                                .disabled(model.thumbnail == nil)
                        }
                    }
                }
            }
            Section("この作品の操作") {
                HStack {
                    Button { model.copyScenario() } label: { Label("複製を保存…", systemImage: "doc.on.doc") }
                    Text("同じ内容の作品ファイルをもう 1 つ作って開きます。改稿前の控えに。").foregroundStyle(.secondary).font(.callout)
                }
                HStack {
                    Button(role: .destructive) { model.confirmDeleteScenario = true } label: { Label("シナリオ削除…", systemImage: "trash") }
                    Text("作品ファイルをゴミ箱に入れます。").foregroundStyle(.secondary).font(.callout)
                }
            }
            Section("仲間に読んでもらう") {
                HStack {
                    Button { model.exportHtml() } label: { Label("HTML を保存…", systemImage: "safari") }
                    Text("Web 版の「劇団員プレビュー」に相当。1 ファイルで、スマホでも縦書き / 横書きで読めます。").foregroundStyle(.secondary).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if let s = model.scenario { draft = s } }
        .onChange(of: model.scenario) { _, new in if let new, new != draft { saveTask?.cancel(); saveTask = nil; draft = new } }
        .onChange(of: draft) { _, new in
            guard let cur = model.scenario, new.id == cur.id, new != cur else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                model.updateScenario(new)
                saveTask = nil
            }
        }
    }

    private func chooseImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.setThumbnail(from: u) }
    }
}
