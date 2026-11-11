'use strict';

const $ = id => document.getElementById(id);
let snapshot;
let selected;
let live = true;
let busy = false;
let refreshQueued = false;
let requestGeneration = 0;
const targetNodes = new Map();
const treeNodes = new Map();

function setLive(value) {
  live = value;
  refreshQueued = false;
  requestGeneration++; // A pending image must not replace a frame being annotated.
  $('live').textContent = live ? 'Pause' : 'Resume live';
  $('live').setAttribute('aria-pressed', String(live));
  if (snapshot) $('status').textContent = live ? 'Live · 1 frame/sec' : 'Paused for comments';
}

function select(id) {
  selected = id;
  setLive(false);
  const element = snapshot.elements.find(item => item.id === id);
  if (!element) return;
  for (const [key, node] of targetNodes) node.classList.toggle('selected', key === id);
  for (const [key, node] of treeNodes) {
    node.classList.toggle('selected', key === id);
    node.setAttribute('aria-pressed', String(key === id));
  }
  $('selection').textContent = `${element.label}\n${element.className} · ${element.role}\n` +
    `${Math.round(element.width)} × ${Math.round(element.height)} pt at ` +
    `${Math.round(element.x)}, ${Math.round(element.y)}\n${element.path}`;
}

function updateElements() {
  const current = new Set(snapshot.elements.map(element => element.id));
  for (const nodes of [targetNodes, treeNodes]) {
    for (const [id, node] of nodes) {
      if (!current.has(id)) { node.remove(); nodes.delete(id); }
    }
  }
  if (selected && !current.has(selected)) {
    selected = undefined;
    $('selection').textContent = 'The previous element is no longer visible.';
  }
  for (const element of snapshot.elements) {
    let target = targetNodes.get(element.id);
    if (!target) {
      target = document.createElement('button');
      target.type = 'button';
      target.className = 'target';
      target.id = `native-${element.id.replace(/[^a-z0-9]/gi, '')}`;
      target.addEventListener('click', () => select(element.id));
      target.append(document.createElement('span'));
      targetNodes.set(element.id, target);
      $('targets').append(target);
    }
    // Actual DOM targets, not just pixels: browser comments carry native context.
    target.setAttribute('aria-label', `${element.label} — ${element.className}`);
    target.title = `${element.label}\n${element.path}`;
    target.dataset.nativeClass = element.className;
    target.dataset.nativePath = element.path;
    target.dataset.nativeFrame = `${element.x},${element.y},${element.width},${element.height}`;
    target.firstChild.textContent = `${element.label} (${element.className})`;
    target.style.left = `${element.x / snapshot.width * 100}%`;
    target.style.top = `${element.y / snapshot.height * 100}%`;
    target.style.width = `${element.width / snapshot.width * 100}%`;
    target.style.height = `${element.height / snapshot.height * 100}%`;
    target.style.zIndex = element.named ? 100 : element.depth + 1;
    target.classList.toggle('selected', selected === element.id);

    let row = treeNodes.get(element.id);
    if (!row) {
      row = document.createElement('button');
      row.type = 'button';
      row.className = 'tree-row';
      row.addEventListener('click', () => select(element.id));
      row.append(document.createElement('span'), document.createElement('small'));
      treeNodes.set(element.id, row);
    }
    row.firstChild.textContent = element.label;
    row.lastChild.textContent = element.className;
    row.title = element.path;
    row.style.paddingLeft = `${8 + Math.min(element.depth, 12) * 8}px`;
    row.classList.toggle('selected', selected === element.id);
    row.setAttribute('aria-pressed', String(selected === element.id));
    $('tree').append(row);
  }
  $('count').textContent = `(${snapshot.elements.length})`;
  filterTree();
}

function filterTree() {
  const filter = $('filter').value.trim().toLowerCase();
  for (const node of treeNodes.values()) node.hidden = !node.textContent.toLowerCase().includes(filter);
}

async function refresh() {
  if (busy) return;
  busy = true;
  const generation = requestGeneration;
  try {
    const response = await fetch('snapshot.json', { cache: 'no-store', signal: AbortSignal.timeout(4000) });
    if (!response.ok) throw new Error(await response.text());
    const next = await response.json();
    if (!Array.isArray(next.elements) || !(next.width > 0 && next.height > 0)) {
      throw new Error('The app returned an invalid frame.');
    }
    // Decode before swapping image and coordinates together; preserve DOM identity while live.
    const decoded = new Image();
    decoded.src = next.image;
    await decoded.decode();
    if (generation !== requestGeneration) return;
    snapshot = next;
    $('frame').src = next.image;
    $('frame').alt = `${next.title} — running Usual Base window`;
    $('stage').classList.remove('stale');
    $('empty').hidden = true;
    $('warning').hidden = !next.warning;
    $('warning').textContent = next.warning || '';
    updateElements();
    $('status').textContent = live ? 'Live · 1 frame/sec' : 'Paused for comments';
  } catch (error) {
    if (generation !== requestGeneration) return;
    $('status').textContent = 'Disconnected';
    $('warning').hidden = false;
    $('warning').textContent = error.message;
    $('stage').classList.add('stale');
  } finally {
    busy = false;
    if (refreshQueued) { refreshQueued = false; refresh(); }
  }
}

function requestRefresh() {
  if (busy) refreshQueued = true;
  else refresh();
}

$('live').addEventListener('click', () => { setLive(!live); if (live) requestRefresh(); });
$('refresh').addEventListener('click', () => { setLive(false); requestRefresh(); });
$('filter').addEventListener('input', filterTree);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { requestGeneration++; refreshQueued = false; }
  else if (live) refresh();
});
setInterval(() => { if (live && !document.hidden) refresh(); }, 1000);
refresh();
