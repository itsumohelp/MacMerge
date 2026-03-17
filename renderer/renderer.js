/* renderer.js – MacMerge (Tauri) */

// ---- Tauri API references (set after DOMContentLoaded) ----
let _invoke, _listen, _ask, _webviewWindow;

// ---- Line ending icon ----
function leIcon(ending) {
  if (!ending) return '';
  if (ending === 'CRLF') return '<span class="le-icon le-crlf">⏎</span>';
  if (ending === 'CR')   return '<span class="le-icon le-cr">↩</span>';
  return '<span class="le-icon le-lf">↵</span>';
}

// ---- Virtual Scroller ----
const ROW_HEIGHT    = 22;   // px per row (fixed height)
const SCROLL_BUFFER = 30;   // extra rows rendered above/below viewport

class VirtualScroller {
  constructor(container, rows) {
    this.rows      = rows;
    this.container = container;

    this.hSplit          = document.createElement('div');
    this.hSplit.className = 'diff-h-split';
    this.hSplit.style.minHeight = `${rows.length * ROW_HEIGHT}px`;

    this.leftWrap           = document.createElement('div');
    this.rightWrap          = document.createElement('div');
    this.leftWrap.className  = 'diff-left-wrap';
    this.rightWrap.className = 'diff-right-wrap';

    this.tableL = document.createElement('table');
    this.tableR = document.createElement('table');
    this.tableL.className = this.tableR.className = 'diff-table';
    this.tableL.style.cssText = this.tableR.style.cssText =
      'position:absolute;top:0;left:0;min-width:100%;';
    this.tbodyL = document.createElement('tbody');
    this.tbodyR = document.createElement('tbody');
    this.tableL.appendChild(this.tbodyL);
    this.tableR.appendChild(this.tbodyR);

    this.leftWrap.appendChild(this.tableL);
    this.rightWrap.appendChild(this.tableR);
    this.hSplit.appendChild(this.leftWrap);
    this.hSplit.appendChild(this.rightWrap);
    container.appendChild(this.hSplit);

    this._start = -1;
    this._end   = -1;
    container.addEventListener('scroll', () => this._update(), { passive: true });
    this._update();
  }

  _update() {
    const scrollTop = this.container.scrollTop;
    const viewH     = this.container.clientHeight;
    const start = Math.max(0, Math.floor(scrollTop / ROW_HEIGHT) - SCROLL_BUFFER);
    const end   = Math.min(this.rows.length, Math.ceil((scrollTop + viewH) / ROW_HEIGHT) + SCROLL_BUFFER);

    if (start === this._start && end === this._end) return;
    this._start = start;
    this._end   = end;

    const topPx = `${start * ROW_HEIGHT}px`;
    this.tableL.style.top = this.tableR.style.top = topPx;

    const fragL = document.createDocumentFragment();
    const fragR = document.createDocumentFragment();
    for (let i = start; i < end; i++) {
      const [trL, trR] = this._makeRow(this.rows[i]);
      fragL.appendChild(trL);
      fragR.appendChild(trR);
    }
    this.tbodyL.replaceChildren(fragL);
    this.tbodyR.replaceChildren(fragR);
  }

  _makeRow(row) {
    const trL = document.createElement('tr');
    const trR = document.createElement('tr');
    trL.style.height = trR.style.height = ROW_HEIGHT + 'px';

    if (row.type === 'same') {
      trL.className = trR.className = 'diff-row-same';
      trL.innerHTML = `<td class="diff-ln">${row.leftNum}</td><td class="diff-code">${row.leftHtml}${leIcon(row.leftEnding)}</td>`;
      trR.innerHTML = `<td class="diff-ln">${row.rightNum}</td><td class="diff-code">${row.rightHtml}${leIcon(row.rightEnding)}</td>`;
    } else if (row.type === 'change') {
      trL.className = trR.className = 'diff-row-change';
      trL.dataset.row = trR.dataset.row = row.rowIdx;
      trL.title = trR.title = 'ダブルクリックで詳細表示';
      trL.innerHTML = `<td class="diff-ln diff-ln-del">${row.leftNum}</td><td class="diff-code diff-code-del">${row.leftHtml}${leIcon(row.leftEnding)}</td>`;
      trR.innerHTML = `<td class="diff-ln diff-ln-ins">${row.rightNum}</td><td class="diff-code diff-code-ins">${row.rightHtml}${leIcon(row.rightEnding)}</td>`;
    } else if (row.type === 'removed') {
      trL.className = trR.className = 'diff-row-change';
      trL.innerHTML = `<td class="diff-ln diff-ln-del">${row.leftNum}</td><td class="diff-code diff-code-del">${row.leftHtml}${leIcon(row.leftEnding)}</td>`;
      trR.innerHTML = `<td class="diff-ln diff-ln-filler"></td><td class="diff-code diff-code-filler"></td>`;
    } else { // added
      trL.className = trR.className = 'diff-row-change';
      trL.innerHTML = `<td class="diff-ln diff-ln-filler"></td><td class="diff-code diff-code-filler"></td>`;
      trR.innerHTML = `<td class="diff-ln diff-ln-ins">${row.rightNum}</td><td class="diff-code diff-code-ins">${row.rightHtml}${leIcon(row.rightEnding)}</td>`;
    }
    return [trL, trR];
  }
}

// ---- State ----
const state = {
  left:  null,  // { path, type: 'file'|'dir' }
  right: null,
};

// ---- DOM refs ----
const dropScreen      = document.getElementById('drop-screen');
const resultScreen    = document.getElementById('result-screen');
const textInputScreen = document.getElementById('text-input-screen');
const dropLeft        = document.getElementById('drop-left');
const dropRight       = document.getElementById('drop-right');
const pathLeft        = document.getElementById('path-left');
const pathRight       = document.getElementById('path-right');
const compareBtn      = document.getElementById('compare-btn');
const textInputBtn    = document.getElementById('text-input-btn');
const textBackBtn     = document.getElementById('text-back-btn');
const textCompareBtn  = document.getElementById('text-compare-btn');
const themeToggle     = document.getElementById('theme-toggle');
const themeLabel      = document.getElementById('theme-label');
const textLeft        = document.getElementById('text-left');
const textRight       = document.getElementById('text-right');
const dropError       = document.getElementById('drop-error');
const backBtn         = document.getElementById('back-btn');
const resultTitle     = document.getElementById('result-title');
const resultSummary   = document.getElementById('result-summary');

