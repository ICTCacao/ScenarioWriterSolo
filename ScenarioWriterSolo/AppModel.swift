import SwiftUI
import AppKit
import ScenarioWriterCore

enum EditorSection: String, CaseIterable, Identifiable {
    case script, scenes, cast, synopsis, info, read
    var id: String { rawValue }
    var label: String {
        switch self {
        case .script: return "シナリオ編集"
        case .scenes: return "場面"
        case .cast: return "登場人物"
        case .synopsis: return "シノプシス"
        case .info: return "シナリオ情報"
        case .read: return "読む"
        }
    }
    var icon: String {
        switch self {
        case .script: return "text.quote"
        case .scenes: return "theatermasks"
        case .cast: return "person.2"
        case .synopsis: return "doc.text"
        case .info: return "info.circle"
        case .read: return "book"
        }
    }
}

typealias WorkSummary = ScenarioStore.WorkSummary

/// 画面の状態と、作品ファイル（.scwd）への読み書きをまとめる。
///
/// - 作品はひとつずつ `<タイトル>.scwd` に入る（JSON。ScenarioFile。1 ファイル 1 作品。編集中はコンテナ内の SQLite の作業用コピーを使う）
/// - スタイルと書式設定は共通で Application Support/settings.sqlite に持ち、開いた作品ファイルにも写す
///   （作品ファイルだけを Web 版の swdata.sqlite として置いても同じ見た目になる）
@MainActor
final class AppModel: ObservableObject {
    /// 共通設定（スタイル・書式・名前）
    private(set) var settingsStore: ScenarioStore?
    /// 開いている作品（コンテナ内の作業用コピー）。本ファイルは ⌘S のときだけ書き換える
    @Published private(set) var store: ScenarioStore?
    /// 本ファイル（ユーザーが選んだ .scwd）
    @Published private(set) var currentWorkURL: URL?
    /// 作業用コピーの場所（Application Support/work/<ID>.sqlite）と、その隣の状態ファイル
    private var workingURL: URL?
    private var workingID: String?
    /// currentWorkURL のセキュリティスコープを握っている間の URL
    private var scopedURL: URL?
    @Published var storeError: String?
    /// 保存していない変更がある
    @Published private(set) var isDirty = false {
        didSet {
            if oldValue != isDirty {
                NSApp.windows.first { $0.isVisible }?.isDocumentEdited = isDirty
                writeWorkingState()
            }
        }
    }
    /// 最後に保存した時点の書き換え行数（SQLite の累計と比べて未保存かを判定）
    private var savedChanges: Int64 = 0

    /// 最近開いた作品（ブックマークで覚える。サンドボックスでも次回そのまま開ける）
    @Published var recents: [WorkSummary] = []
    private var recentBookmarks: [Data] = []
    /// 1.0.0 の全作品入り DB がまだ残っている（作品ファイルに分けていない）
    @Published var hasLegacyDatabase = false

    @Published var selectedScenarioId: Int64? { didSet { if oldValue != selectedScenarioId { loadScenario(); remember() } } }
    /// サイドバーで作品一覧（最近使った作品）を出している状態
    @Published var browsing = false
    var showsScenarioList: Bool { browsing || scenario == nil }
    @Published var lineCounts: [Int64: Int] = [:]
    /// サイドバーで場面の行をクリックして台本を開いた（true）か、「シナリオ編集」から開いた（false）か。ハイライトの位置に使う
    @Published var sidebarSceneFocus = false
    @Published var scenario: Scenario?
    @Published var scenes: [ScriptScene] = []
    @Published var characters: [CastMember] = []
    @Published var synopsis: String = ""
    @Published var selectedSceneId: Int64? { didSet { if oldValue != selectedSceneId { loadLines(); remember() } } }
    @Published var lines: [ScriptLine] = []
    @Published var styles: [LineStyle] = []
    /// 固定スタイル（シノプシス・場面説明・登場人物）
    @Published var textStyles: [TextStyle] = TextStyle.defaults
    @Published var setting = OptionSetting()
    @Published var userName: String = ""
    @Published var thumbnail: Data?

    @Published var section: EditorSection = .script { didSet { remember() } }
    @Published var showNewScenario = false
    @Published var showExport = false
    @Published var showFindReplace = false
    @Published var showBulkScenes = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var confirmDeleteScenario = false

    /// 台本画面で選択・フォーカスしている行
    @Published var selectedLineId: Int64?
    @Published var focusRequestLineId: Int64?
    /// 「読む」画面を作り直す合図
    @Published var documentVersion = 0

    // MARK: - 起動・保存場所

