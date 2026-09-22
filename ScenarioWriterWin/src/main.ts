// ScenarioWriterSolo Windows 版の画面。作品は 1 つずつ .scwd（JSON）で、Mac 版と同じ形式。
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { open as openDialog, save as saveDialog, ask, message } from "@tauri-apps/plugin-dialog";
import * as M from "./model";
import { buildReaderHtml } from "./reader";

type Section = "script" | "scenes" | "cast" | "synopsis" | "info" | "read";

const state = {
  file: null as M.ScwdFile | null,
  path: null as string | null,
  dirty: false,
  scene: 0,
  section: "script" as Section,
  vertical: localStorage.getItem("sw_vertical") === "1",
  fontSize: parseInt(localStorage.getItem("sw_fontSize") || "16", 10) || 16,
  selected: -1,
};

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
// ふつうのブラウザで開いたとき（開発用）は Tauri の窓が無い
const win = inTauri() ? getCurrentWindow() : null;
const FILTERS = [{ name: "ScenarioWriter 作品", extensions: ["scwd"] }];

// ---- 状態表示

function setStatus(s: string) { $("status").textContent = s; if (s) setTimeout(() => { if ($("status").textContent === s) $("status").textContent = ""; }, 4000); }

function updateTitle() {
  const f = state.file;
  const name = f ? (f.scenario.title || "無題") : "作品を開いていません";
  $("docTitle").textContent = f ? `${name}${state.dirty ? " — 未保存の変更あり（Ctrl+S で保存）" : ""}` : name;
  win?.setTitle(`${f ? (state.dirty ? "● " : "") + name + " — " : ""}ScenarioWriterSolo（Windows 版）`).catch(() => {});
}

function markDirty() { if (!state.dirty) { state.dirty = true; updateTitle(); } }

// ---- 最近使った作品（パスだけ覚える）

function recents(): { path: string; title: string }[] {
  try { return JSON.parse(localStorage.getItem("sw_recents") || "[]"); } catch { return []; }
}
function addRecent(path: string, title: string) {
  const list = recents().filter((r) => r.path !== path);
  list.unshift({ path, title });
  localStorage.setItem("sw_recents", JSON.stringify(list.slice(0, 20)));
}

// ---- ファイル

async function confirmDiscard(action: string): Promise<boolean> {
  if (!state.dirty || !state.file) return true;
  const ok = await ask(`「${state.file.scenario.title || "無題"}」に保存していない変更があります。保存しますか？`, { title: action, kind: "warning", okLabel: "保存", cancelLabel: "保存しない" });
  if (ok) { await save(); return !state.dirty; }
  return true;
}

async function openPath(path: string) {
  try {
    const text = await invoke<string>("read_text_file", { path });
    const f = M.parse(text);
    state.file = f; state.path = path; state.dirty = false; state.scene = 0; state.selected = -1;
    addRecent(path, f.scenario.title);
    if (state.section === "read") state.section = "script";
    render();
    updateTitle();
    setStatus("開きました");
  } catch (e: any) {
    await message(`作品ファイルを開けません: ${e?.message ?? e}`, { title: "開けません", kind: "error" });
  }
}

async function openFile() {
  if (!(await confirmDiscard("別の作品を開く"))) return;
  const sel = await openDialog({ multiple: false, directory: false, filters: FILTERS, title: "作品ファイル（.scwd）を開く" });
  if (typeof sel === "string") await openPath(sel);
}

async function newFile() {
  if (!(await confirmDiscard("新しい作品を作る"))) return;
  const path = await saveDialog({ filters: FILTERS, defaultPath: "無題.scwd", title: "新しい作品ファイルの保存先" });
  if (!path) return;
  const name = path.replace(/\\/g, "/").split("/").pop()!.replace(/\.scwd$/i, "");
  state.file = M.emptyFile(name, 1, 2); state.path = path; state.dirty = false; state.scene = 0; state.selected = -1;
  state.section = "script";
  render(); updateTitle();
  await save();
}