const dirView           = document.getElementById('dir-view');
const dirTree           = document.getElementById('dir-tree');
const dirDiffPanel      = document.getElementById('dir-diff-panel');
const diffPanelFilename = document.getElementById('diff-panel-filename');
const diffPanelContent  = document.getElementById('diff-panel-content');
const closeDiffPanel    = document.getElementById('close-diff-panel');

const fileView        = document.getElementById('file-view');
const fileDiffContent = document.getElementById('file-diff-content');
const fileInfoBar     = document.getElementById('file-info-bar');

const promptToggleBtn = document.getElementById('prompt-toggle-btn');
const copyPromptBtn   = document.getElementById('copy-prompt-btn');
const promptPanel     = document.getElementById('prompt-panel');
const promptTextarea  = document.getElementById('prompt-textarea');

const lineDetail  = document.getElementById('line-detail');
const ldpBefore   = document.getElementById('ldp-before');
const ldpAfter    = document.getElementById('ldp-after');
const closeLdp    = document.getElementById('close-ldp');
const ldpInfoBar  = document.getElementById('ldp-info-bar');
const rowDataStore = [];

// ---- Current comparison enc/LE (for LDP) ----
let _cmpEncL = '', _cmpEncR = '', _cmpLeL = '', _cmpLeR = '';

// ---- Current comparison content (for prompt copy) ----
let _currentLeftContent  = '';
let _currentRightContent = '';

// ---- Theme ----
const THEME_KEY = 'macmerge-theme';

function applyTheme(theme) {
  const isLight = theme === 'light';
  document.body.classList.toggle('light-mode', isLight);
  themeToggle.checked = isLight;
  themeLabel.textContent = isLight ? '☀️' : '🌙';
}

function initTheme() {
  const savedTheme = localStorage.getItem(THEME_KEY);
  applyTheme(savedTheme === 'light' ? 'light' : 'dark');
}

themeToggle.addEventListener('change', () => {
  const nextTheme = themeToggle.checked ? 'light' : 'dark';
  applyTheme(nextTheme);
  localStorage.setItem(THEME_KEY, nextTheme);
});

// ---- Prompt panel ----
const PROMPT_KEY = 'macmerge-prompt';

promptTextarea.value = localStorage.getItem(PROMPT_KEY) || '';

promptToggleBtn.addEventListener('click', () => {
  const isHidden = promptPanel.classList.toggle('hidden');
  promptToggleBtn.classList.toggle('active', !isHidden);
  if (!isHidden) promptTextarea.focus();
});

promptTextarea.addEventListener('input', () => {
  localStorage.setItem(PROMPT_KEY, promptTextarea.value);
});

copyPromptBtn.addEventListener('click', () => {
  const prompt = promptTextarea.value.trim();
  const left   = _currentLeftContent;
  const right  = _currentRightContent;

  let text = '';
  if (prompt) text += prompt + '\n\n';
  text += `before: ${left}\nafter: ${right}`;

  navigator.clipboard.writeText(text).then(() => {
    copyPromptBtn.classList.add('copied');
    copyPromptBtn.textContent = '✓';
    setTimeout(() => {
      copyPromptBtn.classList.remove('copied');
      copyPromptBtn.textContent = '📋';
    }, 1200);
  });
});

// ---- Line detail panel ----

closeLdp.addEventListener('click', () => lineDetail.classList.add('hidden'));

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

