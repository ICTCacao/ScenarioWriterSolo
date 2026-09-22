# 作品ファイル `.scwd` の形式（版 1）

ScenarioWriterSolo（Mac 版）と Windows 版で共通の作品ファイル。1 ファイル 1 作品、中身は UTF-8 の JSON。
Mac 版の実装は `Packages/ScenarioWriterCore/Sources/ScenarioWriterCore/ScenarioFile.swift`。

- 拡張子: `.scwd`
- 文字コード: UTF-8（BOM なし。読む側は BOM があっても受け付ける）
- 改行を含む文字列（本文・説明・あらすじ・メモ）は `"\n"` で改行
- 書く側はキーを ABC 順、2 段インデントで書く（人が読んで差分を取れるように）
- 読む側は知らないキーを無視し、無いキーは既定値にする（版を上げても古いアプリで壊れないように）

## 全体

```json
{
  "app": "ScenarioWriterSolo β5",
  "format": "scwd",
  "version": 1,
  "scenario": { … },
  "synopsis": "あらすじ。\n二段落目。",
  "characters": [ … ],
  "scenes": [ … ],
  "styles": [ … ],
  "textStyles": { … },
  "setting": { … },
  "thumbnail": "iVBORw0KGgo…"
}
```

| キー | 型 | 意味 |
|---|---|---|
| `format` | 文字列 | 必ず `"scwd"`。違えば作品ファイルではない |
| `version` | 整数 | 形式の版。いまは `1`。読む側は自分より大きい版を拒む |
| `app` | 文字列 | 書いたアプリと版（参考情報） |
| `scenario` | オブジェクト | 作品情報（下記） |
| `synopsis` | 文字列 | あらすじ |
| `characters` | 配列 | 登場人物。並び順＝配列の順 |
| `scenes` | 配列 | 場面。並び順＝配列の順。台詞は場面の中 |
| `styles` | 配列 | 行の種別ごとの見た目（下記） |
| `textStyles` | オブジェクト | 固定スタイル（`synopsis` / `scene` / `character`） |
| `setting` | オブジェクト | 書式設定 |
| `thumbnail` | 文字列 | 作品画像（PNG の base64）。無ければ省略 |

## `scenario`

| キー | 型 | 意味 |
|---|---|---|
| `title` | 文字列 | 題名 |
| `subtitle` | 文字列 | 副題 |
| `writer` | 文字列 | 作者名 |
| `memo` | 文字列 | メモ・住所など（Word の表紙に出る） |
| `date` | 文字列 | 更新日時 `"yyyy-MM-dd HH:mm:ss"`（ローカル時刻） |
| `category` | 整数 | 分類。0=--- 1=演劇 2=ミュージカル 3=高校演劇 4=大衆演劇 5=映画 6=テレビドラマ 7=テレビ番組 8=ラジオドラマ 9=ラジオ番組 10=その他 |

## `characters[]`

| キー | 型 | 意味 |
|---|---|---|
| `id` | 整数 | このファイルの中だけで使う番号。`scenes[].lines[].character` が指す。重複しないこと |
| `name` | 文字列 | 登場人物名 |
| `chara` | 文字列 | 人物設定（年齢・性格など） |

## `scenes[]`

| キー | 型 | 意味 |
|---|---|---|
| `name` | 文字列 | 場面名（柱） |
| `description` | 文字列 | 場面説明（場所・時間など） |
| `valid` | 真偽 | `false` なら無効の場面（出力に含めない） |
| `minutes` / `seconds` | 整数 | 上演時間の目安 |
| `lines` | 配列 | 台詞・ト書などの行 |

### `scenes[].lines[]`

| キー | 型 | 意味 |
|---|---|---|
| `type` | 整数 | 種別番号。`styles[].id` と結びつく（既定: 1=セリフ 2=ト書 3=歌詞 4=ナレーション 5=モノローグ 6=テロップ 7=演技指示 8=音響指示 9=照明指示 10=フェードイン 11=フェードアウト 12=カットイン 13=カットアウト） |
| `character` | 整数 | 発言する登場人物の `characters[].id`。人物なしなら省略 |
| `text` | 文字列 | 本文 |

