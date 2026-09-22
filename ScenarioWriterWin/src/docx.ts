// Word（.docx）台本。Mac 版 DocxExporter と同じ: deerstudio 配布の脚本テンプレートを同梱し、
// document.xml / core.xml / header・footer を差し替えて ZIP に固める
import { zipSync, strToU8 } from "fflate";
import templates from "./docx-templates.json";
import * as M from "./model";

export type Template = "A4TP" | "A4YP" | "A4TL";
export const TEMPLATE_LABELS: [Template, string][] = [["A4TP", "A4縦 縦書き"], ["A4YP", "A4縦 横書き"], ["A4TL", "A4横 縦書き"]];

export interface CoverInfo {
  writerName: string; writerId: string; version: string; date: Date | null; address: string; phone: string; email: string;
}

type TemplateData = { template: Record<string, string>; snippets: Record<string, string> };
const T = templates as unknown as Record<string, TemplateData>;

/** 本文用: XML エスケープし、改行を <w:br/> にする（<w:t> の中に置く前提） */
function wt(s: string): string {
  return s.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n").map(M.xmlEscape).join('</w:t><w:br/><w:t xml:space="preserve">');
}

function fill(snippet: string, values: Record<string, string>): string {
  let s = snippet;
  for (const [k, v] of Object.entries(values)) s = s.split(`{{${k}}}`).join(v);
  return s.split("<w:t>").join('<w:t xml:space="preserve">');
}

function buildDocumentXML(f: M.ScwdFile, tpl: TemplateData, cover: CoverInfo): string {
  const sn = (n: string) => tpl.snippets[n] ?? "";
  const chars = new Map(f.characters.map((c) => [c.id, c]));
  const nameW = Math.max(f.setting.characterLength, 2);
  // 前後の余白は、罫線などの段落書式が続くように「台詞と同じ書式の空行」で入れる（<w:p/> だと罫線が途切れる）
  const blank = fill(sn("line"), { CHARACTER_DIV: "", LINE: "" });
  let xml = sn("header");
  xml += fill(sn("cover"), {
    TITLE: wt(f.scenario.title), SUBTITLE: wt(f.scenario.subtitle), DATE: wt(cover.date ? M.wareki(cover.date) : ""), VERSION: wt(cover.version),
    WRITER_NAME: wt(cover.writerName || f.scenario.writer), WRITER_ID: wt(cover.writerId),
    ADDRESS: wt(cover.address), PHONE: wt(cover.phone), EMAIL: wt(cover.email),
  });
  xml += fill(sn("characterListTitle"), { TITLE: wt(f.scenario.title) });
  for (const c of f.characters) xml += fill(sn("characterList"), { CHARACTER_NAME: wt(c.name), CHARACTER_CHARA: wt(c.chara || c.name) });
  xml += fill(sn("synopsis"), { TITLE: wt(f.scenario.title), SYNOPSIS: wt(M.toFullWidth(f.synopsis)) });
  for (const scene of f.scenes) {
    if (!scene.valid) continue;
    xml += fill(sn("scene"), { SCENE_NAME: wt(scene.name), SCENE_DESC: wt(scene.description) });
    for (const line of scene.lines) {
      const st = M.resolveStyle(f, line.type);
      const cname = line.character !== undefined ? chars.get(line.character)?.name ?? "" : "";
      const name = M.toFullWidth(st.showsName ? cname : "");
      const abbr = M.toFullWidth(st.abbr);
      const label = !name && !abbr ? "" : !name ? abbr : !abbr ? name : name + "　" + abbr;
      const text = st.kagi ? M.kagikakko(line.text) : line.text;
      const body = M.toFullWidth(text, true);
      xml += blank.repeat(st.marginBefore);
      if (st.indent > 0) {
        // ト書など: 見出しを右寄せ（末尾 N 文字）
        xml += fill(sn("togaki"), { CHARACTER_DIV: wt(M.padLeft(label, nameW)), LINE: wt(body) });
      } else {
        xml += fill(sn("line"), { CHARACTER_DIV: wt(label), LINE: wt(body) });
      }
      xml += blank.repeat(st.marginAfter);
    }
  }
  xml += sn("bodyEnd");
  return xml;
}

/** .docx のバイト列を作る */
export function makeDocx(f: M.ScwdFile, template: Template, cover: CoverInfo, userName: string): Uint8Array {
  const tpl = T[template];
  if (!tpl) throw new Error("テンプレートがありません: " + template);
  const titleX = M.xmlEscape(f.scenario.title);
  const userX = M.xmlEscape(userName || "ScenarioWriterSolo");
  const document = buildDocumentXML(f, tpl, cover);
  const names = Object.keys(tpl.template).sort((a, b) => {
    if (a === "[Content_Types].xml") return -1;
    if (b === "[Content_Types].xml") return 1;
    return a < b ? -1 : a > b ? 1 : 0;
  });
  const files: Record<string, Uint8Array> = {};
  for (const rel of names) {
    let content = tpl.template[rel];
    if (rel === "word/document.xml") content = document;
    else if (rel === "docProps/core.xml" || rel === "word/header1.xml" || rel === "word/footer2.xml") {
      content = content.split("{{USER_NAME}}").join(userX).split("{{TITLE}}").join(titleX);
    }
    files[rel] = strToU8(content);
  }
  return zipSync(files, { level: 6 });
}
