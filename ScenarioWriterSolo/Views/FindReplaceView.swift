import SwiftUI
import ScenarioWriterCore

/// 作品全体の台詞を検索・置換（インスペクタ）
struct FindReplaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var replacement = ""
    @State private var hits: [ScenarioStore.SearchHit] = []
    @State private var confirmReplace = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("検索と置換").font(.headline)
            TextField("探す言葉", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { runSearch() }
                .onChange(of: query) { _, _ in runSearch() }
            HStack {
                TextField("置き換える言葉", text: $replacement).textFieldStyle(.roundedBorder)
                Button("すべて置換") { confirmReplace = true }
                    .disabled(query.isEmpty || hits.isEmpty)
            }
            if !query.isEmpty {
                Text(hits.isEmpty ? "見つかりません" : "\(hits.count) 行に見つかりました。クリックすると移動します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List(hits) { h in
                Button {
                    model.reveal(hit: h)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(h.sceneName.isEmpty ? "（無題の場面）" : h.sceneName).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            let f = model.formatted(h.line)
                            if !f.label.isEmpty { Text(f.label).font(.caption).fontWeight(.semibold) }
                        }
                        highlighted(h.line.text)
                            .lineLimit(3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding()
        .onAppear { focused = true; runSearch() }
        .onChange(of: model.documentVersion) { _, _ in runSearch() }
        .confirmationDialog("\(hits.count) 行の「\(query)」を「\(replacement)」に置き換えますか？", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("置換する") {
                let n = model.replaceAll(query, with: replacement)
                model.infoMessage = "\(n) 行を置き換えました。"
                runSearch()
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("元に戻せません。") }
    }

    private func runSearch() {
        hits = model.search(query)
    }

    private func highlighted(_ text: String) -> Text {
        guard !query.isEmpty else { return Text(text) }
        var result = Text("")
        var rest = text[...]
        while let r = rest.range(of: query, options: .caseInsensitive) {
            result = result + Text(String(rest[rest.startIndex..<r.lowerBound]))
            result = result + Text(String(rest[r])).bold().foregroundColor(.orange)
            rest = rest[r.upperBound...]
        }
        return result + Text(String(rest))
    }
}
