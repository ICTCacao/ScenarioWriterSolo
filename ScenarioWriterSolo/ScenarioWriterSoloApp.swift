import SwiftUI
import AppKit
import ScenarioWriterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    static var reopenWindow: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 未保存なら「保存 / 保存しない / キャンセル」。キャンセルならウインドウを開き直す
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model else { return .terminateNow }
        if model.prepareForTermination() { return .terminateNow }
        Self.reopenWindow?()
        return .terminateCancel
    }
}

@main
struct ScenarioWriterSoloApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("editorVertical") private var editorVertical = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .systemServices) {}
            CommandGroup(replacing: .newItem) {
                Button("新規シナリオ…") { model.showNewScenario = true }
                    .keyboardShortcut("n")
                Button("開く…") { model.openWorkPanel() }
                    .keyboardShortcut("o")
                Menu("最近使った作品") {
                    ForEach(model.recents) { w in
                        Button(w.scenario.title.isEmpty ? w.url.lastPathComponent : w.scenario.title) { model.open(work: w) }
                    }
                    if !model.recents.isEmpty {
                        Divider()
                        Button("一覧を消す") { model.clearRecents() }
                    }
                }
                Button("作品を選ぶ") { model.chooseScenario() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("閉じる") { model.closeWork() }
                    .keyboardShortcut("w")
                    .disabled(model.scenario == nil)
                Button("保存") { model.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(model.scenario == nil || !model.isDirty)
                Button("別名で保存…") { model.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.scenario == nil)
                Button("複製を保存…") { model.copyScenario() }
                    .disabled(model.scenario == nil)
                Button("最後に保存した状態に戻す") { model.revertToSaved() }
                    .disabled(!model.isDirty)
                Button("ゴミ箱に入れる…") { model.confirmDeleteScenario = true }
                    .disabled(model.scenario == nil)
                Divider()
                Button("台本を書き出す…") { model.showExport = true }
                    .keyboardShortcut("e")
                    .disabled(model.scenario == nil)
                Button("この作品を Web 版用に書き出す…") { model.exportForWeb() }
                    .disabled(model.scenario == nil)
                Divider()
                Button("Web 版・バックアップから取り込む…") { model.importDatabase() }
                Button("旧形式（SQLite）の作品ファイルをまとめて変換…") { model.convertLegacyWorks() }
                Button("Finder で表示") { model.revealCurrent() }
                    .disabled(model.scenario == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("検索と置換") { model.showFindReplace.toggle() }
                    .keyboardShortcut("f")
                    .disabled(model.scenario == nil)
                Divider()
                // 縦書きでは行が右から左へ並ぶので「下/上」ではなく「左/右」。次・前の行も ⌘← / ⌘→（本文欄の keyDown と同じ）
                Button(editorVertical ? "この左に行を追加" : "この下に行を追加") { model.insertLine(after: model.selectedLineId) }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.selectedSceneId == nil || model.section != .script)
                Button(editorVertical ? "この右に行を追加" : "この上に行を追加") { if let id = model.selectedLineId { model.insertLine(before: id) } }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(model.selectedLineId == nil || model.section != .script)
                Button(editorVertical ? "次の行へ（左）" : "次の行へ") { model.focusLine(offset: 1) }
                    .keyboardShortcut(editorVertical ? .leftArrow : .downArrow, modifiers: [.command])
                    .disabled(model.section != .script || model.lines.isEmpty)
                Button(editorVertical ? "前の行へ（右）" : "前の行へ") { model.focusLine(offset: -1) }
                    .keyboardShortcut(editorVertical ? .rightArrow : .upArrow, modifiers: [.command])
                    .disabled(model.section != .script || model.lines.isEmpty)
                Divider()
                Button("行を上へ") { if let id = model.selectedLineId { model.moveLine(id, up: true) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(model.selectedLineId == nil || model.section != .script)
                Button("行を下へ") { if let id = model.selectedLineId { model.moveLine(id, up: false) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(model.selectedLineId == nil || model.section != .script)
                Button("行を削除") { if let id = model.selectedLineId { model.deleteLine(id) } }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(model.selectedLineId == nil || model.section != .script)
            }
            CommandMenu("シナリオ") {
                ForEach(Array(EditorSection.allCases.enumerated()), id: \.element.id) { i, sec in
                    Button(sec.label) { model.section = sec }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command])
                        .disabled(model.scenario == nil)
                }
                Divider()
                Toggle("縦書きで編集", isOn: $editorVertical)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
                Button("前の場面") { model.selectScene(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(model.scenario == nil)
                Button("次の場面") { model.selectScene(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(model.scenario == nil)
            }
            CommandGroup(replacing: .help) {
                Button("ScenarioWriterSolo について（README）") {
                    if let url = Bundle.main.url(forResource: "README", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