function showLineDetail(leftText, rightText, forceWholeDiff = false) {
  const buildCharDiffHtml = (left, right) => {
    const charDiff = Diff.diffChars(left, right);
    let leftHtml = '';
    let rightHtml = '';
    for (const c of charDiff) {
      if (c.removed) {
        leftHtml += `<mark class="diff-del">${escHtml(c.value)}</mark>`;
      } else if (c.added) {
        rightHtml += `<mark class="diff-ins">${escHtml(c.value)}</mark>`;
      } else {
        const esc = escHtml(c.value);
        leftHtml += esc;
        rightHtml += esc;
      }
    }
    return { leftHtml, rightHtml };
  };

  const splitJsonKeyValueLine = (line) => {
    const m = line.match(/^(\s*"(?:[^"\\]|\\.)*"\s*:\s*)(.*?)(\s*,\s*)?$/);
    if (!m) return null;
    return { prefix: m[1], value: m[2], suffix: m[3] || '' };
  };

  const splitQuotedValueLine = (line) => {
    const idxDouble = line.indexOf('"');
    const idxSingle = line.indexOf("'");
    let first = -1;
    if (idxDouble >= 0 && idxSingle >= 0) first = Math.min(idxDouble, idxSingle);
    else first = Math.max(idxDouble, idxSingle);
    if (first < 0) return null;
    const quote = line[first];
    const last = line.lastIndexOf(quote);
    if (last <= first) return null;
    return {
      prefix: line.slice(0, first + 1),
      value: line.slice(first + 1, last),
      suffix: line.slice(last)
    };
  };

  const splitBySeparator = (line, sepRegex) => {
    const m = line.match(sepRegex);
    if (!m) return null;
    return { prefix: m[1], value: m[2], suffix: m[3] || '' };
  };

  const parseStructuredLine = (line) => {
    return (
      // JSON: "key": value,
      splitJsonKeyValueLine(line) ||
      // quoted command-like: echo "value", message='value'
      splitQuotedValueLine(line) ||
      // key=value / --flag=value / export KEY=value
      splitBySeparator(line, /^(\s*(?:export\s+)?[A-Za-z_][\w.-]*\s*=\s*|(?:--?[A-Za-z][\w-]*)\s*=\s*)(.*?)(\s*[;,]?\s*)?$/) ||
      // key: value / Header: value
      splitBySeparator(line, /^(\s*[A-Za-z_][\w .-]*\s*:\s*)(.*?)(\s*[;,]?\s*)?$/)
    );
  };

  let beforeHtml = '', afterHtml = '';
  if (forceWholeDiff) {
    const leftStructured = parseStructuredLine(leftText);
    const rightStructured = parseStructuredLine(rightText);
    let structured = null;

    if (leftStructured && rightStructured) {
      structured = { left: leftStructured, right: rightStructured };
    }

    if (
      structured &&
      structured.left.prefix === structured.right.prefix &&
      structured.left.suffix === structured.right.suffix
    ) {
      const valueDiff = buildCharDiffHtml(structured.left.value, structured.right.value);
      beforeHtml =
        escHtml(structured.left.prefix) +
        valueDiff.leftHtml +
        escHtml(structured.left.suffix);
      afterHtml =
        escHtml(structured.right.prefix) +
        valueDiff.rightHtml +
        escHtml(structured.right.suffix);
    } else {
      beforeHtml = leftText ? `<mark class="diff-del">${escHtml(leftText)}</mark>` : '';
      afterHtml  = rightText ? `<mark class="diff-ins">${escHtml(rightText)}</mark>` : '';
    }
  } else {
    const fullDiff = buildCharDiffHtml(leftText, rightText);
    beforeHtml = fullDiff.leftHtml;
    afterHtml = fullDiff.rightHtml;
  }
  ldpBefore.innerHTML = beforeHtml;
  ldpAfter.innerHTML  = afterHtml;

  // Show enc/LE info bar if available
  if (_cmpEncL || _cmpEncR) {
    const encDiff = _cmpEncL !== _cmpEncR;
    const leDiff  = _cmpLeL  !== _cmpLeR;
    document.getElementById('ldp-enc-left').textContent  = _cmpEncL;
    document.getElementById('ldp-enc-right').textContent = _cmpEncR;
    document.getElementById('ldp-enc-left').className  = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');
    document.getElementById('ldp-enc-right').className = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');
    const elLeL = document.getElementById('ldp-le-left');
    const elLeR = document.getElementById('ldp-le-right');
    elLeL.textContent = _cmpLeL;
    elLeR.textContent = _cmpLeR;
    elLeL.style.color = LE_COLOR[_cmpLeL] || '#6c7086';
    elLeR.style.color = LE_COLOR[_cmpLeR] || '#6c7086';
    elLeL.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');
    elLeR.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');
    ldpInfoBar.classList.remove('hidden');
  } else {
    ldpInfoBar.classList.add('hidden');
  }

  lineDetail.classList.remove('hidden');
}

function buildAlignedLinePair(leftText, rightText) {
  const commonPrefixLen = (() => {
    const max = Math.min(leftText.length, rightText.length);
    let i = 0;
    while (i < max && leftText[i] === rightText[i]) i++;
    return i;
  })();
  const commonSuffixLen = (() => {
    const max = Math.min(leftText.length, rightText.length) - commonPrefixLen;
    let i = 0;
    while (
      i < max &&
      leftText[leftText.length - 1 - i] === rightText[rightText.length - 1 - i]
    ) i++;
    return i;
  })();
  const coreLeft = leftText.slice(commonPrefixLen, leftText.length - commonSuffixLen);
  const coreRight = rightText.slice(commonPrefixLen, rightText.length - commonSuffixLen);

  const decisionDiff = Diff.diffChars(coreLeft, coreRight);
  const unchangedLen = decisionDiff
    .filter(c => !c.added && !c.removed)
    .reduce((sum, c) => sum + c.value.length, 0);
  const baseLen = Math.min(coreLeft.length, coreRight.length);
  const similarity = baseLen === 0 ? 1 : unchangedLen / baseLen;
  const hasStableRun = decisionDiff.some(c => !c.added && !c.removed && c.value.length >= 3);
  const forceWholeDiff =
    coreLeft.length > 0 &&
    coreRight.length > 0 &&
    (similarity < 0.7 || (!hasStableRun && similarity < 0.8));

  if (forceWholeDiff) {
    return { alignedLeft: leftText, alignedRight: rightText, forceWholeDiff: true };
  }

  const charDiff = Diff.diffChars(leftText, rightText);
  let alignedLeft = '';
  let alignedRight = '';

  for (let i = 0; i < charDiff.length; i++) {
    const chunk = charDiff[i];

    // Replacement block (removed + added): do not insert blanks for the overlapped part.
    if (chunk.removed && i + 1 < charDiff.length && charDiff[i + 1].added) {
      const removed = chunk.value;
      const added = charDiff[i + 1].value;
      const sharedLen = Math.min(removed.length, added.length);

      alignedLeft += removed.slice(0, sharedLen);
      alignedRight += added.slice(0, sharedLen);

      if (removed.length > sharedLen) {
        const extra = removed.slice(sharedLen);
        alignedLeft += extra;
        alignedRight += ' '.repeat(extra.length);
      } else if (added.length > sharedLen) {
        const extra = added.slice(sharedLen);
        alignedLeft += ' '.repeat(extra.length);
        alignedRight += extra;
      }

      i++;
      continue;
    }

    if (chunk.added && i + 1 < charDiff.length && charDiff[i + 1].removed) {
      const added = chunk.value;
      const removed = charDiff[i + 1].value;
      const sharedLen = Math.min(removed.length, added.length);

      alignedLeft += removed.slice(0, sharedLen);
      alignedRight += added.slice(0, sharedLen);

      if (removed.length > sharedLen) {
        const extra = removed.slice(sharedLen);
        alignedLeft += extra;
        alignedRight += ' '.repeat(extra.length);
      } else if (added.length > sharedLen) {
        const extra = added.slice(sharedLen);
        alignedLeft += ' '.repeat(extra.length);
        alignedRight += extra;
      }

      i++;
      continue;
    }

    if (chunk.added) {
      alignedLeft += ' '.repeat(chunk.value.length);
      alignedRight += chunk.value;
    } else if (chunk.removed) {
      alignedLeft += chunk.value;
      alignedRight += ' '.repeat(chunk.value.length);
    } else {
      alignedLeft += chunk.value;
      alignedRight += chunk.value;
    }
  }

  return { alignedLeft, alignedRight, forceWholeDiff: false };
}

