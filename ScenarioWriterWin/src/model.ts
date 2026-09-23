// 作品ファイル（.scwd = JSON）の型と読み書き。仕様は ../docs/scwd-format.md（Mac 版の ScenarioFile.swift と同じ）

export interface Info { title: string; subtitle: string; writer: string; memo: string; date: string; category: number }
export interface CastMember { id: number; name: string; chara: string }
export interface Line { type: number; character?: number; text: string }
export interface Scene { name: string; description: string; valid: boolean; minutes: number; seconds: number; lines: Line[] }
export interface Style {
  id: number; order: number; name: string; size: number; color: string; indent: number; abbr: string; mode: number;
  marginBefore: number; marginAfter: number;
}
export interface TextStyle { size: number; color: string; indent: number; marginBefore: number; marginAfter: number }
export interface Setting { characterLength: number; bodyLength: number; kagikakko: boolean }
export interface ScwdFile {
  format: string; version: number; app: string;
  scenario: Info; synopsis: string; characters: CastMember[]; scenes: Scene[];
  styles: Style[]; textStyles: Record<string, TextStyle>; setting: Setting; thumbnail?: string;
}

export const FORMAT = "scwd";
export const VERSION = 1;
export const APP_NAME = "ScenarioWriterWin β7";
export const APP_VERSION = "β7";   // 表示用。インストーラの内部番号（数字のみ）は src-tauri/tauri.conf.json の version

export const CATEGORIES: [number, string][] = [
  [0, "---"], [1, "演劇"], [2, "ミュージカル"], [3, "高校演劇"], [4, "大衆演劇"], [5, "映画"],
  [6, "テレビドラマ"], [7, "テレビ番組"], [8, "ラジオドラマ"], [9, "ラジオ番組"], [10, "その他"],
];

/** 既定のスタイル（Mac 版の ScenarioStore.defaultStyles と同じ「きつね」の設定） */
export function defaultStyles(): Style[] {
  const d: [number, number, string, number, string, number, string, number, number, number][] = [
    [1, 100, "セリフ", 14, "#000000", 0, "", 1, 0, 0],
    [2, 200, "ト書", 14, "#006400", 3, "", 0, 1, 1],
    [3, 300, "歌詞", 14, "#ff4500", 4, "Song", 0, 2, 2],
    [4, 400, "ナレーション", 14, "#000000", 0, "NA", 1, 1, 1],
    [5, 500, "モノローグ", 14, "#000000", 0, "M", 1, 1, 1],
    [6, 600, "テロップ", 14, "#ff4500", 4, "T", 0, 1, 1],
    [7, 700, "演技指示", 14, "#8b0000", 4, "", 0, 2, 2],
    [8, 800, "音響指示", 14, "#8b0000", 4, "SE", 0, 2, 2],
    [9, 900, "照明指示", 14, "#8b0000", 4, "L", 0, 2, 2],
    [10, 1000, "フェードイン", 14, "#000000", 4, "(F.I)", 0, 1, 1],
    [11, 1100, "フェードアウト", 14, "#000000", 4, "(F.O)", 0, 1, 1],
    [12, 1200, "カットイン", 14, "#000000", 4, "(C.I)", 0, 1, 1],
    [13, 1300, "カットアウト", 14, "#000000", 4, "(C.O)", 0, 1, 1],
  ];
  return d.map(([id, order, name, size, color, indent, abbr, mode, marginBefore, marginAfter]) =>
    ({ id, order, name, size, color, indent, abbr, mode, marginBefore, marginAfter }));
}

export function defaultTextStyles(): Record<string, TextStyle> {
  return {
    synopsis: { size: 14, color: "#000000", indent: 0, marginBefore: 0, marginAfter: 0 },
    scene: { size: 14, color: "#006400", indent: 0, marginBefore: 0, marginAfter: 0 },
    character: { size: 14, color: "#000000", indent: 0, marginBefore: 0, marginAfter: 0 },
  };
}

