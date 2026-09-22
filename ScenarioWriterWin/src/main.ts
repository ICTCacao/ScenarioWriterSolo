// ScenarioWriterSolo Windows 版の画面。作品は 1 つずつ .scwd（JSON）で、Mac 版と同じ形式。
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { open as openDialog, save as saveDialog, ask, message } from "@tauri-apps/plugin-dialog";
import { Menu, Submenu, MenuItem, CheckMenuItem, PredefinedMenuItem } from "@tauri-apps/api/menu";
import * as M from "./model";
import { buildReaderHtml } from "./reader";

type Section = "script" | "scenes" | "cast" | "synopsis" | "info" | "read" | "styles";

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
  applyLastStyles(state.file);
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
    rememberStyles(state.file);
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
  const ids: Record<Section, string> = { script: "secScript", scenes: "secScenes", cast: "secCast", synopsis: "secSynopsis", info: "secInfo", read: "secRead", styles: "secStyles" };
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
    case "styles": renderStyles(); break;
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
  const vertical = state.vertical || ta.classList.contains("v");
  if (vertical) { ta.style.width = "auto"; ta.style.width = Math.max(ta.scrollWidth, 24) + "px"; }
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
  box.className = "section form" + (state.vertical ? " vertical" : "");
  const ts = f.textStyles.scene;
  const descChars = Math.max(f.setting.bodyLength - ts.indent, 4);
  f.scenes.forEach((s, i) => {
    const row = document.createElement("div"); row.className = "row";
    const col = document.createElement("div"); col.className = "col";
    const h = document.createElement("div"); h.className = "h";
    const num = document.createElement("span"); num.className = "num"; num.textContent = String(i + 1);
    const valid = document.createElement("select"); valid.innerHTML = `<option value="1">有効</option><option value="0">無効</option>`; valid.value = s.valid ? "1" : "0";
    valid.onchange = () => { s.valid = valid.value === "1"; markDirty(); };
    const mi = document.createElement("input"); mi.type = "text"; mi.className = "short"; mi.value = String(s.minutes); mi.oninput = () => { s.minutes = parseInt(mi.value, 10) || 0; markDirty(); };
    const se = document.createElement("input"); se.type = "text"; se.className = "short"; se.value = String(s.seconds); se.oninput = () => { s.seconds = parseInt(se.value, 10) || 0; markDirty(); };
    const go = document.createElement("button"); go.textContent = "台本"; go.title = "この場面の台本を開く"; go.onclick = () => { state.scene = i; state.section = "script"; render(); };
    const del = document.createElement("button"); del.textContent = "削除"; del.onclick = async () => {
      if (s.lines.length && !(await ask(`場面「${s.name}」と、その ${s.lines.length} 行の台詞を削除しますか？`, { kind: "warning", okLabel: "削除する", cancelLabel: "キャンセル" }))) return;
      f.scenes.splice(i, 1); markDirty(); if (state.scene >= f.scenes.length) state.scene = Math.max(0, f.scenes.length - 1); render();
    };
    const count = document.createElement("span"); count.className = "muted count"; count.textContent = `${s.lines.length} 行`;
    if (state.vertical) {
      // 縦書き: 上に番号と操作、下に 場面説明（左）・場面名（右）の縦書き欄
      const top = document.createElement("div"); top.className = "h"; top.append(num, go, del);
      const ctl = document.createElement("div"); ctl.className = "h"; ctl.append(valid, mi, document.createTextNode("分"), se, document.createTextNode("秒"));
      const fields = document.createElement("div"); fields.className = "vfields";
      const desc = document.createElement("textarea"); desc.className = "v"; desc.placeholder = "場面説明"; desc.value = s.description;
      desc.style.color = ts.color; desc.style.fontSize = px(ts.size) + "px"; desc.style.height = `calc(${descChars}em + 10px)`; desc.style.minWidth = "200px";
      desc.oninput = () => { s.description = desc.value; markDirty(); autosize(desc); };
      const name = document.createElement("textarea"); name.className = "v name"; name.placeholder = "場面名（柱）"; name.value = s.name;
      name.style.fontSize = px(ts.size + 2) + "px"; name.style.fontWeight = "bold"; name.style.height = `calc(${descChars}em + 10px)`;
      name.oninput = () => { s.name = name.value; markDirty(); autosize(name); renderSidebar(); };
      fields.append(desc, name);
      col.append(top, ctl, fields, count);
      row.appendChild(col); box.appendChild(row);
      autosize(desc); autosize(name);
    } else {
      row.innerHTML = `<div class="num">${i + 1}</div>`;
      const name = document.createElement("input"); name.type = "text"; name.className = "name wide"; name.placeholder = "場面名（柱）"; name.value = s.name;
      name.oninput = () => { s.name = name.value; markDirty(); renderSidebar(); };
      h.append(name, valid, mi, document.createTextNode("分"), se, document.createTextNode("秒"), go, del);
      col.appendChild(h);
      const desc = document.createElement("textarea"); desc.className = "wide"; desc.rows = 2; desc.placeholder = "場面説明（場所・時間など。台本にも出ます）"; desc.value = s.description;
      desc.style.color = ts.color; desc.style.fontSize = px(ts.size) + "px"; desc.style.maxWidth = `calc(${descChars}em + 24px)`;
      desc.oninput = () => { s.description = desc.value; markDirty(); };
      col.append(desc, count);
      row.appendChild(col); box.appendChild(row);
    }
  });
  if (!state.vertical) { const add = document.createElement("button"); add.textContent = "＋ 場面を追加"; add.className = "small"; add.onclick = addScene; box.appendChild(add); }
  if (state.vertical) box.scrollLeft = box.scrollWidth;
}