function attachDblClickHandler(container) {
  container.addEventListener('dblclick', (e) => {
    const tr = e.target.closest('tr[data-row]');
    if (!tr) return;
    const idx  = parseInt(tr.dataset.row, 10);
    const data = rowDataStore[idx];
    if (data) showLineDetail(data.leftText, data.rightText, !!data.forceWholeDiff);
  });
}

// ---- Custom diff renderer ----

function escHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function splitLinesWithEndings(str) {
  const result = [];
  let i = 0, lineStart = 0;
  while (i < str.length) {
    if (str[i] === '\r' && i + 1 < str.length && str[i + 1] === '\n') {
      result.push({ text: str.slice(lineStart, i), ending: 'CRLF' });
      i += 2; lineStart = i;
    } else if (str[i] === '\r') {
      result.push({ text: str.slice(lineStart, i), ending: 'CR' });
      i++; lineStart = i;
    } else if (str[i] === '\n') {
      result.push({ text: str.slice(lineStart, i), ending: 'LF' });
      i++; lineStart = i;
    } else {
      i++;
    }
  }
  if (lineStart < str.length) {
    result.push({ text: str.slice(lineStart), ending: null });
  }
  return result;
}

function buildRows(leftContent, rightContent) {
  const lineDiff = Diff.diffLines(leftContent, rightContent);
  const rows = [];
  let leftNum = 1, rightNum = 1;
  let i = 0;

  while (i < lineDiff.length) {
    const part = lineDiff[i];

    if (!part.added && !part.removed) {
      for (const { text, ending } of splitLinesWithEndings(part.value)) {
        rows.push({ type: 'same', leftNum: leftNum++, rightNum: rightNum++,
                    leftHtml: escHtml(text), rightHtml: escHtml(text),
                    leftEnding: ending, rightEnding: ending });
      }
      i++;
      continue;
    }

    const leftLines  = part.removed ? splitLinesWithEndings(part.value) : [];
    let   rightLines = [];

    if (part.removed && i + 1 < lineDiff.length && lineDiff[i + 1].added) {
      rightLines = splitLinesWithEndings(lineDiff[i + 1].value);
      i += 2;
    } else if (part.added) {
      rightLines = splitLinesWithEndings(part.value);
      i++;
    } else {
      i++;
    }

    const pairCount = Math.min(leftLines.length, rightLines.length);

    for (let j = 0; j < pairCount; j++) {
      const rowIdx = rowDataStore.length;
      const aligned = buildAlignedLinePair(leftLines[j].text, rightLines[j].text);
      rowDataStore.push({
        leftText: aligned.alignedLeft,
        rightText: aligned.alignedRight,
        forceWholeDiff: aligned.forceWholeDiff
      });
      rows.push({ type: 'change', leftNum: leftNum++, rightNum: rightNum++,
                  leftHtml: escHtml(leftLines[j].text), rightHtml: escHtml(rightLines[j].text),
                  leftEnding: leftLines[j].ending, rightEnding: rightLines[j].ending, rowIdx });
    }

    for (let j = pairCount; j < leftLines.length; j++) {
      rows.push({ type: 'removed', leftNum: leftNum++, rightNum: null,
                  leftHtml: escHtml(leftLines[j].text), rightHtml: '',
                  leftEnding: leftLines[j].ending, rightEnding: null });
    }

    for (let j = pairCount; j < rightLines.length; j++) {
      rows.push({ type: 'added', leftNum: null, rightNum: rightNum++,
                  leftHtml: '', rightHtml: escHtml(rightLines[j].text),
                  leftEnding: null, rightEnding: rightLines[j].ending });
    }
  }

  return rows;
}

function mountSideBySideDiff(container, leftLabel, rightLabel, leftContent, rightContent) {
  const rows         = buildRows(leftContent, rightContent);
  const changedCount = rows.filter(r => r.type !== 'same').length;

  const wrapper = document.createElement('div');
  wrapper.className = 'custom-diff';

  const header = document.createElement('div');
  header.className = 'diff-file-header';
  header.innerHTML = `
    <span class="diff-file-label diff-file-left">${escHtml(leftLabel)}</span>
    <span class="diff-file-sep">↔</span>
    <span class="diff-file-label diff-file-right">${escHtml(rightLabel)}</span>
  `;
  wrapper.appendChild(header);

  let tableWrap = null, vs = null;
  if (changedCount === 0) {
    const noChange = document.createElement('div');
    noChange.className = 'diff-no-change';
    noChange.textContent = '差分なし（ファイルは同一です）';
    wrapper.appendChild(noChange);
  } else {
    tableWrap = document.createElement('div');
    tableWrap.className = 'diff-table-wrap';
    wrapper.appendChild(tableWrap);
    vs = new VirtualScroller(tableWrap, rows);
    attachDblClickHandler(tableWrap);

    let hSync = false;
    vs.leftWrap.addEventListener('scroll', () => {
      if (hSync) return; hSync = true;
      vs.rightWrap.scrollLeft = vs.leftWrap.scrollLeft;
      hSync = false;
    }, { passive: true });
    vs.rightWrap.addEventListener('scroll', () => {
      if (hSync) return; hSync = true;
      vs.leftWrap.scrollLeft = vs.rightWrap.scrollLeft;
      hSync = false;
    }, { passive: true });
  }

  container.innerHTML = '';
  container.appendChild(wrapper);
  return { rows, tableWrap, vs };
}

// ---- Encoding / line-ending detection ----