    static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScenarioWriterSolo", isDirectory: true)
    }
    static var settingsURL: URL { dataDirectory.appendingPathComponent("settings.sqlite") }
    /// 1.0.0 のころの全作品入り DB。作品ファイルに分割してから swdata.migrated.sqlite に改名する
    static var legacyDatabaseURL: URL { dataDirectory.appendingPathComponent("swdata.sqlite") }
    static var thumbDirectory: URL { dataDirectory.appendingPathComponent("thumb", isDirectory: true) }
    /// 作業用コピー置き場
    static var workDirectory: URL { dataDirectory.appendingPathComponent("work", isDirectory: true) }

    private static let recentsKey = "recentBookmarks"
    private static let lastWorkKey = "lastWorkBookmark"
    private static let maxRecents = 20

    init() {
        openSettingsStore()
        hasLegacyDatabase = FileManager.default.fileExists(atPath: Self.legacyDatabaseURL.path)
        loadRecents()
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "section"), let sec = EditorSection(rawValue: raw) { section = sec }
        // 起動引数 -openFile <パス>（コンテナ内のファイル。動作確認用）
        if let path = d.string(forKey: "openFile"), !path.isEmpty {
            openWork(URL(fileURLWithPath: path), restoreScene: nil, resetReading: false)
        } else if !recoverUnsavedWorkIfAny() {
            if let data = d.data(forKey: Self.lastWorkKey), let url = Self.resolve(bookmark: data) {
                openWork(url, restoreScene: Int64(d.integer(forKey: "lastSceneId")), resetReading: false)
            }
        }
        // 起動引数 -focusLine <行ID> で行にフォーカス（動作確認用）
        let fl = Int64(d.integer(forKey: "focusLine"))
        if fl > 0 { selectedLineId = fl; focusRequestLineId = fl }
        browsing = (scenario == nil)
        restoring = false
    }

    private var restoring = true
    private func remember() {
        guard !restoring else { return }
        let d = UserDefaults.standard
        d.set(Int(selectedSceneId ?? 0), forKey: "lastSceneId")
        d.set(section.rawValue, forKey: "section")
    }

    private func openSettingsStore() {
        do {
            let s = try ScenarioStore(url: Self.settingsURL)
            settingsStore = s
            styles = try s.styles()
            textStyles = try s.textStyles()
            setting = try s.setting()
            userName = s.userName
            storeError = nil
        } catch {
            storeError = "設定を開けません: \(error.localizedDescription)"
        }
    }

    // MARK: - ブックマーク（最近使った作品）

    private static func resolve(bookmark: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return url
    }

    private func loadRecents() {
        recentBookmarks = (UserDefaults.standard.array(forKey: Self.recentsKey) as? [Data]) ?? []
        var list: [WorkSummary] = []
        var kept: [Data] = []
        for bm in recentBookmarks {
            guard let url = Self.resolve(bookmark: bm) else { continue }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path), let sum = ScenarioStore.summary(of: url) else { continue }
            list.append(sum)
            kept.append(bm)
        }
        recents = list
        recentBookmarks = kept
        UserDefaults.standard.set(kept, forKey: Self.recentsKey)
    }

    private func addRecent(_ url: URL) {
        guard let bm = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        // 同じファイルは先頭に寄せる
        recentBookmarks.removeAll { Self.resolve(bookmark: $0)?.path == url.path }
        recents.removeAll { $0.url.path == url.path }
        recentBookmarks.insert(bm, at: 0)
        if let sum = ScenarioStore.summary(of: url) { recents.insert(sum, at: 0) }
        if recentBookmarks.count > Self.maxRecents { recentBookmarks = Array(recentBookmarks.prefix(Self.maxRecents)); recents = Array(recents.prefix(Self.maxRecents)) }
        UserDefaults.standard.set(recentBookmarks, forKey: Self.recentsKey)
        UserDefaults.standard.set(bm, forKey: Self.lastWorkKey)
    }

    func clearRecents() {
        recentBookmarks = []
        recents = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    /// 開いている作品の一覧カードを更新（更新日時・画像）
    func refreshCurrentRecent() {
        guard let url = currentWorkURL, let i = recents.firstIndex(where: { $0.url.path == url.path }),
              var sum = ScenarioStore.summary(of: workingURL ?? url) else { return }
        sum.url = url
        recents[i] = sum
    }

    /// エラーをアラートに回す共通処理
    @discardableResult
    func perform<T>(_ body: () throws -> T) -> T? {
        defer { updateDirty() }
        do { return try body() } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func updateDirty() {
        guard let store else { if isDirty { isDirty = false }; return }
        let d = store.db.totalChanges != savedChanges
        if d != isDirty { isDirty = d }
    }

    // MARK: - 作品ファイルを開く・閉じる・保存

    /// 「開く…」（⌘O）
    func openWorkPanel() {
        let p = NSOpenPanel()
        p.message = "作品ファイル（.scwd）を選びます。"
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.allowedContentTypes = [.data]
        guard p.runModal() == .OK, let url = p.url else { return }
        guard url.pathExtension == ScenarioStore.workFileExtension else { errorMessage = "作品ファイル（.scwd）ではありません: \(url.lastPathComponent)"; return }
        openWork(url)
    }

    // MARK: 作業用コピー（書類アプリ方式）

    private struct WorkingState: Codable {
        var originalBookmark: Data
        var originalPath: String
        var title: String
        var dirty: Bool
        var updated: Date
    }

    private func stateURL(for id: String) -> URL { Self.workDirectory.appendingPathComponent(id).appendingPathExtension("json") }
    private func workingURL(for id: String) -> URL { Self.workDirectory.appendingPathComponent(id).appendingPathExtension("sqlite") }

    private func writeWorkingState() {
        guard let id = workingID, let cur = currentWorkURL,
              let bm = try? cur.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let st = WorkingState(originalBookmark: bm, originalPath: cur.path, title: scenario?.title ?? cur.deletingPathExtension().lastPathComponent, dirty: isDirty, updated: Date())
        if let data = try? JSONEncoder().encode(st) { try? data.write(to: stateURL(for: id), options: .atomic) }
    }

    private func removeWorkingFiles(id: String) {
        let fm = FileManager.default
        for u in [workingURL(for: id), stateURL(for: id), URL(fileURLWithPath: workingURL(for: id).path + "-journal")] { try? fm.removeItem(at: u) }
    }

    /// 起動時: 前回、保存しないまま終わった作業用コピーがあれば回復を提案する。回復して開いたら true
    private func recoverUnsavedWorkIfAny() -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.workDirectory.path) else { return false }
        var opened = false
        for n in names where n.hasSuffix(".json") {
            let id = String(n.dropLast(5))
            guard let data = try? Data(contentsOf: stateURL(for: id)), let st = try? JSONDecoder().decode(WorkingState.self, from: data) else {
                removeWorkingFiles(id: id); continue
            }
            guard st.dirty, fm.fileExists(atPath: workingURL(for: id).path) else { removeWorkingFiles(id: id); continue }
            if opened { continue }   // 2 つ以上あれば次回以降に回す
            let alert = NSAlert()
            alert.messageText = "「\(st.title)」に保存していない変更があります"
            alert.informativeText = "前回、保存せずに終わった編集内容が残っています。回復して続きから編集しますか？\n\(st.originalPath)"
            alert.addButton(withTitle: "回復する")
            alert.addButton(withTitle: "破棄する")
            let r = alert.runModal()
            if r == .alertFirstButtonReturn, let url = Self.resolve(bookmark: st.originalBookmark) {
                closeWork(discardChanges: true)
                let scoped = url.startAccessingSecurityScopedResource()
                do {
                    let s = try ScenarioStore(url: workingURL(for: id))
                    store = s
                    currentWorkURL = url
                    scopedURL = scoped ? url : nil
                    workingID = id
                    workingURL = workingURL(for: id)
                    savedChanges = -1   // 回復直後は必ず「未保存」
                    selectedScenarioId = try s.firstScenarioId()
                    browsing = false
                    updateDirty()
                    addRecent(url)
                    opened = true
                } catch {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    errorMessage = "回復できませんでした: \(error.localizedDescription)"
                    removeWorkingFiles(id: id)
                }
            } else {
                removeWorkingFiles(id: id)
            }
        }
        return opened
    }

    /// 未保存なら「保存 / 保存しない / キャンセル」を聞く。続けてよければ true
    @discardableResult
    func confirmDiscardIfDirty(action: String) -> Bool {
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        updateDirty()
        guard isDirty, let cur = currentWorkURL else { return true }
        let alert = NSAlert()
        alert.messageText = "「\(scenario?.title ?? cur.lastPathComponent)」の変更を保存しますか？"
        alert.informativeText = "\(action)前に、作品ファイルに保存していない変更があります。保存しないと失われます。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "保存しない")
        alert.addButton(withTitle: "キャンセル")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveNow(quiet: true)
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    /// 書いたアプリの名前（作品ファイルに入れる）
    static var appVersionString: String {
        "ScenarioWriterSolo " + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "")
    }

    func openWork(_ url: URL, restoreScene: Int64? = nil, resetReading: Bool = true) {
        guard confirmDiscardIfDirty(action: "別の作品を開く") else { return }
        closeWork(discardChanges: true)
        clearUndo()
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            // 本ファイル（JSON）はそのままにして、コンテナ内の作業用コピー（SQLite）に読み込む
            try FileManager.default.createDirectory(at: Self.workDirectory, withIntermediateDirectories: true)
            let id = UUID().uuidString
            let w = workingURL(for: id)
            let data = try Data(contentsOf: url)
            let s: ScenarioStore
            if ScenarioFile.isSQLite(data) {
                // β5 より前の形式（SQLite）。そのまま作業用コピーにして、保存すると JSON になる
                try data.write(to: w)
                s = try ScenarioStore(url: w)
            } else {
                let file = try ScenarioFile.decode(data)
                s = try ScenarioStore(url: w)
                try s.importFile(file)
            }
            try s.replaceStyles(styles, textStyles: textStyles, setting: setting)   // 共通設定を写す
            store = s
            currentWorkURL = url
            scopedURL = scoped ? url : nil
            workingID = id
            workingURL = w
            savedChanges = s.db.totalChanges
            isDirty = false
            let sid = try s.firstScenarioId()
            if selectedScenarioId == sid { loadScenario() } else { selectedScenarioId = sid }
            if let rs = restoreScene, rs > 0, scenes.contains(where: { $0.id == rs }) { selectedSceneId = rs }
            browsing = false
            if resetReading, section == .read { section = .script }
            addRecent(url)
            writeWorkingState()
            NSApp.windows.first { $0.isVisible }?.representedURL = url
            remember()
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            errorMessage = "作品ファイルを開けません: \(error.localizedDescription)"
        }
    }

    func open(work: WorkSummary) { openWork(work.url) }

    /// 「閉じる」（⌘W）。未保存なら聞く
    func closeWork() {
        guard confirmDiscardIfDirty(action: "閉じる") else { return }
        closeWork(discardChanges: true)
    }

    /// 作業用コピーを捨てて閉じる（確認は呼ぶ側で済ませておく）
    func closeWork(discardChanges: Bool) {
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        clearUndo()
        store = nil
        currentWorkURL = nil
        if let id = workingID { removeWorkingFiles(id: id) }
        workingID = nil
        workingURL = nil
        savedChanges = 0
        isDirty = false
        selectedScenarioId = nil
        if let u = scopedURL { u.stopAccessingSecurityScopedResource(); scopedURL = nil }
        NSApp.windows.first { $0.isVisible }?.representedURL = nil
        browsing = true
        remember()
    }

    /// いまの内容を作品ファイル（JSON）のデータにする
    private func currentFileData() throws -> Data {
        guard let store, let id = selectedScenarioId else {
            throw NSError(domain: "ScenarioWriterSolo", code: 1, userInfo: [NSLocalizedDescriptionKey: "作品を開いていません"])
        }
        return try store.exportFile(scenarioId: id, app: Self.appVersionString).encode()
    }

    /// 「保存」（⌘S）: 作業用コピーの内容を本ファイル（JSON）へ書き戻す
    func saveNow(quiet: Bool = false) {
        guard let store, let cur = currentWorkURL else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        do {
            try Self.writeBack(data: try currentFileData(), to: cur)
            savedChanges = store.db.totalChanges
            isDirty = false
            writeWorkingState()
            refreshCurrentRecent()
            if !quiet { infoMessage = "保存しました。" }
        } catch {
            errorMessage = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    /// 本ファイルを置き換える（一時ファイルに書いてから入れ替えるので、途中で失敗しても本ファイルは壊れない）
    private static func writeBack(data: Data, to original: URL) throws {
        let fm = FileManager.default
        if let tmpDir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: original, create: true) {
            let tmp = tmpDir.appendingPathComponent(UUID().uuidString + ".scwd")
            try data.write(to: tmp)
            do {
                _ = try fm.replaceItemAt(original, withItemAt: tmp, backupItemName: nil, options: .usingNewMetadataOnly)
                return
            } catch {
                try? fm.removeItem(at: tmp)
            }
        }
        try data.write(to: original, options: .atomic)
    }

    /// 「最後に保存した状態に戻す」
    func revertToSaved() {
        guard let cur = currentWorkURL, isDirty else { return }
        let alert = NSAlert()
        alert.messageText = "最後に保存した状態に戻しますか？"
        alert.informativeText = "保存していない変更はすべて失われます。"
        alert.addButton(withTitle: "戻す")
        alert.addButton(withTitle: "キャンセル")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let sceneId = selectedSceneId
        let sec = section
        closeWork(discardChanges: true)
        openWork(cur, restoreScene: sceneId, resetReading: false)
        section = sec
    }

    /// 終了時（AppDelegate から）。続けてよければ true
    func prepareForTermination() -> Bool {
        guard confirmDiscardIfDirty(action: "終了する") else { return false }
        closeWork(discardChanges: true)
        return true
    }

    /// 「作品を選ぶ」: 最近使った作品の一覧に戻る（開いていた作品は覚えたまま）
    func chooseScenario() {
        loadRecents()
        browsing = true
    }

    /// Finder からのダブルクリックなど
    func openExternal(url: URL) {
        guard url.pathExtension == ScenarioStore.workFileExtension else { return }
        openWork(url)
    }

    private func savePanelForWork(title: String, message: String, directory: URL? = nil) -> URL? {
        let p = NSSavePanel()
        p.message = message
        p.nameFieldStringValue = TextFormat.safeFileName(title, fallback: "無題") + "." + ScenarioStore.workFileExtension
        p.allowedContentTypes = [.data]
        p.canCreateDirectories = true
        if let directory { p.directoryURL = directory }
        guard p.runModal() == .OK, var url = p.url else { return nil }
        if url.pathExtension != ScenarioStore.workFileExtension { url.appendPathExtension(ScenarioStore.workFileExtension) }
        return url
    }

    /// 「別名で保存…」（⇧⌘S）: いまの内容（未保存分も含む）を別のファイルに書き、以後そちらを本ファイルにする
    func saveAs() {
        guard let cur = currentWorkURL, let sc = scenario else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        guard let dst = savePanelForWork(title: sc.title, message: "この作品を別のファイルとして保存し、以後そちらを編集します。元のファイルは最後に保存した状態のまま残ります。", directory: cur.deletingLastPathComponent()) else { return }
        if dst.path == cur.path { saveNow(); return }
        do {
            let scoped = dst.startAccessingSecurityScopedResource()
            defer { if scoped { dst.stopAccessingSecurityScopedResource() } }
            try currentFileData().write(to: dst, options: .atomic)
        } catch {
            errorMessage = "保存できませんでした: \(error.localizedDescription)"
            return
        }
        // 本ファイルを差し替える（作業用コピーはそのまま使う）
        if let u = scopedURL { u.stopAccessingSecurityScopedResource() }
        let scoped = dst.startAccessingSecurityScopedResource()
        scopedURL = scoped ? dst : nil
        currentWorkURL = dst
        if let store { savedChanges = store.db.totalChanges }
        isDirty = false
        writeWorkingState()
        addRecent(dst)
        NSApp.windows.first { $0.isVisible }?.representedURL = dst
        infoMessage = "「\(dst.lastPathComponent)」に保存しました。"
    }

    var styleByType: [Int: LineStyle] {
        var d: [Int: LineStyle] = [:]
        for s in styles where d[s.styleId] == nil { d[s.styleId] = s }
        return d
    }
    var characterById: [Int64: CastMember] { Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) }) }

    func resolvedStyle(for type: Int) -> ResolvedStyle {
        ScriptFormatter.resolve(type: type, styles: styleByType, useKagikakko: setting.useKagikakko)
    }

    func formatted(_ line: ScriptLine) -> FormattedLine {
        ScriptFormatter.format(line, characters: characterById, styles: styleByType, useKagikakko: setting.useKagikakko)
    }

    // MARK: - シナリオ

    func loadScenario() {
        guard let store, let id = selectedScenarioId else {
            scenario = nil; scenes = []; characters = []; lines = []; synopsis = ""; selectedSceneId = nil; thumbnail = nil; lineCounts = [:]
            return
        }
        perform {
            scenario = try store.scenario(id: id)
            scenes = try store.scenes(scenarioId: id)
            characters = try store.characters(scenarioId: id)
            synopsis = try store.synopsis(scenarioId: id)
            thumbnail = try store.thumbnail(scenarioId: id)
        }
        if let sid = selectedSceneId, scenes.contains(where: { $0.id == sid }) {
            loadLines()
        } else {
            selectedSceneId = scenes.first?.id
            if selectedSceneId == nil { lines = [] }
        }
        documentVersion += 1
    }

    /// コンテナ内の一時 DB で作品を組み立て、作品ファイル（JSON）のデータにする。`build` は作った作品の ID を返す
    private func buildWorkFile(_ build: (ScenarioStore) throws -> Int64) throws -> Data {
        let tmp = Self.workDirectory.appendingPathComponent("build-\(UUID().uuidString).sqlite")
        try FileManager.default.createDirectory(at: Self.workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let w = try ScenarioStore(url: tmp)
        try w.replaceStyles(styles, textStyles: textStyles, setting: setting)
        let id = try build(w)
        return try w.exportFile(scenarioId: id, app: Self.appVersionString).encode()
    }

    /// 新規シナリオ: 保存先を聞いてから作る
    func createScenario(_ s: Scenario, acts: Int, scenesPerAct: Int, actFormat: (String, String), sceneFormat: (String, String), characterCount: Int, characterPrefix: String) {
        guard let url = savePanelForWork(title: s.title, message: "新しい作品ファイルの保存先", directory: currentWorkURL?.deletingLastPathComponent()) else { return }
        let ok: Bool = perform {
            try? FileManager.default.removeItem(at: url)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try buildWorkFile { w in
                try w.createScenario(s, acts: acts, scenesPerAct: scenesPerAct, actFormat: actFormat, sceneFormat: sceneFormat,
                                     characterCount: characterCount, characterPrefix: characterPrefix)
            }
            try data.write(to: url, options: .atomic)
            return true
        } ?? false
        guard ok else { return }
        openWork(url)
        section = .script
    }

    func updateScenario(_ s: Scenario) {
        guard let store, let old = scenario else { return }
        guard old != s else { return }
        perform { try store.updateScenario(s) }
        scenario = s
        registerUndo("シナリオ情報の変更") { m in m.updateScenario(old) }
        refreshCurrentRecent()
        documentVersion += 1
    }

    /// 「複製を保存…」: 同じ内容の作品ファイルをもう 1 つ作って、そちらを開く
    func copyScenario() {
        guard let store, let id = selectedScenarioId, let sc = scenario else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        guard let url = savePanelForWork(title: sc.title + "のコピー", message: "複製の保存先（いまの内容で作ります）", directory: currentWorkURL?.deletingLastPathComponent()) else { return }
        let ok: Bool = perform {
            try? FileManager.default.removeItem(at: url)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try buildWorkFile { w in try w.importScenario(from: store.db, scenarioId: id, titleSuffix: "のコピー") }
            try data.write(to: url, options: .atomic)
            return true
        } ?? false
        guard ok else { return }
        infoMessage = "複製「\(url.lastPathComponent)」を保存しました。"
    }

    func deleteScenario() {
        guard let url = currentWorkURL else { return }
        closeWork(discardChanges: true)
        perform { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        recents.removeAll { $0.url.path == url.path }
        recentBookmarks.removeAll { Self.resolve(bookmark: $0)?.path == url.path }
        UserDefaults.standard.set(recentBookmarks, forKey: Self.recentsKey)
        infoMessage = "「\(url.lastPathComponent)」をゴミ箱に入れました。"
    }

    // MARK: - 作品画像

    func setThumbnail(from source: URL) {
        guard let store, let id = selectedScenarioId, let img = NSImage(contentsOf: source) else { errorMessage = "画像として読めませんでした"; return }
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = NSImage(size: size)
        resized.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        setThumbnailData(png)
    }

    private func setThumbnailData(_ png: Data?) {
        guard let store, let id = selectedScenarioId else { return }
        let old = thumbnail
        perform { try store.setThumbnail(scenarioId: id, png: png) }
        thumbnail = png
        registerUndo("作品画像の変更") { m in m.setThumbnailData(old) }
        documentVersion += 1
        refreshCurrentRecent()
    }

    func removeThumbnail() { setThumbnailData(nil) }

    // MARK: - 元に戻す（構造的な操作）

    /// ウインドウの UndoManager。本文欄の中の文字入力は欄ごとの別の UndoManager なので、ここには行・場面・人物などの操作だけが積まれる
    private var undoManager: UndoManager? { NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager ?? NSApp.windows.first?.undoManager }

    private func registerUndo(_ name: String, _ handler: @escaping (AppModel) -> Void) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { m in handler(m) }
        if !um.isUndoing && !um.isRedoing { um.setActionName(name) }
    }

    func clearUndo() { undoManager?.removeAllActions(withTarget: self) }

    // MARK: - シノプシス

    func saveSynopsis(_ text: String) {
        guard let store, let id = selectedScenarioId else { return }
        let old = synopsis
        guard old != text else { return }
        synopsis = text
        perform { try store.saveSynopsis(scenarioId: id, text: text) }
        registerUndo("シノプシスの変更") { m in m.saveSynopsis(old) }
        documentVersion += 1
    }

    // MARK: - 場面

    func reloadScenes() {
        guard let store, let id = selectedScenarioId else { return }
        perform { scenes = try store.scenes(scenarioId: id) }
        if let sid = selectedSceneId, !scenes.contains(where: { $0.id == sid }) { selectedSceneId = scenes.first?.id }
        lineCounts = (try? store.lineCounts(scenarioId: id)) ?? [:]
        documentVersion += 1
    }

    func addScene(name: String = "新しい場面") {
        guard let store, let id = selectedScenarioId else { return }
        guard let sid = perform({ try store.insertScene(ScriptScene(scenarioId: id, name: name)) }) else { return }
        reloadScenes()
        if let sc = scenes.first(where: { $0.id == sid }) {
            registerUndo("場面を追加") { m in m.removeScene(sc, actionName: "場面を追加") }
        }
    }

    func addScenesInBulk(acts: Int, scenesPerAct: Int, actFormat: (String, String), sceneFormat: (String, String)) {
        guard let store, let id = selectedScenarioId else { return }
        let before = Set(scenes.map(\.id))
        perform { try store.insertScenesInBulk(scenarioId: id, acts: acts, scenesPerAct: scenesPerAct, actFormat: actFormat, sceneFormat: sceneFormat) }
        reloadScenes()
        let added = scenes.filter { !before.contains($0.id) }
        guard !added.isEmpty else { return }
        registerUndo("場面を一括追加") { m in
            for sc in added.reversed() { m.removeScene(sc, actionName: "場面を一括追加", register: false) }
            m.registerUndo("場面を一括追加") { m2 in m2.restoreScenes(added) }
        }
    }

    private func restoreScenes(_ list: [ScriptScene]) {
        guard let store else { return }
        perform { for sc in list { try store.insertScene(restoring: sc) } }
        reloadScenes()
        registerUndo("場面を一括追加") { m in
            for sc in list.reversed() { m.removeScene(sc, actionName: "場面を一括追加", register: false) }
            m.registerUndo("場面を一括追加") { m2 in m2.restoreScenes(list) }
        }
    }

    func updateScene(_ s: ScriptScene) {
        guard let store, let old = scenes.first(where: { $0.id == s.id }) else { return }
        guard old != s else { return }
        perform { try store.updateScene(s) }
        if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s }
        registerUndo("場面の変更") { m in m.updateScene(old) }
        documentVersion += 1
    }

    func deleteScene(_ s: ScriptScene) {
        removeScene(s, actionName: "場面を削除")
    }

    /// 場面を（台詞ごと）消し、戻せるように中身と並び順を覚える
    private func removeScene(_ s: ScriptScene, actionName: String, register: Bool = true) {
        guard let store else { return }
        let savedLines = (try? store.lines(sceneId: s.id)) ?? []
        let order = scenes.map(\.id)
        perform { try store.deleteScene(id: s.id) }
        reloadScenes()
        guard register else { return }
        registerUndo(actionName) { m in m.restoreScene(s, lines: savedLines, order: order, actionName: actionName) }
    }

    private func restoreScene(_ s: ScriptScene, lines savedLines: [ScriptLine], order: [Int64], actionName: String) {
        guard let store, let id = selectedScenarioId else { return }
        perform {
            try store.insertScene(restoring: s)
            for l in savedLines { try store.insertLine(restoring: l) }
            try store.reorderScenes(scenarioId: id, ids: order)
        }
        reloadScenes()
        if selectedSceneId == s.id { loadLines() }
        registerUndo(actionName) { m in m.removeScene(s, actionName: actionName) }
    }

    func moveScenes(from source: IndexSet, to destination: Int) {
        guard let store, let id = selectedScenarioId else { return }
        let old = scenes.map(\.id)
        var ids = old
        ids.move(fromOffsets: source, toOffset: destination)
        guard ids != old else { return }
        perform { try store.reorderScenes(scenarioId: id, ids: ids) }
        reloadScenes()
        registerUndo("場面の並び替え") { m in m.reorderScenes(old) }
    }

    private func reorderScenes(_ ids: [Int64]) {
        guard let store, let id = selectedScenarioId else { return }
        let old = scenes.map(\.id)
        perform { try store.reorderScenes(scenarioId: id, ids: ids) }
        reloadScenes()
        registerUndo("場面の並び替え") { m in m.reorderScenes(old) }
    }

    func moveScene(_ s: ScriptScene, up: Bool) {
        var ids = scenes.map(\.id)
        guard let i = ids.firstIndex(of: s.id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        reorderScenes(ids)
    }

    var totalSceneSeconds: Int { scenes.reduce(0) { $0 + $1.totalSeconds } }

    // MARK: - 登場人物

    func reloadCharacters() {
        guard let store, let id = selectedScenarioId else { return }
        perform { characters = try store.characters(scenarioId: id) }
        documentVersion += 1
    }

    func addCharacter(name: String = "") {
        guard let store, let id = selectedScenarioId else { return }
        let n = name.isEmpty ? "登場人物\(characters.count + 1)" : name
        guard let cid = perform({ try store.insertCharacter(CastMember(scenarioId: id, name: n)) }) else { return }
        reloadCharacters()
        if let c = characters.first(where: { $0.id == cid }) {
            registerUndo("登場人物を追加") { m in m.removeCharacter(c, actionName: "登場人物を追加") }
        }
    }

    func updateCharacter(_ c: CastMember) {
        guard let store, let old = characters.first(where: { $0.id == c.id }) else { return }
        guard old != c else { return }
        perform { try store.updateCharacter(c) }
        if let i = characters.firstIndex(where: { $0.id == c.id }) { characters[i] = c }
        registerUndo("登場人物の変更") { m in m.updateCharacter(old) }
        documentVersion += 1
    }

    func deleteCharacter(_ c: CastMember) {
        removeCharacter(c, actionName: "登場人物を削除")
    }

    private func removeCharacter(_ c: CastMember, actionName: String) {
        guard let store, let id = selectedScenarioId else { return }
        let affected = ((try? store.allLines(scenarioId: id)) ?? []).filter { $0.characterId == c.id }.map(\.id)
        let order = characters.map(\.id)
        perform { try store.deleteCharacter(id: c.id) }
        reloadCharacters()
        loadLines()
        registerUndo(actionName) { m in m.restoreCharacter(c, lineIds: affected, order: order, actionName: actionName) }
    }

    private func restoreCharacter(_ c: CastMember, lineIds: [Int64], order: [Int64], actionName: String) {
        guard let store, let id = selectedScenarioId else { return }
        perform {
            try store.insertCharacter(restoring: c)
            try store.setCharacter(c.id, forLines: lineIds)
            try store.reorderCharacters(scenarioId: id, ids: order)
        }
        reloadCharacters()
        loadLines()
        registerUndo(actionName) { m in m.removeCharacter(c, actionName: actionName) }
    }

    func moveCharacters(from source: IndexSet, to destination: Int) {
        let old = characters.map(\.id)
        var ids = old
        ids.move(fromOffsets: source, toOffset: destination)
        guard ids != old else { return }
        reorderCharacters(ids)
    }

    private func reorderCharacters(_ ids: [Int64]) {
        guard let store, let id = selectedScenarioId else { return }
        let old = characters.map(\.id)
        perform { try store.reorderCharacters(scenarioId: id, ids: ids) }
        reloadCharacters()
        registerUndo("登場人物の並び替え") { m in m.reorderCharacters(old) }
    }

    func moveCharacter(_ c: CastMember, up: Bool) {
        var ids = characters.map(\.id)
        guard let i = ids.firstIndex(of: c.id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        reorderCharacters(ids)
    }

    // MARK: - 台詞（行）

    func loadLines() {
        guard let store, let sid = selectedSceneId else { lines = []; return }
        perform { lines = try store.lines(sceneId: sid) }
        if let id = selectedScenarioId { lineCounts = (try? store.lineCounts(scenarioId: id)) ?? [:] }
    }

    var selectedScene: ScriptScene? { scenes.first { $0.id == selectedSceneId } }

    func selectScene(offset: Int) {
        guard let cur = scenes.firstIndex(where: { $0.id == selectedSceneId }) else { selectedSceneId = scenes.first?.id; return }
        let n = cur + offset
        guard scenes.indices.contains(n) else { return }
        selectedSceneId = scenes[n].id
    }

    /// 行を追加。`after` が nil なら末尾、0 なら先頭。種別と人物は直前の行を引き継ぐ。
    func insertLine(after: Int64?, type: Int? = nil, characterId: Int64?? = nil) {
        guard let store, let scenarioId = selectedScenarioId, let sceneId = selectedSceneId else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        let ref: ScriptLine? = {
            if let a = after, a > 0 { return lines.first { $0.id == a } }
            if after == nil { return lines.last }
            return nil
        }()
        let t = type ?? ref?.type ?? 1
        let c: Int64? = characterId ?? (resolvedStyle(for: t).showsName ? ref?.characterId : nil)
        if let id = perform({ try store.insertLine(ScriptLine(scenarioId: scenarioId, sceneId: sceneId, type: t, characterId: c, text: ""), after: after) }) {
            loadLines()
            selectedLineId = id
            focusRequestLineId = id
            if let l = lines.first(where: { $0.id == id }) {
                registerUndo("行を追加") { m in m.removeLine(l, actionName: "行を追加") }
            }
            touchDocument()
        }
    }

    /// 前後の行の本文欄にフォーカスを移す（Tab / ⇧Tab / ⌘↓ / ⌘↑）
    func focusLine(offset: Int, from id: Int64? = nil) {
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        guard !lines.isEmpty else { return }
        let cur = (id ?? selectedLineId).flatMap { i in lines.firstIndex { $0.id == i } }
        let next: Int
        if let c = cur { next = min(max(c + offset, 0), lines.count - 1) } else { next = offset >= 0 ? 0 : lines.count - 1 }
        selectedLineId = lines[next].id
        focusRequestLineId = lines[next].id
    }

    func insertLine(before id: Int64) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        insertLine(after: i == 0 ? 0 : lines[i - 1].id, type: lines[i].type, characterId: .some(lines[i].characterId))
    }

    func updateLine(_ l: ScriptLine) {
        guard let store else { return }
        let old = lines.first { $0.id == l.id }
        if let old, old == l { return }
        perform { try store.updateLine(l) }
        if let i = lines.firstIndex(where: { $0.id == l.id }) { lines[i] = l }
        if let old {
            let name = old.text != l.text ? "本文の変更" : (old.type != l.type ? "種別の変更" : "登場人物の変更")
            registerUndo(name) { m in m.updateLine(old) }
        }
        touchDocument()
    }

    func deleteLine(_ id: Int64) {
        guard let l = lines.first(where: { $0.id == id }) else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        removeLine(l, actionName: "行を削除")
    }

    /// 行を消し、戻せるように中身と並び順を覚える
    private func removeLine(_ l: ScriptLine, actionName: String) {
        guard let store else { return }
        let idx = lines.firstIndex { $0.id == l.id }
        let order = (try? store.lines(sceneId: l.sceneId).map(\.id)) ?? []
        perform { try store.deleteLine(id: l.id) }
        if selectedSceneId == l.sceneId {
            loadLines()
            if let i = idx { selectedLineId = lines.indices.contains(i) ? lines[i].id : lines.last?.id }
        } else { loadLines() }
        registerUndo(actionName) { m in m.restoreLine(l, order: order, actionName: actionName) }
        touchDocument()
    }

    private func restoreLine(_ l: ScriptLine, order: [Int64], actionName: String) {
        guard let store else { return }
        perform {
            try store.insertLine(restoring: l)
            try store.reorderLines(sceneId: l.sceneId, ids: order)
        }
        if selectedSceneId != l.sceneId { selectedSceneId = l.sceneId } else { loadLines() }
        selectedLineId = l.id
        registerUndo(actionName) { m in m.removeLine(l, actionName: actionName) }
        touchDocument()
    }

    func moveLine(_ id: Int64, up: Bool) {
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        var ids = lines.map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        reorderLines(ids, in: lines.first { $0.id == id }?.sceneId ?? selectedSceneId ?? 0, select: id)
    }

    func moveLines(from source: IndexSet, to destination: Int) {
        guard let sid = selectedSceneId else { return }
        let old = lines.map(\.id)
        var ids = old
        ids.move(fromOffsets: source, toOffset: destination)
        guard ids != old else { return }
        reorderLines(ids, in: sid, select: nil)
    }

    private func reorderLines(_ ids: [Int64], in sceneId: Int64, select: Int64?) {
        guard let store else { return }
        let old = (try? store.lines(sceneId: sceneId).map(\.id)) ?? []
        perform { try store.reorderLines(sceneId: sceneId, ids: ids) }
        if selectedSceneId != sceneId { selectedSceneId = sceneId } else { loadLines() }
        if let s = select { selectedLineId = s }
        registerUndo("行の並び替え") { m in m.reorderLines(old, in: sceneId, select: select) }
        touchDocument()
    }

    func moveLine(_ id: Int64, toScene sceneId: Int64) {
        guard let store, let l = lines.first(where: { $0.id == id }) else { return }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        let fromOrder = lines.map(\.id)
        perform { try store.moveLine(id: id, toScene: sceneId) }
        loadLines()
        registerUndo("行を別の場面へ移動") { m in m.moveLineBack(id, toScene: l.sceneId, order: fromOrder, redoScene: sceneId) }
        touchDocument()
    }

    private func moveLineBack(_ id: Int64, toScene sceneId: Int64, order: [Int64], redoScene: Int64) {
        guard let store else { return }
        let redoOrder = (try? store.lines(sceneId: redoScene).map(\.id)) ?? []
        perform {
            try store.moveLine(id: id, toScene: sceneId)
            try store.reorderLines(sceneId: sceneId, ids: order)
        }
        if selectedSceneId != sceneId { selectedSceneId = sceneId } else { loadLines() }
        selectedLineId = id
        registerUndo("行を別の場面へ移動") { m in m.moveLineBack(id, toScene: redoScene, order: redoOrder, redoScene: sceneId) }
        touchDocument()
    }

    private var touchTask: Task<Void, Never>?
    /// 台詞を直したら更新日時と「読む」画面を（まとめて）更新
    func touchDocument() {
        touchTask?.cancel()
        touchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.documentVersion += 1
            self.refreshCurrentRecent()
        }
    }

    // MARK: - 検索・置換

    func search(_ q: String) -> [ScenarioStore.SearchHit] {
        guard let store, let id = selectedScenarioId else { return [] }
        return perform { try store.searchLines(scenarioId: id, query: q) } ?? []
    }

    func replaceAll(_ q: String, with r: String) -> Int {
        guard let store, let id = selectedScenarioId else { return 0 }
        NotificationCenter.default.post(name: .swFlushLineEdits, object: nil)
        let before = ((try? store.allLines(scenarioId: id)) ?? []).filter { $0.text.contains(q) }
        let n = perform { try store.replaceInLines(scenarioId: id, search: q, replacement: r) } ?? 0
        loadLines()
        if n > 0 { registerUndo("置換") { m in m.restoreTexts(before, redo: (q, r)) } }
        touchDocument()
        return n
    }

    private func restoreTexts(_ list: [ScriptLine], redo: (String, String)) {
        guard let store else { return }
        perform { for l in list { try store.updateLine(l) } }
        loadLines()
        registerUndo("置換") { m in _ = m.replaceAll(redo.0, with: redo.1) }
        touchDocument()
    }

    func reveal(hit: ScenarioStore.SearchHit) {
        section = .script
        if selectedSceneId != hit.line.sceneId { selectedSceneId = hit.line.sceneId }
        selectedLineId = hit.line.id
        focusRequestLineId = hit.line.id
    }

    // MARK: - スタイル・設定（共通設定に保存し、開いている作品ファイルにも写す）

    private func syncStylesToWork() {
        if let store { perform { try store.replaceStyles(styles, textStyles: textStyles, setting: setting) } }
        documentVersion += 1
    }

    func saveSetting(_ s: OptionSetting) {
        guard let settingsStore else { return }
        perform { try settingsStore.saveSetting(s) }
        setting = s
        syncStylesToWork()
    }

    func saveUserName(_ n: String) {
        guard let settingsStore else { return }
        perform { try settingsStore.setUserName(n) }
        userName = n
    }

    func reloadStyles() {
        guard let settingsStore else { return }
        perform { styles = try settingsStore.styles(); textStyles = try settingsStore.textStyles() }
        syncStylesToWork()
    }

    /// 固定スタイル（シノプシス・場面説明・登場人物）
    func textStyle(_ kind: TextStyleKind) -> TextStyle { textStyles.first { $0.kind == kind } ?? .default(kind) }
    func updateTextStyle(_ t: TextStyle) { guard let settingsStore else { return }; perform { try settingsStore.saveTextStyle(t) }; reloadStyles() }

    func addStyle(_ s: LineStyle) { guard let settingsStore else { return }; perform { try settingsStore.insertStyle(s) }; reloadStyles() }
    func updateStyle(_ s: LineStyle) { guard let settingsStore else { return }; perform { try settingsStore.updateStyle(s) }; reloadStyles() }
    func deleteStyle(_ s: LineStyle) { guard let settingsStore else { return }; perform { try settingsStore.deleteStyle(id: s.id) }; reloadStyles() }
    func resetStyles() { guard let settingsStore else { return }; perform { try settingsStore.resetStylesToDefault() }; reloadStyles() }

    /// すべてのスタイルのフォントサイズを同じ値にする
    func setAllStyleFontSizes(_ size: Int) {
        guard let settingsStore else { return }
        perform {
            for var st in styles { st.fontSize = size; try settingsStore.updateStyle(st) }
            for var t in textStyles { t.fontSize = size; try settingsStore.saveTextStyle(t) }
        }
        reloadStyles()
    }

    // MARK: - 出力

    func currentDocument() -> ScenarioDocument? {
        guard let store, let id = selectedScenarioId else { return nil }
        return perform { try store.document(scenarioId: id) } ?? nil
    }

    func readerHTML() -> String {
        guard let doc = currentDocument() else { return "" }
        return HtmlExporter.make(doc)
    }

    private func savePanel(name: String, ext: String, message: String) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = "\(TextFormat.safeFileName(name)).\(ext)"
        p.message = message
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    func exportText(encoding: TextExporter.Encoding, lineEnding: TextExporter.LineEnding) {
        guard let doc = currentDocument() else { return }
        guard let url = savePanel(name: doc.scenario.title, ext: "txt", message: "テキスト台本の保存先") else { return }
        perform { try TextExporter.makeData(doc, encoding: encoding, lineEnding: lineEnding).write(to: url) }
        infoMessage = "テキストを保存しました。"
    }

    func exportDocx(template: DocxExporter.Template, cover: DocxExporter.CoverInfo) {
        guard let doc = currentDocument() else { return }
        guard let url = savePanel(name: doc.scenario.title + "_" + template.label.replacingOccurrences(of: " ", with: ""), ext: "docx", message: "Word 台本の保存先") else { return }
        perform { try DocxExporter.make(doc, template: template, cover: cover, userName: userName).write(to: url) }
        infoMessage = "Word ファイルを保存しました。"
    }

    func exportXml(cover: DocxExporter.CoverInfo) {
        guard let doc = currentDocument() else { return }
        guard let url = savePanel(name: doc.scenario.title, ext: "xml", message: "Word 2003 XML の保存先") else { return }
        perform { try Data(try XmlExporter.make(doc, cover: cover).utf8).write(to: url) }
        infoMessage = "XML を保存しました。"
    }

    func exportHtml() {
        guard let doc = currentDocument() else { return }
        guard let url = savePanel(name: doc.scenario.title, ext: "html", message: "劇団員に渡す HTML の保存先（このファイル 1 つで読めます）") else { return }
        perform { try Data(HtmlExporter.make(doc).utf8).write(to: url) }
        infoMessage = "HTML を保存しました。メールや LINE でそのまま送れます。"
    }

    /// 開いている作品ファイルを Web 版の swdata.sqlite として書き出す
    func exportForWeb() {
        guard let cur = workingURL else { return }
        guard let url = savePanel(name: "swdata", ext: "sqlite", message: "Web 版 ScenarioWriterCafe の sw_config/swdata.sqlite として置けるファイルを書き出します（この作品だけが入ります）") else { return }
        perform {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: cur, to: url)
        }
        infoMessage = "書き出しました。Web 版の sw_config/swdata.sqlite として置くと、この作品がそのまま開けます。"
    }

    // MARK: - 取り込み・Finder

    func revealCurrent() {
        if let cur = currentWorkURL { NSWorkspace.shared.activateFileViewerSelecting([cur]) }
    }

    /// Web 版の swdata.sqlite（sw_config フォルダごとがおすすめ）や 1.0.0 のバックアップを、作品ごとの .scwd に分けて保存する。
    /// 取り込み元 → 分割先フォルダ の順に選ぶ。
    func importDatabase(source presetSource: URL? = nil) {
        var source = presetSource
        if source == nil {
            let p = NSOpenPanel()
            p.message = "取り込み元: Web 版の sw_config フォルダごと（おすすめ。書きかけの更新が入った swdata.sqlite-wal も一緒に読めます）、または swdata.sqlite を選びます。"
            p.prompt = "取り込み元にする"
            p.allowsMultipleSelection = false
            p.canChooseDirectories = true
            p.canChooseFiles = true
            p.allowedContentTypes = [.data, .folder]
            guard p.runModal() == .OK, let u = p.url else { return }
            source = u
        }
        guard let src = source else { return }
        let d = NSOpenPanel()
        d.message = "分割先: 作品ごとの .scwd ファイルを入れるフォルダを選びます（書類の中に「ScenarioWriterSolo」などを作るのがおすすめ）。"
        d.prompt = "このフォルダに保存"
        d.canChooseDirectories = true
        d.canChooseFiles = false
        d.canCreateDirectories = true
        d.allowsMultipleSelection = false
        d.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard d.runModal() == .OK, let dest = d.url else { return }
        let okS = src.startAccessingSecurityScopedResource()
        let okD = dest.startAccessingSecurityScopedResource()
        defer { if okS { src.stopAccessingSecurityScopedResource() }; if okD { dest.stopAccessingSecurityScopedResource() } }
        let stylesToo = recents.isEmpty && styles.count == ScenarioStore.defaultStyles.count
        var n = 0, lineCount = 0
        var importedStyles = false
        var first: URL?
        perform {
            let (db, cleanup) = try ScenarioStore.openSource(src)
            defer { cleanup() }
            if stylesToo, let st = try ScenarioStore.styles(in: db), let settings = settingsStore {
                try settings.replaceStyles(st.styles, textStyles: st.textStyles, setting: st.setting)
                styles = try settings.styles()
                textStyles = try settings.textStyles()
                setting = try settings.setting()
                importedStyles = true
            }
            try FileManager.default.createDirectory(at: Self.workDirectory, withIntermediateDirectories: true)
            for s in try ScenarioStore.scenarios(in: db) {
                let dst = ScenarioStore.uniqueWorkURL(in: dest, title: s.title)
                let data = try buildWorkFile { w in
                    let nid = try w.importScenario(from: db, scenarioId: s.id)
                    // 1.0.0 の作品画像（thumb/<ID>.png）があれば同梱
                    if let png = try? Data(contentsOf: Self.thumbDirectory.appendingPathComponent("\(s.id).png")) { try w.setThumbnail(scenarioId: nid, png: png) }
                    lineCount += Int(try w.db.scalarInt("SELECT COUNT(*) FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ?", [.int(nid)]) ?? 0)
                    return nid
                }
                try data.write(to: dst, options: .atomic)
                if first == nil { first = dst }
                n += 1
            }
        }
        if n > 0 {
            NSWorkspace.shared.activateFileViewerSelecting([first ?? dest])
            infoMessage = "\(n) 作品（台詞 \(lineCount) 行）を、作品ごとのファイルとして「\(dest.lastPathComponent)」に保存しました。" + (importedStyles ? "スタイル設定も引き継ぎました。" : "") + "「ファイル › 開く…」で開けます。"
            if n == 1, let f = first { openWork(f) }
        }
    }

    /// 1.0.0 の全作品入り DB を作品ファイルに分ける
    func migrateLegacy() {
        let legacy = Self.legacyDatabaseURL
        guard FileManager.default.fileExists(atPath: legacy.path) else { hasLegacyDatabase = false; return }
        importDatabase(source: legacy)
        // 分割できたら（infoMessage が出る）元の DB は改名して残す
        if infoMessage != nil {
            let moved = Self.dataDirectory.appendingPathComponent("swdata.migrated.sqlite")
            try? FileManager.default.removeItem(at: moved)
            try? FileManager.default.moveItem(at: legacy, to: moved)
            hasLegacyDatabase = false
        }
    }
}