function addScene() {
  const f = state.file!;
  f.scenes.push({ name: `　${f.scenes.length + 1}場`, description: "", valid: true, minutes: 0, seconds: 0, lines: [] });
  markDirty(); render();
}

function renderCast() {
  const f = state.file!;
  const box = $("secCast"); box.innerHTML = "";
  box.className = "section form" + (state.vertical ? " vertical" : "");
  const counts = new Map<number, number>();
  for (const s of f.scenes) for (const l of s.lines) if (l.character !== undefined) counts.set(l.character, (counts.get(l.character) ?? 0) + 1);
  const ts = f.textStyles.character;
  const charaChars = Math.max(f.setting.bodyLength - ts.indent, 4);
  f.characters.forEach((c, i) => {
    const row = document.createElement("div"); row.className = "row";
    const col = document.createElement("div"); col.className = "col";
    const num = document.createElement("span"); num.className = "num"; num.textContent = String(i + 1);
    const cnt = document.createElement("span"); cnt.className = "muted count"; cnt.textContent = `${counts.get(c.id) ?? 0} 台詞`;
    const swap = (j: number) => { if (j < 0 || j >= f.characters.length) return; [f.characters[i], f.characters[j]] = [f.characters[j], f.characters[i]]; markDirty(); render(); };
    const up = document.createElement("button"); up.textContent = state.vertical ? "→" : "↑"; up.title = "前へ"; up.onclick = () => swap(i - 1);
    const dn = document.createElement("button"); dn.textContent = state.vertical ? "←" : "↓"; dn.title = "次へ"; dn.onclick = () => swap(i + 1);
    const del = document.createElement("button"); del.textContent = "削除"; del.onclick = async () => {
      if (!(await ask(`「${c.name}」を削除しますか？この人物の台詞は名前なしになります（台詞そのものは残ります）。`, { kind: "warning", okLabel: "削除する", cancelLabel: "キャンセル" }))) return;
      for (const s of f.scenes) for (const l of s.lines) if (l.character === c.id) delete l.character;
      f.characters.splice(i, 1); markDirty(); render();
    };
    if (state.vertical) {
      const top = document.createElement("div"); top.className = "h"; top.append(num, cnt, up, dn, del);
      const fields = document.createElement("div"); fields.className = "vfields";
      const chara = document.createElement("textarea"); chara.className = "v"; chara.placeholder = "人物設定"; chara.value = c.chara;
      chara.style.color = ts.color; chara.style.fontSize = px(ts.size) + "px"; chara.style.height = `calc(${charaChars}em + 10px)`; chara.style.minWidth = "148px";
      chara.oninput = () => { c.chara = chara.value; markDirty(); autosize(chara); };
      const name = document.createElement("textarea"); name.className = "v name"; name.placeholder = "登場人物名"; name.value = c.name;
      name.style.fontSize = px(ts.size + 2) + "px"; name.style.fontWeight = "bold"; name.style.height = `calc(${charaChars}em + 10px)`;
      name.oninput = () => { c.name = name.value; markDirty(); autosize(name); renderSidebar(); };
      fields.append(chara, name);
      col.append(top, fields);
      row.appendChild(col); box.appendChild(row);
      autosize(chara); autosize(name);
    } else {
      row.innerHTML = `<div class="num">${i + 1}</div>`;
      const h = document.createElement("div"); h.className = "h";
      const name = document.createElement("input"); name.type = "text"; name.className = "name"; name.style.width = "240px"; name.placeholder = "登場人物名"; name.value = c.name;
      name.oninput = () => { c.name = name.value; markDirty(); renderSidebar(); };
      h.append(name, cnt, up, dn, del);
      col.appendChild(h);
      const chara = document.createElement("textarea"); chara.className = "wide"; chara.rows = 2; chara.placeholder = "人物設定（年齢・性格など。台本の人物表に出ます）"; chara.value = c.chara;
      chara.style.color = ts.color; chara.style.fontSize = px(ts.size) + "px"; chara.style.maxWidth = `calc(${charaChars}em + 24px)`;
      chara.oninput = () => { c.chara = chara.value; markDirty(); };
      col.appendChild(chara);
      row.appendChild(col); box.appendChild(row);
    }
  });
  if (!state.vertical) { const add = document.createElement("button"); add.textContent = "＋ 登場人物を追加"; add.className = "small"; add.onclick = addCast; box.appendChild(add); }
  if (state.vertical) box.scrollLeft = box.scrollWidth;
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
  const wrap = $("synopsisWrap");
  ta.value = f.synopsis;
  ta.className = "synopsis" + (state.vertical ? " vertical" : "");
  wrap.className = "synwrap" + (state.vertical ? " vertical" : "");
  ta.style.color = ts.color; ta.style.fontSize = px(ts.size) + "px";
  const n = Math.max(f.setting.bodyLength - ts.indent, 4);
  if (state.vertical) {
    ta.style.height = `calc(${n}em + 24px)`; ta.style.width = "";
    autosize(ta);
    wrap.scrollLeft = wrap.scrollWidth;
  } else {
    ta.style.width = `calc(${n}em + 24px)`; ta.style.height = "";
  }
  ta.oninput = () => { f.synopsis = ta.value; markDirty(); if (state.vertical) autosize(ta); };
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

// ---- スタイル（行の種別ごとの見た目と、固定スタイル）。作品ファイルに保存され、次の新規作品にも引き継ぐ

const MODE_LABELS: [number, string][] = [
  [1, "登場人物名を出す・台詞を「」で囲む"], [2, "登場人物名を出す・「」で囲まない"],
  [3, "登場人物名を出さない・台詞を「」で囲む"], [0, "登場人物名を出さない・「」で囲まない"],
];
const TEXT_STYLE_LABELS: [string, string][] = [["synopsis", "シノプシス"], ["scene", "場面説明"], ["character", "登場人物"]];

function rememberStyles(f: M.ScwdFile) {
  try { localStorage.setItem("sw_lastStyles", JSON.stringify({ styles: f.styles, textStyles: f.textStyles, setting: f.setting })); } catch {}
}
function applyLastStyles(f: M.ScwdFile) {
  try {
    const raw = localStorage.getItem("sw_lastStyles"); if (!raw) return;
    const j = JSON.parse(raw);
    if (Array.isArray(j.styles) && j.styles.length) f.styles = j.styles;
    if (j.textStyles) f.textStyles = { ...f.textStyles, ...j.textStyles };
    if (j.setting) f.setting = { ...f.setting, ...j.setting };
  } catch {}
}

function renderStyles() {
  const f = state.file!;
  const box = $("secStyles"); box.innerHTML = "";
  box.className = "section form";
  const head = document.createElement("p"); head.className = "muted";
  head.textContent = "行の「種別」ごとの見た目。台本画面の種別メニューにはこの並び順で出ます。🔒 は固定スタイル（名前を変えたり消したりできません）。変更はこの作品ファイルに保存され、次に作る作品にも引き継がれます。";
  box.appendChild(head);
  const table = document.createElement("table"); table.className = "styles-table";
  table.innerHTML = `<thead><tr><th>順</th><th>スタイル名</th><th>番号</th><th>サイズ</th><th>色</th><th>字下げ</th><th>省略文字</th><th>余白 前</th><th>後</th><th>表示の仕方</th><th></th></tr></thead>`;
  const tbody = document.createElement("tbody");
  const num = (get: () => number, set: (v: number) => void, min: number, max: number) => {
    const i = document.createElement("input"); i.type = "number"; i.className = "n"; i.min = String(min); i.max = String(max); i.value = String(get());
    i.onchange = () => { const v = Math.max(min, Math.min(max, parseInt(i.value, 10) || 0)); set(v); i.value = String(v); markDirty(); };
    return i;
  };
  const text = (get: () => string, set: (v: string) => void, cls: string) => {
    const i = document.createElement("input"); i.type = "text"; i.className = cls; i.value = get();
    i.oninput = () => { set(i.value); markDirty(); };
    return i;
  };
  const color = (get: () => string, set: (v: string) => void) => {
    const i = document.createElement("input"); i.type = "color"; i.value = /^#[0-9a-fA-F]{6}$/.test(get()) ? get() : "#000000";
    i.oninput = () => { set(i.value); markDirty(); };
    return i;
  };
  const td = (el: HTMLElement | string) => { const c = document.createElement("td"); if (typeof el === "string") c.textContent = el; else c.appendChild(el); return c; };
  [...f.styles].sort((a, b) => a.order - b.order || a.id - b.id).forEach((st) => {
    const tr = document.createElement("tr");
    tr.append(
      td(num(() => st.order, (v) => { st.order = v; }, 0, 100000)),
      td(text(() => st.name, (v) => { st.name = v; }, "nm")),
      td(String(st.id)),
      td(num(() => st.size, (v) => { st.size = v; }, 6, 48)),
      td(color(() => st.color, (v) => { st.color = v; })),
      td(num(() => st.indent, (v) => { st.indent = v; }, 0, 20)),
      td(text(() => st.abbr, (v) => { st.abbr = v; }, "ab")),
      td(num(() => st.marginBefore, (v) => { st.marginBefore = v; }, 0, 4)),
      td(num(() => st.marginAfter, (v) => { st.marginAfter = v; }, 0, 4)),
    );
    const mode = document.createElement("select");
    mode.innerHTML = MODE_LABELS.map(([v, l]) => `<option value="${v}" ${v === st.mode ? "selected" : ""}>${l}</option>`).join("");
    mode.onchange = () => { st.mode = parseInt(mode.value, 10); markDirty(); };
    tr.appendChild(td(mode));
    const del = document.createElement("button"); del.textContent = "削除"; del.className = "small"; del.style.margin = "0";
    del.onclick = async () => {
      const used = f.scenes.reduce((n, sc) => n + sc.lines.filter((l) => l.type === st.id).length, 0);
      if (!(await ask(`スタイル「${st.name}」を削除しますか？${used ? `この種別を使っている ${used} 行は「種別 ${st.id}」として残ります。` : ""}`, { kind: "warning", okLabel: "削除する", cancelLabel: "キャンセル" }))) return;
      f.styles = f.styles.filter((x) => x !== st); markDirty(); renderStyles();
    };
    tr.appendChild(td(del));
    tbody.appendChild(tr);
  });
  for (const [key, label] of TEXT_STYLE_LABELS) {
    const ts = f.textStyles[key] ?? (f.textStyles[key] = M.defaultTextStyles()[key]);
    const tr = document.createElement("tr"); tr.className = "fixed";
    const nameCell = document.createElement("td"); nameCell.innerHTML = `${label}<span class="lock">🔒</span>`;
    tr.append(td("—"), nameCell, td("—"),
      td(num(() => ts.size, (v) => { ts.size = v; }, 6, 48)),
      td(color(() => ts.color, (v) => { ts.color = v; })),
      td(num(() => ts.indent, (v) => { ts.indent = v; }, 0, 20)),
      td(""),
      td(num(() => ts.marginBefore, (v) => { ts.marginBefore = v; }, 0, 4)),
      td(num(() => ts.marginAfter, (v) => { ts.marginAfter = v; }, 0, 4)),
      td("固定（削除できません）"), td(""));
    tbody.appendChild(tr);
  }
  table.appendChild(tbody); box.appendChild(table);
  const actions = document.createElement("div"); actions.className = "styles-actions";
  const add = document.createElement("button"); add.textContent = "＋ USER STYLE 追加";
  add.onclick = () => {
    const id = f.styles.reduce((m, x) => Math.max(m, x.id), 0) + 1;
    const order = f.styles.reduce((m, x) => Math.max(m, x.order), 0) + 100;
    f.styles.push({ id, order, name: "新しいスタイル", size: 14, color: "#000000", indent: 0, abbr: "", mode: 1, marginBefore: 0, marginAfter: 0 });
    markDirty(); renderStyles();
  };
  const bulk = document.createElement("button"); bulk.textContent = "サイズを一括設定…";
  bulk.onclick = async () => {
    const v = prompt("すべてのスタイルのフォントサイズ（6〜48）", String(f.styles[0]?.size ?? 14));
    const n = v ? parseInt(v, 10) : NaN;
    if (!n || n < 6 || n > 48) return;
    for (const st of f.styles) st.size = n;
    for (const k of Object.keys(f.textStyles)) f.textStyles[k].size = n;
    markDirty(); renderStyles();
  };
  const reset = document.createElement("button"); reset.textContent = "既定に戻す…";
  reset.onclick = async () => {
    if (!(await ask("スタイルを既定の 13 種に戻しますか？自分で追加・変更したスタイルは消えます（固定スタイルも既定に戻ります）。台詞の種別番号は変わりません。", { kind: "warning", okLabel: "既定に戻す", cancelLabel: "キャンセル" }))) return;
    f.styles = M.defaultStyles(); f.textStyles = M.defaultTextStyles(); markDirty(); renderStyles();
  };
  const note = document.createElement("span"); note.className = "muted"; note.textContent = "サイズ 12 が基準。編集画面の文字の大きさはツールバーの「文字」でも変えられます。";
  actions.append(add, bulk, reset, note);
  box.appendChild(actions);
}

function renderReader() {
  const f = state.file!;
  const iframe = $("reader") as HTMLIFrameElement;
  iframe.srcdoc = buildReaderHtml(f, { vertical: state.vertical, fontSize: state.fontSize, showBar: true });
}

// ---- 全体の操作

let verticalMenuItem: CheckMenuItem | null = null;

function setVertical(v: boolean) {
  state.vertical = v;
  localStorage.setItem("sw_vertical", v ? "1" : "0");
  $("btnVertical").classList.toggle("on", v);
  $("btnVertical").textContent = v ? "縦書き" : "横書き";
  verticalMenuItem?.setChecked(v).catch(() => {});
  if (state.file) show(state.section);
}

function changeFontSize(d: number) {
  const fs = $("fontSize") as HTMLInputElement;
  fs.value = String(Math.max(12, Math.min(28, state.fontSize + d)));
  fs.dispatchEvent(new Event("input"));
}

/** 編集メニューの「元に戻す」などは、いま文字を打っている欄に効かせる */
function editCommand(cmd: "undo" | "redo" | "cut" | "copy" | "paste" | "selectAll") {
  const el = document.activeElement as HTMLElement | null;
  if (cmd === "paste") {
    navigator.clipboard.readText().then((t) => {
      if (el && (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement)) {
        const a = el.selectionStart ?? el.value.length, b = el.selectionEnd ?? a;
        el.setRangeText(t, a, b, "end");
        el.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }).catch(() => {});
    return;
  }
  document.execCommand(cmd);
}

/** Windows 標準のメニューバー（Mac ではアプリのメニュー）。ショートカットはメニュー側で受ける */
async function setupMenu() {
  const isMac = navigator.platform.toLowerCase().includes("mac");
  const item = (text: string, action: () => void, accelerator?: string) => MenuItem.new({ text, action, accelerator });
  const sep = () => PredefinedMenuItem.new({ item: "Separator" });
  const items: (Submenu | MenuItem | PredefinedMenuItem)[] = [];
  if (isMac) {
    items.push(await Submenu.new({ text: "ScenarioWriterWin", items: [
      await PredefinedMenuItem.new({ item: { About: { name: "ScenarioWriterWin", version: "0.5.0" } }, text: "ScenarioWriterWin について" }),
      await sep(),
      await PredefinedMenuItem.new({ item: "Hide", text: "隠す" }),
      await sep(),
      await PredefinedMenuItem.new({ item: "Quit", text: "終了" }),
    ] }));
  }
  items.push(await Submenu.new({ text: "ファイル", items: [
    await item("新規…", newFile, "CmdOrCtrl+N"),
    await item("開く…", openFile, "CmdOrCtrl+O"),
    await sep(),
    await item("保存", save, "CmdOrCtrl+S"),
    await item("別名で保存…", saveAs, "CmdOrCtrl+Shift+S"),
    await sep(),
    await item("作品を閉じる", closeFile, "CmdOrCtrl+W"),
    ...(isMac ? [] : [await sep(), await PredefinedMenuItem.new({ item: "Quit", text: "終了" })]),
  ] }));
  verticalMenuItem = await CheckMenuItem.new({ text: "縦書きで編集", checked: state.vertical, accelerator: "CmdOrCtrl+Alt+T", action: () => setVertical(!state.vertical) });
  items.push(await Submenu.new({ text: "編集", items: [
    await item("元に戻す", () => editCommand("undo")),
    await item("やり直す", () => editCommand("redo")),
    await sep(),
    await item("切り取り", () => editCommand("cut")),
    await item("コピー", () => editCommand("copy")),
    await item("貼り付け", () => editCommand("paste")),
    await item("すべて選択", () => editCommand("selectAll")),
    await sep(),
    await item("行を追加（末尾）", () => { if (state.file?.scenes[state.scene]) insertLine(state.file.scenes[state.scene].lines.length); }),
    await item("選択中の行の後に追加　Ctrl+Enter", () => { if (state.selected >= 0) insertLine(state.selected + 1); }),
    await item("選択中の行の前に追加　Ctrl+Shift+Enter", () => { if (state.selected >= 0) insertLine(state.selected); }),
    await item("選択中の行を削除", () => { if (state.selected >= 0) deleteLine(state.selected); }),
    await sep(),
    await item("場面を追加", addScene),
    await item("登場人物を追加", addCast),
  ] }));
  items.push(await Submenu.new({ text: "表示", items: [
    await item("シナリオ編集", () => state.file && show("script"), "CmdOrCtrl+1"),
    await item("場面", () => state.file && show("scenes"), "CmdOrCtrl+2"),
    await item("登場人物", () => state.file && show("cast"), "CmdOrCtrl+3"),
    await item("シノプシス", () => state.file && show("synopsis"), "CmdOrCtrl+4"),
    await item("シナリオ情報", () => state.file && show("info"), "CmdOrCtrl+5"),
    await item("読む", () => state.file && show("read"), "CmdOrCtrl+6"),
    await sep(),
    await item("前の場面", () => $("btnPrevScene").click(), "CmdOrCtrl+["),
    await item("次の場面", () => $("btnNextScene").click(), "CmdOrCtrl+]"),
    await sep(),
    verticalMenuItem,
    await item("文字を大きく", () => changeFontSize(1), "CmdOrCtrl+="),
    await item("文字を小さく", () => changeFontSize(-1), "CmdOrCtrl+-"),
  ] }));
  items.push(await Submenu.new({ text: "設定", items: [
    await item("書式（本文の文字数・「」）…", () => state.file && show("info")),
    await item("スタイル…", () => state.file && show("styles"), "CmdOrCtrl+7"),
  ] }));
  items.push(await Submenu.new({ text: "ヘルプ", items: [
    await item("ScenarioWriterSolo（Windows 版）について", () => message(`${M.APP_NAME}\n作品ファイル .scwd（JSON、版 ${M.VERSION}）は Mac 版 ScenarioWriterSolo と共通です。`, { title: "バージョン情報" })),
  ] }));
  const menu = await Menu.new({ items });
  await menu.setAsAppMenu();
}

async function closeFile() {
  if (!state.file) return;
  if (!(await confirmDiscard("作品を閉じる"))) return;
  state.file = null; state.path = null; state.dirty = false; state.selected = -1;
  render(); updateTitle();
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
  if (inTauri()) {
    $("fileButtons").classList.add("hidden");
    setupMenu().catch((e) => console.warn("menu", e));
  } else {
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
      else if (/^[1-7]$/.test(ev.key) && state.file) { ev.preventDefault(); show((["script", "scenes", "cast", "synopsis", "info", "read", "styles"] as Section[])[parseInt(ev.key, 10) - 1]); }
    });
  }
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