function detectEncoding(content) {
  return (content.length > 0 && content.charCodeAt(0) === 0xFEFF) ? 'UTF-8 BOM' : 'UTF-8';
}

function detectLineEnding(content) {
  const hasCRLF = content.includes('\r\n');
  const stripped = content.replace(/\r\n/g, '');
  const hasCR  = stripped.includes('\r');
  const hasLF  = stripped.includes('\n');
  const n = (hasCRLF ? 1 : 0) + (hasCR ? 1 : 0) + (hasLF ? 1 : 0);
  if (n === 0)   return 'None';
  if (n > 1)     return 'Mixed';
  if (hasCRLF)   return 'CRLF';
  if (hasCR)     return 'CR';
  return 'LF';
}

const LE_COLOR = { LF: '#a6e3a1', CRLF: '#fab387', CR: '#f38ba8', Mixed: '#f9e2af', None: '#6c7086' };

function updateFileInfoBar(leftEnc, rightEnc, leftLE, rightLE) {
  // Store for LDP
  _cmpEncL = leftEnc; _cmpEncR = rightEnc;
  _cmpLeL  = leftLE;  _cmpLeR  = rightLE;

  const encDiff = leftEnc !== rightEnc;
  const leDiff  = leftLE  !== rightLE;

  const elEncL = document.getElementById('info-enc-left');
  const elEncR = document.getElementById('info-enc-right');
  const elLeL  = document.getElementById('info-le-left');
  const elLeR  = document.getElementById('info-le-right');

  elEncL.textContent = leftEnc;
  elEncR.textContent = rightEnc;
  elEncL.className = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');
  elEncR.className = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');

  elLeL.textContent = leftLE;
  elLeR.textContent = rightLE;
  elLeL.style.color = LE_COLOR[leftLE]  || '#6c7086';
  elLeR.style.color = LE_COLOR[rightLE] || '#6c7086';
  elLeL.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');
  elLeR.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');

  fileInfoBar.classList.remove('hidden');
}

// ---- Binary view ----

function mountBinaryView(container, leftLabel, rightLabel, isSame) {
  const wrapper = document.createElement('div');
  wrapper.className = 'custom-diff';

  const header = document.createElement('div');
  header.className = 'diff-file-header';
  header.innerHTML = `
    <span class="diff-file-label diff-file-left">${escHtml(leftLabel)}</span>
    <span class="diff-file-sep">↔</span>
    <span class="diff-file-label diff-file-right">${escHtml(rightLabel)}</span>
  `;
  wrapper.appendChild(header);

  const body = document.createElement('div');
  body.className = 'binary-view';
  body.innerHTML = `
    <div class="binary-icon">⬛</div>
    <div class="binary-label">バイナリファイル</div>
    <div class="binary-result ${isSame ? 'binary-same' : 'binary-diff'}">
      ${isSame ? '✓ 一致' : '✗ 不一致'}
    </div>
  `;
  wrapper.appendChild(body);

  container.innerHTML = '';
  container.appendChild(wrapper);
}

// ---- File comparison ----
let _fileTableWrap = null;
let _fileVs        = null;

async function runFileCompare(leftPath, rightPath, restoreScroll = null) {
  const result = await _invoke('compare_files', { left: leftPath, right: rightPath });

  if (result.isBinary) {
    rowDataStore.length = 0;
    _cmpEncL = _cmpEncR = _cmpLeL = _cmpLeR = '';
    _currentLeftContent = _currentRightContent = '(バイナリファイル)';
    mountBinaryView(fileDiffContent, leftPath, rightPath, result.isSame);
    resultTitle.textContent   = `${leftPath}  ↔  ${rightPath}`;
    resultSummary.textContent = result.isSame ? '一致' : '不一致';
    fileInfoBar.classList.add('hidden');
    _invoke('watch_files', { leftPath, rightPath });
    fileView.classList.remove('hidden');
    dirView.classList.add('hidden');
    return;
  }

  let leftContent  = result.leftContent;
  let rightContent = result.rightContent;

  const leftEnc = detectEncoding(leftContent);
  const rightEnc = detectEncoding(rightContent);
  const leftLE  = detectLineEnding(leftContent);
  const rightLE = detectLineEnding(rightContent);

  if (leftEnc !== rightEnc && !restoreScroll) {
    const msg = `文字コードが異なります\n左: ${leftEnc}　右: ${rightEnc}\n\n文字コードを差分として扱いますか？`;
    const treatAsDiff = _ask
      ? await _ask(msg, { title: '文字コードの確認', okLabel: '差分として扱う', cancelLabel: '無視して比較' })
      : window.confirm(msg);
    if (!treatAsDiff) {
      leftContent  = leftContent.replace(/^\uFEFF/, '');
      rightContent = rightContent.replace(/^\uFEFF/, '');
    }
  }

  rowDataStore.length = 0;
  _currentLeftContent  = leftContent;
  _currentRightContent = rightContent;

  const { rows, tableWrap, vs } = mountSideBySideDiff(
    fileDiffContent,
    leftPath, rightPath,
    leftContent, rightContent
  );

  _fileTableWrap = tableWrap;
  _fileVs        = vs;

  resultTitle.textContent = `${leftPath}  ↔  ${rightPath}`;
  const added   = rows.filter(r => r.type === 'added'   || r.type === 'change').length;
  const removed = rows.filter(r => r.type === 'removed' || r.type === 'change').length;
  resultSummary.textContent = `+${added} / -${removed}`;

  if (restoreScroll && tableWrap) {
    const maxTop = tableWrap.scrollHeight - tableWrap.clientHeight;
    tableWrap.scrollTop = Math.min(restoreScroll.scrollTop, Math.max(0, maxTop));
    if (vs) {
      requestAnimationFrame(() => {
        const maxLeft = vs.leftWrap.scrollWidth - vs.leftWrap.clientWidth;
        const left    = Math.min(restoreScroll.scrollLeft, Math.max(0, maxLeft));
        vs.leftWrap.scrollLeft  = left;
        vs.rightWrap.scrollLeft = left;
      });
    }
  }

  updateFileInfoBar(leftEnc, rightEnc, leftLE, rightLE);

  _invoke('watch_files', { leftPath, rightPath });

  fileView.classList.remove('hidden');
  dirView.classList.add('hidden');
}

