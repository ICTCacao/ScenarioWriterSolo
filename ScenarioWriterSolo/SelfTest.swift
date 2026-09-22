import Foundation
import AppKit
import ScenarioWriterCore

/// 動作確認用: `open App --args -openFile <scwd> -selfTestUndo <出力ファイル>` で起動すると、
/// 元に戻す／やり直すを一通り実行して結果を書き出し、終了する。ふだんは動かない。
enum SelfTest {
    @MainActor
    static func runIfRequested(_ model: AppModel) {
        guard let out = UserDefaults.standard.string(forKey: "selfTestUndo"), !out.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            var log: [String] = []
            func check(_ name: String, _ ok: Bool) { log.append((ok ? "PASS " : "FAIL ") + name) }
            guard let um = NSApp.keyWindow?.undoManager ?? NSApp.windows.first?.undoManager else {
                log.append("FAIL no undo manager"); finish(out, log); return
            }
            func undo() { um.undo() }
            func redo() { um.redo() }

            guard model.scenario != nil, !model.lines.isEmpty else { log.append("FAIL no work open"); finish(out, log); return }
            let n = model.lines.count
            let first = model.lines[0]

            // 行を追加 → 戻す → やり直す
            model.insertLine(after: nil)
            check("insert", model.lines.count == n + 1)
            undo(); check("insert undo", model.lines.count == n)
            redo(); check("insert redo", model.lines.count == n + 1)
            undo(); check("insert undo2", model.lines.count == n)

            // 行を削除 → 戻す（同じ ID・同じ位置）
            model.deleteLine(first.id)
            check("delete", model.lines.count == n - 1 && !model.lines.contains { $0.id == first.id })
            undo(); check("delete undo", model.lines.count == n && model.lines[0].id == first.id && model.lines[0].text == first.text)

            // 並び替え
            let second = model.lines[1]
            model.moveLine(first.id, up: false)
            check("move", model.lines[0].id == second.id && model.lines[1].id == first.id)
            undo(); check("move undo", model.lines[0].id == first.id && model.lines[1].id == second.id)

            // 種別の変更
            var l = model.lines[1]; let oldType = l.type; l.type = oldType == 2 ? 1 : 2
            model.updateLine(l)
            check("type", model.lines[1].type == l.type)
            undo(); check("type undo", model.lines[1].type == oldType)

            // 置換
            let word = "三条さん"
            let before = model.lines.filter { $0.text.contains(word) }
            let dbBefore = ((try? model.store?.allLines(scenarioId: model.selectedScenarioId ?? 0)) ?? nil) ?? []
            log.append("INFO dbBefore174=\(dbBefore.first { $0.id == 174 }?.text.prefix(20) ?? "nil") dbBeforeCount=\(dbBefore.filter { $0.text.contains(word) }.count) totalDb=\(dbBefore.count) totalModel=\(model.lines.count)")
            let cnt = model.replaceAll(word, with: "三條さん")
            let still = model.lines.filter { $0.text.contains(word) }.count
            let after = ((try? model.store?.allLines(scenarioId: model.selectedScenarioId ?? 0)) ?? nil) ?? []
            log.append("INFO replace cnt=\(cnt) before=\(before.count) still=\(still) err=\(model.errorMessage ?? "-")")
            log.append("INFO before ids=\(before.map { "\($0.id):\($0.text.prefix(12))" })")
            log.append("INFO after with 三條=\(after.filter { $0.text.contains("三條さん") }.map { "\($0.id):\($0.text.prefix(12))" })")
            log.append("INFO model174=\(model.lines.first { $0.id == 174 }?.text ?? "nil") db174=\(after.first { $0.id == 174 }?.text ?? "nil") db174scene=\(after.first { $0.id == 174 }?.sceneId ?? -1)")
            check("replace", cnt >= before.count && still == 0)   // 置換は全場面が対象
            undo(); check("replace undo", model.lines.filter { $0.text.contains(word) }.count == before.count)

            // 場面の削除
            let sc = model.scenes.count
            if model.scenes.count > 1 {
                let last = model.scenes[model.scenes.count - 1]
                model.deleteScene(last)
                check("scene delete", model.scenes.count == sc - 1)
                undo(); check("scene delete undo", model.scenes.count == sc && model.scenes.last?.id == last.id)
            }

            // 登場人物の削除（台詞の参照も戻る）
            if let c = model.characters.first, let anyLine = model.lines.first(where: { $0.characterId == c.id }) {
                model.deleteCharacter(c)
                check("cast delete", !model.characters.contains { $0.id == c.id } && model.lines.first { $0.id == anyLine.id }?.characterId == nil)
                undo(); check("cast delete undo", model.characters.first?.id == c.id && model.lines.first { $0.id == anyLine.id }?.characterId == c.id)
            }

            // シノプシス
            let syn = model.synopsis
            model.saveSynopsis(syn + "追記")
            check("synopsis", model.synopsis == syn + "追記")
            undo(); check("synopsis undo", model.synopsis == syn)

            // 未保存 → 保存 → 本ファイルに反映
            check("dirty", model.isDirty)
            model.saveNow(quiet: true)
            check("saved", !model.isDirty)
            if let cur = model.currentWorkURL, let sum = ScenarioStore.summary(of: cur) {
                check("written back", sum.scenario.title == model.scenario?.title)
            }
            model.saveSynopsis((model.synopsis) + "x")
            check("dirty again", model.isDirty)
            finish(out, log)
        }
    }

    @MainActor
    static func finish(_ out: String, _ log: [String]) {
        try? log.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        // 動作確認用の起動なので、確認ダイアログや終了処理を通さずにそのまま終わる
        // （NSApp.terminate を非同期タスクの中から呼ぶと AppKit が落ちてクラッシュレポートが残る）
        AppDelegate.model?.closeWork(discardChanges: true)
        exit(0)
    }
}
