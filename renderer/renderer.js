/* renderer.js – MacMerge renderer process */

// ---- State ----
const state = {
  left: null,   // { path, type: 'file'|'dir' }
  right: null,
};

// ---- DOM refs ----
const dropScreen   = document.getElementById('drop-screen');
const resultScreen = document.getElementById('result-screen');
const dropLeft     = document.getElementById('drop-left');
const dropRight    = document.getElementById('drop-right');
const pathLeft     = document.getElementById('path-left');
const pathRight    = document.getElementById('path-right');
const compareBtn   = document.getElementById('compare-btn');
const dropError    = document.getElementById('drop-error');
const backBtn      = document.getElementById('back-btn');
const resultTitle  = document.getElementById('result-title');
const resultSummary= document.getElementById('result-summary');

const dirView      = document.getElementById('dir-view');
const dirTree      = document.getElementById('dir-tree');
const dirDiffPanel = document.getElementById('dir-diff-panel');
const diffPanelFilename = document.getElementById('diff-panel-filename');
const diffPanelContent  = document.getElementById('diff-panel-content');
const closeDiffPanel    = document.getElementById('close-diff-panel');

const fileView     = document.getElementById('file-view');
const fileDiffContent = document.getElementById('file-diff-content');

// ---- Drag & drop handling ----

// Extract type (file/dir) from a DataTransferItem
function getItemType(item) {
  const fsEntry = item && item.webkitGetAsEntry ? item.webkitGetAsEntry() : null;
  return fsEntry && fsEntry.isDirectory ? 'dir' : 'file';
}

// Shared drop handler – called from zone handlers and the screen-level handler
function handleDrop(e, defaultSide) {
  const files = e.dataTransfer.files;
  const items = e.dataTransfer.items;
  if (!files || files.length === 0) return;

  if (files.length >= 2) {
    // 2ファイル同時ドロップ → 両スロット設定 & 即比較
    const p0 = window.api.getPathForFile(files[0]) || files[0].path;
    const p1 = window.api.getPathForFile(files[1]) || files[1].path;
    if (!p0 || !p1) { showError('パスを取得できませんでした'); return; }

    const type0 = getItemType(items[0]);
    const type1 = getItemType(items[1]);
    if (type0 !== type1) { showError('ファイルとフォルダを混在させることはできません'); return; }

    setSlot('left',  { path: p0, type: type0 });
    setSlot('right', { path: p1, type: type1 });
    doCompare();
    return;
  }

  // 1ファイル → 指定スロットへ
  const filePath = window.api.getPathForFile(files[0]) || files[0].path;
  if (!filePath) { showError('パスを取得できませんでした'); return; }
  const type = getItemType(items[0]);
  setSlot(defaultSide, { path: filePath, type });
}

function setupDropZone(zone, side) {
  zone.addEventListener('dragover', (e) => {
    e.preventDefault();
    e.stopPropagation();
    // 2アイテムなら両ゾーンをハイライト
    if (e.dataTransfer.items.length >= 2) {
      dropLeft.classList.add('drag-over');
      dropRight.classList.add('drag-over');
    } else {
      zone.classList.add('drag-over');
    }
  });

  zone.addEventListener('dragleave', (e) => {
    e.preventDefault();
    e.stopPropagation();
    dropLeft.classList.remove('drag-over');
    dropRight.classList.remove('drag-over');
  });

  zone.addEventListener('drop', (e) => {
    e.preventDefault();
    e.stopPropagation();
    dropLeft.classList.remove('drag-over');
    dropRight.classList.remove('drag-over');
    handleDrop(e, side);
  });
}

// 画面全体（ゾーン外）へのドロップも受け付ける
dropScreen.addEventListener('dragover', (e) => {
  e.preventDefault();
  if (e.dataTransfer.items.length >= 2) {
    dropLeft.classList.add('drag-over');
    dropRight.classList.add('drag-over');
  }
});
dropScreen.addEventListener('dragleave', () => {
  dropLeft.classList.remove('drag-over');
  dropRight.classList.remove('drag-over');
});
dropScreen.addEventListener('drop', (e) => {
  e.preventDefault();
  dropLeft.classList.remove('drag-over');
  dropRight.classList.remove('drag-over');
  handleDrop(e, state.left ? 'right' : 'left');
});

