#!/bin/zsh
# バージョンを上げる。1.0.0 から正式版で、0.0.1 ずつ（例: 1.0.0 → 1.0.1）。Mac 版と Windows 版は同じ番号。
# 配布するビルドの前に実行する。引数で指定すればその値にする（例: ./bump-version.sh 1.1.0）。
# 「β5」「β7」などは古い版を指す歴史の記述なので変えない
set -euo pipefail
cd "$(dirname "$0")"
cur=$(sed -n 's/.*CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml | head -1)
if [[ $# -ge 1 ]]; then
  new=$1
else
  parts=(${(s:.:)cur})
  new="${parts[1]}.${parts[2]}.$(( parts[3] + 1 ))"
fi
esc=${cur//./\\.}
# Mac 版
sed -i '' "s/\"$esc\"/\"$new\"/g" project.yml
sed -i '' "s|<string>$esc</string>|<string>$new</string>|g" ScenarioWriterSolo/Resources/Info.plist
# Windows 版（数字の内部番号と、画面の表示）
sed -i '' -E "s/\"version\": \"$esc\"/\"version\": \"$new\"/" ScenarioWriterWin/package.json ScenarioWriterWin/src-tauri/tauri.conf.json
sed -i '' "s/$esc/$new/g" ScenarioWriterWin/src-tauri/tauri.conf.json ScenarioWriterWin/index.html ScenarioWriterWin/src/main.ts ScenarioWriterWin/src/model.ts
# マニュアル・README（版の表記と配布物の名前。日付は今月）
month="$(date +%Y) 年 $(( $(date +%m) )) 月"
for f in docs/MANUAL.md docs/MANUAL.html ScenarioWriterWin/docs/MANUAL.md ScenarioWriterWin/docs/MANUAL.html; do
  sed -i '' -E "s/^(<p>)?$esc　[0-9]+ 年 [0-9]+ 月/\1$new　$month/" "$f"
  sed -i '' "s/-$esc/-$new/g" "$f"
done
sed -i '' "s/$esc/$new/g" README.md ScenarioWriterWin/README.md
echo "$cur → $new（Mac・Windows）"
