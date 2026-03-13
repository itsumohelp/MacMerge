use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

// ---- Watched file state ----

struct WatchedFile {
    path: String,
    mtime: u64,
}

#[derive(Default)]
struct WatchState {
    left: Option<WatchedFile>,
    right: Option<WatchedFile>,
}

fn get_mtime(path: &str) -> Option<u64> {
    fs::metadata(path)
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
}

// ---- Commands ----

fn is_binary(bytes: &[u8]) -> bool {
    bytes.contains(&0u8)
}

#[tauri::command]
fn compare_files(left: String, right: String) -> Result<serde_json::Value, String> {
    let left_bytes  = fs::read(&left).map_err(|e| e.to_string())?;
    let right_bytes = fs::read(&right).map_err(|e| e.to_string())?;

    if is_binary(&left_bytes) || is_binary(&right_bytes) {
        return Ok(serde_json::json!({
            "isBinary":     true,
            "isSame":       left_bytes == right_bytes,
            "leftContent":  "",
            "rightContent": "",
            "leftPath":     left,
            "rightPath":    right,
        }));
    }

    let left_content  = String::from_utf8_lossy(&left_bytes).into_owned();
    let right_content = String::from_utf8_lossy(&right_bytes).into_owned();
    Ok(serde_json::json!({
        "isBinary":     false,
        "leftContent":  left_content,
        "rightContent": right_content,
        "leftPath":     left,
        "rightPath":    right,
    }))
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct DirEntry {
    rel_path: String,
    left_full: Option<String>,
    right_full: Option<String>,
    status: String,
}

#[tauri::command]
async fn compare_dirs(app: AppHandle, left_dir: String, right_dir: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let left_map  = walk_dir(&left_dir);
        let right_map = walk_dir(&right_dir);

        let mut all_keys: Vec<String> = left_map
            .keys()
            .chain(right_map.keys())
            .cloned()
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();
        all_keys.sort();

        for rel_path in &all_keys {
            let left_full  = left_map.get(rel_path).cloned();
            let right_full = right_map.get(rel_path).cloned();

            let status = match (&left_full, &right_full) {
                (None, _) => "added",
                (_, None) => "removed",
                (Some(l), Some(r)) => {
                    match (fs::read_to_string(l), fs::read_to_string(r)) {
                        (Ok(lc), Ok(rc)) if lc == rc => "same",
                        _ => "modified",
                    }
                }
            };

            let entry = DirEntry {
                rel_path:   rel_path.clone(),
                left_full,
                right_full,
                status: status.to_string(),
            };
            let _ = app.emit("dir-entry", &entry);
        }

        let _ = app.emit("dir-compare-done", serde_json::json!({
            "leftDir":  left_dir,
            "rightDir": right_dir,
        }));
    })
    .await
    .map_err(|e| e.to_string())
}

fn walk_dir(dir: &str) -> HashMap<String, String> {
    let mut result = HashMap::new();
    let base = Path::new(dir);

    fn walk(current: &Path, base: &Path, result: &mut HashMap<String, String>) {
        let Ok(entries) = fs::read_dir(current) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if let Ok(rel) = path.strip_prefix(base) {
                let rel_str = rel.to_string_lossy().to_string();
                if path.is_dir() {
                    walk(&path, base, result);
                } else {
                    result.insert(rel_str, path.to_string_lossy().to_string());
                }
            }
        }
    }

    walk(base, base, &mut result);
    result
}

#[tauri::command]
fn read_file_pair(
    left_full: Option<String>,
    right_full: Option<String>,
) -> Result<serde_json::Value, String> {
    let left_bytes = match &left_full {
        Some(p) => fs::read(p).map_err(|e| e.to_string())?,
        None => Vec::new(),
    };
    let right_bytes = match &right_full {
        Some(p) => fs::read(p).map_err(|e| e.to_string())?,
        None => Vec::new(),
    };

    if is_binary(&left_bytes) || is_binary(&right_bytes) {
        return Ok(serde_json::json!({
            "isBinary":     true,
            "isSame":       left_bytes == right_bytes,
            "leftContent":  "",
            "rightContent": "",
        }));
    }

    let left_content  = String::from_utf8_lossy(&left_bytes).into_owned();
    let right_content = String::from_utf8_lossy(&right_bytes).into_owned();
    Ok(serde_json::json!({
        "isBinary":     false,
        "leftContent":  left_content,
        "rightContent": right_content,
    }))
}

#[tauri::command]
fn watch_files(
    left_path: Option<String>,
    right_path: Option<String>,
    state: tauri::State<Mutex<WatchState>>,
) {
    let mut ws = state.lock().unwrap();
    ws.left  = left_path.map( |p| WatchedFile { mtime: get_mtime(&p).unwrap_or(0), path: p });
    ws.right = right_path.map(|p| WatchedFile { mtime: get_mtime(&p).unwrap_or(0), path: p });
}

#[tauri::command]
fn get_path_type(path: String) -> &'static str {
    if Path::new(&path).is_dir() { "dir" } else { "file" }
}

// ---- App entry ----

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(Mutex::new(WatchState::default()))
        .invoke_handler(tauri::generate_handler![
            compare_files,
            compare_dirs,
            read_file_pair,
            watch_files,
            get_path_type,
        ])
        .setup(|app| {
            let app_handle = app.handle().clone();
            let dialog_showing = Arc::new(Mutex::new(false));

            if let Some(window) = app.get_webview_window("main") {
                // Open DevTools automatically in development builds
                #[cfg(debug_assertions)]
                window.open_devtools();

                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::Focused(true) = event {
                        let app   = app_handle.clone();
                        let guard = dialog_showing.clone();
                        tauri::async_runtime::spawn(async move {
                            // Skip if a dialog is already up
                            {
                                let mut showing = guard.lock().unwrap();
                                if *showing { return; }
                                *showing = true;
                            }

                            let changed = {
                                let ws = app.state::<Mutex<WatchState>>();
                                let mut ws = ws.lock().unwrap();

                                let mut changed_names = Vec::new();
                                // Check left and right separately to satisfy borrow checker
                                if let Some(ref mut side) = ws.left {
                                    if let Some(mtime) = get_mtime(&side.path) {
                                        if mtime != side.mtime {
                                            changed_names.push(
                                                Path::new(&side.path).file_name()
                                                    .map(|n| n.to_string_lossy().to_string())
                                                    .unwrap_or_default()
                                            );
                                            side.mtime = mtime;
                                        }
                                    }
                                }
                                if let Some(ref mut side) = ws.right {
                                    if let Some(mtime) = get_mtime(&side.path) {
                                        if mtime != side.mtime {
                                            changed_names.push(
                                                Path::new(&side.path).file_name()
                                                    .map(|n| n.to_string_lossy().to_string())
                                                    .unwrap_or_default()
                                            );
                                            side.mtime = mtime;
                                        }
                                    }
                                }
                                changed_names
                            };

                            if changed.is_empty() {
                                *guard.lock().unwrap() = false;
                                return;
                            }

                            // Let the frontend handle the dialog and reload decision
                            let _ = app.emit("files-changed", changed);
                            *guard.lock().unwrap() = false;
                        });
                    }
                });
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
