'use strict';

const el = id => document.getElementById(id);
const catalog = el('catalog');
const stage = el('stage');
const filter = el('module');
const folders = [];
for (const section of catalog.querySelectorAll('section[data-category]')) {
  for (const group of section.querySelectorAll('.module-group')) {
    for (const page of group.querySelectorAll('article')) {
      folders.push({
        anchor: page.id, categoryKey: section.id, category: section.dataset.category,
        id: page.dataset.page, name: page.querySelector('h4').textContent,
        owner: group.dataset.owner, module: group.querySelector('h3').textContent,
        images: Array.from(page.querySelectorAll('.card'), link => ({
          state: link.querySelector('span').textContent,
          url: link.href, path: link.dataset.path
        }))
      });
    }
  }
}

let scope = folders;
let folder = null;
let index = 0;
let step = 1;
let returnCategory = '';
let homeScroll = 0;
let zoomed = null;
let scale = 1;
let feedbackTimer;
let copyRequest = 0;
const compact = matchMedia('(max-width:720px)');
const roundSpec = JSON.parse(el('current-round').textContent);
const reviewRound = roundSpec && {anchor:'current-review', name:roundSpec.title, images:[]};
const commentPrefix = 'design-gallery.comment:';
const oldPrefix = 'design-gallery.review:';
const threads = new Map();
const drafts = new Map();
let storageAvailable = true;
let placingPin = false;

if (reviewRound) {
  const byPath = new Map();
  for (const page of folders) {
    for (const image of page.images) {
      if (!byPath.has(image.path)) byPath.set(image.path, {...image, page});
    }
  }
  reviewRound.images = roundSpec.images.map(({path, digest}) => {
    const version = path + ':' + digest;
    threads.set(version, new Map());
    return {...byPath.get(path), digest, version};
  });
}

function storeComment(version, id, comment) {
  const thread = threads.get(version);
  if (comment) thread.set(id, comment);
  else thread.delete(id);
  const key = commentPrefix + version + '|' + id;
  try {
    if (comment) localStorage.setItem(key, JSON.stringify(comment));
    else localStorage.removeItem(key);
    return true;
  } catch { storageAvailable = false; return false; }
}

function readComment(key, value) {
  if (!key.startsWith(commentPrefix)) return;
  const split = key.lastIndexOf('|');
  const thread = threads.get(key.slice(commentPrefix.length, split));
  if (!thread) return;
  const id = key.slice(split + 1);
  if (value === null) { thread.delete(id); return; }
  try {
    const saved = JSON.parse(value);
    if (saved && typeof saved.text === 'string' && saved.text.trim()) thread.set(id, saved);
  } catch { /* Ignore an unreadable entry, leaving other comments available. */ }
}

function loadComments() {
  const retired = new Set(JSON.parse(el('replaced-revisions').textContent));
  try {
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith(commentPrefix)) {
        const version = key.slice(commentPrefix.length, key.lastIndexOf('|'));
        if (retired.has(version)) localStorage.removeItem(key);
        else readComment(key, localStorage.getItem(key));
      } else if (key.startsWith(oldPrefix)) {
        const version = key.slice(oldPrefix.length);
        if (retired.has(version)) localStorage.removeItem(key);
        else if (threads.has(version)) {
          let saved;
          try { saved = JSON.parse(localStorage.getItem(key)); } catch { continue; }
          const text = typeof saved?.note === 'string' ? saved.note.trim() : '';
          if (!text || storeComment(version, 'legacy', {text, time:0}))
            localStorage.removeItem(key);
        }
      }
    }
  } catch { storageAvailable = false; }
}

function commentsOf(image) {
  return [...threads.get(image.version)].sort(([aId, a], [bId, b]) =>
    a.time - b.time || aId.localeCompare(bId));
}

function updateRound() {
  if (!reviewRound) return;
  el('round').hidden = false;
  el('round-name').textContent = reviewRound.name;
  const items = reviewRound.images;
  const marked = items.filter(item => threads.get(item.version).size > 0).length;
  el('round-progress').textContent = items.length + ' 张图稿 · ' + marked + ' 张有评论，未评论的图视为没有问题';
  el('start-round').textContent = '查看本轮';
  const list = document.createDocumentFragment();
  items.forEach((item, i) => {
    const row = document.createElement('li');
    const link = document.createElement('a');
    link.href = '#current-review?image=' + (i + 1);
    link.dataset.key = reviewRound.anchor;
    link.textContent = item.state.replace(/^待审 · /, '');
    const result = document.createElement('span');
    result.className = 'comment-count';
    const count = threads.get(item.version).size;
    result.textContent = count ? count + ' 条评论' : '无修改意见';
    row.append(link, result);
    list.append(row);
  });
  el('round-list').replaceChildren(list);
  el('persistence-note').hidden = storageAvailable;
}