extension Notification.Name {
    static let swFlushLineEdits = Notification.Name("swFlushLineEdits")
}

/// 編集画面のフォント設定（UserDefaults。作品ファイルには入れない）
enum EditorFont {
    static let familyKey = "editorFontFamily"      // "" = システムフォント
    static let sizeKey = "editorFontSize"          // 基準サイズ（スタイルのサイズ 12 のときの大きさ）
    static let lineHeightKey = "editorLineHeight"  // 行間（倍率）
    static let kernKey = "editorKern"              // 文字間隔（pt）

    static func font(family: String, size: CGFloat) -> NSFont {
        if family.isEmpty { return NSFont.systemFont(ofSize: size) }
        let desc = NSFontDescriptor(fontAttributes: [.family: family])
        return NSFont(descriptor: desc, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// スタイルのサイズ（12 が標準）を編集画面の大きさに直す
    static func pointSize(base: Double, styleSize: Int) -> CGFloat {
        CGFloat(base) + CGFloat(styleSize - 12) * 0.5
    }

    /// 日本語が使えるフォントファミリーを先頭に、残りを名前順で
    static var families: [String] {
        let all = NSFontManager.shared.availableFontFamilies
        let jp = ["Hiragino Sans", "Hiragino Mincho ProN", "Hiragino Maru Gothic ProN", "YuGothic", "YuMincho", "Toppan Bunkyu Gothic", "Toppan Bunkyu Mincho", "Toppan Bunkyu Midashi Gothic", "Toppan Bunkyu Midashi Mincho", "Tsukushi A Round Gothic", "Tsukushi B Round Gothic", "Klee", "Osaka"]
        let present = jp.filter { all.contains($0) }
        let rest = all.filter { !present.contains($0) && !$0.hasPrefix(".") }.sorted()
        return present + rest
    }
}

extension Color {
    /// "#rrggbb" → Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = .primary; return }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// スタイルの色（明るい背景向けの黒・濃緑・暗赤など）をダークモードでも読めるようにする
    static func adaptive(hex: String, dark: Bool) -> Color {
        guard dark else { return Color(hex: hex) }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .primary }
        let ns = NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        if sat < 0.15 && b < 0.5 { return .primary }
        if b < 0.7 { return Color(nsColor: NSColor(hue: h, saturation: sat * 0.8, brightness: 0.85, alpha: 1)) }
        return Color(hex: hex)
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
