const { app, BrowserWindow, ipcMain, screen, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

// Watched file state: { left: {path, mtime} | null, right: {path, mtime} | null }
let watchedFiles = { left: null, right: null };
let dialogShowing = false;

function createWindow() {
  const { width, height } = screen.getPrimaryDisplay().workAreaSize;
  const win = new BrowserWindow({
    width: Math.round(width * 0.5),
    height: Math.round(height * 0.5),
    minWidth: 600,
    minHeight: 400,
    title: 'MacMerge',
    icon: path.join(__dirname, 'assets', 'icon.icns'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // Check for file changes when the window regains focus
  win.on('focus', async () => {
    if (dialogShowing) return;
    const changed = [];
    for (const side of ['left', 'right']) {
      const w = watchedFiles[side];
      if (!w) continue;
      try {
        const mtime = fs.statSync(w.path).mtimeMs;
        if (mtime !== w.mtime) changed.push(w.path);
      } catch { /* file deleted or inaccessible */ }
    }
    if (changed.length === 0) return;

    dialogShowing = true;
    const { response } = await dialog.showMessageBox(win, {
      type: 'question',
      buttons: ['再読み込み', 'キャンセル'],
      defaultId: 0,
      cancelId: 1,
      title: 'ファイルが更新されました',
      message: 'ファイルが更新されました',
      detail: changed.map(p => path.basename(p)).join('\n') + '\n\n再度読み込みますか？',
    });
    dialogShowing = false;

    // Update stored mtimes regardless of choice (avoid repeated prompts)
    for (const side of ['left', 'right']) {
      const w = watchedFiles[side];
      if (w) { try { w.mtime = fs.statSync(w.path).mtimeMs; } catch { /* ignore */ } }
    }

    if (response === 0) {
      win.webContents.send('reload-files');
    }
  });
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// ---- IPC handlers ----

// Register the two files currently being compared for change detection
ipcMain.handle('watch-files', (_event, leftPath, rightPath) => {
  watchedFiles.left  = leftPath  ? { path: leftPath,  mtime: statSafe(leftPath)?.mtimeMs  ?? 0 } : null;
  watchedFiles.right = rightPath ? { path: rightPath, mtime: statSafe(rightPath)?.mtimeMs ?? 0 } : null;
  return { ok: true };
});

function statSafe(p) {
  try { return fs.statSync(p); } catch { return null; }
}

function walkDir(dir) {
  const result = new Map();
  function walk(current, rel) {
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const relPath = path.join(rel, entry.name);
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath, relPath);
      } else {
        result.set(relPath, fullPath);
      }
    }
  }
  walk(dir, '');
  return result;
}

ipcMain.handle('compare-files', async (_event, leftPath, rightPath) => {
  try {
    const leftContent = fs.readFileSync(leftPath, 'utf8');
    const rightContent = fs.readFileSync(rightPath, 'utf8');
    return { ok: true, leftContent, rightContent, leftPath, rightPath };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle('compare-dirs', async (event, leftDir, rightDir) => {
  try {
    const leftMap = walkDir(leftDir);
    const rightMap = walkDir(rightDir);

    const allKeys = [...new Set([...leftMap.keys(), ...rightMap.keys()])].sort();
    let count = 0;

    for (const relPath of allKeys) {
      const leftFull = leftMap.get(relPath);
      const rightFull = rightMap.get(relPath);

      let status;
      if (!leftFull) {
        status = 'added';
      } else if (!rightFull) {
        status = 'removed';
      } else {
        const leftContent = fs.readFileSync(leftFull, 'utf8');
        const rightContent = fs.readFileSync(rightFull, 'utf8');
        status = leftContent === rightContent ? 'same' : 'modified';
      }

      event.sender.send('dir-entry', { relPath, leftFull: leftFull || null, rightFull: rightFull || null, status });

      // Yield every 20 entries to keep UI responsive
      if (++count % 20 === 0) {
        await new Promise(resolve => setImmediate(resolve));
      }
    }

    event.sender.send('dir-compare-done', { leftDir, rightDir });
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle('read-file-pair', async (_event, leftFull, rightFull) => {
  try {
    const leftContent = leftFull ? fs.readFileSync(leftFull, 'utf8') : '';
    const rightContent = rightFull ? fs.readFileSync(rightFull, 'utf8') : '';
    return { ok: true, leftContent, rightContent };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});