function updateHome() {
  scope = folders.filter(item => !filter.value || item.owner === filter.value);
  const categories = new Map();
  for (const item of scope) {
    if (!categories.has(item.categoryKey)) {
      categories.set(item.categoryKey, {name:item.category, owners:new Set(), count:0});
    }
    const category = categories.get(item.categoryKey);
    category.owners.add(item.module);
    category.count += item.images.length;
  }
  const rows = document.createDocumentFragment();
  for (const [key, category] of categories) {
    const row = el('row-template').content.firstElementChild.cloneNode(true);
    row.href = '#' + key;
    row.dataset.key = key;
    row.querySelector('.category-icon use').setAttribute('href', '#i-' + key);
    row.querySelector('.name').textContent = category.name;
    row.querySelector('.owners').textContent = [...category.owners].join('、');
    row.querySelector('.total').textContent = category.count + ' 张';
    rows.append(row);
  }
  el('rows').replaceChildren(rows);
  const pages = new Set(scope.map(item => item.id)).size;
  const count = scope.reduce((total, item) => total + item.images.length, 0);
  el('summary').textContent = categories.size + ' 个分类　/　' + pages + ' 个页面　/　' + count + ' 个状态';
}

function resetZoom() {
  if (zoomed) {
    zoomed.classList.remove('zoomed');
    zoomed = null;
  }
  scale = 1;
  el('scale').textContent = '';
}

function zoom(tile, event, value) {
  const rect = tile.getBoundingClientRect();
  if (!rect.width || !rect.height) return;
  if (zoomed !== tile) resetZoom();
  zoomed = tile;
  scale = value;
  tile.classList.add('zoomed');
  tile.style.setProperty('--scale', scale);
  tile.style.setProperty('--ox', ((event.clientX - rect.left) / rect.width * 100) + '%');
  tile.style.setProperty('--oy', ((event.clientY - rect.top) / rect.height * 100) + '%');
  el('scale').textContent = Math.round(scale * 100) + '%';
}

function createTile(item, position) {
  const tile = document.createElement('button');
  tile.className = 'tile';
  tile.dataset.folder = folder.anchor;
  tile.dataset.position = position;
  tile.setAttribute('aria-label', '选择第 ' + (position + 1) + ' 张，' + item.state);
  const img = document.createElement('img');
  img.alt = item.state;
  img.draggable = false;
  img.addEventListener('load', () => tile.style.setProperty('--ratio', img.naturalWidth / img.naturalHeight));
  img.src = item.url;
  const layer = document.createElement('span');
  layer.className = 'image-layer';
  layer.append(img);
  tile.append(layer);
  if (folder === reviewRound) {
    const label = document.createElement('span');
    label.className = 'figure-label';
    label.textContent = '图 ' + (position + 1);
    label.setAttribute('aria-hidden', 'true');
    tile.append(label);
  }
  tile.addEventListener('pointermove', event => {
    if (!placingPin && event.pointerType === 'mouse') zoom(tile, event, zoomed === tile ? scale : 1.25);
  });
  tile.addEventListener('pointerleave', () => { if (zoomed === tile) resetZoom(); });
  tile.addEventListener('wheel', event => {
    if (placingPin || event.ctrlKey || event.deltaY === 0) return;
    event.preventDefault();
    const current = zoomed === tile ? scale : 1;
    const value = current + (event.deltaY < 0 ? .15 : -.15);
    zoom(tile, event, Math.max(1, Math.min(3, value)));
  }, {passive:false});
  tile.addEventListener('click', event => {
    if (placingPin && folder === reviewRound && position === index && event.detail > 0) {
      const rect = img.getBoundingClientRect();
      const unit = value => Math.max(0, Math.min(1, value));
      draftFor(item).point = {x:unit((event.clientX - rect.left) / rect.width), y:unit((event.clientY - rect.top) / rect.height)};
      placingPin = false;
      drawComments();
      groupFor(position).querySelector('.comment-input').focus();
    } else select(folder, position);
  });
  return tile;
}

