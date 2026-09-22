import SwiftUI
import WebKit
import ScenarioWriterCore

/// 通し読み（Web 版「シナリオを読む」「劇団員プレビュー」）。HTML 書き出しと同じものを表示する。
struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("readerVertical") private var vertical = false
    @AppStorage("readerFontSize") private var fontSize = 16
    @State private var html = ""

    private func rebuild() {
        guard let doc = model.currentDocument() else { html = ""; return }
        html = HtmlExporter.make(doc, options: .init(vertical: vertical, fontSize: fontSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("書き出す HTML と同じ見え方です。下のバーで場面ジャンプ・文字サイズ・縦書き / 横書きを切り替えられます。")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.exportHtml() } label: { Label("HTML を保存…", systemImage: "square.and.arrow.up") }
                Button { model.exportText(encoding: .utf8, lineEnding: .lf) } label: { Label("テキストを保存…", systemImage: "doc.plaintext") }
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            WebView(html: html, onPrefs: { v, fs in vertical = v; fontSize = fs })
        }
        .onAppear { rebuild() }
        .onChange(of: model.documentVersion) { _, _ in rebuild() }
        .onChange(of: model.selectedScenarioId) { _, _ in rebuild() }
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    var onPrefs: ((Bool, Int) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "swPrefs")
        context.coordinator.onPrefs = onPrefs
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        v.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        // スクロール位置を保ったまま差し替える
        v.evaluateJavaScript("[window.scrollX, window.scrollY, (document.querySelector('.pv-scroll')||{}).scrollLeft||0]") { r, _ in
            let pos = (r as? [Double]) ?? [0, 0, 0]
            v.loadHTMLString(html, baseURL: nil)
            context.coordinator.pendingScroll = pos
        }
        v.navigationDelegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML = ""
        var pendingScroll: [Double]?
        var onPrefs: ((Bool, Int) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "swPrefs", let d = message.body as? [String: Any] else { return }
            let v = (d["v"] as? Bool) ?? false
            let fs = (d["fs"] as? Int) ?? Int((d["fs"] as? Double) ?? 16)
            onPrefs?(v, fs)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let p = pendingScroll else { return }
            pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(\(p[0]), \(p[1])); var s=document.querySelector('.pv-scroll'); if(s){s.scrollLeft=\(p[2]);}", completionHandler: nil)
        }
    }
}