async function save() {
  if (!state.file) return;
  if (!state.path) return saveAs();
  try {
    state.file.scenario.date = M.now();
    await invoke("write_text_file", { path: state.path, text: M.serialize(state.file) });
    state.dirty = false;
    addRecent(state.path, state.file.scenario.title);
    updateTitle();
    setStatus("保存しました");
  } catch (e: any) {
    await message(`保存できませんでした: ${e?.message ?? e}`, { title: "保存できません", kind: "error" });
  }
}

async function saveAs() {
  if (!state.file) return;
  const path = await saveDialog({ filters: FILTERS, defaultPath: (state.file.scenario.title || "無題") + ".scwd", title: "別名で保存" });
  if (!path) return;
  state.path = path;
  await save();
}

// ---- 描画

function show(section: Section) {
  state.section = section;
  document.querySelectorAll<HTMLButtonElement>(".sections button").forEach((b) => b.classList.toggle("on", b.dataset.section === section));
  const ids: Record<Section, string> = { script: "secScript", scenes: "secScenes", cast: "secCast", synopsis: "secSynopsis", info: "secInfo", read: "secRead" };
  for (const k of Object.keys(ids) as Section[]) $(ids[k]).hidden = k !== section || !state.file;
  $("empty").hidden = !!state.file;
  if (!state.file) { renderEmpty(); return; }
  switch (section) {
    case "script": renderScript(); break;
    case "scenes": renderScenes(); break;
    case "cast": renderCast(); break;
    case "synopsis": renderSynopsis(); break;
    case "info": renderInfo(); break;
    case "read": renderReader(); break;
  }
}

function render() { renderSidebar(); show(state.section); }

function renderEmpty() {
  const ul = $("recentList");
  ul.innerHTML = "";
  for (const r of recents()) {
    const li = document.createElement("li");
    li.innerHTML = `<span class="t">${M.escapeHtml(r.title || "無題")}</span><span class="p">${M.escapeHtml(r.path)}</span>`;
    li.onclick = () => openPath(r.path);
    ul.appendChild(li);
  }
}

function renderSidebar() {
  const f = state.file;
  const sl = $("sceneList"); sl.innerHTML = "";
  const cl = $("castList"); cl.innerHTML = "";
  $("btnAddScene").hidden = !f; $("btnAddCast").hidden = !f;
  if (!f) return;
  f.scenes.forEach((s, i) => {
    const li = document.createElement("li");
    li.className = i === state.scene && state.section === "script" ? "on" : "";
    li.innerHTML = `<span class="n">${i + 1}. ${M.escapeHtml(s.name || "（無題の場面）")}</span><span class="c">${s.lines.length}</span>`;
    li.onclick = () => { state.scene = i; state.selected = -1; state.section = "script"; render(); };
    sl.appendChild(li);
  });
  f.characters.forEach((c) => {
    const li = document.createElement("li");
    li.innerHTML = `<span class="n">${M.escapeHtml(c.name || "（無名）")}</span>`;
    li.onclick = () => { state.section = "cast"; render(); };
    cl.appendChild(li);
  });
}

// ---- 台本（行の編集）

function px(size: number) { return state.fontSize * (size / 12); }

function autosize(ta: HTMLTextAreaElement) {
  if (state.vertical) { ta.style.width = "auto"; ta.style.width = Math.max(ta.scrollWidth, 24) + "px"; }
  else { ta.style.height = "auto"; ta.style.height = Math.max(ta.scrollHeight, 24) + "px"; }
}

function focusLine(i: number, atEnd = false) {
  const ta = document.querySelector<HTMLTextAreaElement>(`.line[data-i="${i}"] textarea.body`);
  if (!ta) return;
  ta.focus();
  if (atEnd) ta.setSelectionRange(ta.value.length, ta.value.length);
  ta.scrollIntoView({ block: "nearest", inline: "nearest" });
}

