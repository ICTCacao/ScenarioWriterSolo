; Tauri の NSIS インストーラに足す処理。.scwd 書類のアイコンを、exe のアイコンではなく書類用の scwd.ico にする
!macro NSIS_HOOK_POSTINSTALL
  ReadRegStr $0 SHCTX "Software\Classes\.scwd" ""
  StrCmp $0 "" +2
  WriteRegStr SHCTX "Software\Classes\$0\DefaultIcon" "" "$INSTDIR\icons\scwd.ico"
  ; エクスプローラのアイコンのキャッシュを更新（SHCNE_ASSOCCHANGED）
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
!macroend