function setSlot(side, info) {
  state[side] = info;
  const pathEl = side === 'left' ? pathLeft : pathRight;
  const zone   = side === 'left' ? dropLeft  : dropRight;

  const icon = info.type === 'dir' ? '📁' : '📄';
  pathEl.textContent = `${icon} ${info.path}`;
  zone.classList.add('has-file');
  dropError.textContent = '';
  updateCompareBtn();
}

function updateCompareBtn() {
  if (!state.left || !state.right) { compareBtn.disabled = true; return; }
  if (state.left.type !== state.right.type) {
    showError('ファイルとフォルダを混在させることはできません');
    compareBtn.disabled = true;
    return;
  }
  dropError.textContent = '';
  compareBtn.disabled = false;
}

function showError(msg) { dropError.textContent = msg; }

setupDropZone(dropLeft,  'left');
setupDropZone(dropRight, 'right');

// ---- Compare (shared logic) ----
async function doCompare() {
  if (!state.left || !state.right) return;
  dropError.textContent = '';
  compareBtn.disabled = true;
  compareBtn.textContent = '比較中…';

  try {
    if (state.left.type === 'file') {
      await runFileCompare(state.left.path, state.right.path);
    } else {
      await runDirCompare(state.left.path, state.right.path);
    }
    showResultScreen();
  } catch (err) {
    showError('エラー: ' + err.message);
    compareBtn.disabled = false;
  } finally {
    compareBtn.textContent = '比較する';
  }
}

compareBtn.addEventListener('click', doCompare);

// ---- Back button ----
backBtn.addEventListener('click', () => {
  dropScreen.classList.remove('hidden');
  resultScreen.classList.add('hidden');
  dirView.classList.add('hidden');
  fileView.classList.add('hidden');
  dirDiffPanel.classList.add('hidden');
  lineDetail.classList.add('hidden');
  compareBtn.disabled = false;
});

// ---- Line detail panel ----
const lineDetail    = document.getElementById('line-detail');
const ldpBefore     = document.getElementById('ldp-before');
const ldpAfter      = document.getElementById('ldp-after');
const closeLdp      = document.getElementById('close-ldp');
const rowDataStore  = [];   // { leftText, rightText } per change row

closeLdp.addEventListener('click', () => lineDetail.classList.add('hidden'));

// Sync horizontal scroll between Before / After
let isSyncing = false;
function syncScroll(source, target) {
  source.addEventListener('scroll', () => {
    if (isSyncing) return;
    isSyncing = true;
    target.scrollLeft = source.scrollLeft;
    isSyncing = false;
  });
}
syncScroll(ldpBefore, ldpAfter);
syncScroll(ldpAfter,  ldpBefore);

function showLineDetail(leftText, rightText) {
  const charDiff = Diff.diffChars(leftText, rightText);
  let beforeHtml = '', afterHtml = '';
  for (const c of charDiff) {
    if (c.removed) {
      beforeHtml += `<mark class="diff-del">${escHtml(c.value)}</mark>`;
    } else if (c.added) {
      afterHtml  += `<mark class="diff-ins">${escHtml(c.value)}</mark>`;
    } else {
      const esc = escHtml(c.value);
      beforeHtml += esc;
      afterHtml  += esc;
    }
  }
  ldpBefore.innerHTML = beforeHtml;
  ldpAfter.innerHTML  = afterHtml;
  lineDetail.classList.remove('hidden');
}

// Delegate double-click on any diff container
function attachDblClickHandler(container) {
  container.addEventListener('dblclick', (e) => {
    const tr = e.target.closest('tr[data-row]');
    if (!tr) return;
    const idx = parseInt(tr.dataset.row, 10);
    const data = rowDataStore[idx];
    if (data) showLineDetail(data.leftText, data.rightText);
  });
}

// ---- Custom diff renderer ----

function escHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function splitLines(str) {
  const lines = str.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/**
 * Build an array of row objects from two file contents.
 * Each row: { type: 'same'|'change'|'removed'|'added',
 *             leftNum, rightNum, leftHtml, rightHtml }
 * 'change'  = line exists on both sides but differs (charDiff applied)
 * 'removed' = line only on left
 * 'added'   = line only on right
 * 'same'    = identical line on both sides
 */
function buildRows(leftContent, rightContent) {
  const lineDiff = Diff.diffLines(leftContent, rightContent);
  const rows = [];
  let leftNum = 1, rightNum = 1;
  let i = 0;

  while (i < lineDiff.length) {
    const part = lineDiff[i];

    if (!part.added && !part.removed) {
      for (const line of splitLines(part.value)) {
        rows.push({ type: 'same', leftNum: leftNum++, rightNum: rightNum++,
                    leftHtml: escHtml(line), rightHtml: escHtml(line) });
      }
      i++;
      continue;
    }

    // Collect consecutive removed / added blocks
    const leftLines  = part.removed ? splitLines(part.value) : [];
    let   rightLines = [];

    if (part.removed && i + 1 < lineDiff.length && lineDiff[i + 1].added) {
      rightLines = splitLines(lineDiff[i + 1].value);
      i += 2;
    } else if (part.added) {
      rightLines = splitLines(part.value);
      i++;
    } else {
      i++;
    }

    const pairCount = Math.min(leftLines.length, rightLines.length);

    // Paired lines → character-level diff
    for (let j = 0; j < pairCount; j++) {
      const charDiff = Diff.diffChars(leftLines[j], rightLines[j]);
      let leftHtml = '', rightHtml = '';
      for (const c of charDiff) {
        if (c.removed) {
          leftHtml  += `<mark class="diff-del">${escHtml(c.value)}</mark>`;
        } else if (c.added) {
          rightHtml += `<mark class="diff-ins">${escHtml(c.value)}</mark>`;
        } else {
          const esc = escHtml(c.value);
          leftHtml  += esc;
          rightHtml += esc;
        }
      }
      const rowIdx = rowDataStore.length;
      rowDataStore.push({ leftText: leftLines[j], rightText: rightLines[j] });
      rows.push({ type: 'change', leftNum: leftNum++, rightNum: rightNum++, leftHtml, rightHtml, rowIdx });
    }

    // Unpaired removed lines
    for (let j = pairCount; j < leftLines.length; j++) {
      rows.push({ type: 'removed', leftNum: leftNum++, rightNum: null,
                  leftHtml: escHtml(leftLines[j]), rightHtml: '' });
    }

    // Unpaired added lines
    for (let j = pairCount; j < rightLines.length; j++) {
      rows.push({ type: 'added', leftNum: null, rightNum: rightNum++,
                  leftHtml: '', rightHtml: escHtml(rightLines[j]) });
    }
  }

  return rows;
}

function renderSideBySideDiff(leftLabel, rightLabel, leftContent, rightContent) {
  const rows = buildRows(leftContent, rightContent);

  const changedCount = rows.filter(r => r.type !== 'same').length;
  if (changedCount === 0) {
    return '<div class="diff-no-change">差分なし（ファイルは同一です）</div>';
  }

  let html = `
    <div class="custom-diff">
      <div class="diff-file-header">
        <span class="diff-file-label diff-file-left">${escHtml(leftLabel)}</span>
        <span class="diff-file-sep">↔</span>
        <span class="diff-file-label diff-file-right">${escHtml(rightLabel)}</span>
      </div>
      <div class="diff-table-wrap"><table class="diff-table"><tbody>
  `;

  for (const row of rows) {
    if (row.type === 'same') {
      html += `<tr class="diff-row-same">
        <td class="diff-ln">${row.leftNum}</td>
        <td class="diff-code">${row.leftHtml}</td>
        <td class="diff-ln">${row.rightNum}</td>
        <td class="diff-code">${row.rightHtml}</td>
      </tr>`;
    } else if (row.type === 'change') {
      html += `<tr class="diff-row-change" data-row="${row.rowIdx}" title="ダブルクリックで詳細表示">
        <td class="diff-ln diff-ln-del">${row.leftNum}</td>
        <td class="diff-code diff-code-del">${row.leftHtml}</td>
        <td class="diff-ln diff-ln-ins">${row.rightNum}</td>
        <td class="diff-code diff-code-ins">${row.rightHtml}</td>
      </tr>`;
    } else if (row.type === 'removed') {
      html += `<tr class="diff-row-change">
        <td class="diff-ln diff-ln-del">${row.leftNum}</td>
        <td class="diff-code diff-code-del">${row.leftHtml}</td>
        <td class="diff-ln"></td>
        <td class="diff-code diff-code-empty"></td>
      </tr>`;
    } else { // added
      html += `<tr class="diff-row-change">
        <td class="diff-ln"></td>
        <td class="diff-code diff-code-empty"></td>
        <td class="diff-ln diff-ln-ins">${row.rightNum}</td>
        <td class="diff-code diff-code-ins">${row.rightHtml}</td>
      </tr>`;
    }
  }

  html += '</tbody></table></div></div>';
  return html;
}

// ---- File comparison ----
async function runFileCompare(leftPath, rightPath) {
  const result = await window.api.compareFiles(leftPath, rightPath);
  if (!result.ok) throw new Error(result.error);

  rowDataStore.length = 0;
  fileDiffContent.innerHTML = renderSideBySideDiff(
    leftPath, rightPath,
    result.leftContent, result.rightContent
  );
  attachDblClickHandler(fileDiffContent);

  resultTitle.textContent = `${leftPath}  ↔  ${rightPath}`;

  const rows = buildRows(result.leftContent, result.rightContent);
  const added   = rows.filter(r => r.type === 'added'   || r.type === 'change').length;
  const removed = rows.filter(r => r.type === 'removed' || r.type === 'change').length;
  resultSummary.textContent = `+${added} / -${removed}`;

  fileView.classList.remove('hidden');
  dirView.classList.add('hidden');
}

// ---- Directory comparison ----
let dirEntries = [];

async function runDirCompare(leftDir, rightDir) {
  const result = await window.api.compareDirs(leftDir, rightDir);
  if (!result.ok) throw new Error(result.error);

  dirEntries = result.entries;

  const counts = { same: 0, modified: 0, added: 0, removed: 0 };
  for (const e of dirEntries) counts[e.status]++;

  resultTitle.textContent = `${leftDir}  ↔  ${rightDir}`;
  resultSummary.textContent =
    `変更: ${counts.modified}  追加: ${counts.added}  削除: ${counts.removed}  同一: ${counts.same}`;

  renderDirTree(dirEntries);
  fileView.classList.add('hidden');
  dirView.classList.remove('hidden');
  dirDiffPanel.classList.add('hidden');
}

function renderDirTree(entries) {
  const statusLabel = { same: '同一', modified: '変更', added: '追加', removed: '削除' };

  dirTree.innerHTML = `
    <div class="tree-legend">
      <span class="legend-item"><span class="legend-dot" style="background:#fab387"></span>変更</span>
      <span class="legend-item"><span class="legend-dot" style="background:#a6e3a1"></span>追加</span>
      <span class="legend-item"><span class="legend-dot" style="background:#f38ba8"></span>削除</span>
      <span class="legend-item"><span class="legend-dot" style="background:#45475a"></span>同一</span>
    </div>
  `;

  for (const entry of entries) {
    const item = document.createElement('div');
    item.className = `tree-item status-${entry.status}`;
    item.dataset.relPath = entry.relPath;

    item.innerHTML = `
      <span class="tree-status"></span>
      <span class="tree-name" title="${entry.relPath}">${entry.relPath}</span>
      <span class="tree-badge">${statusLabel[entry.status]}</span>
    `;

    if (entry.status !== 'same') {
      item.addEventListener('click', () => openDirFileDiff(entry, item));
    }

    dirTree.appendChild(item);
  }
}

async function openDirFileDiff(entry, itemEl) {
  document.querySelectorAll('.tree-item.selected').forEach(el => el.classList.remove('selected'));
  itemEl.classList.add('selected');

  diffPanelFilename.textContent = entry.relPath;
  diffPanelContent.innerHTML = '<div class="empty-panel">読み込み中…</div>';
  dirDiffPanel.classList.remove('hidden');

  const result = await window.api.readFilePair(entry.leftFull, entry.rightFull);
  if (!result.ok) {
    diffPanelContent.innerHTML = `<div class="empty-panel" style="color:#f38ba8">エラー: ${result.error}</div>`;
    return;
  }

  const leftLabel  = entry.leftFull  || '(存在しない)';
  const rightLabel = entry.rightFull || '(存在しない)';

  rowDataStore.length = 0;
  diffPanelContent.innerHTML = renderSideBySideDiff(
    leftLabel, rightLabel,
    result.leftContent, result.rightContent
  );
  attachDblClickHandler(diffPanelContent);
}

closeDiffPanel.addEventListener('click', () => {
  dirDiffPanel.classList.add('hidden');
  document.querySelectorAll('.tree-item.selected').forEach(el => el.classList.remove('selected'));
});

// ---- Show result screen ----
function showResultScreen() {
  dropScreen.classList.add('hidden');
  resultScreen.classList.remove('hidden');
}