function renderScript(focus?: number) {
  const f = state.file!;
  if (state.scene >= f.scenes.length) state.scene = Math.max(0, f.scenes.length - 1);
  const scene = f.scenes[state.scene];
  const sel = $("sceneSelect") as HTMLSelectElement;
  sel.innerHTML = f.scenes.map((s, i) => `<option value="${i}" ${i === state.scene ? "selected" : ""}>${i + 1}. ${M.escapeHtml(s.name || "（無題の場面）")}</option>`).join("");
  $("btnPrevScene").toggleAttribute("disabled", state.scene <= 0);
  $("btnNextScene").toggleAttribute("disabled", state.scene >= f.scenes.length - 1);
  $("sceneDesc").textContent = scene ? scene.description.replace(/\n/g, " ") : "";
  $("lineCount").textContent = scene ? `${scene.lines.length} 行` : "";
  const box = $("lines");
  box.className = "lines " + (state.vertical ? "vertical" : "horizontal");
  box.innerHTML = "";
  if (!scene) { box.innerHTML = `<div class="hint">場面がありません。「場面」画面で場面を追加すると台詞を書けます。</div>`; return; }
  const bodyChars = (indent: number) => Math.max(f.setting.bodyLength - indent, 4);
  scene.lines.forEach((line, i) => {
    const st = M.resolveStyle(f, line.type);
    const el = document.createElement("div");
    el.className = "line" + (i === state.selected ? " sel" : "");
    el.dataset.i = String(i);
    // 見出し: 種別・人物（または省略文字）・メニュー
    const hd = document.createElement("div"); hd.className = "hd";
    const typeSel = document.createElement("select"); typeSel.className = "type";
    typeSel.innerHTML = [...f.styles].sort((a, b) => a.order - b.order).map((s) => `<option value="${s.id}" ${s.id === line.type ? "selected" : ""}>${M.escapeHtml(s.name)}</option>`).join("")
      + (f.styles.some((s) => s.id === line.type) ? "" : `<option value="${line.type}" selected>種別 ${line.type}</option>`);
    typeSel.style.color = st.color;
    typeSel.onchange = () => { line.type = parseInt(typeSel.value, 10); markDirty(); renderScript(i); };
    const row1 = document.createElement("div"); row1.style.display = "flex"; row1.style.gap = "4px"; row1.style.alignItems = "center";
    row1.appendChild(typeSel);
    const menu = document.createElement("button"); menu.className = "menu"; menu.textContent = "⋯"; menu.title = "行の操作";
    menu.onclick = (ev) => showLineMenu(ev, i);
    row1.appendChild(menu);
    hd.appendChild(row1);
    if (st.showsName) {
      const cs = document.createElement("select"); cs.className = "chara";
      cs.innerHTML = `<option value="">（人物なし）</option>` + f.characters.map((c) => `<option value="${c.id}" ${c.id === line.character ? "selected" : ""}>${M.escapeHtml(c.name)}</option>`).join("");
      cs.onchange = () => { if (cs.value) line.character = parseInt(cs.value, 10); else delete line.character; markDirty(); };
      hd.appendChild(cs);
    } else {
      const ab = document.createElement("div"); ab.className = "abbr"; ab.textContent = st.abbr; ab.style.color = st.color; hd.appendChild(ab);
    }
    el.appendChild(hd);
    // 本文: 「読む」と同じ文字数で折り返す。文字の大きさと色はスタイルに従う
    const bd = document.createElement("div"); bd.className = "bd";
    const ta = document.createElement("textarea");
    ta.className = "body"; ta.value = line.text; ta.rows = 1; ta.spellcheck = false; ta.placeholder = "本文";
    ta.style.fontSize = px(st.size) + "px"; ta.style.color = st.color;
    const n = bodyChars(st.indent);
    if (state.vertical) {
      ta.style.height = `calc(${n}em + 10px)`;
      ta.style.marginTop = `${st.indent}em`;
    } else {
      ta.style.width = `calc(${n}em + 10px)`;
      if (st.indent > 0) { const sp = document.createElement("div"); sp.style.width = `${st.indent * px(st.size)}px`; sp.style.flex = "0 0 auto"; bd.appendChild(sp); }
      if (st.kagi) { const k = document.createElement("span"); k.className = "kagi"; k.textContent = "「"; k.style.color = st.color; bd.appendChild(k); }
    }
    ta.oninput = () => { line.text = ta.value; markDirty(); autosize(ta); };
    ta.onfocus = () => { document.querySelectorAll(".line.sel").forEach((x) => x.classList.remove("sel")); el.classList.add("sel"); state.selected = i; };
    ta.onkeydown = (ev) => onLineKey(ev, i);
    bd.appendChild(ta);
    el.appendChild(bd);
    box.appendChild(el);
    autosize(ta);
  });
  const add = document.createElement("div"); add.className = "add-col";
  const ab = document.createElement("button"); ab.textContent = "＋ 行を追加"; ab.onclick = () => insertLine(scene.lines.length);
  add.appendChild(ab); box.appendChild(add);
  if (!scene.lines.length) { const h = document.createElement("div"); h.className = "hint"; h.textContent = "まだ台詞がありません。「行を追加」か、行の中で Ctrl+Enter で書き始めてください。"; box.appendChild(h); }
  // 縦書きは右端（先頭）から
  if (state.vertical) box.scrollLeft = box.scrollWidth;
  if (focus !== undefined) focusLine(focus, true);
  renderSidebar();
}

