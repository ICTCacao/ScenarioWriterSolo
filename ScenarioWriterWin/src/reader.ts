// 「読む」画面の HTML。Mac 版 HtmlExporter と同じ見た目（人物名欄と本文の幅は文字数で固定、柱は枠、余白は行数）
import * as M from "./model";

const t = (s: string) => M.escapeHtml(M.toFullWidth(s)).replace(/\r\n/g, "\n").replace(/\n/g, "<br>");
const safeColor = (c: string) => /^#?[0-9a-fA-F]{3,8}$|^[a-zA-Z]+$/.test(c);
const em = (n: number) => n.toFixed(2) + "em";

function textStyleCSS(f: M.ScwdFile, nameW: number, bodyW: number): string {
  const rule = (sel: string, ts: M.TextStyle, indentFrom: number | null) => {
    let s = "";
    if (safeColor(ts.color)) s += `color:${ts.color};`;
    if (ts.size > 0 && ts.size !== 12) s += `font-size:${em(ts.size / 12)};`;
    if (indentFrom !== null) {
      const indent = Math.min(Math.max(ts.indent, 0), bodyW - 2);
      s += `margin-inline-start:${indentFrom + indent}em;max-inline-size:${bodyW - indent}em;`;
    } else if (ts.indent > 0) s += `margin-inline-start:${Math.min(ts.indent, bodyW - 2)}em;`;
    if (ts.marginBefore > 0) s += `margin-block-start:${ts.marginBefore * 1.9}em;`;
    if (ts.marginAfter > 0) s += `margin-block-end:${ts.marginAfter * 1.9}em;`;
    return `${sel} { ${s} }`;
  };
  return [
    rule(".pv-body .pv-synopsis p", f.textStyles.synopsis, nameW),
    rule(".pv-body .pv-scene-desc", f.textStyles.scene, nameW),
    rule(".pv-body .pv-cast-row", f.textStyles.character, null),
    ".pv-body .pv-cast dd { color: inherit; }",
  ].join("\n");
}