// ---- Directory comparison ----
let dirEntries = [];
let _unlistenDirEntry = null;
let _unlistenDirDone  = null;

async function runDirCompare(leftDir, rightDir) {
  dirEntries = [];
  const counts = { same: 0, modified: 0, added: 0, removed: 0 };

  if (_unlistenDirEntry) { _unlistenDirEntry(); _unlistenDirEntry = null; }
  if (_unlistenDirDone)  { _unlistenDirDone();  _unlistenDirDone  = null; }

  resultTitle.textContent    = `${leftDir}  ↔  ${rightDir}`;
  resultSummary.textContent  = '比較中…';
  renderDirTree([]);
  fileView.classList.add('hidden');
  dirView.classList.remove('hidden');
  dirDiffPanel.classList.add('hidden');
  showResultScreen();

  return new Promise(async (resolve, reject) => {
    _unlistenDirEntry = await _listen('dir-entry', (event) => {
      const entry = event.payload;
      dirEntries.push(entry);
      counts[entry.status]++;
    });

    _unlistenDirDone = await _listen('dir-compare-done', () => {
      if (_unlistenDirEntry) { _unlistenDirEntry(); _unlistenDirEntry = null; }
      if (_unlistenDirDone)  { _unlistenDirDone();  _unlistenDirDone  = null; }
      resultSummary.textContent =
        `変更: ${counts.modified}  追加: ${counts.added}  削除: ${counts.removed}  同一: ${counts.same}`;
      renderDirTree(dirEntries);
      resolve();
    });

    _invoke('compare_dirs', { leftDir, rightDir }).catch((err) => {
      if (_unlistenDirEntry) { _unlistenDirEntry(); _unlistenDirEntry = null; }
      if (_unlistenDirDone)  { _unlistenDirDone();  _unlistenDirDone  = null; }
      reject(new Error(err));
    });
  });
}

function buildTree(entries) {
  const root = { isDir: true, children: new Map(), status: 'same' };

  for (const entry of entries) {
    const parts = entry.relPath.replace(/\\/g, '/').split('/');
    let node = root;
    for (let i = 0; i < parts.length - 1; i++) {
      const part = parts[i];
      if (!node.children.has(part)) {
        node.children.set(part, { name: part, isDir: true, children: new Map(), status: 'same' });
      }
      node = node.children.get(part);
    }
    const fileName = parts[parts.length - 1];
    node.children.set(fileName, { name: fileName, isDir: false, entry, status: entry.status });
  }

  const priority = { modified: 3, added: 2, removed: 1, same: 0 };
  function propagate(node) {
    if (!node.isDir) return node.status;
    let worst = 'same';
    for (const child of node.children.values()) {
      const cs = propagate(child);
      if (priority[cs] > priority[worst]) worst = cs;
    }
    node.status = worst;
    return worst;
  }
  propagate(root);
  return root;
}

function renderTreeNode(node, depth, container) {
  const statusLabel = { same: '同一', modified: '変更', added: '追加', removed: '削除' };
  const sorted = [...node.children.values()].sort((a, b) => {
    if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
    return a.name.localeCompare(b.name, 'ja');
  });

  for (const child of sorted) {
    if (child.isDir) {
      const item = document.createElement('div');
      item.className = `tree-item tree-dir status-${child.status}`;
      item.style.paddingLeft = `${8 + depth * 16}px`;
      item.innerHTML = `<span class="tree-dir-icon">▶</span><span class="tree-name" title="${escHtml(child.name)}">${escHtml(child.name)}</span>`;
      container.appendChild(item);

      const sub = document.createElement('div');
      sub.classList.add('hidden');
      container.appendChild(sub);
      renderTreeNode(child, depth + 1, sub);

      item.addEventListener('click', () => {
        const collapsed = sub.classList.toggle('hidden');
        item.querySelector('.tree-dir-icon').textContent = collapsed ? '▶' : '▼';
      });
    } else {
      const { entry } = child;
      const item = document.createElement('div');
      item.className = `tree-item status-${entry.status}`;
      item.style.paddingLeft = `${8 + depth * 16}px`;
      item.dataset.relPath = entry.relPath;
      item.innerHTML = `<span class="tree-status"></span><span class="tree-name" title="${escHtml(entry.relPath)}">${escHtml(child.name)}</span><span class="tree-badge">${statusLabel[entry.status]}</span>`;
      if (entry.status !== 'same') {
        item.addEventListener('click', () => openDirFileDiff(entry, item));
      }
      container.appendChild(item);
    }
  }
}

function renderDirTree(entries) {
  dirTree.innerHTML = `
    <div class="tree-legend">
      <span class="legend-item"><span class="legend-dot" style="background:#fab387"></span>変更</span>
      <span class="legend-item"><span class="legend-dot" style="background:#a6e3a1"></span>追加</span>
      <span class="legend-item"><span class="legend-dot" style="background:#f38ba8"></span>削除</span>
      <span class="legend-item"><span class="legend-dot" style="background:#45475a"></span>同一</span>
    </div>
  `;
  if (entries.length === 0) return;
  const tree = buildTree(entries);
  renderTreeNode(tree, 0, dirTree);
}