export function now(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

/** 新しい作品 */
export function emptyFile(title = "無題", scenes = 1, characters = 2): ScwdFile {
  const f: ScwdFile = {
    format: FORMAT, version: VERSION, app: APP_NAME,
    scenario: { title, subtitle: "", writer: "", memo: "", date: now(), category: 1 },
    synopsis: "", characters: [], scenes: [],
    styles: defaultStyles(), textStyles: defaultTextStyles(),
    setting: { characterLength: 8, bodyLength: 32, kagikakko: true },
  };
  for (let i = 1; i <= scenes; i++) f.scenes.push({ name: `　${i}場`, description: "", valid: true, minutes: 0, seconds: 0, lines: [] });
  for (let i = 1; i <= characters; i++) f.characters.push({ id: i, name: `登場人物${i}`, chara: "" });
  return f;
}

/** ファイルの文字列 → 作品。知らないキーは無視、無いキーは既定値 */
export function parse(text: string): ScwdFile {
  let raw: any;
  try { raw = JSON.parse(text.replace(/^﻿/, "")); } catch { throw new Error("ScenarioWriter の作品ファイル（JSON）ではありません"); }
  if (!raw || typeof raw !== "object" || raw.format !== FORMAT) throw new Error("ScenarioWriter の作品ファイルではありません（format が違います）");
  if (typeof raw.version === "number" && raw.version > VERSION) throw new Error(`この作品ファイルは新しい形式（版 ${raw.version}）です。アプリを更新してください`);
  const str = (v: any, d = "") => (typeof v === "string" ? v : d);
  const num = (v: any, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);
  const bool = (v: any, d: boolean) => (typeof v === "boolean" ? v : d);
  const sc = raw.scenario ?? {};
  const f: ScwdFile = {
    format: FORMAT, version: VERSION, app: str(raw.app),
    scenario: { title: str(sc.title), subtitle: str(sc.subtitle), writer: str(sc.writer), memo: str(sc.memo), date: str(sc.date), category: num(sc.category) },
    synopsis: str(raw.synopsis),
    characters: Array.isArray(raw.characters) ? raw.characters.map((c: any) => ({ id: num(c?.id), name: str(c?.name), chara: str(c?.chara) })) : [],
    scenes: Array.isArray(raw.scenes) ? raw.scenes.map((s: any) => ({
      name: str(s?.name), description: str(s?.description), valid: bool(s?.valid, true), minutes: num(s?.minutes), seconds: num(s?.seconds),
      lines: Array.isArray(s?.lines) ? s.lines.map((l: any) => {
        const line: Line = { type: num(l?.type, 1), text: str(l?.text) };
        if (typeof l?.character === "number") line.character = l.character;
        return line;
      }) : [],
    })) : [],
    styles: Array.isArray(raw.styles) && raw.styles.length ? raw.styles.map((s: any) => ({
      id: num(s?.id), order: num(s?.order), name: str(s?.name), size: num(s?.size, 12), color: str(s?.color, "#000000"), indent: num(s?.indent),
      abbr: str(s?.abbr), mode: num(s?.mode), marginBefore: num(s?.marginBefore), marginAfter: num(s?.marginAfter),
    })) : defaultStyles(),
    textStyles: defaultTextStyles(),
    setting: { characterLength: num(raw.setting?.characterLength, 8), bodyLength: num(raw.setting?.bodyLength, 32), kagikakko: bool(raw.setting?.kagikakko, true) },
  };
  if (raw.textStyles && typeof raw.textStyles === "object") {
    for (const k of Object.keys(f.textStyles)) {
      const t = raw.textStyles[k];
      if (t && typeof t === "object") {
        f.textStyles[k] = { size: num(t.size, 14), color: str(t.color, "#000000"), indent: num(t.indent), marginBefore: num(t.marginBefore), marginAfter: num(t.marginAfter) };
      }
    }
  }
  if (typeof raw.thumbnail === "string" && raw.thumbnail) f.thumbnail = raw.thumbnail;
  // 登場人物の id が無い・重複しているファイルは振り直す
  const seen = new Set<number>();
  let next = 1;
  for (const c of f.characters) {
    if (!c.id || seen.has(c.id)) { while (seen.has(next)) next++; c.id = next; }
    seen.add(c.id);
  }
  return f;
}

/** 作品 → ファイルの文字列（キーは ABC 順、2 段インデント。Mac 版と同じ並び） */
export function serialize(f: ScwdFile): string {
  const sorted = (v: any): any => {
    if (Array.isArray(v)) return v.map(sorted);
    if (v && typeof v === "object") {
      const o: any = {};
      for (const k of Object.keys(v).sort()) if (v[k] !== undefined) o[k] = sorted(v[k]);
      return o;
    }
    return v;
  };
  const out: ScwdFile = { ...f, format: FORMAT, version: VERSION, app: APP_NAME };
  return JSON.stringify(sorted(out), null, 2) + "\n";
}

// ---- 書式（Mac 版 ScriptFormatter / TextFormat と同じ規則）

export interface Resolved {
  name: string; size: number; color: string; indent: number; abbr: string; showsName: boolean; kagi: boolean; marginBefore: number; marginAfter: number;
}

function fallback(type: number): Resolved {
  const base: Resolved = { name: `種別 ${type}`, size: 12, color: "#000000", indent: 0, abbr: "", showsName: false, kagi: false, marginBefore: 0, marginAfter: 0 };
  switch (type) {
    case 1: return { ...base, name: "セリフ", showsName: true, kagi: true };
    case 2: return { ...base, name: "ト書", color: "#006400", indent: 3 };
    case 3: return { ...base, name: "歌詞", indent: 3, abbr: "歌" };
    case 4: return { ...base, name: "ナレーション", abbr: "NA", showsName: true, kagi: true };
    case 5: return { ...base, name: "モノローグ", abbr: "M", showsName: true, kagi: true };
    case 6: return { ...base, name: "テロップ", indent: 3, abbr: "T" };
    case 7: return { ...base, name: "演技指示", color: "#8b0000", indent: 3 };
    case 8: return { ...base, name: "音響指示", color: "#8b0000", indent: 3, abbr: "SE" };
    case 9: return { ...base, name: "照明指示", color: "#8b0000", indent: 3, abbr: "L" };
    default: return base;
  }
}

export function resolveStyle(f: ScwdFile, type: number): Resolved {
  const s = f.styles.find((x) => x.id === type);
  let r: Resolved;
  if (s) {
    r = { name: s.name, size: s.size > 0 ? s.size : 12, color: s.color || "#000000", indent: Math.max(s.indent, 0), abbr: s.abbr,
      showsName: s.mode === 1 || s.mode === 2, kagi: s.mode === 1 || s.mode === 3, marginBefore: Math.max(s.marginBefore, 0), marginAfter: Math.max(s.marginAfter, 0) };
  } else {
    r = fallback(type);
  }
  if (!f.setting.kagikakko) r.kagi = false;
  return r;
}

/** 見出し = 人物名 ＋ 省略文字。名前を出さないスタイルでは省略文字だけ */
export function labelFor(name: string, st: Resolved): string {
  const n = st.showsName ? name : "";
  if (!n && !st.abbr) return "";
  if (!n) return st.abbr;
  if (!st.abbr) return n;
  return n + "　" + st.abbr;
}

/** 台詞を「」で囲む。末尾の「。」は落とし、空なら囲まない */
export function kagikakko(text: string): string {
  return "「" + text.replace(/。$/, "") + "」";
}

/** 半角の英数・カナを全角に（読む画面・テキスト出力の「日本語英数」） */
export function toFullWidth(s: string, asciiSymbols = false): string {
  let out = "";
  for (const ch of s) {
    const v = ch.codePointAt(0)!;
    if ((v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5a) || (v >= 0x61 && v <= 0x7a)) out += String.fromCodePoint(v + 0xfee0);
    else if (asciiSymbols && v >= 0x21 && v <= 0x7e && v !== 0x22 && v !== 0x27 && v !== 0x5c && v !== 0x7e) out += String.fromCodePoint(v + 0xfee0);
    else if (v >= 0xff61 && v <= 0xff9f) out += ch.normalize("NFKC");
    else out += ch;
  }
  // 半角カナの濁点・半濁点は NFKC で結合されるので、結合文字が残ったら合成する
  return out.normalize("NFC");
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** 和暦（令和・平成・昭和・大正・明治）。1 年は「元年」 */
export function wareki(d: Date): string {
  const y = d.getFullYear(), m = d.getMonth() + 1, day = d.getDate();
  const ymd = y * 10000 + m * 100 + day;
  let gengo = "明治", wy = y - 1867;
  if (ymd >= 20190501) { gengo = "令和"; wy = y - 2018; }
  else if (ymd >= 19890108) { gengo = "平成"; wy = y - 1988; }
  else if (ymd >= 19261225) { gengo = "昭和"; wy = y - 1925; }
  else if (ymd >= 19120730) { gengo = "大正"; wy = y - 1911; }
  return `${gengo}${wy === 1 ? "元" : wy}年${m}月${day}日`;
}

/** 先頭から n 文字に揃える（足りなければ全角空白を前に足し、多ければ末尾 n 文字） */
export function padLeft(s: string, n: number): string {
  const chars = Array.from(s);
  if (chars.length >= n) return chars.slice(chars.length - n).join("");
  return "　".repeat(n - chars.length) + s;
}

export function xmlEscape(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}