function onLineKey(ev: KeyboardEvent, i: number) {
  const f = state.file!;
  const scene = f.scenes[state.scene];
  const mod = ev.ctrlKey || ev.metaKey;
  if (ev.isComposing) return;   // 日本語入力の変換中は IME に任せる
  if (ev.key === "Tab") { ev.preventDefault(); focusLine(ev.shiftKey ? i - 1 : i + 1); return; }
  if (mod && ev.key === "Enter") { ev.preventDefault(); insertLine(ev.shiftKey ? i : i + 1); return; }
  if (mod && !state.vertical && (ev.key === "ArrowDown" || ev.key === "ArrowUp")) { ev.preventDefault(); focusLine(ev.key === "ArrowDown" ? i + 1 : i - 1); return; }
  if (mod && state.vertical && (ev.key === "ArrowLeft" || ev.key === "ArrowRight")) { ev.preventDefault(); focusLine(ev.key === "ArrowLeft" ? i + 1 : i - 1); return; }
  if (mod && ev.altKey && (ev.key === "ArrowDown" || ev.key === "ArrowUp" || ev.key === "ArrowLeft" || ev.key === "ArrowRight")) {
    ev.preventDefault();
    const down = ev.key === "ArrowDown" || ev.key === "ArrowLeft";
    moveLine(i, down ? 1 : -1);
    return;
  }
  if (ev.key === "Escape") { (ev.target as HTMLElement).blur(); }
  void scene;
}

function insertLine(at: number) {
  const f = state.file!;
  const scene = f.scenes[state.scene];
  const prev = scene.lines[Math.max(0, at - 1)];
  // 直前の行が名前を出す種別ならその人物を、そうでなければセリフを既定にする
  const line: M.Line = { type: prev ? prev.type : 1, text: "" };
  if (prev?.character !== undefined && M.resolveStyle(f, line.type).showsName) line.character = prev.character;
  scene.lines.splice(at, 0, line);
  markDirty();
  state.selected = at;
  renderScript(at);
}

function deleteLine(i: number) {
  const scene = state.file!.scenes[state.scene];
  scene.lines.splice(i, 1);
  markDirty();
  state.selected = Math.min(i, scene.lines.length - 1);
  renderScript(state.selected >= 0 ? state.selected : undefined);
}

function moveLine(i: number, d: number) {
  const scene = state.file!.scenes[state.scene];
  const j = i + d;
  if (j < 0 || j >= scene.lines.length) return;
  [scene.lines[i], scene.lines[j]] = [scene.lines[j], scene.lines[i]];
  markDirty();
  state.selected = j;
  renderScript(j);
}

