// ScenarioWriterSolo Windows 版の Rust 側。ファイルの読み書きだけを受け持つ（画面は src/ の TypeScript）。
use std::fs;

/// 作品ファイル（UTF-8 のテキスト）を読む。β5 より前の Mac 版が作った SQLite のファイルは分かる言葉で断る
#[tauri::command]
fn read_text_file(path: String) -> Result<String, String> {
    let bytes = fs::read(&path).map_err(|e| format!("{}: {}", path, e))?;
    if bytes.starts_with(b"SQLite format 3") {
        return Err("このファイルは旧形式（SQLite）の作品ファイルです。Mac 版 ScenarioWriterSolo（β5 以降）で開いて保存すると新しい形式（JSON）になり、Windows 版でも開けます。".to_string());
    }
    let text = String::from_utf8(bytes).map_err(|_| "ScenarioWriter の作品ファイル（UTF-8 の JSON）ではありません".to_string())?;
    Ok(text.trim_start_matches('\u{feff}').to_string())
}

/// 作品ファイルを書く。いったん隣に書いてから置き換えるので、途中で失敗しても元のファイルは壊れない
#[tauri::command]
fn write_text_file(path: String, text: String) -> Result<(), String> {
    let tmp = format!("{}.tmp", path);
    fs::write(&tmp, text.as_bytes()).map_err(|e| format!("{}: {}", tmp, e))?;
    fs::rename(&tmp, &path).map_err(|e| format!("{}: {}", path, e))
}

/// 起動時に渡された作品ファイル（Windows でダブルクリックしたとき・コマンドライン）
#[tauri::command]
fn startup_file() -> Option<String> {
    std::env::args().skip(1).find(|a| a.to_lowercase().ends_with(".scwd") && std::path::Path::new(a).is_file())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![read_text_file, write_text_file, startup_file])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
