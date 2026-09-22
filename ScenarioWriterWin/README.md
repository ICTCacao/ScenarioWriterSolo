# ScenarioWriterWin — ScenarioWriterSolo の Windows 版

Mac 版 ScenarioWriterSolo と同じ作品ファイル `.scwd`（JSON。[形式の説明](../docs/scwd-format.md)）を読み書きする、
Windows 向けの脚本エディタです。画面は HTML / CSS / TypeScript、土台は [Tauri 2](https://tauri.app)
（Windows では OS 付属の WebView2、Mac では WebKit、Linux では WebKitGTK で動きます）。

縦書きの編集が目玉なので、本文欄は `writing-mode: vertical-rl` の textarea です。日本語 IME もそのまま使えます。

## できること（0.5）

- 作品ファイルを開く・保存・別名で保存・新規（Ctrl+O / Ctrl+S / Ctrl+Shift+S / Ctrl+N）。`.scwd` をダブルクリックしても開く
- 台本の編集: 縦書き / 横書き（Ctrl+Alt+T）、種別と登場人物の選択、行の追加（Ctrl+Enter、Shift で上に）・移動（Ctrl+Alt+矢印）・削除、Tab / Shift+Tab で前後の行へ
- 本文は 設定の「本文の文字数」（−字下げ）で折り返し、文字の大きさと色はスタイルに従う（Mac 版と同じ）
- 場面（追加・名前・有効・時間・説明）、登場人物（追加・並べ替え・人物設定）、シノプシス、シナリオ情報と書式
- 読む（Mac 版と同じ HTML。縦書き / 横書き、文字サイズ、場面ジャンプ）
- 最近使った作品

まだ無いもの: テキスト / Word / HTML ファイルの書き出し、スタイルの編集画面（作品ファイルに入っているスタイルをそのまま使う）、
行の操作の「元に戻す」（本文の文字入力は textarea の Ctrl+Z が効く）、Web 版データの取り込み。

## 開発

必要なもの: Node 20 以上、Rust（`rustup`）。Windows では Visual Studio の C++ ビルドツールと WebView2（Windows 10/11 は標準）。

```bash
npm install
npm run tauri dev                      # 開発モードで起動（Mac でも動く）
npm run tauri dev -- -- 作品.scwd      # 起動時に作品を開く
npm run tauri build                    # 配布物（Windows: NSIS の setup.exe と msi / Mac: .app と .dmg）
```

Windows 用のインストーラは Windows 機が無くても作れます。GitHub に push して Actions（`.github/workflows/build.yml`）を
動かすと、Artifacts に `setup.exe` と `.msi` ができます。

ふつうのブラウザで画面だけ確かめたいときは、`public/sample.scwd` を置いて `npm run dev` → `http://localhost:1420/?sample=1`（保存はできません）。

## 構成

```
src/
├── main.ts     # 画面（ファイル操作・台本の編集・場面・登場人物・シノプシス・情報・読む）
├── model.ts    # 作品ファイルの型・読み書き・書式の規則（Mac 版の ScenarioFile / ScriptFormatter と同じ）
├── reader.ts   # 「読む」画面の HTML（Mac 版 HtmlExporter と同じ）
└── styles.css
src-tauri/
├── src/lib.rs  # ファイルの読み書きと、起動時に渡された作品ファイル
├── tauri.conf.json
└── capabilities/default.json
```