function showLineMenu(ev: MouseEvent, i: number) {
  ev.stopPropagation();
  document.querySelectorAll(".menu-pop").forEach((x) => x.remove());
  const pop = document.createElement("div"); pop.className = "menu-pop";
  const v = state.vertical;
  const items: [string, () => void, string?][] = [
    [v ? "この右に行を追加" : "この上に行を追加", () => insertLine(i)],
    [v ? "この左に行を追加" : "この下に行を追加", () => insertLine(i + 1)],
    ["-", () => {}],
    [v ? "前へ（右へ）" : "上へ", () => moveLine(i, -1)],
    [v ? "次へ（左へ）" : "下へ", () => moveLine(i, 1)],
    ["-", () => {}],
    ["削除", () => deleteLine(i), "danger"],
  ];
  for (const [label, fn, cls] of items) {
    if (label === "-") { pop.appendChild(document.createElement("hr")); continue; }
    const b = document.createElement("button"); b.textContent = label; if (cls) b.className = cls;
    b.onclick = () => { pop.remove(); fn(); };
    pop.appendChild(b);
  }
  const r = (ev.target as HTMLElement).getBoundingClientRect();
  pop.style.left = Math.min(r.left, window.innerWidth - 180) + "px"; pop.style.top = r.bottom + 4 + "px";
  document.body.appendChild(pop);
  setTimeout(() => document.addEventListener("click", () => pop.remove(), { once: true }), 0);
}

// ---- 場面・登場人物・シノプシス・情報

function inputRow(label: string, value: string, onChange: (v: string) => void, cls = "wide"): HTMLElement {
  const wrap = document.createElement("div");
  const l = document.createElement("label"); l.textContent = label; wrap.appendChild(l);
  const inp = document.createElement("input"); inp.type = "text"; inp.className = cls; inp.value = value;
  inp.oninput = () => { onChange(inp.value); markDirty(); };
  wrap.appendChild(inp);
  return wrap;
}

function renderScenes() {
  const f = state.file!;
  const box = $("secScenes"); box.innerHTML = "";
  const head = document.createElement("div"); head.className = "muted"; head.textContent = `場面 ${f.scenes.length}`; box.appendChild(head);
  f.scenes.forEach((s, i) => {
    const row = document.createElement("div"); row.className = "row";
    row.innerHTML = `<div class="num">${i + 1}</div>`;
    const col = document.createElement("div"); col.className = "col";
    const h = document.createElement("div"); h.className = "h";
    const name = document.createElement("input"); name.type = "text"; name.className = "name wide"; name.placeholder = "場面名（柱）"; name.value = s.name;
    name.oninput = () => { s.name = name.value; markDirty(); renderSidebar(); };
    const valid = document.createElement("select"); valid.innerHTML = `<option value="1">有効</option><option value="0">無効</option>`; valid.value = s.valid ? "1" : "0";
    valid.onchange = () => { s.valid = valid.value === "1"; markDirty(); };
    const mi = document.createElement("input"); mi.type = "text"; mi.className = "short"; mi.value = String(s.minutes); mi.oninput = () => { s.minutes = parseInt(mi.value, 10) || 0; markDirty(); };
    const se = document.createElement("input"); se.type = "text"; se.className = "short"; se.value = String(s.seconds); se.oninput = () => { s.seconds = parseInt(se.value, 10) || 0; markDirty(); };
    const go = document.createElement("button"); go.textContent = "台本"; go.title = "この場面の台本を開く"; go.onclick = () => { state.scene = i; state.section = "script"; render(); };
    const del = document.createElement("button"); del.textContent = "削除"; del.onclick = async () => {
      if (s.lines.length && !(await ask(`場面「${s.name}」と、その ${s.lines.length} 行の台詞を削除しますか？`, { kind: "warning", okLabel: "削除する", cancelLabel: "キャンセル" }))) return;
      f.scenes.splice(i, 1); markDirty(); if (state.scene >= f.scenes.length) state.scene = Math.max(0, f.scenes.length - 1); render();
    };
    h.append(name, valid, mi, document.createTextNode("分"), se, document.createTextNode("秒"), go, del);
    col.appendChild(h);
    const ts = f.textStyles.scene;
    const desc = document.createElement("textarea"); desc.className = "wide"; desc.rows = 2; desc.placeholder = "場面説明（場所・時間など。台本にも出ます）"; desc.value = s.description;
    desc.style.color = ts.color; desc.style.fontSize = px(ts.size) + "px";
    desc.oninput = () => { s.description = desc.value; markDirty(); };
    col.appendChild(desc);
    const c = document.createElement("div"); c.className = "muted"; c.textContent = `${s.lines.length} 行`; col.appendChild(c);
    row.appendChild(col); box.appendChild(row);
  });
  const add = document.createElement("button"); add.textContent = "＋ 場面を追加"; add.className = "small"; add.onclick = addScene; box.appendChild(add);
}

