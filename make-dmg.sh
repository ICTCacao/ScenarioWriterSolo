#!/bin/zsh
# 使い方: ./make-dmg.sh
# dist/ScenarioWriterSolo.app から、背景に矢印付きのドラッグ＆ドロップ式 dmg を dist/ScenarioWriterSolo-<version>.dmg に作る。
set -euo pipefail
cd "$(dirname "$0")"

app="ScenarioWriterSolo"
bundle="dist/$app.app"
BG_PNG="dmg/background-$app.png"
if [[ ! -f "$BG_PNG" || dmg/make-background.swift -nt "$BG_PNG" ]]; then
  swift dmg/make-background.swift "$BG_PNG" "$app"
fi
[[ -d "$bundle" ]] || { echo "見つかりません: $bundle（先にビルドして dist に置いてください）"; exit 1; }
version=$(defaults read "$PWD/$bundle/Contents/Info.plist" CFBundleShortVersionString)
volname="$app $version"
dmg="dist/$app-$version.dmg"
tmp="dist/.tmp-$app.dmg"
staging=$(mktemp -d)

# 1. 中身を用意
cp -R "$bundle" "$staging/"
ln -s /Applications "$staging/Applications"
# 見本の作品（架空の短い戯曲）も同梱する
[[ -f samples/sample.scwd ]] && cp samples/sample.scwd "$staging/sample.scwd"
mkdir "$staging/.background"
cp "$BG_PNG" "$staging/.background/background.png"

# 2. 読み書き可能な dmg を作ってマウント
rm -f "$tmp" "$dmg"
hdiutil create -volname "$volname" -srcfolder "$staging" -ov -format UDRW -quiet "$tmp"
rm -rf "$staging"
mount="/Volumes/$volname"
hdiutil detach "$mount" -quiet 2>/dev/null || true
hdiutil attach -readwrite -noverify -noautoopen -quiet "$tmp"
sleep 1

# 3. Finder でウインドウの見た目（アイコン表示・位置・背景）を設定
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volname"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "$app.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    try
      set position of item "sample.scwd" of container window to {300, 330}
    end try
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# 4. 読み取り専用に圧縮して完成
sync
hdiutil detach "$mount" -quiet
hdiutil convert "$tmp" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$dmg"
rm -f "$tmp"
echo "作成: $dmg ($(du -h "$dmg" | cut -f1))"