function firstVisible() {
  if (step === 3) return Math.floor(index / 3) * 3;
  if (compact.matches || folder === reviewRound) return index;
  return Math.max(0, Math.min(index - 1, folder.images.length - 3));
}

function resetFeedback() {
  copyRequest++;
  clearTimeout(feedbackTimer);
  for (const button of document.querySelectorAll('.copy.done')) {
    button.querySelector('span').textContent = button.dataset.label;
    button.classList.remove('done');
  }
}

function stateParts() {
  const image = folder.images[index];
  const state = image.state;
  const match = /^(待审|已确认|现有界面参考) · (.+)$/.exec(state);
  const name = match ? match[2] : state;
  const prefix = (image.page || folder).name + '／';
  return {name: name.startsWith(prefix) ? name.slice(prefix.length) : name, review: match ? match[1] : ''};
}

function draw() {
  const first = firstVisible();
  const visible = step === 1 && (compact.matches || folder === reviewRound) ? 1 : 3;
  const items = folder.images.slice(first, first + visible);
  const nodes = items.map((item, slot) => {
    const position = first + slot;
    const existing = stage.children[slot];
    const tile = existing && existing.dataset.folder === folder.anchor && Number(existing.dataset.position) === position
      ? existing : createTile(item, position);
    tile.setAttribute('aria-pressed', String(position === index));
    return tile;
  });
  if (nodes.length !== stage.childElementCount || nodes.some((tile, i) => stage.children[i] !== tile)) {
    stage.replaceChildren(...nodes);
  }
  const image = folder.images[index];
  const page = image.page || folder;
  const inReview = folder === reviewRound;
  el('catalog-details').hidden = inReview;
  document.querySelector('[data-copy="comments"]').hidden = !inReview;
  el('category-name').textContent = inReview ? '本轮审核' : folder.category;
  el('owner-name').textContent = page.module;
  el('page-name').textContent = page.name;
  el('count').textContent = (index + 1) + ' / ' + folder.images.length;
  const state = stateParts();
  el('state').textContent = state.name;
  el('state').href = folder.images[index].url;
  el('review').textContent = inReview ? '' : state.review;
  drawComments();
  el('announce').textContent = page.name + '，' + state.name + '，' + el('count').textContent;
  el('prev').disabled = (inReview || folder === scope[0]) && (step === 3 ? first === 0 : index === 0);
  el('next').disabled = (inReview || folder === scope[scope.length - 1]) &&
    (step === 3 ? first + 3 >= folder.images.length : index === folder.images.length - 1);
  for (const [id, name] of [['prev', '上'], ['next', '下']]) {
    const label = name + (step === 3 ? '一组' : '一张');
    el(id).setAttribute('aria-label', label);
    el(id).title = label;
    el(id + '-label').textContent = label;
  }
  for (const b of document.querySelectorAll('[data-step]')) b.setAttribute('aria-pressed', String(Number(b.dataset.step) === step));
}

function select(item, position) {
  const focusWasImage = stage.contains(document.activeElement);
  resetZoom();
  resetFeedback();
  placingPin = false;
  folder = item;
  index = position;
  draw();
  if (!el('comments').contains(document.activeElement)) revealGroup();
  if (focusWasImage) stage.querySelector('[aria-pressed=true]').focus({preventScroll:true});
  history.replaceState(history.state, '', '#' + folder.anchor + (index ? '?image=' + (index + 1) : ''));
}

function move(direction) {
  const position = step === 3 ? firstVisible() + 3 * direction : index + direction;
  if (position >= 0 && position < folder.images.length) {
    select(folder, position);
    return;
  }
  if (folder === reviewRound) return;
  const next = scope[scope.indexOf(folder) + direction];
  if (next) select(next, direction > 0 ? 0 : next.images.length - 1);
}

function showRoute() {
  const [anchor, query] = location.hash.slice(1).split('?');
  let target = reviewRound && anchor === reviewRound.anchor ? reviewRound
    : scope.find(item => item.anchor === anchor || item.categoryKey === anchor);
  if (!target && anchor) {
    target = folders.find(item => item.anchor === anchor || item.categoryKey === anchor);
    if (target) { filter.value = ''; updateHome(); }
  }
  const wasViewing = !!folder;
  el('viewer').hidden = !target;
  el('home').hidden = !!target;
  document.body.classList.toggle('viewing', !!target);
  if (target) {
    const requested = Number(new URLSearchParams(query).get('image')) || 1;
    const position = Number.isInteger(requested) ? Math.min(Math.max(requested, 1), target.images.length) - 1 : 0;
    select(target, position);
    if (!wasViewing) el('back').focus({preventScroll:true});
  } else {
    resetZoom();
    resetFeedback();
    folder = null;
    placingPin = false;
    drawComments();
    stage.replaceChildren();
    if (wasViewing) {
      window.scrollTo(0, homeScroll);
      const row = returnCategory === 'current-review' ? el('start-round')
        : [...el('rows').children].find(node => node.dataset.key === returnCategory);
      (row || filter).focus({preventScroll:true});
    }
  }
}