function addScene() {
  const f = state.file!;
  f.scenes.push({ name: `　${f.scenes.length + 1}場`, description: "", valid: true, minutes: 0, seconds: 0, lines: [] });
  markDirty(); render();
}

function renderCast() {
  const f = state.file!;
  const box = $("secCast"); box.innerHTML = "";
  const head = document.createElement("div"); head.className = "muted"; head.textContent = `登場人物 ${f.characters.length}`; box.appendChild(head);
  const counts = new Map<number, number>();
  for (const s of f.scenes) for (const l of s.lines) if (l.character !== undefined) counts.set(l.character, (counts.get(l.character) ?? 0) + 1);
  f.characters.forEach((c, i) => {
    const row = document.createElement("div"); row.className = "row";
    row.innerHTML = `<div class="num">${i + 1}</div>`;
    const col = document.createElement("div"); col.className = "col";
    const h = document.createElement("div"); h.className = "h";
    const name = document.createElement("input"); name.type = "text"; name.className = "name"; name.style.width = "240px"; name.placeholder = "登場人物名"; name.value = c.name;
    name.oninput = () => { c.name = name.value; markDirty(); renderSidebar(); };
    const cnt = document.createElement("span"); cnt.className = "muted"; cnt.textContent = `${counts.get(c.id) ?? 0} 台詞`;
    const up = document.createElement("button"); up.textContent = "↑"; up.onclick = () => { if (i > 0) { [f.characters[i - 1], f.characters[i]] = [f.characters[i], f.characters[i - 1]]; markDirty(); render(); } };
    const dn = document.createElement("button"); dn.textContent = "↓"; dn.onclick = () => { if (i < f.characters.length - 1) { [f.characters[i + 1], f.characters[i]] = [f.characters[i], f.characters[i + 1]]; markDirty(); render(); } };
    const del = document.createElement("button"); del.textContent = "削除"; del.onclick = async () => {
      if (!(await ask(`「${c.name}」を削除しますか？この人物の台詞は名前なしになります（台詞そのものは残ります）。`, { kind: "warning", okLabel: "削除する", cancelLabel: "キャンセル" }))) return;
      for (const s of f.scenes) for (const l of s.lines) if (l.character === c.id) delete l.character;
      f.characters.splice(i, 1); markDirty(); render();
    };
    h.append(name, cnt, up, dn, del);
    col.appendChild(h);
    const ts = f.textStyles.character;
    const chara = document.createElement("textarea"); chara.className = "wide"; chara.rows = 2; chara.placeholder = "人物設定（年齢・性格など。台本の人物表に出ます）"; chara.value = c.chara;
    chara.style.color = ts.color; chara.style.fontSize = px(ts.size) + "px";
    chara.oninput = () => { c.chara = chara.value; markDirty(); };
    col.appendChild(chara);
    row.appendChild(col); box.appendChild(row);
  });
  const add = document.createElement("button"); add.textContent = "＋ 登場人物を追加"; add.className = "small"; add.onclick = addCast; box.appendChild(add);
}

function addCast() {
  const f = state.file!;
  const id = f.characters.reduce((m, c) => Math.max(m, c.id), 0) + 1;
  f.characters.push({ id, name: `登場人物${f.characters.length + 1}`, chara: "" });
  markDirty(); render();
}