async function openDirFileDiff(entry, itemEl) {
  document.querySelectorAll('.tree-item.selected').forEach(el => el.classList.remove('selected'));
  itemEl.classList.add('selected');

  diffPanelFilename.textContent = entry.relPath;
  diffPanelContent.innerHTML    = '<div class="empty-panel">読み込み中…</div>';
  dirDiffPanel.classList.remove('hidden');

  const dirFileInfoBar = document.getElementById('dir-file-info-bar');
  dirFileInfoBar.classList.add('hidden');

  try {
    const result     = await _invoke('read_file_pair', {
      leftFull:  entry.leftFull  || null,
      rightFull: entry.rightFull || null,
    });
    const leftLabel  = entry.leftFull  || '(存在しない)';
    const rightLabel = entry.rightFull || '(存在しない)';
    rowDataStore.length = 0;

    if (result.isBinary) {
      _cmpEncL = _cmpEncR = _cmpLeL = _cmpLeR = '';
      _currentLeftContent = _currentRightContent = '(バイナリファイル)';
      mountBinaryView(diffPanelContent, leftLabel, rightLabel, result.isSame);
    } else {
      _currentLeftContent  = result.leftContent;
      _currentRightContent = result.rightContent;
      mountSideBySideDiff(diffPanelContent, leftLabel, rightLabel, result.leftContent, result.rightContent);

      const leftEnc  = detectEncoding(result.leftContent);
      const rightEnc = detectEncoding(result.rightContent);
      const leftLE   = detectLineEnding(result.leftContent);
      const rightLE  = detectLineEnding(result.rightContent);

      // Store for LDP
      _cmpEncL = leftEnc; _cmpEncR = rightEnc;
      _cmpLeL  = leftLE;  _cmpLeR  = rightLE;

      const encDiff = leftEnc !== rightEnc;
      const leDiff  = leftLE  !== rightLE;

      const elEncL = document.getElementById('dir-info-enc-left');
      const elEncR = document.getElementById('dir-info-enc-right');
      const elLeL  = document.getElementById('dir-info-le-left');
      const elLeR  = document.getElementById('dir-info-le-right');

      elEncL.textContent = leftEnc;
      elEncR.textContent = rightEnc;
      elEncL.className = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');
      elEncR.className = 'info-enc-badge' + (encDiff ? ' info-badge-diff' : '');

      elLeL.textContent = leftLE;
      elLeR.textContent = rightLE;
      elLeL.style.color = LE_COLOR[leftLE]  || '#6c7086';
      elLeR.style.color = LE_COLOR[rightLE] || '#6c7086';
      elLeL.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');
      elLeR.className = 'info-le-badge' + (leDiff ? ' info-badge-diff' : '');

      dirFileInfoBar.classList.remove('hidden');
    }
  } catch (err) {
    diffPanelContent.innerHTML =
      `<div class="empty-panel" style="color:#f38ba8">エラー: ${err}</div>`;
  }
}

closeDiffPanel.addEventListener('click', () => {
  dirDiffPanel.classList.add('hidden');
  document.querySelectorAll('.tree-item.selected').forEach(el => el.classList.remove('selected'));
});

// ---- Compare ----
async function doCompare() {
  if (!state.left || !state.right) return;
  dropError.textContent   = '';
  compareBtn.disabled     = true;
  compareBtn.textContent  = '比較中…';

  try {
    if (state.left.type === 'file') {
      await runFileCompare(state.left.path, state.right.path);
      showResultScreen();
    } else {
      await runDirCompare(state.left.path, state.right.path);
    }
  } catch (err) {
    showError('エラー: ' + err.message);
    compareBtn.disabled = false;
  } finally {
    compareBtn.textContent = '比較する';
  }
}

compareBtn.addEventListener('click', doCompare);

// ---- Text input mode ----
let _fromTextInput = false;

textInputBtn.addEventListener('click', () => {
  dropScreen.classList.add('hidden');
  textInputScreen.classList.remove('hidden');
  textCompareBtn.classList.remove('hidden');
  textLeft.focus();
});

textBackBtn.addEventListener('click', () => {
  textInputScreen.classList.add('hidden');
  textCompareBtn.classList.add('hidden');
  dropScreen.classList.remove('hidden');
});

function runTextCompare() {
  rowDataStore.length = 0;
  _cmpEncL = _cmpEncR = _cmpLeL = _cmpLeR = '';
  _currentLeftContent  = textLeft.value;
  _currentRightContent = textRight.value;
  const { rows } = mountSideBySideDiff(
    fileDiffContent,
    '左 (Before)', '右 (After)',
    textLeft.value, textRight.value
  );
  const added   = rows.filter(r => r.type === 'added'   || r.type === 'change').length;
  const removed = rows.filter(r => r.type === 'removed' || r.type === 'change').length;
  resultTitle.textContent   = 'テキスト比較';
  resultSummary.textContent = `+${added} / -${removed}`;
  fileView.classList.remove('hidden');
  dirView.classList.add('hidden');
  _fromTextInput = true;
  textInputScreen.classList.add('hidden');
  textCompareBtn.classList.add('hidden');
  resultScreen.classList.remove('hidden');
}

textCompareBtn.addEventListener('click', runTextCompare);

document.addEventListener('keydown', (e) => {
  if (e.key === 'F5' && !textInputScreen.classList.contains('hidden')) {
    e.preventDefault();
    runTextCompare();
  }
});

// ---- Back button ----
backBtn.addEventListener('click', () => {
  resultScreen.classList.add('hidden');
  dirView.classList.add('hidden');
  fileView.classList.add('hidden');
  dirDiffPanel.classList.add('hidden');
  lineDetail.classList.add('hidden');
  compareBtn.disabled = false;
  if (_fromTextInput) {
    _fromTextInput = false;
    textInputScreen.classList.remove('hidden');
    textCompareBtn.classList.remove('hidden');
  } else {
    dropScreen.classList.remove('hidden');
    _invoke('watch_files', { leftPath: null, rightPath: null });
  }
});

// ---- Show result screen ----
function showResultScreen() {
  dropScreen.classList.add('hidden');
  resultScreen.classList.remove('hidden');
}

function showError(msg) { dropError.textContent = msg; }

function setSlot(side, info) {
  state[side] = info;
  const pathEl = side === 'left' ? pathLeft : pathRight;
  const zone   = side === 'left' ? dropLeft  : dropRight;
  const icon   = info.type === 'dir' ? '📁' : '📄';
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
  compareBtn.disabled   = false;
}

function isOnDropScreen() {
  return !dropScreen.classList.contains('hidden');
}

