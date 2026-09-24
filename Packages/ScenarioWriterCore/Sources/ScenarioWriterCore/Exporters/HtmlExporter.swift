import Foundation

/// 読むための HTML（1 ファイル完結）。Web 版「劇団員プレビュー」の閲覧ページと同じ見た目・操作
/// （場面ジャンプ・文字サイズ・縦書き/横書き）。アプリ内の「読む」画面もこれを表示する。
public enum HtmlExporter {

    public struct Options: Sendable {
        public var vertical: Bool
        public var fontSize: Int
        public var showBar: Bool
        public init(vertical: Bool = false, fontSize: Int = 16, showBar: Bool = true) {
            self.vertical = vertical; self.fontSize = fontSize; self.showBar = showBar
        }
    }

    /// 表示用: 半角の英数・カナを全角にしてから HTML エスケープ（テキスト出力と同じ「日本語英数」の見え方）
    static func text(_ s: String) -> String {
        TextFormat.htmlEscape(TextFormat.toFullWidth(s)).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }

    static func isSafeColor(_ c: String) -> Bool {
        let r = c.range(of: "^#?[0-9a-fA-F]{3,8}$|^[a-zA-Z]+$", options: .regularExpression)
        return r != nil
    }

    public static func makeBody(_ doc: ScenarioDocument) -> (html: String, index: [(id: String, name: String)]) {
        let chars = doc.characterById
        let styles = doc.styleByType
        let bodyW = max(doc.setting.bodyLength, 4)
        var h = ""
        if !doc.characters.isEmpty {
            h += "<section class=\"pv-cast\"><h2>登場人物</h2><dl>"
            for c in doc.characters {
                h += "<div class=\"pv-cast-row\"><dt>\(text(c.name))</dt><dd>\(text(c.chara))</dd></div>"
            }
            h += "</dl></section>"
        }
        if !doc.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            h += "<section class=\"pv-synopsis\"><h2>シノプシス</h2><p>\(text(doc.synopsis))</p></section>"
        }
        var index: [(String, String)] = []
        for (i, scene) in doc.scenes.enumerated() {
            let sid = "scene\(i + 1)"
            index.append((sid, TextFormat.toFullWidth(scene.name)))
            h += "<section class=\"pv-scene\" id=\"\(sid)\">"
            h += "<h2 class=\"pv-hashira\">\(text(scene.name))</h2>"
            if !scene.description.trimmingCharacters(in: .whitespaces).isEmpty {
                h += "<p class=\"pv-scene-desc\">\(text(scene.description))</p>"
            }
            for line in doc.lines(of: scene) {
                let f = ScriptFormatter.format(line, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko)
                // 見出し欄は設定の文字数ぶん常に確保し、本文は「本文の文字数 − 字下げ」で折り返す（テキスト出力と同じ組み方）
                let indent = min(max(f.style.indent, 0), bodyW - 2)
                var style = ""
                // 前後の余白（行数）。行送り 1.9 の 1 行ぶんを単位にする。縦書きでは列の間隔になる
                if f.style.marginBefore > 0 { style += "margin-block-start:\(Double(f.style.marginBefore) * 1.9)em;" }
                if f.style.marginAfter > 0 { style += "margin-block-end:\(0.35 + Double(f.style.marginAfter) * 1.9)em;" }
                if isSafeColor(f.style.color) { style += "color:\(f.style.color);" }
                if f.style.fontSize > 0, f.style.fontSize != 12 {
                    style += "font-size:\(String(format: "%.2f", Double(f.style.fontSize) / 12.0))em;"
                }
                h += "<div class=\"pv-line pv-type\(line.type)\" id=\"line\(line.id)\" style=\"\(style)\">"
                h += "<span class=\"pv-name\">\(text(f.label))</span>"
                h += "<span class=\"pv-text\" style=\"margin-inline-start:\(indent)em;inline-size:\(bodyW - indent)em;\">\(text(f.text))</span></div>"
            }
            h += "</section>"
        }
        if doc.scenes.isEmpty { h += "<p class=\"pv-empty\">まだ場面がありません。</p>" }
        return (h, index)
    }

    /// 固定スタイル（シノプシス・場面説明・登場人物）の色・大きさ・字下げ・前後の余白
    static func textStyleCSS(_ doc: ScenarioDocument, nameW: Int, bodyW: Int) -> String {
        func rule(_ selector: String, _ t: TextStyle, indentFrom: Int?) -> String {
            var s = ""
            if isSafeColor(t.color) { s += "color:\(t.color);" }
            if t.fontSize > 0, t.fontSize != 12 { s += "font-size:\(String(format: "%.2f", Double(t.fontSize) / 12.0))em;" }
            if let base = indentFrom {
                let indent = min(max(t.indent, 0), bodyW - 2)
                s += "margin-inline-start:\(base + indent)em;max-inline-size:\(bodyW - indent)em;"
            } else if t.indent > 0 {
                s += "margin-inline-start:\(min(t.indent, bodyW - 2))em;"
            }
            if t.marginBefore > 0 { s += "margin-block-start:\(Double(t.marginBefore) * 1.9)em;" }
            if t.marginAfter > 0 { s += "margin-block-end:\(Double(t.marginAfter) * 1.9)em;" }
            return "\(selector) { \(s) }"
        }
        return [
            rule(".pv-body .pv-synopsis p", doc.textStyle(.synopsis), indentFrom: nameW),
            rule(".pv-body .pv-scene-desc", doc.textStyle(.sceneDescription), indentFrom: nameW),
            rule(".pv-body .pv-cast-row", doc.textStyle(.character), indentFrom: nil),
            ".pv-body .pv-cast dd { color: inherit; }",
        ].joined(separator: "\n        ")
    }

    public static func make(_ doc: ScenarioDocument, options: Options = Options()) -> String {
        let (body, index) = makeBody(doc)
        let nameW = max(doc.setting.characterLength, 2)
        let bodyW = max(doc.setting.bodyLength, 4)
        let title = TextFormat.htmlEscape(TextFormat.toFullWidth(doc.scenario.title))
        let subtitle = TextFormat.htmlEscape(TextFormat.toFullWidth(doc.scenario.subtitle))
        let writer = TextFormat.htmlEscape(TextFormat.toFullWidth(doc.scenario.writerName))
        let indexHtml = index.map { "<a href=\"#\($0.id)\">\(TextFormat.htmlEscape($0.name))</a>" }.joined()
        let bar = options.showBar ? """
        <div class="pv-bar">
          <button type="button" id="pvIdxBtn" title="場面一覧">場面</button>
          <span class="pv-bar-title">\(title)</span>
          <button type="button" id="pvSmall" title="文字を小さく">A-</button>
          <button type="button" id="pvLarge" title="文字を大きく">A+</button>
          <button type="button" id="pvMode">縦書き</button>
        </div>
        <div class="pv-index" id="pvIndex">\(indexHtml)</div>
        """ : ""
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex, nofollow">
        <title>\(title) - ScenarioWriterSolo</title>
        <style>
        :root { --pv-fs: \(options.fontSize)px; --pv-bar: \(options.showBar ? 44 : 0)px; }
        * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; background: #fbfaf7; color: #222; }
        body { font-family: "Hiragino Mincho ProN", "Yu Mincho", "YuMincho", "Noto Serif JP", serif; font-size: var(--pv-fs); line-height: 1.9; -webkit-text-size-adjust: 100%; }
        .pv-bar { position: fixed; top: 0; left: 0; right: 0; height: var(--pv-bar); background: #fff; border-bottom: 1px solid #e3e0d8; display: flex; align-items: center; gap: 6px; padding: 0 8px; z-index: 10; font-family: -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif; font-size: 13px; }
        .pv-bar .pv-bar-title { flex: 1 1 auto; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; font-weight: bold; }
        .pv-bar button, .pv-bar select { font-size: 13px; height: 30px; padding: 0 8px; border: 1px solid #cfcac0; border-radius: 6px; background: #fff; color: #222; }
        .pv-bar button.on { background: #f7931e; border-color: #f7931e; color: #fff; }
        .pv-wrap { padding-top: var(--pv-bar); }
        .pv-head { padding: 16px 16px 8px; border-bottom: 1px dashed #d8d3c8; }
        .pv-title { font-size: 1.4em; font-weight: bold; margin: 0; line-height: 1.5; }
        .pv-subtitle { margin: 2px 0 0; color: #555; }
        .pv-writer { margin: 6px 0 0; color: #555; font-size: 0.9em; }
        .pv-body { padding: 8px 16px 40px; }
        .pv-body h2 { font-size: 1.05em; font-weight: bold; margin: 1.6em 0 0.6em; padding-inline-start: 0; }
        /* 柱: 台本の慣習どおり、ページを端から端まで通した枠で囲む（横書きは横一杯の帯、縦書きは上下一杯の縦枠） */
        .pv-hashira { border: 1.5px solid #444; inline-size: 100%; box-sizing: border-box; padding: 0.35em 0.8em; margin: 1.8em 0 0.8em; }
        .pv-scene-desc { color: #006400; margin: 0 0 0.8em; }
        .pv-cast dl { margin: 0; } .pv-cast-row { display: flex; align-items: flex-start; margin: 0 0 0.2em; } .pv-cast dt { flex: 0 0 \(nameW)em; inline-size: \(nameW)em; font-weight: bold; overflow-wrap: anywhere; } .pv-cast dd { margin: 0; color: #555; max-inline-size: \(bodyW)em; overflow-wrap: anywhere; }
        .pv-synopsis p { margin: 0; }
        .pv-line { margin: 0; margin-block-end: 0.35em; display: flex; align-items: flex-start; }
        .pv-name { flex: 0 0 \(nameW)em; inline-size: \(nameW)em; overflow-wrap: anywhere; }
        .pv-text { flex: 0 0 auto; max-inline-size: calc(100% - \(nameW)em); overflow-wrap: anywhere; }
        .pv-body .pv-scene-desc, .pv-body .pv-synopsis p { margin-inline-start: \(nameW)em; max-inline-size: \(bodyW)em; overflow-wrap: anywhere; }
        \(textStyleCSS(doc, nameW: nameW, bodyW: bodyW))
        .pv-line.hl { background: #fff3d6; outline: 2px solid #f7931e; border-radius: 4px; }
        .pv-name { font-weight: bold; }
        .pv-empty { color: #999; }
        body.vertical .pv-wrap { height: 100vh; overflow: hidden; }
        body.vertical .pv-scroll { height: calc(100vh - var(--pv-bar)); overflow-x: auto; overflow-y: hidden; -webkit-overflow-scrolling: touch; }
        body.vertical .pv-doc { writing-mode: vertical-rl; text-orientation: mixed; height: 100%; padding: 20px 20px 16px 20px; width: max-content; }
        body.vertical .pv-head { border-bottom: 0; border-block-end: 1px dashed #d8d3c8; padding: 0 12px 0 20px; margin: 0; }
        body.vertical .pv-hashira { padding: 0.8em 0.35em; margin: 0 1.2em 0 1.2em; }
        body.vertical .pv-body h2 { margin: 0 0 0 1.2em; }
        body.vertical .pv-body h2.pv-hashira { margin: 0 1.2em 0 1.2em; }
        body.vertical .pv-body { padding: 0 8px 0 16px; }
        body.vertical .pv-line { margin: 0; margin-block-end: 0.3em; }
        body.vertical .pv-text { max-inline-size: calc(100% - \(nameW)em); }
        body.vertical .pv-title { margin-inline-end: 0.4em; }
        .pv-index { display: none; position: fixed; top: var(--pv-bar); right: 8px; max-height: 60vh; overflow: auto; background: #fff; border: 1px solid #cfcac0; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,.15); z-index: 11; min-width: 160px; font-family: -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif; font-size: 13px; }
        .pv-index.open { display: block; }
        .pv-index a { display: block; padding: 8px 12px; color: #222; text-decoration: none; border-bottom: 1px solid #eee; }
        .pv-index a:last-child { border-bottom: 0; }
        /* 縦書きのページ送り（左 = 次のページ、右 = 前のページ）。端まで来たほうは隠す */
        .pv-page { display: none; position: fixed; top: calc(50% + var(--pv-bar) / 2); transform: translateY(-50%); z-index: 9; width: 36px; height: 56px; padding: 0; border: 1px solid rgba(0,0,0,.12); border-radius: 10px; background: rgba(255,255,255,.85); color: #666; font: 600 22px/1 -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif; box-shadow: 0 1px 4px rgba(0,0,0,.15); cursor: pointer; -webkit-backdrop-filter: blur(6px); backdrop-filter: blur(6px); }
        .pv-page:hover { background: #fff; color: #222; }
        .pv-page.next { left: 8px; } .pv-page.prev { right: 8px; }
        body.vertical .pv-page { display: block; }
        body.vertical .pv-page.hide { display: none; }
        /* マウスのある端末では、ポインタが左右の端の列に来たときだけ出す（いつも出ていると本文に重なる）。タッチ端末はいつも出す */
        @media (hover: hover) { .pv-page { opacity: 0; pointer-events: none; transition: opacity .15s; } .pv-page.near { opacity: 1; pointer-events: auto; } }
        @media print { .pv-bar, .pv-index, .pv-page { display: none !important; } .pv-wrap { padding-top: 0; } }
        </style>
        </head>
        <body class="\(options.vertical ? "vertical" : "")">
        \(bar)
        <div class="pv-wrap"><div class="pv-scroll"><div class="pv-doc">
          <div class="pv-head">
            <h1 class="pv-title">\(title)</h1>
            \(subtitle.isEmpty ? "" : "<p class=\"pv-subtitle\">\(subtitle)</p>")
            \(writer.isEmpty ? "" : "<p class=\"pv-writer\">作：\(writer)</p>")
          </div>
          <div class="pv-body">\(body)</div>
        </div></div></div>
        <button type="button" class="pv-page next" id="pvNext" title="次のページへ" aria-label="次のページへ">&#x2039;</button>
        <button type="button" class="pv-page prev" id="pvPrev" title="前のページへ" aria-label="前のページへ">&#x203A;</button>
        <script>
        (function(){
          var body = document.body, modeBtn = document.getElementById('pvMode');
          var fs = \(options.fontSize), vertical = \(options.vertical ? "true" : "false");
          try { fs = parseInt(localStorage.getItem('swpv_fs') || String(fs), 10) || fs; var m = localStorage.getItem('swpv_mode'); if (m) { vertical = m === 'v'; } } catch(e) {}
          // keep: 文字の大きさだけ変えたとき、いま読んでいる位置（見えている範囲の中央）を保つ。向きを変えたときは先頭へ
          function readPos(){
            if (vertical) { var t = scroller.scrollWidth || 1; return (t - scroller.scrollLeft - scroller.clientWidth / 2) / t; }
            var h = document.documentElement.scrollHeight || 1; return (window.pageYOffset + window.innerHeight / 2) / h;
          }
          function apply(keep){
            var pos = keep ? readPos() : null;
            document.documentElement.style.setProperty('--pv-fs', fs + 'px');
            body.classList.toggle('vertical', vertical);
            if (modeBtn) { modeBtn.textContent = vertical ? '横書き' : '縦書き'; modeBtn.classList.toggle('on', vertical); }
            try { localStorage.setItem('swpv_fs', fs); localStorage.setItem('swpv_mode', vertical ? 'v' : 'h'); } catch(e) {}
            try { if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.swPrefs) { window.webkit.messageHandlers.swPrefs.postMessage({ v: vertical, fs: fs }); } } catch(e) {}
            if (pos !== null) { window.swMapJump(pos); }
            else if (vertical) { var sc = document.querySelector('.pv-scroll'); sc.scrollLeft = sc.scrollWidth; }
            updatePager();
            if (typeof mapReport === 'function') { setTimeout(function(){ mapReport(true); }, 0); }
          }
          // 縦書きのページ送り。1 ページ = 見えている幅の 85%（前のページの端が少し残る）
          var scroller = document.querySelector('.pv-scroll'), nextBtn = document.getElementById('pvNext'), prevBtn = document.getElementById('pvPrev');
          function updatePager(){
            if (!nextBtn || !prevBtn) { return; }
            var max = scroller.scrollWidth - scroller.clientWidth;
            nextBtn.classList.toggle('hide', !vertical || scroller.scrollLeft <= 1);
            prevBtn.classList.toggle('hide', !vertical || scroller.scrollLeft >= max - 1);
          }
          function page(dir){ scroller.scrollBy({ left: dir * Math.max(80, scroller.clientWidth * 0.85), behavior: 'smooth' }); }
          if (nextBtn) { nextBtn.addEventListener('click', function(){ page(-1); }); }
          if (prevBtn) { prevBtn.addEventListener('click', function(){ page(1); }); }
          scroller.addEventListener('scroll', updatePager, { passive: true });
          window.addEventListener('resize', updatePager);
          // ポインタが見えている範囲の左右の端（端の列）から 110px 以内に来たら、その側のボタンを出す
          var ZONE = 110;
          function nearEdge(x){
            if (!nextBtn || !prevBtn) { return; }
            nextBtn.classList.toggle('near', x != null && x < ZONE);
            prevBtn.classList.toggle('near', x != null && x > window.innerWidth - ZONE);
          }
          document.addEventListener('mousemove', function(e){ nearEdge(e.clientY > scroller.getBoundingClientRect().top ? e.clientX : null); }, { passive: true });
          document.documentElement.addEventListener('mouseleave', function(){ nearEdge(null); });
          // アプリ（ScenarioWriterSolo の「読む」）のツールバーのミニマップへ、行の並びと見えている範囲を知らせる。
          // 位置は先頭からの割合（縦書きは右端が先頭）。書き出した HTML では送り先が無いので何もしない
          function mapHandler(){ try { return window.webkit.messageHandlers.swMap; } catch(e) { return null; } }
          function mapReport(full){
            var h = mapHandler(); if (!h) { return; }
            var msg = { rtl: vertical }, total, lo, hi;
            if (vertical) {
              total = scroller.scrollWidth || 1;
              lo = (total - (scroller.scrollLeft + scroller.clientWidth)) / total; hi = (total - scroller.scrollLeft) / total;
            } else {
              total = document.documentElement.scrollHeight || 1;
              lo = window.pageYOffset / total; hi = (window.pageYOffset + window.innerHeight) / total;
            }
            msg.lo = lo; msg.hi = hi;
            if (full) {
              var marks = [], base = vertical ? scroller.getBoundingClientRect().left - scroller.scrollLeft : -window.pageYOffset;
              var colH = scroller.clientHeight || 1, rowW = (document.querySelector('.pv-body') || document.body).clientWidth || 1;
              document.querySelectorAll('.pv-line, h2.pv-hashira').forEach(function(el){
                var r = el.getBoundingClientRect(), head = el.tagName === 'H2', t = el.querySelector('.pv-text') || el, tr = t.getBoundingClientRect();
                var pos, len, fill;
                if (vertical) { var x = r.left - base; pos = (total - (x + r.width)) / total; len = r.width / total; fill = tr.height / colH; }
                else { pos = (r.top - base) / total; len = r.height / total; fill = tr.width / rowW; }
                marks.push([pos, len, fill, head ? '' : getComputedStyle(t).color, head ? 1 : 0]);
              });
              msg.marks = marks;
            }
            try { h.postMessage(msg); } catch(e) {}
          }
          var mapPending = false;
          function mapScroll(){ if (mapPending) { return; } mapPending = true; requestAnimationFrame(function(){ mapPending = false; mapReport(false); }); }
          scroller.addEventListener('scroll', mapScroll, { passive: true });
          window.addEventListener('scroll', mapScroll, { passive: true });
          window.addEventListener('resize', function(){ mapReport(true); });
          // ミニマップのクリック: 先頭からの割合 f が画面の中央に来るように
          window.swMapJump = function(f){
            if (vertical) { var total = scroller.scrollWidth; scroller.scrollLeft = total * (1 - f) - scroller.clientWidth / 2; }
            else { window.scrollTo(0, document.documentElement.scrollHeight * f - window.innerHeight / 2); }
          };
          window.swSetVertical = function(v){ vertical = !!v; apply(); };
          window.swSetFontSize = function(n){ fs = Math.max(10, Math.min(36, n)); apply(true); };
          window.swJump = function(id){
            var t = document.getElementById(id); if (!t) { return; }
            document.querySelectorAll('.pv-line.hl').forEach(function(e){ e.classList.remove('hl'); });
            if (t.classList.contains('pv-line')) { t.classList.add('hl'); }
            if (vertical) { t.scrollIntoView({ inline: 'end', block: 'nearest' }); }
            else { window.scrollTo({ top: t.getBoundingClientRect().top + window.pageYOffset - 52 }); }
          };
          if (modeBtn) { modeBtn.addEventListener('click', function(){ vertical = !vertical; apply(); }); }
          var sm = document.getElementById('pvSmall'), lg = document.getElementById('pvLarge');
          if (sm) { sm.addEventListener('click', function(){ fs = Math.max(12, fs - 1); apply(true); }); }
          if (lg) { lg.addEventListener('click', function(){ fs = Math.min(28, fs + 1); apply(true); }); }
          var idx = document.getElementById('pvIndex'), idxBtn = document.getElementById('pvIdxBtn');
          if (idx && idxBtn) {
            idxBtn.addEventListener('click', function(e){ e.stopPropagation(); idx.classList.toggle('open'); });
            document.addEventListener('click', function(){ idx.classList.remove('open'); });
            idx.addEventListener('click', function(e){
              var a = e.target.closest('a'); if (!a) { return; }
              e.preventDefault(); idx.classList.remove('open');
              window.swJump(a.getAttribute('href').substring(1));
            });
          }
          apply();
        })();
        </script>
        </body>
        </html>
        """
    }
}
