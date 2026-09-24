import SwiftUI
import ScenarioWriterCore

/// 台本の書き出し（Web 版「ダウンロード」）
struct ExportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.encoding") private var encodingRaw = TextExporter.Encoding.utf8.rawValue
    @AppStorage("export.lineEnding") private var lineEndingRaw = TextExporter.LineEnding.lf.rawValue
    @AppStorage("export.template") private var templateRaw = DocxExporter.Template.a4PortraitVertical.rawValue
    @AppStorage("export.writerId") private var writerId = ""
    @AppStorage("export.version") private var version = ""
    @AppStorage("export.address") private var address = ""
    @AppStorage("export.phone") private var phone = ""
    @AppStorage("export.email") private var email = ""
    @AppStorage("export.pdfTrimMarks") private var pdfTrimMarks = false
    @State private var writerName = ""
    @State private var useDate = true
    @State private var date = Date()

    private var encoding: TextExporter.Encoding { TextExporter.Encoding(rawValue: encodingRaw) ?? .utf8 }
    private var lineEnding: TextExporter.LineEnding { TextExporter.LineEnding(rawValue: lineEndingRaw) ?? .lf }
    private var template: DocxExporter.Template { DocxExporter.Template(rawValue: templateRaw) ?? .a4PortraitVertical }
    private var cover: DocxExporter.CoverInfo {
        .init(writerName: writerName, writerId: writerId, version: version, date: useDate ? date : nil, address: address, phone: phone, email: email)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("「\(model.scenario?.title ?? "")」を台本ファイルにします。")
                }
                Section("テキスト（.txt）") {
                    Text("文字だけのファイル。字下げは全角空白で揃え、1 行の文字数は「設定 › 書式」の文字数に従います。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("文字コード", selection: $encodingRaw) {
                            ForEach(TextExporter.Encoding.allCases) { e in Text(e.rawValue).tag(e.rawValue) }
                        }
                        Picker("改行コード", selection: $lineEndingRaw) {
                            ForEach(TextExporter.LineEnding.allCases) { e in Text(e.rawValue).tag(e.rawValue) }
                        }
                        Spacer()
                        Button("テキストを保存…") { model.exportText(encoding: encoding, lineEnding: lineEnding) }
                    }
                }
                Section("Word（.docx）・PDF") {
                    Text("Word は株式会社 deerstudio 配布の脚本テンプレートを使ったファイル（Word 2007 以降）。PDF は同じ用紙・書き方で組み、文字をアウトライン化するので印刷所への版下にそのまま使えます。表紙に下の情報が入ります。")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("用紙・書き方", selection: $templateRaw) {
                        ForEach(DocxExporter.Template.allCases) { t in Text(t.label).tag(t.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    TextField("作者名", text: $writerName)
                    TextField("脚本協会登録番号など", text: $writerId)
                    TextField("草稿バージョンなど（例: 第 1 稿）", text: $version)
                    HStack {
                        Toggle("日付", isOn: $useDate).toggleStyle(.checkbox)
                        DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().disabled(!useDate)
                        Text(useDate ? TextFormat.wareki(date) : "（表紙に日付を入れない）").foregroundStyle(.secondary)
                    }
                    TextField("住所", text: $address)
                    TextField("電話番号", text: $phone)
                    TextField("電子メール", text: $email)
                    HStack {
                        Toggle("PDF にトンボと裁ち落とし（3mm）を付ける", isOn: $pdfTrimMarks).toggleStyle(.checkbox)
                        Spacer()
                        Button("PDF を保存…") { model.exportPdf(template: template, cover: cover, options: .init(trimMarks: pdfTrimMarks)) }
                        Button("Word を保存…") { model.exportDocx(template: template, cover: cover) }
                    }
                }
                Section("そのほか") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("XML（Word 2003 XML、横書き）")
                            Text("表紙の情報は上の Word の欄を使います。").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("XML を保存…") { model.exportXml(cover: cover) }
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("HTML（劇団員に渡す 1 ファイル）")
                            Text("スマホでも読め、縦書き / 横書きと文字サイズを切り替えられます。").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("HTML を保存…") { model.exportHtml() }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 640, height: 720)
        .onAppear { writerName = model.scenario?.writerName ?? "" }
    }
}