## `styles[]`（行の種別）

| キー | 型 | 意味 |
|---|---|---|
| `id` | 整数 | 種別番号 |
| `order` | 整数 | 並び順（種別メニューの順） |
| `name` | 文字列 | 表示名 |
| `size` | 整数 | フォントサイズ（12 が基準。読む画面では `size/12` 倍） |
| `color` | 文字列 | `#rrggbb` |
| `indent` | 整数 | 字下げ（文字数） |
| `abbr` | 文字列 | 省略文字（NA / M / SE …）。名前を出さない種別で、本文の前に出す |
| `mode` | 整数 | 1=名前を出す・台詞を「」で囲む 2=名前を出す 3=名前なし・「」で囲む 0=名前なし |
| `marginBefore` / `marginAfter` | 整数 | 前後に空ける行数（0〜4） |

## `textStyles`

`synopsis`（シノプシス）・`scene`（場面説明）・`character`（登場人物）の 3 つ。それぞれ:

| キー | 型 | 意味 |
|---|---|---|
| `size` | 整数 | フォントサイズ（12 が基準） |
| `color` | 文字列 | `#rrggbb` |
| `indent` | 整数 | 字下げ（文字数） |
| `marginBefore` / `marginAfter` | 整数 | 前後に空ける行数 |

## `setting`

| キー | 型 | 意味 |
|---|---|---|
| `characterLength` | 整数 | 見出し欄（登場人物名）の文字数。既定 8 |
| `bodyLength` | 整数 | 本文 1 行の文字数。既定 32。編集画面・読む画面・テキスト出力はこの文字数（−字下げ）で折り返す |
| `kagikakko` | 真偽 | 台詞を「」で囲むか |

## 例

```json
{
  "app": "ScenarioWriterSolo β5",
  "characters": [
    { "chara": "二十歳。少し内気な大学生。", "id": 1, "name": "太郎" },
    { "chara": "", "id": 2, "name": "花子" }
  ],
  "format": "scwd",
  "scenario": { "category": 1, "date": "2026-09-22 17:30:00", "memo": "", "subtitle": "", "title": "夕暮れの谷", "writer": "作者" },
  "scenes": [
    {
      "description": "夜。古い教会の礼拝堂。",
      "lines": [
        { "character": 1, "text": "こんばんは。", "type": 1 },
        { "text": "花子、振り向く。", "type": 2 },
        { "character": 2, "text": "……誰？\n太郎くん？", "type": 1 }
      ],
      "minutes": 3, "name": "一　礼拝堂", "seconds": 0, "valid": true
    }
  ],
  "setting": { "bodyLength": 32, "characterLength": 8, "kagikakko": true },
  "styles": [
    { "abbr": "", "color": "#000000", "id": 1, "indent": 0, "marginAfter": 0, "marginBefore": 0, "mode": 1, "name": "セリフ", "order": 100, "size": 14 },
    { "abbr": "", "color": "#006400", "id": 2, "indent": 3, "marginAfter": 1, "marginBefore": 1, "mode": 0, "name": "ト書", "order": 200, "size": 14 }
  ],
  "synopsis": "夕暮れの谷で、一匹の狼が問いかける。",
  "textStyles": {
    "character": { "color": "#000000", "indent": 0, "marginAfter": 0, "marginBefore": 0, "size": 14 },
    "scene": { "color": "#006400", "indent": 0, "marginAfter": 0, "marginBefore": 0, "size": 14 },
    "synopsis": { "color": "#000000", "indent": 0, "marginAfter": 0, "marginBefore": 0, "size": 14 }
  },
  "version": 1
}
```

## 旧形式との関係

- β5 より前の `.scwd` は SQLite（Web 版 ScenarioWriterCafe と同じ表）だった。Mac 版は先頭 16 バイトが `SQLite format 3` なら旧形式として開き、保存すると JSON になる。
- Web 版からの取り込み（`swdata.sqlite` → 作品ごとの `.scwd`）と Web 版用の書き出し（SQLite）は Mac 版だけの機能。
