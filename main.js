const { app, BrowserWindow, ipcMain, screen } = require('electron');
const path = require('path');
const fs = require('fs');

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

ipcMain.handle('compare-dirs', async (_event, leftDir, rightDir) => {
  try {
    const leftMap = walkDir(leftDir);
    const rightMap = walkDir(rightDir);

    const allKeys = new Set([...leftMap.keys(), ...rightMap.keys()]);
    const entries = [];

    for (const relPath of [...allKeys].sort()) {
      const leftFull = leftMap.get(relPath);
      const rightFull = rightMap.get(relPath);

      let status;
      if (!leftFull) {
        status = 'added'; // exists only in right
      } else if (!rightFull) {
        status = 'removed'; // exists only in left
      } else {
        const leftContent = fs.readFileSync(leftFull, 'utf8');
        const rightContent = fs.readFileSync(rightFull, 'utf8');
        status = leftContent === rightContent ? 'same' : 'modified';
      }

      entries.push({
        relPath,
        leftFull: leftFull || null,
        rightFull: rightFull || null,
        status,
      });
    }

    return { ok: true, entries, leftDir, rightDir };
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