function back() {
  if (history.state && history.state.fromCategory) history.back();
  else {
    history.replaceState(null, '', location.href.split('#')[0]);
    showRoute();
  }
}

el('home').addEventListener('click', event => {
  const row = event.target.closest('a[data-key]');
  if (!row || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  returnCategory = row.dataset.key;
  homeScroll = window.scrollY;
  history.pushState({fromCategory:true}, '', row.hash);
  showRoute();
});
filter.addEventListener('change', updateHome);
el('back').addEventListener('click', back);
el('prev').addEventListener('click', () => move(-1));
el('next').addEventListener('click', () => move(1));
for (const button of document.querySelectorAll('[data-step]')) {
  button.addEventListener('click', () => {
    step = Number(button.dataset.step);
    resetZoom();
    draw();
  });
}
window.addEventListener('hashchange', showRoute);
compact.addEventListener('change', () => { if (folder) { resetZoom(); draw(); } });
document.addEventListener('keydown', event => {
  if (!folder || event.target.closest('input, textarea, select') || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
  if (event.key === 'Escape') { event.preventDefault(); back(); }
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault();
    move(event.key === 'ArrowRight' ? 1 : -1);
  }
});

function originalPath(item) {
  const url = new URL(item.url);
  if (url.protocol !== 'file:') return url.href;
  const path = decodeURIComponent(url.pathname);
  if (url.host) return ('//' + url.host + path).replaceAll('/', '\\');
  return /^\/[a-z]:\//i.test(path) ? path.slice(1).replaceAll('/', '\\') : path;
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value);
    return true;
  } catch {
    const active = document.activeElement;
    const input = document.createElement('textarea');
    input.className = 'sr-only';
    input.value = value;
    document.body.append(input);
    input.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch { /* Manual copy remains available. */ }
    input.remove();
    active.focus({preventScroll:true});
    if (!copied) window.prompt('请复制以下图片信息', value);
    return copied;
  }
}

for (const button of document.querySelectorAll('[data-copy]')) {
  const label = button.querySelector('span');
  button.dataset.label = label.textContent;
  button.addEventListener('click', async () => {
    resetFeedback();
    const request = copyRequest;
    const item = folder.images[index];
    const page = item.page || folder;
    let value;
    switch (button.dataset.copy) {
      case 'file': value = item.path.split('/').pop(); break;
      case 'path': value = originalPath(item); break;
      case 'comments': value = roundCommentText(); break;
      case 'reference':
        value = [page.category + ' / ' + page.module + ' / ' + page.name + ' / ' + stateParts().name,
          '页面标识 ' + page.id, '所属模块 ' + page.owner, '状态 ' + item.state, '原图 ' + item.path].join('\n');
        break;
    }
    if (!await copyText(value) || request !== copyRequest) return;
    button.classList.add('done');
    label.textContent = '✓ 已复制';
    el('announce').textContent = '已复制' + button.dataset.label;
    feedbackTimer = setTimeout(resetFeedback, 1500);
  });
}

function draftFor(image) {
  if (!drafts.has(image.version)) drafts.set(image.version, {text:'', point:null});
  return drafts.get(image.version);
}

function addPin(layer, point, label, draft = false) {
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return;
  const pin = document.createElement('span');
  pin.className = draft ? 'pin draft' : 'pin';
  pin.setAttribute('aria-hidden', 'true');
  pin.style.left = point.x * 100 + '%';
  pin.style.top = point.y * 100 + '%';
  pin.textContent = label;
  layer.append(pin);
}

const commentGroups = new Map();
let commentScope = 'visible';

