import SwiftUI
import ScenarioWriterCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            Group {
                if model.storeError != nil {
                    ContentUnavailableView("設定を開けません", systemImage: "exclamationmark.triangle", description: Text(model.storeError ?? ""))
                } else if model.scenario != nil {
                    ScenarioEditorView()
                } else {
                    EmptyStateView()
                }
            }
            .inspector(isPresented: $model.showFindReplace) {
                FindReplaceView()
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
            }
        }
        .navigationTitle(model.scenario?.title ?? "ScenarioWriterSolo")
        .navigationSubtitle(model.scenario.map { ($0.subtitle.isEmpty ? ScenarioCategory.label(for: $0.category) : $0.subtitle) + (model.isDirty ? "　— 未保存の変更あり（⌘S で保存）" : "") } ?? "")
        .sheet(isPresented: $model.showNewScenario) { NewScenarioSheet() }
        .sheet(isPresented: $model.showExport) { ExportSheet() }
        .alert("エラー", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("完了", isPresented: Binding(get: { model.infoMessage != nil }, set: { if !$0 { model.infoMessage = nil } })) {
            Button("OK") { model.infoMessage = nil }
        } message: { Text(model.infoMessage ?? "") }
        .confirmationDialog("「\(model.scenario?.title ?? "")」を削除しますか？", isPresented: $model.confirmDeleteScenario, titleVisibility: .visible) {
            Button("ゴミ箱に入れる", role: .destructive) { model.deleteScenario() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("作品ファイル「\(model.currentWorkURL?.lastPathComponent ?? "")」をゴミ箱に入れます。戻したいときは Finder のゴミ箱から保存フォルダへ戻してください。")
        }
        .onOpenURL { url in model.openExternal(url: url) }
        .onAppear {
            AppDelegate.model = model
            AppDelegate.reopenWindow = { openWindow(id: "main") }
            SelfTest.runIfRequested(model)
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "theatermasks")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("ScenarioWriterSolo")
                .font(.title)
            Text("舞台・映像の脚本を、この Mac だけで書くためのエディタです。\n作品は 1 つずつ「タイトル.scwd」というファイルに保存されます。\n左の一覧から最近使った作品を選ぶか、ファイルを開くか、新しいシナリオを作ってください。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("開く…") { model.openWorkPanel() }
                Button("新規シナリオ…") { model.showNewScenario = true }
                    .keyboardShortcut(.defaultAction)
                Button("Web 版のデータを取り込む…") { model.importDatabase() }
            }
            .padding(.top, 8)
            if model.hasLegacyDatabase {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("以前のバージョンのデータがあります").font(.headline)
                        Text("1.0.0 では全作品を 1 つのデータベースに入れていました。作品ごとの .scwd ファイルに分けて、好きなフォルダに保存できます。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("作品ファイルに分けて保存…") { model.migrateLegacy() }
                    }
                    .padding(6)
                }
                .frame(maxWidth: 520)
                .padding(.top, 16)
            }
        }
        .padding(40)
    }
}

// MARK: - サイドバー
// 作品を選ぶ前（または「作品を選ぶ」を押したあと）は作品一覧、作品を開いている間はその作品の画面・場面・登場人物。

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.showsScenarioList {
                ScenarioListView()
            } else {
                ScenarioNavView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.openWorkPanel() } label: { Label("開く", systemImage: "folder") }
                    .help("作品ファイル（.scwd）を開く（⌘O）")
                Button { model.showNewScenario = true } label: { Label("新規シナリオ", systemImage: "plus") }
                    .help("新規シナリオ（⌘N）")
            }
        }
    }
}

struct ScenarioListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.scenario != nil {
                Section {
                    Button {
                        model.browsing = false
                    } label: {
                        Label("開いている作品に戻る", systemImage: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            Section("最近使った作品") {
                ForEach(model.recents) { w in
                    Button { model.open(work: w) } label: {
                        ScenarioCard(work: w)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(w.url == model.currentWorkURL ? Color.primary.opacity(0.06) : nil)
                    .contextMenu {
                        Button("開く") { model.open(work: w) }
                        Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([w.url]) }
                    }
                }
                Button { model.openWorkPanel() } label: { Label("ほかのファイルを開く…", systemImage: "folder") }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.recents.isEmpty && model.storeError == nil {
                Text("まだ作品を開いていません")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 開いている作品の中身（Web 版の Scenario Edit Menu ＋ 場面・登場人物の一覧）
enum SidebarItem: Hashable {
    case section(EditorSection)
    case scene(Int64)
    case character(Int64)
}

struct ScenarioNavView: View {
    @EnvironmentObject private var model: AppModel

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: {
                if model.section == .script, model.sidebarSceneFocus, let sid = model.selectedSceneId { return .scene(sid) }
                return .section(model.section)
            },
            set: { item in
                switch item {
                case .section(let s): model.sidebarSceneFocus = false; model.section = s
                case .scene(let id): model.sidebarSceneFocus = true; model.selectedSceneId = id; model.section = .script
                case .character: model.section = .cast
                case .none: break
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Button { model.chooseScenario() } label: {
                    Label("作品を選ぶ", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Section(model.scenario?.title ?? "") {
                ForEach(EditorSection.allCases) { s in
                    Label(s.label, systemImage: s.icon).tag(SidebarItem.section(s))
                }
            }
            Section {
                ForEach(Array(model.scenes.enumerated()), id: \.element.id) { i, sc in
                    HStack {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(sc.name.isEmpty ? "（無題の場面）" : sc.name).lineLimit(1)
                        Spacer()
                        Text("\(model.lineCounts[sc.id] ?? 0)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .tag(SidebarItem.scene(sc.id))
                    .contextMenu {
                        Button("場面設定を開く") { model.section = .scenes }
                        Button("上へ") { model.moveScene(sc, up: true) }
                        Button("下へ") { model.moveScene(sc, up: false) }
                    }
                }
                Button { model.addScene(); model.section = .scenes } label: { Label("場面を追加", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            } header: {
                Label("台本（場面ごと）", systemImage: "text.quote")
            }
            Section {
                ForEach(model.characters) { c in
                    Text(c.name.isEmpty ? "（名前なし）" : c.name).lineLimit(1).tag(SidebarItem.character(c.id))
                }
                Button { model.addCharacter(); model.section = .cast } label: { Label("登場人物を追加", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            } header: {
                Label("登場人物", systemImage: "person.2")
            }
        }
        .listStyle(.sidebar)
    }
}

struct ScenarioCard: View {
    let work: WorkSummary
    private var scenario: Scenario { work.scenario }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let d = work.thumbnail, let img = NSImage(data: d) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                        Image(systemName: "text.book.closed").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title.isEmpty ? "（無題）" : scenario.title)
                    .font(.headline)
                    .lineLimit(2)
                if !scenario.subtitle.isEmpty {
                    Text(scenario.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if scenario.category != 0 {
                        Text(ScenarioCategory.label(for: scenario.category))
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(String(scenario.date.prefix(16)))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 作品の編集（セクション切替）

struct ScenarioEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.section {
                case .script: ScriptEditorView()
                case .scenes: ScenesView()
                case .cast: CastView()
                case .synopsis: SynopsisView()
                case .info: InfoView()
                case .read: ReaderView()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showFindReplace.toggle() } label: { Label("検索と置換", systemImage: "magnifyingglass") }
                    .help("作品全体の台詞から探す（⌘F）")
                Button { model.showExport = true } label: { Label("書き出し", systemImage: "square.and.arrow.up") }
                    .help("テキスト / Word / XML / HTML に書き出す（⌘E）")
            }
        }
    }
}
