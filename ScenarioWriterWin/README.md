# ScenarioWriterWin — ScenarioWriterSolo の Windows 版

Mac 版 ScenarioWriterSolo と同じ作品ファイル `.scwd`（JSON。[形式の説明](../docs/scwd-format.md)）を読み書きする、
Windows 向けの脚本エディタです。画面は HTML / CSS / TypeScript、土台は [Tauri 2](https://tauri.app)
（Windows では OS 付属の WebView2、Mac では WebKit、Linux では WebKitGTK で動きます）。

縦書きの編集が目玉なので、本文欄は `writing-mode: vertical-rl` の textarea です。日本語 IME もそのまま使えます。

## できること（β8）

- 作品ファイルを開く・保存・別名で保存・新規（Ctrl+O / Ctrl+S / Ctrl+Shift+S / Ctrl+N）。`.scwd` をダブルクリックしても開く
- 台本の編集: 縦書き / 横書き（Ctrl+Alt+T）、種別と登場人物の選択、行の追加（Ctrl+Enter、Shift で上に）・移動（Ctrl+Alt+矢印）・削除、Tab / Shift+Tab で前後の行へ
- 本文は 設定の「本文の文字数」（−字下げ）で折り返し、文字の大きさと色はスタイルに従う（Mac 版と同じ）
- 場面（追加・名前・有効・時間・説明）、登場人物（追加・並べ替え・人物設定）、シノプシス、シナリオ情報と書式。縦書きのときは場面・登場人物・シノプシスも縦書き
- Windows 標準のメニューバー（ファイル / 編集 / 表示 / 設定 / ヘルプ）。ショートカットはメニュー側で受ける
- スタイル（設定 › スタイル…、Ctrl+7。左の一覧には出さない）: 行の種別ごとの名前・並び順・サイズ・色・字下げ・省略文字・表示の仕方・前後の余白を表の中で直接編集。追加・削除・既定に戻す・サイズ一括設定。固定スタイル（シノプシス・場面説明・登場人物）も同じ表で（名前と削除は不可）。作品ファイルに保存され、次の新規作品にも引き継がれる
- 読む（Mac 版と同じ HTML。縦書き / 横書き、文字サイズ、場面ジャンプ）
- Word（.docx）の台本の書き出し（Ctrl+E）。Mac 版と同じ deerstudio の脚本テンプレート（A4縦 縦書き / A4縦 横書き / A4横 縦書き）。テンプレートは `scripts/pack-docx-templates.py` で Mac 版の資源から `src/docx-templates.json` に詰め直す
- 最近使った作品

まだ無いもの: テキスト / HTML ファイルの書き出し、行の操作の「元に戻す」（本文の文字入力は textarea の Ctrl+Z が効く）、Web 版データの取り込み。

## 見本の作品

配布 zip の `sample.scwd`（リポジトリでは `../samples/sample.scwd`）は架空の短い作品「夕暮れの谷」で、種別を一通り使っています。最初に開いて試すのに使ってください。

## 開発

必要なもの: Node 20 以上、Rust（`rustup`）。Windows では Visual Studio の C++ ビルドツールと WebView2（Windows 10/11 は標準）。

```bash
npm install
npm run tauri dev                      # 開発モードで起動（Mac でも動く）
npm run tauri dev -- -- 作品.scwd      # 起動時に作品を開く
npm run tauri build                    # 配布物（Windows: NSIS の setup.exe と msi / Mac: .app と .dmg）
```

Windows 用のインストーラは Windows 機が無くても作れます。

- **この Mac で作る**（Tauri の実験的なクロスビルド。`brew install nsis llvm`、`rustup target add x86_64-pc-windows-msvc`、`cargo install cargo-xwin` のあと）:
  ```bash
  PATH="/opt/homebrew/opt/llvm/bin:$PATH" npm run tauri build -- --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis
  # → src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/ScenarioWriterWin_0.8.0_x64-setup.exe（dist では ScenarioWriterWin-β8-setup.exe に改名。内部番号は数字しか使えないので 0.8.0）
  #   （生の exe は src-tauri/target/x86_64-pc-windows-msvc/release/scenariowriterwin.exe。WebView2 があれば単体で動く）
  ```
  署名はしないので、Windows で最初に開くとき SmartScreen の「詳細情報 → 実行」が要ります。
- **GitHub Actions**: リポジトリ直下の `.github/workflows/build.yml` を動かすと、Artifacts に `setup.exe` と `.msi`（と Linux の deb / AppImage）ができます。

ふつうのブラウザで画面だけ確かめたいときは、`public/sample.scwd` を置いて `npm run dev` → `http://localhost:1420/?sample=1`（保存はできません）。

## 構成

```
src/
├── main.ts     # 画面（ファイル操作・台本の編集・場面・登場人物・シノプシス・情報・読む）
├── model.ts    # 作品ファイルの型・読み書き・書式の規則（Mac 版の ScenarioFile / ScriptFormatter と同じ）
├── reader.ts   # 「読む」画面の HTML（Mac 版 HtmlExporter と同じ）
├── docx.ts     # Word の台本（Mac 版 DocxExporter と同じ。テンプレートは docx-templates.json）
└── styles.css
src-tauri/
├── src/lib.rs  # ファイルの読み書きと、起動時に渡された作品ファイル
├── tauri.conf.json
└── capabilities/default.json
```
