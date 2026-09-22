import Foundation

/// Word 2003 XML（単一ファイル、横書き）。Web 版 swScenarioDownloadXMLYoko.php の移植。
public enum XmlExporter {

    static func snippet(_ name: String) throws -> String {
        let url = try DocxExporter.resourceRoot.appendingPathComponent("xml/\(name).xml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func make(_ doc: ScenarioDocument, cover: DocxExporter.CoverInfo) throws -> String {
        let chars = doc.characterById
        let styles = doc.styleByType
        let wt = DocxExporter.wt
        let fill = DocxExporter.fill
        var xml = try snippet("header")
        let dateStr = cover.date.map { TextFormat.wareki($0) } ?? ""
        let writer = cover.writerName.isEmpty ? doc.scenario.writerName : cover.writerName
        xml += fill(try snippet("cover"), [
            "TITLE": wt(doc.scenario.title), "SUBTITLE": wt(doc.scenario.subtitle), "DATE": wt(dateStr), "VERSION": wt(cover.version),
            "WRITER_NAME": wt("脚本： " + writer), "WRITER_ID": wt(cover.writerId),
            "ADDRESS": wt(cover.address), "PHONE": wt(cover.phone), "EMAIL": wt(cover.email),
        ])
        xml += fill(try snippet("characterListTitle"), ["TITLE": wt(doc.scenario.title)])
        let ch = try snippet("character")
        for c in doc.characters {
            xml += fill(ch, ["CHARACTER_NAME": wt(c.name), "CHARACTER_CHARA": wt(c.chara.isEmpty ? c.name : c.chara)])
        }
        xml += fill(try snippet("synopsis"), ["TITLE": wt(doc.scenario.title), "SYNOPSIS": wt(doc.synopsis)])
        let sc = try snippet("scene")
        let ln = try snippet("line")
        for scene in doc.scenes {
            xml += fill(sc, ["SCENE_NAME": wt(scene.name), "SCENE_DESC": wt(scene.description)])
            for line in doc.lines(of: scene) {
                let f = ScriptFormatter.format(line, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko)
                xml += fill(ln, ["CHARACTER_DIV": wt(f.label), "LINE": wt(f.text)])
            }
        }
        xml += fill(try snippet("bodyEnd"), ["TITLE": wt(doc.scenario.title)])
        return xml
    }
}
