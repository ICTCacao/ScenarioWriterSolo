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
                Text("書き出す HTML と同じ見え方です。上のバーで場面ジャンプ・文字サイズ・縦書き / 横書きを切り替えられます。")
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
            WebView(html: html, vertical: vertical, fontSize: fontSize, onPrefs: { v, fs in vertical = v; fontSize = fs })
        }
        .onAppear { rebuild() }
        .onChange(of: model.documentVersion) { _, _ in rebuild() }
        .onChange(of: model.selectedScenarioId) { _, _ in rebuild() }
        .onDisappear { MinimapModel.shared.detach("reader") }
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    /// ページの縦書き / 横書き。ツールバーのボタンで変わったらページに伝える（ページのバーで変えたときは onPrefs で戻ってくる）
    var vertical: Bool? = nil
    /// ページの文字の大きさ。ツールバーのスライダーで変わったらページに伝える
    var fontSize: Int? = nil
    var onPrefs: ((Bool, Int) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "swPrefs")
        cfg.userContentController.add(context.coordinator, name: "swMap")
        context.coordinator.onPrefs = onPrefs
        let v = WKWebView(frame: .zero, configuration: cfg)
        context.coordinator.webView = v
        v.setValue(false, forKey: "drawsBackground")
        v.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        context.coordinator.lastVertical = vertical
        context.coordinator.lastFontSize = fontSize
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        if let vertical, context.coordinator.lastVertical != vertical {
            context.coordinator.lastVertical = vertical
            v.evaluateJavaScript("window.swSetVertical && window.swSetVertical(\(vertical))", completionHandler: nil)
        }
        if let fontSize, context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            v.evaluateJavaScript("window.swSetFontSize && window.swSetFontSize(\(fontSize))", completionHandler: nil)
        }
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

    static func dismantleNSView(_ v: WKWebView, coordinator: Coordinator) {
        // 画面が消えたあとに届いたミニマップの知らせで、ミニマップを出し直さないように
        coordinator.webView = nil
        v.configuration.userContentController.removeScriptMessageHandler(forName: "swMap")
        v.configuration.userContentController.removeScriptMessageHandler(forName: "swPrefs")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML = ""
        var pendingScroll: [Double]?
        var lastVertical: Bool?
        var lastFontSize: Int?
        weak var webView: WKWebView?
        var onPrefs: ((Bool, Int) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "swMap", let d = message.body as? [String: Any] { minimap(d); return }
            guard message.name == "swPrefs", let d = message.body as? [String: Any] else { return }
            let v = (d["v"] as? Bool) ?? false
            let fs = (d["fs"] as? Int) ?? Int((d["fs"] as? Double) ?? 16)
            lastVertical = v
            lastFontSize = fs
            onPrefs?(v, fs)
        }
        /// ページからの知らせ（行の並び・見えている範囲）をツールバーのミニマップへ
        private func minimap(_ d: [String: Any]) {
            guard webView != nil else { return }
            let map = MinimapModel.shared
            map.attach("reader", rightToLeft: (d["rtl"] as? Bool) ?? false) { [weak self] f in
                self?.webView?.evaluateJavaScript("window.swMapJump && window.swMapJump(\(f))", completionHandler: nil)
            }
            if let raw = d["marks"] as? [[Any]] {
                func num(_ v: Any) -> CGFloat { CGFloat((v as? NSNumber)?.doubleValue ?? 0) }
                map.setMarks(raw.compactMap { a in
                    guard a.count >= 5 else { return nil }
                    let head = num(a[4]) > 0
                    return .init(pos: num(a[0]), len: num(a[1]), fill: num(a[2]),
                                 color: head ? nil : Color(cssRGB: (a[3] as? String) ?? "", plainAsNil: true), heading: head)
                })
            }
            map.setVisible(CGFloat((d["lo"] as? NSNumber)?.doubleValue ?? 0), CGFloat((d["hi"] as? NSNumber)?.doubleValue ?? 1))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let p = pendingScroll else { return }
            pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(\(p[0]), \(p[1])); var s=document.querySelector('.pv-scroll'); if(s){s.scrollLeft=\(p[2]);}", completionHandler: nil)
        }
    }
}