function renderSynopsis() {
  const f = state.file!;
  const ta = $("synopsis") as HTMLTextAreaElement;
  const ts = f.textStyles.synopsis;
  ta.value = f.synopsis;
  ta.className = "synopsis" + (state.vertical ? " vertical" : "");
  ta.style.color = ts.color; ta.style.fontSize = px(ts.size) + "px";
  const n = Math.max(f.setting.bodyLength - ts.indent, 4);
  if (state.vertical) { ta.style.height = `calc(${n}em + 24px)`; ta.style.width = ""; ta.style.alignSelf = "flex-end"; }
  else { ta.style.width = `calc(${n}em + 24px)`; ta.style.height = ""; ta.style.alignSelf = ""; }
  ta.oninput = () => { f.synopsis = ta.value; markDirty(); };
}

function renderInfo() {
  const f = state.file!;
  const box = $("secInfo"); box.innerHTML = "";
  box.appendChild(inputRow("題名", f.scenario.title, (v) => { f.scenario.title = v; updateTitle(); }));
  box.appendChild(inputRow("副題", f.scenario.subtitle, (v) => { f.scenario.subtitle = v; }));
  box.appendChild(inputRow("作者名", f.scenario.writer, (v) => { f.scenario.writer = v; }));
  const catWrap = document.createElement("div"); const cl = document.createElement("label"); cl.textContent = "分類"; catWrap.appendChild(cl);
  const cat = document.createElement("select"); cat.innerHTML = M.CATEGORIES.map(([v, l]) => `<option value="${v}" ${v === f.scenario.category ? "selected" : ""}>${l}</option>`).join("");
  cat.onchange = () => { f.scenario.category = parseInt(cat.value, 10); markDirty(); }; catWrap.appendChild(cat); box.appendChild(catWrap);
  const memoWrap = document.createElement("div"); const ml = document.createElement("label"); ml.textContent = "メモ（住所など）"; memoWrap.appendChild(ml);
  const memo = document.createElement("textarea"); memo.className = "wide"; memo.rows = 3; memo.value = f.scenario.memo; memo.oninput = () => { f.scenario.memo = memo.value; markDirty(); };
  memoWrap.appendChild(memo); box.appendChild(memoWrap);
  const h = document.createElement("h3"); h.textContent = "書式（この作品に保存されます）"; h.style.marginTop = "20px"; box.appendChild(h);
  const num = (label: string, get: () => number, set: (v: number) => void) => {
    const w = document.createElement("div"); const l = document.createElement("label"); l.textContent = label; w.appendChild(l);
    const inp = document.createElement("input"); inp.type = "number"; inp.className = "short"; inp.min = "4"; inp.max = "60"; inp.value = String(get());
    inp.onchange = () => { set(Math.max(4, Math.min(60, parseInt(inp.value, 10) || get()))); inp.value = String(get()); markDirty(); };
    w.appendChild(inp); box.appendChild(w);
  };
  num("見出し欄（登場人物名）の文字数", () => f.setting.characterLength, (v) => { f.setting.characterLength = v; });
  num("本文 1 行の文字数（編集画面・読む画面で折り返す長さ）", () => f.setting.bodyLength, (v) => { f.setting.bodyLength = v; });
  const kw = document.createElement("div"); const kl = document.createElement("label"); kl.textContent = "台詞"; kw.appendChild(kl);
  const kagi = document.createElement("input"); kagi.type = "checkbox"; kagi.checked = f.setting.kagikakko;
  kagi.onchange = () => { f.setting.kagikakko = kagi.checked; markDirty(); };
  const klab = document.createElement("label"); klab.style.display = "inline"; klab.append(kagi, " 台詞を「」で囲む"); kw.appendChild(klab); box.appendChild(kw);
  const note = document.createElement("p"); note.className = "muted"; note.textContent = `更新: ${f.scenario.date}　保存先: ${state.path ?? "（未保存）"}`; box.appendChild(note);
}

function renderReader() {
  const f = state.file!;
  const iframe = $("reader") as HTMLIFrameElement;
  iframe.srcdoc = buildReaderHtml(f, { vertical: state.vertical, fontSize: state.fontSize, showBar: true });
}