export function buildReaderHtml(f: M.ScwdFile, opts: { vertical: boolean; fontSize: number; showBar: boolean }): string {
  const nameW = Math.max(f.setting.characterLength, 2);
  const bodyW = Math.max(f.setting.bodyLength, 4);
  const chars = new Map(f.characters.map((c) => [c.id, c]));
  let body = "";
  if (f.characters.length) {
    body += `<section class="pv-cast"><h2>登場人物</h2><dl>`;
    for (const c of f.characters) body += `<div class="pv-cast-row"><dt>${t(c.name)}</dt><dd>${t(c.chara)}</dd></div>`;
    body += `</dl></section>`;
  }
  if (f.synopsis.trim()) body += `<section class="pv-synopsis"><h2>シノプシス</h2><p>${t(f.synopsis)}</p></section>`;
  const index: { id: string; name: string }[] = [];
  f.scenes.forEach((scene, i) => {
    if (!scene.valid) return;
    const sid = `scene${i + 1}`;
    index.push({ id: sid, name: M.toFullWidth(scene.name) });
    body += `<section class="pv-scene" id="${sid}"><h2 class="pv-hashira">${t(scene.name)}</h2>`;
    if (scene.description.trim()) body += `<p class="pv-scene-desc">${t(scene.description)}</p>`;
    scene.lines.forEach((line, j) => {
      const st = M.resolveStyle(f, line.type);
      const name = line.character !== undefined ? chars.get(line.character)?.name ?? "" : "";
      const label = M.labelFor(name, st);
      const text = st.kagi ? M.kagikakko(line.text) : line.text;
      const indent = Math.min(Math.max(st.indent, 0), bodyW - 2);
      let style = "";
      if (st.marginBefore > 0) style += `margin-block-start:${st.marginBefore * 1.9}em;`;
      if (st.marginAfter > 0) style += `margin-block-end:${0.35 + st.marginAfter * 1.9}em;`;
      if (safeColor(st.color)) style += `color:${st.color};`;
      if (st.size > 0 && st.size !== 12) style += `font-size:${em(st.size / 12)};`;
      body += `<div class="pv-line pv-type${line.type}" id="line${i + 1}-${j + 1}" style="${style}">`;
      body += `<span class="pv-name">${t(label)}</span>`;
      body += `<span class="pv-text" style="margin-inline-start:${indent}em;inline-size:${bodyW - indent}em;">${t(text)}</span></div>`;
    });
    body += `</section>`;
  });
  if (!f.scenes.length) body += `<p class="pv-empty">まだ場面がありません。</p>`;

  const title = M.escapeHtml(M.toFullWidth(f.scenario.title));
  const subtitle = M.escapeHtml(M.toFullWidth(f.scenario.subtitle));
  const writer = M.escapeHtml(M.toFullWidth(f.scenario.writer));
  const indexHtml = index.map((x) => `<a href="#${x.id}">${M.escapeHtml(x.name)}</a>`).join("");
  const bar = opts.showBar ? `
    <div class="pv-bar">
      <button type="button" id="pvIdxBtn" title="場面一覧">場面</button>
      <span class="pv-bar-title">${title}</span>
      <button type="button" id="pvSmall" title="文字を小さく">A-</button>
      <button type="button" id="pvLarge" title="文字を大きく">A+</button>
      <button type="button" id="pvMode">縦書き</button>
    </div>
    <div class="pv-index" id="pvIndex">${indexHtml}</div>` : "";

  return `<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
:root { --pv-fs: ${opts.fontSize}px; --pv-bar: ${opts.showBar ? 44 : 0}px; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #fbfaf7; color: #222; }
body { font-family: "Hiragino Mincho ProN", "Yu Mincho", "YuMincho", "Noto Serif JP", "MS Mincho", serif; font-size: var(--pv-fs); line-height: 1.9; }
.pv-bar { position: fixed; top: 0; left: 0; right: 0; height: var(--pv-bar); background: #fff; border-bottom: 1px solid #e3e0d8; display: flex; align-items: center; gap: 6px; padding: 0 8px; z-index: 10; font-family: -apple-system, "Segoe UI", "Yu Gothic UI", "Hiragino Sans", "Noto Sans JP", sans-serif; font-size: 13px; }
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
.pv-hashira { border: 1.5px solid #444; inline-size: 100%; box-sizing: border-box; padding: 0.35em 0.8em; margin: 1.8em 0 0.8em; }
.pv-scene-desc { color: #006400; margin: 0 0 0.8em; }
.pv-cast dl { margin: 0; } .pv-cast-row { display: flex; align-items: flex-start; margin: 0 0 0.2em; } .pv-cast dt { flex: 0 0 ${nameW}em; inline-size: ${nameW}em; font-weight: bold; overflow-wrap: anywhere; } .pv-cast dd { margin: 0; color: #555; max-inline-size: ${bodyW}em; overflow-wrap: anywhere; }
.pv-synopsis p { margin: 0; }
.pv-line { margin: 0; margin-block-end: 0.35em; display: flex; align-items: flex-start; }
.pv-name { flex: 0 0 ${nameW}em; inline-size: ${nameW}em; overflow-wrap: anywhere; font-weight: bold; }
.pv-text { flex: 0 0 auto; max-inline-size: calc(100% - ${nameW}em); overflow-wrap: anywhere; }
.pv-body .pv-scene-desc, .pv-body .pv-synopsis p { margin-inline-start: ${nameW}em; max-inline-size: ${bodyW}em; overflow-wrap: anywhere; }
${textStyleCSS(f, nameW, bodyW)}
.pv-line.hl { background: #fff3d6; outline: 2px solid #f7931e; border-radius: 4px; }
.pv-empty { color: #999; }
body.vertical .pv-wrap { height: 100vh; overflow: hidden; }
body.vertical .pv-scroll { height: calc(100vh - var(--pv-bar)); overflow-x: auto; overflow-y: hidden; }
body.vertical .pv-doc { writing-mode: vertical-rl; text-orientation: mixed; height: 100%; padding: 20px 20px 16px 20px; width: max-content; }
body.vertical .pv-head { border-bottom: 0; border-block-end: 1px dashed #d8d3c8; padding: 0 12px 0 20px; margin: 0; }
body.vertical .pv-hashira { padding: 0.8em 0.35em; margin: 0 1.2em 0 1.2em; }
body.vertical .pv-body h2 { margin: 0 0 0 1.2em; }
body.vertical .pv-body h2.pv-hashira { margin: 0 1.2em 0 1.2em; }
body.vertical .pv-body { padding: 0 8px 0 16px; }
body.vertical .pv-line { margin: 0; margin-block-end: 0.3em; }
body.vertical .pv-text { max-inline-size: calc(100% - ${nameW}em); }
body.vertical .pv-title { margin-inline-end: 0.4em; }
.pv-index { display: none; position: fixed; top: var(--pv-bar); right: 8px; max-height: 60vh; overflow: auto; background: #fff; border: 1px solid #cfcac0; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,.15); z-index: 11; min-width: 160px; font-family: -apple-system, "Segoe UI", "Yu Gothic UI", sans-serif; font-size: 13px; }
.pv-index.open { display: block; }
.pv-index a { display: block; padding: 8px 12px; color: #222; text-decoration: none; border-bottom: 1px solid #eee; }
.pv-index a:last-child { border-bottom: 0; }
/* 縦書きのページ送り（左 = 次のページ、右 = 前のページ）。端まで来たほうは隠す（Mac 版と同じ） */
.pv-page { display: none; position: fixed; top: calc(50% + var(--pv-bar) / 2); transform: translateY(-50%); z-index: 9; width: 36px; height: 56px; padding: 0; border: 1px solid rgba(0,0,0,.12); border-radius: 10px; background: rgba(255,255,255,.85); color: #666; font: 600 22px/1 -apple-system, "Segoe UI", "Yu Gothic UI", sans-serif; box-shadow: 0 1px 4px rgba(0,0,0,.15); cursor: pointer; -webkit-backdrop-filter: blur(6px); backdrop-filter: blur(6px); }
.pv-page:hover { background: #fff; color: #222; }
.pv-page.next { left: 8px; } .pv-page.prev { right: 8px; }
body.vertical .pv-page { display: block; }
body.vertical .pv-page.hide { display: none; }
/* マウスのある端末では、ポインタが左右の端の列に来たときだけ出す（いつも出ていると本文に重なる）。タッチ端末はいつも出す */
@media (hover: hover) { .pv-page { opacity: 0; pointer-events: none; transition: opacity .15s; } .pv-page.near { opacity: 1; pointer-events: auto; } }
@media print { .pv-bar, .pv-index, .pv-page { display: none !important; } .pv-wrap { padding-top: 0; } }
</style></head>
<body class="${opts.vertical ? "vertical" : ""}">
${bar}
<div class="pv-wrap"><div class="pv-scroll"><div class="pv-doc">
  <div class="pv-head">
    <h1 class="pv-title">${title}</h1>
    ${subtitle ? `<p class="pv-subtitle">${subtitle}</p>` : ""}
    ${writer ? `<p class="pv-writer">作：${writer}</p>` : ""}
  </div>
  <div class="pv-body">${body}</div>
</div></div></div>
<button type="button" class="pv-page next" id="pvNext" title="次のページへ" aria-label="次のページへ">&#x2039;</button>
<button type="button" class="pv-page prev" id="pvPrev" title="前のページへ" aria-label="前のページへ">&#x203A;</button>
<script>
(function(){
  var body = document.body, modeBtn = document.getElementById('pvMode');
  var fs = ${opts.fontSize}, vertical = ${opts.vertical ? "true" : "false"};
  try { fs = parseInt(localStorage.getItem('swpv_fs') || String(fs), 10) || fs; var m = localStorage.getItem('swpv_mode'); if (m) { vertical = m === 'v'; } } catch(e) {}
  function apply(){
    document.documentElement.style.setProperty('--pv-fs', fs + 'px');
    body.classList.toggle('vertical', vertical);
    if (modeBtn) { modeBtn.textContent = vertical ? '横書き' : '縦書き'; modeBtn.classList.toggle('on', vertical); }
    try { localStorage.setItem('swpv_fs', fs); localStorage.setItem('swpv_mode', vertical ? 'v' : 'h'); } catch(e) {}
    if (vertical) { var sc = document.querySelector('.pv-scroll'); sc.scrollLeft = sc.scrollWidth; }
    updatePager();
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
  window.swJump = function(id){
    var t = document.getElementById(id); if (!t) { return; }
    document.querySelectorAll('.pv-line.hl').forEach(function(e){ e.classList.remove('hl'); });
    if (t.classList.contains('pv-line')) { t.classList.add('hl'); }
    if (vertical) { t.scrollIntoView({ inline: 'end', block: 'nearest' }); }
    else { window.scrollTo({ top: t.getBoundingClientRect().top + window.pageYOffset - 52 }); }
  };
  if (modeBtn) { modeBtn.addEventListener('click', function(){ vertical = !vertical; apply(); }); }
  var sm = document.getElementById('pvSmall'), lg = document.getElementById('pvLarge');
  if (sm) { sm.addEventListener('click', function(){ fs = Math.max(12, fs - 1); apply(); }); }
  if (lg) { lg.addEventListener('click', function(){ fs = Math.min(28, fs + 1); apply(); }); }
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
</body></html>`;
}
