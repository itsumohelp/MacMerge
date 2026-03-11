const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('api', {
  compareFiles:   (left, right) => ipcRenderer.invoke('compare-files', left, right),
  compareDirs:    (left, right) => ipcRenderer.invoke('compare-dirs', left, right),
  readFilePair:   (left, right) => ipcRenderer.invoke('read-file-pair', left, right),
  getPathForFile: (file) => webUtils.getPathForFile(file),
});