// ---- 全体の操作

function setVertical(v: boolean) {
  state.vertical = v;
  localStorage.setItem("sw_vertical", v ? "1" : "0");
  $("btnVertical").classList.toggle("on", v);
  $("btnVertical").textContent = v ? "縦書き" : "横書き";
  if (state.file) show(state.section);
}

function setup() {
  $("btnNew").onclick = newFile; $("btnNew2").onclick = newFile;
  $("btnOpen").onclick = openFile; $("btnOpen2").onclick = openFile;
  $("btnSave").onclick = save; $("btnSaveAs").onclick = saveAs;
  $("btnVertical").onclick = () => setVertical(!state.vertical);
  const fs = $("fontSize") as HTMLInputElement;
  fs.value = String(state.fontSize);
  fs.oninput = () => { state.fontSize = parseInt(fs.value, 10); localStorage.setItem("sw_fontSize", fs.value); document.documentElement.style.setProperty("--base-fs", state.fontSize + "px"); if (state.file) show(state.section); };
  document.documentElement.style.setProperty("--base-fs", state.fontSize + "px");
  document.querySelectorAll<HTMLButtonElement>(".sections button").forEach((b) => { b.onclick = () => { if (state.file) show(b.dataset.section as Section); }; });
  $("btnAddScene").onclick = addScene; $("btnAddCast").onclick = addCast;
  ($("sceneSelect") as HTMLSelectElement).onchange = (e) => { state.scene = parseInt((e.target as HTMLSelectElement).value, 10); state.selected = -1; renderScript(); };
  $("btnPrevScene").onclick = () => { if (state.scene > 0) { state.scene--; state.selected = -1; renderScript(); } };
  $("btnNextScene").onclick = () => { if (state.file && state.scene < state.file.scenes.length - 1) { state.scene++; state.selected = -1; renderScript(); } };
  $("btnAddLine").onclick = () => { if (state.file?.scenes[state.scene]) insertLine(state.file.scenes[state.scene].lines.length); };
  document.addEventListener("keydown", (ev) => {
    const mod = ev.ctrlKey || ev.metaKey;
    if (!mod) return;
    const k = ev.key.toLowerCase();
    if (k === "s") { ev.preventDefault(); if (ev.shiftKey) saveAs(); else save(); }
    else if (k === "o") { ev.preventDefault(); openFile(); }
    else if (k === "n") { ev.preventDefault(); newFile(); }
    else if (k === "t" && ev.altKey) { ev.preventDefault(); setVertical(!state.vertical); }
    else if (k === "[" && state.file) { ev.preventDefault(); $("btnPrevScene").click(); }
    else if (k === "]" && state.file) { ev.preventDefault(); $("btnNextScene").click(); }
    else if (/^[1-6]$/.test(ev.key) && state.file) { ev.preventDefault(); show((["script", "scenes", "cast", "synopsis", "info", "read"] as Section[])[parseInt(ev.key, 10) - 1]); }
  });
  win?.onCloseRequested(async (ev) => {
    if (!state.dirty) return;
    ev.preventDefault();
    if (await confirmDiscard("終了する")) { state.dirty = false; await win.destroy(); }
  });
  setVertical(state.vertical);
  render();
  updateTitle();
  // 起動時に .scwd が渡されていれば開く（Windows の関連付け・コマンドライン）
  if (inTauri()) {
    invoke<string | null>("startup_file").then((p) => { if (p) openPath(p); }).catch(() => {});
  } else if (location.search.includes("sample")) {
    // 開発用: ふつうのブラウザで開いたときは public/sample.scwd を読む（保存はできない）
    fetch("/sample.scwd").then((r) => r.text()).then((t) => { state.file = M.parse(t); state.path = null; render(); updateTitle(); }).catch(() => {});
  }
}

function inTauri(): boolean { return !!(window as any).__TAURI_INTERNALS__; }

window.addEventListener("DOMContentLoaded", setup);
