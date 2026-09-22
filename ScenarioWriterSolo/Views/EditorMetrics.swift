import Foundation

/// 編集画面の本文欄の寸法。「読む」と同じく、本文は 設定 › 書式 の「本文の文字数」（−字下げ）で折り返す
enum EditorMetrics {
    /// 本文の文字数ぶんの長さ（横書きなら幅、縦書きなら高さ）。
    /// LineTextView の inset 4pt×2 と lineFragmentPadding 2pt×2、それに 2pt の余裕を足す。
    /// 全角 1 文字の送りは 1em（＋文字間隔）。半角はもっと入る（「読む」は全角に直して数える）
    static func bodyExtent(chars: Int, indent: Int, pointSize: CGFloat, kern: CGFloat) -> CGFloat {
        let n = max(chars - max(indent, 0), 4)
        return ceil(CGFloat(n) * (pointSize + max(kern, 0)) + 14)
    }
}
