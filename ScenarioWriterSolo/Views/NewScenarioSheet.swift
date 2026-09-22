import SwiftUI
import ScenarioWriterCore

/// 新規シナリオ（Web 版 swNewScenario.php と同じ項目）
struct NewScenarioSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subtitle = ""
    @State private var writer = ""
    @State private var category = 0
    @State private var memo = ""
    @State private var acts = 1
    @State private var scenesPerAct = 3
    @State private var actBefore = "第"
    @State private var actAfter = "幕"
    @State private var sceneBefore = "　"
    @State private var sceneAfter = "場"
    @State private var characterCount = 3
    @State private var characterPrefix = "登場人物"

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("作品") {
                    TextField("タイトル（ファイル名にもなります）", text: $title)
                    TextField("サブタイトル", text: $subtitle)
                    TextField("作者名", text: $writer)
                    Picker("分類", selection: $category) {
                        ForEach(ScenarioCategory.allCases) { c in Text(c.label).tag(c.rawValue) }
                    }
                    TextField("メモ（台本には出ません）", text: $memo, axis: .vertical).lineLimit(2...4)
                }
                Section("場面設定") {
                    HStack {
                        Stepper("幕の数: \(acts)", value: $acts, in: 0...20)
                        Stepper("1 幕あたりの場の数: \(scenesPerAct)", value: $scenesPerAct, in: 0...50)
                    }
                    HStack(spacing: 4) {
                        Text("場面名:")
                        TextField("", text: $actBefore).frame(width: 40)
                        Text("1").foregroundStyle(.secondary)
                        TextField("", text: $actAfter).frame(width: 40)
                        TextField("", text: $sceneBefore).frame(width: 40)
                        Text("1").foregroundStyle(.secondary)
                        TextField("", text: $sceneAfter).frame(width: 40)
                        Spacer()
                        Text("例: \(sampleSceneName)").foregroundStyle(.secondary)
                    }
                    Text("あとから「場面」画面で足したり名前を変えたりできます。0 にすれば場面なしで始められます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("登場人物") {
                    HStack {
                        Stepper("人数: \(characterCount)", value: $characterCount, in: 0...50)
                        TextField("仮の名前", text: $characterPrefix).frame(width: 140)
                        Text("→ \(characterPrefix)1, \(characterPrefix)2 …").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("新規シナリオ登録") {
                    model.createScenario(Scenario(title: title.isEmpty ? "無題" : title, subtitle: subtitle, writerName: writer, memo: memo, category: category),
                                         acts: acts, scenesPerAct: scenesPerAct, actFormat: (actBefore, actAfter), sceneFormat: (sceneBefore, sceneAfter),
                                         characterCount: characterCount, characterPrefix: characterPrefix)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 620, height: 560)
        .onAppear { writer = model.recents.first?.scenario.writerName ?? "" }
    }

    private var sampleSceneName: String {
        acts > 1 ? "\(actBefore)1\(actAfter)\(sceneBefore)1\(sceneAfter)" : "\(actBefore)1\(actAfter)\(sceneBefore)1\(sceneAfter)"
    }
}