// ---- Drag & Drop via Tauri ----

document.addEventListener('dragover', (e) => e.preventDefault(), false);
document.addEventListener('drop',     (e) => e.preventDefault(), false);

async function setupTauriDragDrop(webviewWindow) {
  await webviewWindow.onDragDropEvent(async (event) => {
    const { type } = event.payload;

    if (type === 'enter' || type === 'over') {
      const pos = event.payload.position;
      if (pos) {
        const dpr = window.devicePixelRatio || 1;
        const lx = pos.x / dpr;
        const ly = pos.y / dpr;
        const lRect = dropLeft.getBoundingClientRect();
        const rRect = dropRight.getBoundingClientRect();
        if (lx >= lRect.left && lx <= lRect.right && ly >= lRect.top && ly <= lRect.bottom) {
          dropLeft.classList.add('drag-over');
          dropRight.classList.remove('drag-over');
        } else if (lx >= rRect.left && lx <= rRect.right && ly >= rRect.top && ly <= rRect.bottom) {
          dropLeft.classList.remove('drag-over');
          dropRight.classList.add('drag-over');
        } else {
          dropLeft.classList.add('drag-over');
          dropRight.classList.add('drag-over');
        }
      } else {
        dropLeft.classList.add('drag-over');
        dropRight.classList.add('drag-over');
      }
      return;
    }

    if (type === 'leave' || type === 'cancel') {
      dropLeft.classList.remove('drag-over');
      dropRight.classList.remove('drag-over');
      return;
    }

    if (type !== 'drop') return;

    dropLeft.classList.remove('drag-over');
    dropRight.classList.remove('drag-over');

    const paths = event.payload.paths;
    if (!paths || paths.length === 0) return;

    // Drop outside drop-screen → open new window
    if (!isOnDropScreen()) {
      if (paths.length >= 2) {
        _invoke('open_window', { left: paths[0], right: paths[1] }).catch(() => {});
      } else {
        _invoke('open_window', { left: paths[0], right: null }).catch(() => {});
      }
      return;
    }

    if (paths.length >= 2) {
      try {
        const [type0, type1] = await Promise.all([
          _invoke('get_path_type', { path: paths[0] }),
          _invoke('get_path_type', { path: paths[1] }),
        ]);
        if (type0 !== type1) { showError('ファイルとフォルダを混在させることはできません'); return; }
        setSlot('left',  { path: paths[0], type: type0 });
        setSlot('right', { path: paths[1], type: type1 });
        doCompare();
      } catch (err) {
        showError('エラー: ' + err);
      }
      return;
    }

    // Single item – choose target side by drop position
    let targetSide = state.left ? 'right' : 'left';
    const pos = event.payload.position;
    if (pos) {
      const dpr = window.devicePixelRatio || 1;
      const lx = pos.x / dpr;
      const ly = pos.y / dpr;
      const lRect = dropLeft.getBoundingClientRect();
      const rRect = dropRight.getBoundingClientRect();
      if (lx >= lRect.left && lx <= lRect.right && ly >= lRect.top && ly <= lRect.bottom) {
        targetSide = 'left';
      } else if (lx >= rRect.left && lx <= rRect.right && ly >= rRect.top && ly <= rRect.bottom) {
        targetSide = 'right';
      }
    }

    try {
      const itemType = await _invoke('get_path_type', { path: paths[0] });
      setSlot(targetSide, { path: paths[0], type: itemType });
    } catch (err) {
      showError('エラー: ' + err);
    }
  });
}

// ---- File change detection ----
let filesChangedDialogShowing = false;

async function setupFilesChangedListener() {
  await _listen('files-changed', async (event) => {
    if (filesChangedDialogShowing) return;
    filesChangedDialogShowing = true;
    try {
      const names   = event.payload;
      const detail  = names.join('\n') + '\n\n再度読み込みますか？';
      const confirmed = _ask
        ? await _ask(detail, { title: 'ファイルが更新されました', okLabel: '再読み込み', cancelLabel: 'キャンセル' })
        : window.confirm('ファイルが更新されました\n\n' + detail);
      if (confirmed && state.left?.type === 'file' && state.right?.type === 'file') {
        const restoreScroll = {
          scrollTop:  _fileTableWrap ? _fileTableWrap.scrollTop : 0,
          scrollLeft: _fileVs        ? _fileVs.leftWrap.scrollLeft : 0,
        };
        lineDetail.classList.add('hidden');
        runFileCompare(state.left.path, state.right.path, restoreScroll)
          .catch(err => showError('エラー: ' + err.message));
      }
    } finally {
      filesChangedDialogShowing = false;
    }
  });
}

// ---- Initialise Tauri APIs then boot ----
window.addEventListener('DOMContentLoaded', async () => {
  try {
    initTheme();
    const tauri = window.__TAURI__;
    _invoke        = tauri.core.invoke;
    _listen        = tauri.event.listen;
    _ask           = tauri.dialog?.ask;
    _webviewWindow = tauri.webviewWindow.getCurrentWebviewWindow();

    await setupTauriDragDrop(_webviewWindow);
    await setupFilesChangedListener();

    // Check if this window was opened with pre-set paths
    const windowLabel = _webviewWindow.label;
    if (windowLabel !== 'main') {
      try {
        const args = await _invoke('get_window_args', { label: windowLabel });
        if (args) {
          const leftPath  = args.left;
          const rightPath = args.right;
          if (leftPath) {
            const t = await _invoke('get_path_type', { path: leftPath });
            setSlot('left', { path: leftPath, type: t });
          }
          if (rightPath) {
            const t = await _invoke('get_path_type', { path: rightPath });
            setSlot('right', { path: rightPath, type: t });
          }
          if (leftPath && rightPath) {
            doCompare();
          }
        }
      } catch (_) { /* no args */ }
    }
  } catch (err) {
    console.error('MacMerge init error:', err);
    document.querySelector('.app-subtitle').textContent = '初期化エラー: ' + err.message;
  }
});