function groupFor(position) {
  if (commentGroups.has(position)) return commentGroups.get(position);
  const image = reviewRound.images[position];
  const number = '图 ' + (position + 1);
  const title = image.state.replace(/^待审 · /, '');
  const group = el('picture-thread-template').content.firstElementChild.cloneNode(true);
  group.dataset.position = position;
  group.setAttribute('aria-label', number + ' ' + title);
  const heading = group.querySelector('.group-title');
  heading.querySelector('.figure-number').textContent = number;
  heading.querySelector('strong').textContent = title;
  heading.addEventListener('click', () => select(reviewRound, position));
  const field = group.querySelector('.comment-input');
  field.setAttribute('aria-label', number + ' ' + title + '的评论');
  field.placeholder = '给' + number + '写评论…';
  field.addEventListener('focus', () => {
    if (index !== position) select(reviewRound, position);
  });
  field.addEventListener('input', () => {
    draftFor(image).text = field.value;
    group.querySelector('.send-comment').disabled = !field.value.trim();
  });
  group.querySelector('.place-pin').addEventListener('click', () => {
    if (index !== position) select(reviewRound, position);
    placingPin = !placingPin;
    resetZoom();
    drawComments();
    if (placingPin) el('announce').textContent = '点选' + number + '上的位置。';
  });
  group.querySelector('.comment-form').addEventListener('submit', event => {
    event.preventDefault();
    const draft = draftFor(image);
    if (!draft.text.trim()) return;
    const id = Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16).padStart(8, '0')).join('');
    storeComment(image.version, id, {text:draft.text.trim(), point:draft.point, time:Date.now()});
    drafts.delete(image.version);
    if (index === position) placingPin = false;
    updateRound();
    drawComments();
    field.focus();
  });
  commentGroups.set(position, group);
  return group;
}

function commentNumber(location, i) {
  const serial = i < 20 ? String.fromCodePoint(0x2460 + i) : '(' + (i + 1) + ')';
  return location + serial;
}

function updateGroup(position, location) {
  const group = groupFor(position);
  const image = reviewRound.images[position];
  const draft = draftFor(image);
  const pinned = position === index && placingPin;
  group.querySelector('.group-title').setAttribute('aria-current', String(position === index));
  const pinButton = group.querySelector('.place-pin');
  pinButton.title = pinned ? '取消定位' : draft.point ? '重新标位置' : '标注位置';
  pinButton.setAttribute('aria-label', pinButton.title);
  pinButton.classList.toggle('has-point', !!draft.point);
  pinButton.setAttribute('aria-pressed', String(pinned));
  const field = group.querySelector('.comment-input');
  if (field.value !== draft.text) field.value = draft.text;
  group.querySelector('.send-comment').disabled = !draft.text.trim();

  const list = group.querySelector('.picture-thread');
  const entries = commentsOf(image);
  const signature = JSON.stringify([location, entries]);
  if (list.dataset.signature === signature) return group;
  list.dataset.signature = signature;
  const rows = entries.map(([id, comment], i) => {
    const row = document.createElement('li');
    const number = document.createElement('span');
    number.className = 'comment-num';
    number.textContent = commentNumber(location, i);
    row.append(number);
    const text = document.createElement('span');
    text.className = 'comment-text';
    text.textContent = comment.text;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'remove-comment';
    remove.textContent = '×';
    remove.title = '移除评论';
    remove.setAttribute('aria-label', '移除图 ' + (position + 1) + ' 的第 ' + (i + 1) + ' 条评论');
    remove.addEventListener('click', () => {
      storeComment(image.version, id, null);
      updateRound();
      drawComments();
    });
    row.append(text, remove);
    return row;
  });
  list.replaceChildren(...rows);
  return group;
}

function drawComments() {
  const panel = el('comments');
  const reviewing = !!reviewRound && folder === reviewRound;
  panel.hidden = !reviewing;
  el('viewer').classList.toggle('reviewing', reviewing);
  el('viewer').classList.toggle('pinning', reviewing && placingPin);
  if (!reviewing) return;
  const visible = Array.from(stage.children, tile => Number(tile.dataset.position));
  const positions = commentScope === 'round' ? reviewRound.images.map((_, i) => i) : visible;
  const sides = visible.length === 3 ? ['左', '中', '右'] : ['左', '右'];
  const locations = new Map(visible.map((position, slot) => [position, sides[slot]]));
  const groups = positions.map(position => updateGroup(position, locations.get(position) || '图 ' + (position + 1)));
  const body = el('thread-body');
  if (body.childElementCount !== groups.length || groups.some((node, i) => node !== body.children[i])) {
    body.replaceChildren(...groups);
  }
  for (const tile of stage.children) {
    const position = Number(tile.dataset.position);
    const item = folder.images[position];
    const layer = tile.querySelector('.image-layer');
    layer.querySelectorAll('.pin').forEach(pin => pin.remove());
    commentsOf(item).forEach(([,comment], i) => addPin(layer, comment.point, commentNumber(locations.get(position), i)));
    if (position === index) addPin(layer, draftFor(item).point, '+', true);
  }
}

