const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('api', {
  compareFiles:     (left, right) => ipcRenderer.invoke('compare-files', left, right),
  compareDirs:      (left, right) => ipcRenderer.invoke('compare-dirs', left, right),
  readFilePair:     (left, right) => ipcRenderer.invoke('read-file-pair', left, right),
  getPathForFile:   (file) => webUtils.getPathForFile(file),
  onDirEntry:       (cb) => ipcRenderer.on('dir-entry', (_e, entry) => cb(entry)),
  onDirCompareDone: (cb) => ipcRenderer.on('dir-compare-done', (_e, data) => cb(data)),
  offDirEvents:     () => {
    ipcRenderer.removeAllListeners('dir-entry');
    ipcRenderer.removeAllListeners('dir-compare-done');
  },
  watchFiles:       (left, right) => ipcRenderer.invoke('watch-files', left, right),
  onReloadFiles:    (cb) => ipcRenderer.on('reload-files', () => cb()),
  offReloadFiles:   () => ipcRenderer.removeAllListeners('reload-files'),
});
