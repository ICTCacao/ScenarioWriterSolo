import Foundation

/// 台本出力で使う日本語テキスト処理（Web 版 include/swFunc.php の移植）。
public enum TextFormat {

    // MARK: 全角化（mb_convert_kana の K V R N / A に相当）

    /// 半角カタカナ → 全角（濁点を結合）、半角英字・数字 → 全角。`ascii` が true なら記号（!〜~）も全角にする。
    public static func toFullWidth(_ s: String, asciiSymbols: Bool = false) -> String {
        var out = ""
        var kanaRun = ""
        func flushKana() {
            if !kanaRun.isEmpty {
                out += kanaRun.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? kanaRun
                kanaRun = ""
            }
        }
        for ch in s.unicodeScalars {
            let v = ch.value
            if (0xFF61...0xFF9F).contains(v) {
                kanaRun.unicodeScalars.append(ch)
                continue
            }
            flushKana()
            if (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
                out.unicodeScalars.append(Unicode.Scalar(v + 0xFEE0)!)
            } else if asciiSymbols, (0x21...0x7E).contains(v), v != 0x22, v != 0x27, v != 0x5C, v != 0x7E {
                out.unicodeScalars.append(Unicode.Scalar(v + 0xFEE0)!)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
        flushKana()
        return out
    }

    /// 末尾が `suffix` ならそれを落とす（台詞の末尾の「。」）
    public static func removeLast(_ s: String, _ suffix: Character) -> String {
        if let last = s.last, last == suffix { return String(s.dropLast()) }
        return s
    }

    /// 「」で囲む。末尾の「。」は落とす（Web 版の台詞表示と同じ）
    public static func kagikakko(_ s: String) -> String {
        "「" + removeLast(s, "。") + "」"
    }

    /// 全角空白を n 個
    public static func spaces(_ n: Int) -> String { String(repeating: "　", count: max(n, 0)) }

    /// 先頭から n 文字（足りなければ全角空白で埋める）
    public static func padRight(_ s: String, to n: Int) -> String {
        let chars = Array(s)
        if chars.count >= n { return String(chars.prefix(n)) }
        return s + spaces(n - chars.count)
    }

    /// 末尾の n 文字（足りなければ左を全角空白で埋める）
    public static func padLeft(_ s: String, to n: Int) -> String {
        let chars = Array(s)
        if chars.count >= n { return String(chars.suffix(n)) }
        return spaces(n - chars.count) + s
    }

    // MARK: 禁則処理付きの折り返し（swFunc_JpHyphenation）

    static let lineEndForbidden: Set<Character> = Set(Array("｛〔〈《「『【〘〖〝｟—…‥〴〵"))
    static let lineStartForbidden: Set<Character> = Set(Array("、〕〉》」』】〙〗〟｠ゝゞ々ーァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇷ゚ㇺㇻㇼㇽㇾㇿ々〻〜～‼⁇⁈⁉・。"))

    /// 改行で分けたうえで、1 行 `width` 文字で折り返す。行頭禁則はぶら下げ、行末禁則は前で折る。
    public static func wrap(_ text: String, width: Int) -> [String] {
        let w = max(width, 2)
        var out: [String] = []
        for para in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = Array(para)
            if rest.count <= w { out.append(String(rest)); continue }
            while !rest.isEmpty {
                if rest.count <= w { out.append(String(rest)); break }
                // 次行の先頭になる文字が行頭禁則ならぶら下げる（1 文字だけ余るときは丸ごと）
                if rest.count > w, lineStartForbidden.contains(rest[w]) {
                    if rest.count == w + 1 { out.append(String(rest)); break }
                    out.append(String(rest[0...w]))
                    rest = Array(rest[(w + 1)...])
                    continue
                }
                // 行末の文字が行末禁則なら 1 文字手前で折る
                if lineEndForbidden.contains(rest[w - 1]) {
                    out.append(String(rest[0..<(w - 1)]))
                    rest = Array(rest[(w - 1)...])
                    continue
                }
                out.append(String(rest[0..<w]))
                rest = Array(rest[w...])
            }
        }
        return out
    }

    // MARK: 和暦（swFunc_SWHenkan。令和を追加）

    public static func wareki(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        let ymd = y * 10000 + m * 100 + d
        let (gengo, wYear): (String, Int)
        if ymd >= 20190501 { (gengo, wYear) = ("令和", y - 2018) }
        else if ymd >= 19890108 { (gengo, wYear) = ("平成", y - 1988) }
        else if ymd >= 19261225 { (gengo, wYear) = ("昭和", y - 1925) }
        else if ymd >= 19120730 { (gengo, wYear) = ("大正", y - 1911) }
        else { (gengo, wYear) = ("明治", y - 1867) }
        let ys = wYear == 1 ? "元" : String(wYear)
        return "\(gengo)\(ys)年\(m)月\(d)日"
    }

    // MARK: XML / HTML エスケープ

    public static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    public static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// ファイル名に使えない文字を置き換える
    public static func safeFileName(_ s: String, fallback: String = "scenario") -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let t = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
}