function revealGroup() {
  const body = el('thread-body');
  if (body.hidden || folder !== reviewRound || !reviewRound) return;
  const group = groupFor(index);
  const bounds = body.getBoundingClientRect();
  const rect = group.getBoundingClientRect();
  if (rect.top < bounds.top || rect.top >= bounds.bottom - 35) body.scrollTop += rect.top - bounds.top;
}

function setCommentSide(left) {
  el('viewer').classList.toggle('comments-left', left);
  el('move-comments').textContent = left ? '移到右侧' : '移到左侧';
}
try { setCommentSide(localStorage.getItem('design-gallery.comment-side') === 'left'); }
catch { setCommentSide(false); }
el('move-comments').addEventListener('click', () => {
  const left = !el('viewer').classList.contains('comments-left');
  setCommentSide(left);
  try { localStorage.setItem('design-gallery.comment-side', left ? 'left' : 'right'); }
  catch { /* The side can still be changed for the current session. */ }
});
el('toggle-comments').addEventListener('click', () => {
  const hidden = !el('thread-body').hidden;
  el('thread-body').hidden = hidden;
  el('comments').classList.toggle('collapsed', hidden);
  el('toggle-comments').setAttribute('aria-expanded', String(!hidden));
  el('toggle-comments').textContent = hidden ? '展开评论' : '收起';
  placingPin = false;
  drawComments();
  if (!hidden) revealGroup();
});
for (const button of el('comment-scope').querySelectorAll('button')) {
  button.addEventListener('click', () => {
    commentScope = button.dataset.scope;
    for (const option of el('comment-scope').children) option.setAttribute('aria-pressed', String(option === button));
    drawComments();
    revealGroup();
  });
}
window.addEventListener('storage', event => {
  if (event.key === null) {
    for (const thread of threads.values()) thread.clear();
    loadComments();
  } else if (event.key.startsWith(commentPrefix)) readComment(event.key, event.newValue);
  else return;
  updateRound();
  drawComments();
});

function commentReport() {
  const images = reviewRound.images.filter(item => threads.get(item.version).size).map(item => ({
    path:item.path, digest:item.digest, state:item.state.replace(/^待审 · /, ''),
    comments:commentsOf(item).map(([,comment]) => ({text:comment.text, point:comment.point || null}))
  }));
  return {format:'design-gallery-comments-v1', title:reviewRound.name, images};
}
function handoff(message) {
  el('handoff').hidden = false;
  el('handoff').textContent = message;
}
function roundCommentText() {
  const report = commentReport();
  const groups = report.images.map(item => [item.state, item.path, 'SHA-256 ' + item.digest, ...item.comments.map(comment => {
    const p = comment.point;
    return '• ' + (p ? '图中位置（横向 ' + Math.round(p.x * 100) + '%，纵向 ' + Math.round(p.y * 100) + '%）' : '') + comment.text;
  })].join('\n'));
  const summary = groups.length ? '请按以下评论修订，未评论的图没有问题。' : '本轮没有修改意见。';
  return [report.title, summary, ...groups].join('\n\n');
}
el('copy-round').addEventListener('click', async () => {
  if (await copyText(roundCommentText())) handoff('已复制本轮评论，可粘贴回对话。');
});
el('save-round').addEventListener('click', async () => {
  const name = '本轮评论.json';
  const contents = JSON.stringify(commentReport(), null, 2) + '\n';
  if (window.showSaveFilePicker) {
    try {
      const handle = await window.showSaveFilePicker({id:'design-review', suggestedName:name,
        types:[{description:'评论文件', accept:{'application/json':['.json']}}]});
      const writer = await handle.createWritable();
      await writer.write(contents);
      await writer.close();
      handoff('评论文件已保存。存入看图目录后，可在对话中要求按评论修改。');
      return;
    } catch (error) {
      if (error.name === 'AbortError') return;
    }
  }
  const url = URL.createObjectURL(new Blob([contents], {type:'application/json'}));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
  handoff('已导出本轮评论。可将文件放入看图目录，或直接附到对话。');
});

loadComments();

updateRound();
updateHome();
catalog.hidden = true;
showRoute();
