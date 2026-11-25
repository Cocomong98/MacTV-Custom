const $ = s => document.querySelector(s);

// Haptics: Android vibrates; iPhone (iOS 18+) ticks when a switch toggles, so flip a hidden one.
const haptic = (() => {
  const vibrate = typeof navigator.vibrate === 'function';
  let iosSwitch = null;
  if (!vibrate) {
    iosSwitch = document.createElement('label');
    iosSwitch.style.display = 'none';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    iosSwitch.appendChild(input);
    document.body.appendChild(iosSwitch);
  }
  // Short pulses feel like light ticks; longer ones buzz.
  const patterns = { tick: 6, tap: 10, repeat: 4, error: [10, 50, 10] };
  return kind => {
    try {
      if (vibrate) navigator.vibrate(patterns[kind] ?? 14);
      else if (kind !== 'repeat') {
        iosSwitch.click();
        if (kind === 'error') setTimeout(() => iosSwitch.click(), 140);
      }
    } catch {}
  };
})();

// Visible press feedback on every button (Android Chrome's :active is unreliable on touch).
document.addEventListener('pointerdown', e => {
  const b = e.target.closest('button');
  if (!b) return;
  b.classList.add('pressed');
  const release = () => { b.classList.remove('pressed'); ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => b.removeEventListener(t, release)); };
  ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => b.addEventListener(t, release));
});

const store = {
  get() { try { return localStorage.getItem('mactvKey') || localStorage.getItem('matineeKey') || localStorage.getItem('couchKey') || ''; } catch { return ''; } },
  set(v) {
    for (const old of ['matineeKey', 'couchKey']) { try { localStorage.removeItem(old); } catch {} }
    try { localStorage.setItem('mactvKey', v); } catch {}
  },
};
const qrCode = new URLSearchParams(location.search).get('k') || '';
// A remote that moved here from another of the Mac's addresses brings its key in the fragment,
// which browsers never send to the server.
const carriedKey = new URLSearchParams(location.hash.slice(1)).get('key') || '';
if (carriedKey) store.set(carriedKey);
if (qrCode || carriedKey) history.replaceState(null, '', location.pathname);
let key = store.get();

// Every address the Mac answers at (its name, IP and Tailscale), from its last state.
const addresses = {
  get() { try { const list = JSON.parse(localStorage.getItem('mactvAddresses') || '[]'); return Array.isArray(list) ? list : []; } catch { return []; } },
  set(list) { try { localStorage.setItem('mactvAddresses', JSON.stringify(list)); } catch {} },
};

// A remote saved to the home screen always opens at the address it was saved from, and keeps its key
// there. Opening another address would leave it, so it asks the Mac there instead, from where it is.
const installed = (() => {
  try { return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; } catch { return false; }
})();
// Where requests go: this address, or another of the Mac's when an installed remote can't reach it here.
let base = '';
const isOrigin = origin => typeof origin === 'string' && /^http:\/\/[^/]+$/.test(origin);

async function answers(origin, fetcher) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  try {
    return (await fetcher(origin + '/state', { headers: { 'X-Couch-Key': key }, signal: controller.signal })).ok;
  } catch { return false; } finally { clearTimeout(timer); }
}

// When this address stops answering (the Mac's IP changed while it slept, say), try its other
// addresses and move to the first one that still knows this phone, taking the key along.
let unanswered = 0, moving = false;
async function moveToAnotherAddress(fetcher = fetch, go = url => location.replace(url)) {
  if (moving || !key) return false;
  moving = true;
  try {
    const here = base || location.origin;
    // An installed remote asking from elsewhere tries its own address again too.
    const list = base ? [location.origin, ...addresses.get()] : addresses.get();
    for (const origin of list) {
      if (!isOrigin(origin) || origin === here || !await answers(origin, fetcher)) continue;
      if (installed) base = origin === location.origin ? '' : origin;
      else go(origin + '/#key=' + encodeURIComponent(key));
      return true;
    }
    return false;
  } finally { moving = false; }
}

// The Mac's IP can change; its name doesn't. A remote opened at the IP on the home network moves to
// the name when the phone can reach it there, so the one saved to the home screen keeps working.
// Tailscale addresses stay put: they don't change, and also work away from home.
let settled = false;
async function settleOnHome(home, fetcher = fetch, go = url => location.replace(url)) {
  if (settled || installed || !key || !isOrigin(home) || home === location.origin) return false;
  const ip = location.hostname.split('.').map(Number);
  if (ip.length !== 4 || ip.some(n => !Number.isInteger(n)) || ip[0] === 127 || (ip[0] === 100 && ip[1] >= 64 && ip[1] <= 127)) return false;
  settled = true;
  if (!await answers(home, fetcher)) return false;
  go(home + '/#key=' + encodeURIComponent(key));
  return true;
}

let remoteReachable = false;

// Keep a reachable sleeping display distinct from an offline Mac.
function online(ok, sleeping = false) {
  const changed = remoteReachable !== ok;
  remoteReachable = ok;
  $('.status').hidden = ok && !sleeping;
  // A Mac that's fully asleep is off the network; only its own keyboard, trackpad or lid wakes it.
  $('#status').textContent = !ok ? 'Mac에 연결할 수 없습니다. 잠자기 상태라면 키보드를 누르거나 덮개를 열어 깨우세요.' : sleeping ? '화면 잠자기 중 · 조작하면 깨어납니다' : '';
  if (!ok) updateSeekButtons(false);
  if (changed && !ok) {
    brightnessRevision++;
    for (const row of brightnessRows.values()) {
      enableBrightness(row, false);
      displayBrightness(row, null);
    }
    showBrightnessMessage('Mac 연결이 끊겼습니다.');
    renderSpeaker();
    if (!displayChanging) updateDisplays({ displays: availableDisplays });
  }
}

// A timed-out POST may already have reached the TV; never replay it automatically.
async function request(path, body, authenticated = true, cancelSignal = null) {
  if (cancelSignal?.aborted) throw new Error('cancelled');
  const controller = new AbortController();
  const credential = key;
  let timer, cancel;
  const interrupted = new Promise((_, reject) => {
    timer = setTimeout(() => { controller.abort(); reject(new Error('Request timed out.')); }, 9000);
    cancel = () => { controller.abort(); reject(new Error('cancelled')); };
    if (cancelSignal) {
      if (cancelSignal.aborted) cancel();
      else cancelSignal.addEventListener('abort', cancel, { once: true });
    }
  });
  try {
    return await Promise.race([interrupted, (async () => {
      const res = await fetch(base + path, {
        method: body ? 'POST' : 'GET',
        headers: authenticated ? { 'Content-Type': 'application/json', 'X-Couch-Key': credential } : { 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
      if (authenticated && res.status === 401) {
        // A late response from an old request must not revoke a newly paired key.
        if (key === credential) { key = ''; store.set(''); showPair(); }
        throw new Error('unpaired');
      }
      const data = await res.json();
      if (!res.ok) {
        const error = new Error(data.error || res.statusText);
        error.status = res.status;
        throw error;
      }
      return data;
    })()]);
  } finally {
    clearTimeout(timer);
    if (cancelSignal) cancelSignal.removeEventListener('abort', cancel);
  }
}
function api(path, body, signal) { return request(path, body, true, signal); }

// Keep server error text intact for protocol handling, and translate it when shown.
const remoteMessages = new Map(Object.entries({
  'unpaired': '먼저 CouchDial에 연결하세요.',
  'Request timed out.': '요청 시간이 초과되었습니다. 다시 시도하세요.',
  'Not allowed': '이 작업은 허용되지 않습니다.',
  'Not found': '요청한 항목을 찾을 수 없습니다.',
  'This action requires a trusted remote.': '전체 권한이 있는 리모컨에서만 이 작업을 할 수 있습니다.',
  'This action requires a trusted remote here.': '전체 권한이 있는 리모컨에서만 이 작업을 할 수 있습니다.',
  'Guests cannot manage devices': '게스트 기기는 연결을 관리할 수 없습니다.',
  'Could not save changes': '변경 사항을 저장하지 못했습니다.',
  'Missing device': '기기를 선택하세요.',
  'No audio output available.': '사용할 수 있는 오디오 출력이 없습니다.',
  'Switch the Mac’s sound output to its built-in speakers to use this slider.': '이 슬라이더를 사용하려면 Mac의 사운드 출력을 내장 스피커로 바꾸세요.',
  'Speaker volume is unavailable.': '스피커 음량을 조절할 수 없습니다.',
  'Built-in brightness is unavailable.': '내장 디스플레이 밝기를 조절할 수 없습니다.',
  'Choose a connected display and a brightness from 0 to 100.': '연결된 화면과 0~100% 사이의 밝기를 선택하세요.',
  'The Mac did not confirm the brightness change.': 'Mac에서 변경된 밝기를 확인하지 못했습니다.',
  'Wait for the monitor to report its brightness.': '모니터의 밝기 값이 표시될 때까지 기다리세요.',
  'BetterDisplay is not available.': 'BetterDisplay를 사용할 수 없습니다.',
  'The brightness control changed. Try again after it refreshes.': '밝기 제어 방식이 바뀌었습니다. 화면이 갱신된 뒤 다시 시도하세요.',
  "Open BetterDisplay to control this monitor's brightness.": '이 모니터의 밝기를 조절하려면 BetterDisplay를 실행하세요.',
  "BetterDisplay could not read this monitor's brightness.": 'BetterDisplay가 이 모니터의 밝기를 읽지 못했습니다.',
  'Enter a shared folder like nas.local/Movies.': '공유 폴더 주소를 입력하세요. 예: nas.local/Movies',
  'Choose a share.': '공유 폴더를 선택하세요.',
  'Connected': '연결됨',
  'Connecting…': '연결 중…',
  'Not connected': '연결 안 됨',
  'Check the address': '주소를 확인하세요.',
  'Accessibility': '손쉬운 사용',
  'Device Control and Data Access': '기기 제어 및 데이터 접근',
}));
function remoteText(message) { return remoteMessages.get(message) ?? message ?? ''; }

// Keep a small bounded queue: repeats are dropped under load and urgent actions jump ahead.
const commandQueue = [];
let activeCommand = null;
function pumpCommands() {
  if (activeCommand || !commandQueue.length) return;
  const item = commandQueue.shift();
  if (!key) { item.done(); pumpCommands(); return; }
  const controller = new AbortController();
  activeCommand = controller;
  api('/cmd', item.body, controller.signal).catch(e => {
    if (e.message !== 'unpaired' && e.message !== 'cancelled') { online(false); haptic('error'); }
  }).finally(() => { activeCommand = null; item.done(); pumpCommands(); });
}
function send(a, extra, kind = 'tick') {
  haptic(kind);
  return new Promise(resolve => {
    const urgent = a === 'home' || a === 'screenoff';
    if (urgent) {
      while (commandQueue.length) commandQueue.shift().done();
      if (activeCommand) activeCommand.abort();
      commandQueue.unshift({ body: { a, ...extra }, done: resolve });
    } else if ((kind === 'repeat' && (activeCommand || commandQueue.length)) || commandQueue.length >= 8) {
      resolve(); return;
    } else {
      commandQueue.push({ body: { a, ...extra }, done: resolve });
    }
    pumpCommands();
  });
}

// State: connection, the app list, settings.
let appsShown = '', apps = [], tvSheet = '', currentLocalMovie = null, iinaInstalled = false;
let stateGeneration = 0, appMutationPending = false, displayChanging = false, availableDisplays = [];
let stateInFlight = null;
async function refresh(duringMutation = false) {
  if (appMutationPending && !duringMutation) return false;
  if (!key) { showPair(); return false; }
  if (stateInFlight) {
    if (!duringMutation) return stateInFlight;
    await stateInFlight; // The pre-edit snapshot must finish before the reconciliation read.
    if (!key) return false;
  }
  const pending = readState();
  stateInFlight = pending;
  try { return await pending; } finally { if (stateInFlight === pending) stateInFlight = null; }
}
async function readState() {
  const generation = ++stateGeneration;
  try {
    const s = await api('/state');
    // A newer refresh or an edit invalidates an older in-flight response.
    if (generation !== stateGeneration) return false;
    unanswered = 0;
    if (Array.isArray(s.addresses) && s.addresses.length) addresses.set(s.addresses);
    settleOnHome(s.home);
    online(true, s.displaysSleeping === true);
    document.body.classList.toggle('guest', s.guest === true);
    if (s.guest === true) document.querySelectorAll('.scrim.show').forEach(sheet => sheet.classList.remove('show'));
    const focused = appFocus();
    apps = s.apps;
    currentLocalMovie = s.currentLocalMovie || null;
    updateSeekButtons(s.current?.id === 'youtube' && s.youtubeSeekSeconds === 15);
    tvSheet = typeof s.sheet === 'string' ? s.sheet : '';
    iinaInstalled = !!s.iinaInstalled;
    updateMovieOptions();
    showSleep(s.sleepMinutes || 0);
    $('#auto-skip').checked = s.autoSkip;
    $('#auto-next').checked = s.autoNext;
    $('#keep-awake').checked = s.keepMacAwake;
    $('#lid-override').checked = s.lidOverride;
    $('#lid-status').textContent = remoteText(s.lidStatus);
    if (!speaker.saving) updateSpeaker(s.speakerVolume);
    if (!displayChanging) updateDisplays(s.displaySetup);
    refreshBrightness();
    renderPlayerChoices(typeof s.websitePlayer === 'string' ? s.websitePlayer : 'embedded', s.braveInstalled === true, s.websitePlayers);
    const player = s.externalPlayer && s.externalPlayer.name === 'IINA' ? s.externalPlayer : null;
    $('#iina-controls').hidden = !player;
    const iinaStatus = player && typeof player.status === 'string' ? player.status : '';
    const iinaError = player && typeof player.error === 'string' ? player.error : '';
    $('#iina-status').textContent = iinaStatus;
    $('#iina-status').hidden = !iinaStatus;
    $('#iina-error').textContent = iinaError;
    $('#iina-error').hidden = !iinaError;
    const browser = s.externalBrowser;
    $('#browser-controls').hidden = !browser;
    const browserError = browser && typeof browser.error === 'string' ? browser.error : '';
    $('#browser-error').textContent = browserError;
    $('#browser-error').hidden = !browserError;
    $('#browser-retry').hidden = !browserError;
    $('#browser-retry').disabled = !!(browser && browser.opening);
    $('#browser-control-note').textContent = browser && browser.accessibilityAllowed === false
      ? `시스템 설정 › 개인정보 보호 및 보안 › ${remoteText(browser.permissionPane || 'Accessibility')}에서 CouchDial를 허용하면 ${browser.name || '브라우저'} 창을 열고 이동하고 조작할 수 있습니다.` : '';
    $('#browser-return').textContent = `${browser && browser.name ? browser.name : '브라우저'}로 돌아가기`;
    const sig = JSON.stringify(s.apps);
    if (sig !== appsShown) {
      appsShown = sig;
      if (!appMutationPending) renderApps(focused);
    }
    return true;
  } catch (e) {
    if (generation === stateGeneration && e.message !== 'unpaired') {
      online(false);
      // About nine seconds without an answer: look for the Mac at its other addresses.
      if (++unanswered >= 3) moveToAnotherAddress();
    }
    return false;
  }
}

// Settings choices: a list with a checkmark, in place of a dropdown.
function choiceRow(title, detail, selected, disabled, onPick) {
  const row = document.createElement('button');
  row.className = 'row';
  row.setAttribute('aria-pressed', String(selected));
  row.disabled = disabled;
  const name = document.createElement('span'); name.textContent = title; row.appendChild(name);
  if (detail) { const value = document.createElement('span'); value.className = 'value'; value.textContent = detail; row.appendChild(value); }
  row.onclick = onPick;
  return row;
}

function updateDisplays(setup) {
  const list = $('#display-select');
  availableDisplays = Array.isArray(setup?.displays) ? setup.displays : [];
  const selected = availableDisplays.find(display => display.preferred) || availableDisplays.find(display => display.current);
  $('#display-value').textContent = selected ? selected.name : '없음';
  list.replaceChildren(...(availableDisplays.length
    ? availableDisplays.map(display => choiceRow(display.name, display.current ? '현재 재생 화면' : '', display === selected,
        displayChanging || !remoteReachable, () => chooseDisplay(display)))
    : [choiceRow('연결된 화면 없음', '', false, true, () => {})]));
}

const brightnessRows = new Map();
const brightnessPresets = [0, 25, 50, 75, 100];
const brightnessHoldMs = 350;
let brightnessReading = false, brightnessRevision = 0;

function brightnessVisible() {
  return key && $('#power-sheet').classList.contains('show') && !$('#page-display').hidden
    && !document.body.classList.contains('guest');
}

function showBrightnessMessage(message) {
  const note = $('#brightness-msg');
  note.textContent = message;
  note.hidden = !message;
}

function displayBrightness(row, value) {
  row.input.value = value ?? 0;
  row.amount.textContent = value === null ? '—' : `${value}%`;
  row.presets.forEach((button, i) => button.setAttribute('aria-pressed', String(brightnessPresets[i] === value)));
}

function enableBrightness(row, enabled) {
  row.input.disabled = !enabled;
  row.presets.forEach(button => { button.disabled = !enabled; });
  if (!enabled) row.cancelGesture();
}

async function refreshBrightness() {
  if (!remoteReachable || !brightnessVisible() || brightnessReading) return;
  brightnessReading = true;
  const revision = brightnessRevision;
  try {
    const displays = await api('/display/brightness');
    if (revision !== brightnessRevision || !brightnessVisible()) return;
    const current = new Set(displays.map(display => display.id));
    for (const [id, row] of brightnessRows) {
      if (current.has(id)) continue;
      row.cancelGesture();
      row.element.remove();
      brightnessRows.delete(id);
    }
    for (const display of displays) {
      const row = brightnessRows.get(display.id) || addBrightnessRow(display.id);
      if (!row.gesture && !row.saving) {
        const title = display.method === 'betterDisplay' ? `${display.name} (BetterDisplay)` : display.name;
        row.name.textContent = title;
        row.method = display.method;
        row.input.setAttribute('aria-label', `${title} 밝기`);
        row.presetGroup.setAttribute('aria-label', `${title} 밝기 프리셋`);
        row.value = Number.isInteger(display.value) ? display.value : null;
        displayBrightness(row, row.value);
        enableBrightness(row, display.pending !== true && !!row.method && row.value !== null);
      }
      row.note.textContent = remoteText(display.error) || (display.pending ? '밝기를 확인하는 중…' : '');
      row.note.hidden = !row.note.textContent;
    }
    if (!displays.length) showBrightnessMessage('연결된 화면이 없습니다.');
    else if (['연결된 화면이 없습니다.', '화면 밝기를 읽지 못했습니다.', 'Mac 연결이 끊겼습니다.'].includes($('#brightness-msg').textContent)) showBrightnessMessage('');
  } catch (error) {
    if (revision !== brightnessRevision || error.message === 'unpaired') return;
    for (const row of brightnessRows.values()) enableBrightness(row, false);
    showBrightnessMessage('화면 밝기를 읽지 못했습니다.');
  } finally {
    brightnessReading = false;
  }
}

function addBrightnessRow(id) {
  const element = document.createElement('div'); element.className = 'row brightness-row';
  const name = document.createElement('span'), amount = document.createElement('output');
  const track = document.createElement('div'); track.className = 'brightness-track';
  const input = document.createElement('input'); input.type = 'range'; input.min = '0'; input.max = '100'; input.step = '1';
  input.setAttribute('aria-describedby', 'brightness-help');
  track.appendChild(input);
  const presetGroup = document.createElement('div'); presetGroup.className = 'brightness-presets';
  presetGroup.setAttribute('role', 'group');
  const presets = brightnessPresets.map(value => {
    const button = document.createElement('button'); button.type = 'button'; button.textContent = `${value}%`;
    button.addEventListener('click', () => saveBrightness(row, value));
    presetGroup.appendChild(button);
    return button;
  });
  const note = document.createElement('small'); note.hidden = true;
  element.append(name, amount, track, presetGroup, note);
  $('#display-brightness').appendChild(element);
  const row = { id, element, name, amount, input, note, presets, presetGroup, gesture: null, saving: false, value: null };
  brightnessRows.set(id, row);
  input.addEventListener('input', () => displayBrightness(row, Number(input.value)));
  input.addEventListener('change', () => saveBrightness(row, Number(input.value)));
  row.cancelGesture = bindBrightnessTrack(track, row);
  return row;
}

function bindBrightnessTrack(track, row) {
  const at = event => {
    const { left, width } = track.getBoundingClientRect();
    return Math.round(Math.max(0, Math.min(1, (event.clientX - left) / width)) * 100);
  };
  function cancel() {
    if (!row.gesture) return;
    const { id, timer } = row.gesture;
    row.gesture = null;
    clearTimeout(timer);
    track.classList.remove('precise');
    if (track.hasPointerCapture(id)) track.releasePointerCapture(id);
    displayBrightness(row, row.value);
  }
  track.addEventListener('contextmenu', event => event.preventDefault());
  track.addEventListener('pointerdown', event => {
    if (event.button !== 0 || !event.isPrimary || row.input.disabled || row.gesture) return;
    track.setPointerCapture(event.pointerId);
    const gesture = { id: event.pointerId, x: event.clientX, y: event.clientY, precise: false, moved: false };
    gesture.timer = setTimeout(() => {
      gesture.precise = true;
      track.classList.add('precise');
    }, brightnessHoldMs);
    row.gesture = gesture;
  });
  track.addEventListener('pointermove', event => {
    const gesture = row.gesture;
    if (gesture?.id !== event.pointerId) return;
    const distance = Math.hypot(event.clientX - gesture.x, event.clientY - gesture.y);
    if (!gesture.precise && distance > 9) { cancel(); return; }
    if (gesture.precise && (gesture.moved || distance > 4)) {
      gesture.moved = true;
      displayBrightness(row, at(event));
    }
  });
  track.addEventListener('pointerup', event => {
    const gesture = row.gesture;
    if (gesture?.id !== event.pointerId) return;
    const value = at(event);
    cancel();
    if (!gesture.precise) saveBrightness(row, Math.round(value / 25) * 25);
    else if (gesture.moved) saveBrightness(row, value);
  });
  for (const type of ['pointercancel', 'lostpointercapture']) {
    track.addEventListener(type, event => { if (row.gesture?.id === event.pointerId) cancel(); });
  }
  return cancel;
}

async function saveBrightness(row, value) {
  if (!remoteReachable || row.saving || row.input.disabled || !brightnessVisible() || value === row.value) return;
  row.saving = true;
  enableBrightness(row, false);
  displayBrightness(row, value);
  brightnessRevision++;
  showBrightnessMessage('');
  try {
    const result = await api('/display/brightness', { id: row.id, value, method: row.method });
    if (!remoteReachable || !brightnessVisible()) return;
    if (result.pending) {
      row.note.textContent = '밝기를 적용하는 중…';
      row.note.hidden = false;
    } else {
      row.value = result.value;
      displayBrightness(row, row.value);
      enableBrightness(row, true);
    }
  } catch (error) {
    displayBrightness(row, remoteReachable ? row.value : null);
    if (error.message !== 'unpaired') showBrightnessMessage(remoteText(error.message));
  } finally {
    row.saving = false;
    refreshBrightness();
  }
}

const speaker = { reported: null, editingID: null, saving: false, error: '' };
const speakerSlider = $('#speaker-range');

function updateSpeaker(reported) {
  if (speaker.reported?.id !== reported?.id) speaker.error = '';
  speaker.reported = reported;
  renderSpeaker();
}

function renderSpeaker() {
  const { id, name, value, muted, error } = speaker.reported || {};
  $('#speaker-name').textContent = name || '내장 스피커';
  const available = remoteReachable && Number.isInteger(id) && Number.isInteger(value);
  speakerSlider.disabled = !available || speaker.saving;
  if (!speaker.saving && !(available && speaker.editingID === id)) {
    speakerSlider.value = available ? value : 0;
    $('#speaker-value').textContent = !available ? '—' : muted ? '음소거' : `${value}%`;
  }
  const message = $('#speaker-msg');
  message.textContent = !remoteReachable ? 'Mac 연결이 끊겼습니다.' : remoteText(error) || speaker.error ||
    (speaker.saving ? '음량을 적용하는 중…' : available ? '' : '스피커 음량을 조절할 수 없습니다.');
  message.hidden = !message.textContent;
}

speakerSlider.addEventListener('input', () => {
  speaker.editingID ??= speaker.reported?.id;
  $('#speaker-value').textContent = `${speakerSlider.value}%`;
});
speakerSlider.addEventListener('pointercancel', () => { speaker.editingID = null; renderSpeaker(); });
speakerSlider.addEventListener('blur', () => { speaker.editingID = null; renderSpeaker(); });
speakerSlider.addEventListener('change', async () => {
  const id = speaker.editingID ?? speaker.reported?.id;
  speaker.editingID = null;
  if (speakerSlider.disabled || !brightnessVisible() || id !== speaker.reported?.id) { renderSpeaker(); return; }
  const value = Number(speakerSlider.value);
  speaker.saving = true;
  speaker.error = '';
  stateGeneration++;
  renderSpeaker();
  try {
    const confirmed = await api('/audio/volume', { id, value });
    speaker.reported = { ...speaker.reported, ...confirmed };
  } catch (error) {
    if (error.message !== 'unpaired') speaker.error = remoteText(error.message);
  } finally {
    speaker.saving = false;
    renderSpeaker();
    await refresh(true);
  }
});

// The browsers on this Mac, as the Mac lists them; an older Mac TV sends no list, so offer Built-in and Brave.
function renderPlayerChoices(current, braveInstalled, players) {
  if (!Array.isArray(players) || !players.length) {
    $('#website-player-value').textContent = current === 'brave' ? 'Brave' : '내장 플레이어';
    $('#website-player').replaceChildren(
      choiceRow('내장 플레이어', '', current !== 'brave', false, () => choosePlayer('embedded')),
      choiceRow('Brave', braveInstalled ? '' : '설치 안 됨', current === 'brave', !braveInstalled && current !== 'brave', () => choosePlayer('brave')));
    return;
  }
  const selected = players.find(player => player.id === current) || players[0];
  $('#website-player-value').textContent = selected.id === 'embedded' ? '내장 플레이어' : selected.name;
  $('#website-player').replaceChildren(...players.map(player =>
    choiceRow(player.id === 'embedded' ? '내장 플레이어' : player.name, '', player === selected, false, () => choosePlayer(player.id))));
}

// Apps sheet: launch tiles, or accessible controls for arranging the same apps.
let editing = false;
function appFocus() {
  const active = document.activeElement;
  if (!$('#apps').contains(active) || !active.dataset.appId) return null;
  return { id: active.dataset.appId, action: active.dataset.action, element: active,
           index: apps.findIndex(app => app.id === active.dataset.appId) };
}
function appArt(app) {
  const art = document.createElement('span');
  art.className = 'art';
  if (app.icon) {
    const img = document.createElement('img');
    img.src = `${base}/icon/${encodeURIComponent(app.id)}?v=${encodeURIComponent(appsShown.length)}`;
    img.alt = '';
    art.appendChild(img);
  } else {
    art.textContent = app.name.slice(0, 1).toUpperCase();
  }
  return art;
}
function favouriteBadge() {
  const badge = document.createElement('span');
  badge.className = 'favourite';
  badge.textContent = '★';
  badge.setAttribute('aria-hidden', 'true');
  return badge;
}
function appMessage(message, error = false) {
  const note = $('#apps-msg');
  note.textContent = message;
  note.className = error ? 'note err' : 'note ok';
  note.hidden = !message;
}
async function changeApp(path, body, message) {
  if (appMutationPending) return;
  const focused = appFocus();
  appMutationPending = true;
  ++stateGeneration;
  $('#apps').setAttribute('aria-busy', 'true');
  $('#apps').querySelectorAll('button').forEach(button => { button.disabled = true; });
  $('#edit-apps').disabled = true;
  appMessage('저장 중…');
  haptic('tap');
  try {
    await api(path, body);
    const updated = await refresh(true);
    appMessage(updated ? message : '저장했습니다. 앱 목록을 갱신하려면 다시 연결하세요.', !updated);
  } catch (e) {
    haptic('error');
    appMessage(remoteText(e.message), true);
    // Another remote may have changed the app or its position.
    await refresh(true);
  } finally {
    appMutationPending = false;
    // Do not take focus back if the user moved to Done or another sheet while waiting.
    const keepFocus = focused && (document.activeElement === focused.element || document.activeElement === document.body);
    renderApps(keepFocus ? focused : null);
  }
}
function renderApps(focused = appFocus()) {
  const box = $('#apps');
  const sheet = $('#apps-sheet .sheet');
  const scrollTop = sheet.scrollTop;
  box.textContent = '';
  box.classList.toggle('editing', editing);
  box.setAttribute('aria-busy', String(appMutationPending));
  for (const app of apps) {
    if (editing) {
      const card = document.createElement('div');
      card.className = 'app-editor';
      const head = document.createElement('div');
      head.className = 'app-editor-head';
      const icon = document.createElement('span');
      icon.className = 'app';
      icon.appendChild(appArt(app));
      if (app.pinned) icon.appendChild(favouriteBadge());
      const name = document.createElement('span');
      name.className = 'app-editor-name';
      name.textContent = app.name;
      head.append(icon, name);
      const actions = document.createElement('div');
      actions.className = 'app-actions';
      const action = (kind, label, description, available, path, body, message) => {
        const button = document.createElement('button');
        button.className = kind;
        button.textContent = label;
        button.dataset.appId = app.id;
        button.dataset.action = kind;
        button.setAttribute('aria-label', description);
        button.disabled = appMutationPending || !available;
        button.onclick = () => changeApp(path, body, message);
        actions.appendChild(button);
        return button;
      };
      const pin = action('pin', app.pinned ? '★ 고정 해제' : '☆ 즐겨찾기 고정',
        `${app.name} ${app.pinned ? '고정 해제' : '고정'}`, true, '/apps/pin', { id: app.id, pinned: !app.pinned },
        `${app.name} ${app.pinned ? '고정 해제됨' : '즐겨찾기에 고정됨'}.`);
      pin.setAttribute('aria-pressed', String(!!app.pinned));
      action('remove', '제거', `${app.name} 제거`, true, '/apps/remove', { id: app.id }, `${app.name} 제거됨`);
      action('earlier', '↑ 앞으로', `${app.name} 앞으로 이동`, !!app.canMoveEarlier,
        '/apps/move', { id: app.id, offset: -1 }, `${app.name}을(를) 앞으로 이동했습니다.`);
      action('later', '↓ 뒤로', `${app.name} 뒤로 이동`, !!app.canMoveLater,
        '/apps/move', { id: app.id, offset: 1 }, `${app.name}을(를) 뒤로 이동했습니다.`);
      card.append(head, actions);
      box.appendChild(card);
      continue;
    }
    const b = document.createElement('button');
    b.className = 'app';
    b.dataset.appId = app.id;
    b.dataset.action = 'launch';
    const name = document.createElement('span');
    name.textContent = app.name;
    b.append(appArt(app), name);
    if (app.pinned) b.appendChild(favouriteBadge());
    b.setAttribute('aria-label', `${app.name} 열기${app.pinned ? ', 즐겨찾기' : ''}`);
    b.onclick = () => {
      closeSheets();
      send('launch', { id: app.id }, 'tap');
    };
    box.appendChild(b);
  }
  const add = document.createElement('button');
  add.className = 'app add';
  add.innerHTML = '<span class="art">+</span><span>앱 추가</span>';
  add.onclick = () => { haptic('tick'); openAdd(); };
  box.appendChild(add);
  $('#edit-apps').textContent = editing ? '완료' : '편집';
  $('#edit-apps').classList.toggle('on', editing);
  $('#edit-apps').disabled = appMutationPending;
  $('#edit-note').hidden = !editing;
  $('#apps-title').textContent = editing ? '앱 정리' : 'TV에서 열기';
  if (focused && $('#apps-sheet').classList.contains('show') && !$('#pair').classList.contains('show')) {
    const buttons = [...box.querySelectorAll('button[data-app-id]')];
    const sameApp = buttons.filter(button => button.dataset.appId === focused.id && !button.disabled);
    const target = sameApp.find(button => button.dataset.action === focused.action) || sameApp[0]
      || buttons.find(button => button.dataset.appId === apps[Math.min(Math.max(focused.index, 0), apps.length - 1)]?.id && !button.disabled)
      || $('#edit-apps');
    target.focus({ preventScroll: true });
  }
  sheet.scrollTop = scrollTop;
}
$('#edit-apps').onclick = () => { haptic('tick'); editing = !editing; appMessage(''); renderApps(); };

// File IDs come from the server and remain opaque; names are always rendered as text.
let fileTrail = [], fileEntries = [], fileNext = null, selectedMovie = null, fileGeneration = 0;
function fileMessage(message, error = false) {
  $('#files-msg').textContent = message;
  $('#files-msg').className = error ? 'note err' : 'note';
}
function updateMovieOptions() {
  $('#play-iina').disabled = !iinaInstalled;
  $('#play-iina').textContent = iinaInstalled ? 'IINA에서 재생' : 'IINA 설치 안 됨';
  $('#subtitle-search-iina').disabled = !iinaInstalled;
}
async function loadFiles(more = false) {
  const generation = ++fileGeneration;
  const folder = fileTrail[fileTrail.length - 1];
  const offset = more ? fileNext : 0;
  fileMessage('Loading…');
  try {
    const data = await api(folder ? `/files?folder=${encodeURIComponent(folder.id)}&offset=${encodeURIComponent(offset)}&limit=100` : '/files/roots');
    if (generation !== fileGeneration) return;
    const items = folder ? (data.entries || []) : (data.roots || []);
    fileEntries = more ? fileEntries.concat(items) : items;
    fileNext = folder && data.nextOffset != null ? data.nextOffset : null;
    fileMessage('');
    renderFiles();
  } catch (e) {
    if (generation !== fileGeneration) return;
    fileMessage(remoteText(e.message), true);
  }
}
function renderFiles() {
  $('#files-path').textContent = ['위치', ...fileTrail.map(item => item.name)].join(' › ');
  $('#files-back').disabled = !fileTrail.length;
  $('#files-more').hidden = fileNext == null;
  const list = $('#files-list'); list.textContent = '';
  const filter = $('#files-filter').value.trim().toLocaleLowerCase();
  const matches = fileEntries.filter(item => item.name.toLocaleLowerCase().includes(filter));
  for (const item of matches) {
    const button = document.createElement('button');
    const name = document.createElement('span'); name.textContent = item.name;
    const tag = document.createElement('span');
    tag.textContent = item.kind === 'directory' ? '폴더 ›' : item.kind === 'subtitle' ? '자막' : '동영상';
    button.append(name, tag);
    button.onclick = () => {
      if (item.kind === 'directory') {
        fileTrail.push({ id:item.id, name:item.name });
        $('#files-filter').value = ''; loadFiles();
      } else if (item.kind === 'video') {
        selectedMovie = { id:item.id, title:item.name };
        $('#movie-name').textContent = item.name;
        $('#movie-options').hidden = false;
        $('#subtitle-panel').hidden = true;
        fileMessage('재생 앱이나 자막 옵션을 선택하세요.');
      } else if (item.kind === 'subtitle' && selectedMovie) {
        applySubtitle(item.id);
      } else {
        fileMessage('동영상을 선택한 다음 자막을 고르세요.');
      }
    };
    list.appendChild(button);
  }
  if (!matches.length) {
    const empty = document.createElement('p'); empty.className = 'note';
    empty.textContent = filter ? '검색과 일치하는 파일이 없습니다.' : '이 위치에 재생할 파일이나 폴더가 없습니다.';
    list.appendChild(empty);
  }
}
$('#open-files').onclick = () => {
  haptic('tick'); $('#apps-sheet').classList.remove('show'); $('#files-sheet').classList.add('show');
  fileTrail = []; fileEntries = []; fileNext = null; $('#files-filter').value = '';
  selectedMovie = currentLocalMovie;
  $('#movie-options').hidden = !selectedMovie; $('#subtitle-panel').hidden = true;
  if (selectedMovie) $('#movie-name').textContent = selectedMovie.title;
  updateMovieOptions(); loadFiles();
};
$('#files-back').onclick = () => { if (fileTrail.length) { fileTrail.pop(); $('#files-filter').value = ''; loadFiles(); } };
$('#files-filter').addEventListener('input', renderFiles);
$('#files-more').onclick = () => { if (fileNext != null) loadFiles(true); };
async function playFile(player) {
  if (!selectedMovie) return;
  try {
    fileMessage('동영상을 여는 중…');
    await api('/files/play', { id:selectedMovie.id, player });
    fileMessage(player === 'iina' ? 'Mac의 IINA에 재생을 요청했습니다.' : 'CouchDial에 재생을 요청했습니다.');
    refresh();
  } catch (e) { fileMessage(remoteText(e.message), true); }
}
$('#play-native').onclick = () => playFile('native');
$('#play-iina').onclick = () => playFile('iina');
async function applySubtitle(id) {
  if (!selectedMovie) return;
  try { await api('/files/subtitle', { movie:selectedMovie.id, subtitle:id }); fileMessage('IINA에서 자막과 함께 재생하는 중…'); }
  catch (e) { fileMessage(remoteText(e.message), true); }
}
$('#subtitle-options').onclick = async () => {
  if (!selectedMovie) return;
  $('#subtitle-panel').hidden = false;
  const list = $('#subtitle-list'); list.textContent = '';
  try {
    const data = await api(`/files/subtitles?movie=${encodeURIComponent(selectedMovie.id)}`);
    for (const item of data.entries || []) {
      const button = document.createElement('button'); button.textContent = item.name;
      button.onclick = () => applySubtitle(item.id); list.appendChild(button);
    }
    if (!list.childElementCount) { const note = document.createElement('p'); note.className = 'note'; note.textContent = '동영상과 같은 폴더에 자막이 없습니다.'; list.appendChild(note); }
  } catch (e) { fileMessage(remoteText(e.message), true); }
};
$('#subtitle-upload').onchange = async e => {
  const input = e.target, file = input.files[0];
  if (!file || !selectedMovie) return;
  try {
    if (!/\.srt$/i.test(file.name) || !file.size || file.size > 256 * 1024) throw new Error('내용이 있는 256KB 이하의 .srt 파일을 선택하세요.');
    const content = new TextDecoder('utf-8', { fatal:true }).decode(await file.arrayBuffer());
    await api('/files/subtitle-upload', { movie:selectedMovie.id, name:file.name, content });
    fileMessage('자막을 올렸습니다. IINA에서 동영상을 여는 중…');
  } catch (err) { fileMessage(err.message === 'unpaired' ? '먼저 CouchDial에 연결하세요.' : err.message, true); }
  finally { input.value = ''; }
};
$('#subtitle-search-iina').onclick = async () => {
  if (!selectedMovie) return;
  try { await api('/files/subtitle-search', { movie:selectedMovie.id }); fileMessage('IINA에 자막 검색을 요청했습니다.'); }
  catch (e) { fileMessage(remoteText(e.message), true); }
};
$('#subtitle-search-web').onclick = () => {
  if (!selectedMovie) return;
  window.open('https://www.opensubtitles.org/en/search/sublanguageid-all/moviename-' + encodeURIComponent(selectedMovie.title.replace(/\.(mp4|m4v|mov|mkv|webm|avi|wmv|flv|ts|m2ts|mts|mpg|mpeg|3gp)$/i, '')), '_blank', 'noopener,noreferrer');
  fileMessage('휴대전화에서 자막을 받은 다음 .srt 파일을 여기에 올리세요.');
};

function openAdd() {
  $('#apps-sheet').classList.remove('show');
  $('#add-sheet').classList.add('show');
  $('#add-msg').textContent = '';
  $('#add-msg').className = 'note';
  addTab('web');
}
function addTab(which) {
  $('#add-web-tab').classList.toggle('on', which === 'web');
  $('#add-mac-tab').classList.toggle('on', which === 'mac');
  $('#web-form').hidden = which !== 'web';
  $('#mac-form').hidden = which !== 'mac';
  if (which === 'mac') searchMac();
}
$('#add-web-tab').onclick = () => { haptic('tick'); addTab('web'); };
$('#add-mac-tab').onclick = () => { haptic('tick'); addTab('mac'); };

function added(result) {
  haptic('tap');
  const msg = $('#add-msg');
  msg.className = 'note ok';
  msg.textContent = `${result.name}이(가) TV에 추가되었습니다.`;
  refresh();
  setTimeout(() => { closeSheets(); }, 1400);
}
function failed(e) {
  haptic('error');
  const msg = $('#add-msg');
  msg.className = 'note err';
  msg.textContent = remoteText(e.message);
}
$('#web-form').onsubmit = e => {
  e.preventDefault();
  const url = $('#web-url').value.trim();
  if (!url) { failed(new Error('웹사이트 주소를 입력하세요.')); return; }
  $('#add-msg').className = 'note';
  $('#add-msg').textContent = '추가 중…';
  api('/apps/add', { url, name: $('#web-name').value.trim() }).then(r => {
    $('#web-url').value = ''; $('#web-name').value = '';
    added(r);
  }).catch(failed);
};

let macTimer = 0;
$('#mac-q').addEventListener('input', () => { clearTimeout(macTimer); macTimer = setTimeout(searchMac, 200); });
async function searchMac() {
  try {
    const list = await api(`/macapps?q=${encodeURIComponent($('#mac-q').value)}`);
    const box = $('#mac-list');
    box.textContent = '';
    for (const app of list) {
      const b = document.createElement('button');
      const name = document.createElement('span');
      name.textContent = app.name;
      const tag = document.createElement('span');
      tag.textContent = app.added ? '추가됨' : '추가';
      b.append(name, tag);
      b.disabled = app.added;
      b.onclick = () => api('/apps/add', { bundleID: app.bundleID }).then(added).catch(failed);
      box.appendChild(b);
    }
    if (!list.length) box.innerHTML = '<p class="note">검색과 일치하는 앱이 없습니다.</p>';
  } catch (e) { failed(e); }
}

// A six-digit code is exchanged once for a separate device credential.
function showPair() { if ($('#pair').classList.contains('show')) return; $('#pair').classList.add('show'); setTimeout(() => $('#code').focus(), 50); }
async function pair(code, name) {
  const data = await request('/pair', { code, name }, false);
  key = data.token;
  store.set(key);
  $('#pair').classList.remove('show');
  $('#pair-err').textContent = '';
  $('#code').value = '';
  return refresh();
}
$('#pair-btn').onclick = async () => {
  try { await pair($('#code').value.trim(), $('#device-name').value.trim()); haptic('tap'); }
  catch (e) {
    haptic('error');
    $('#pair-err').textContent = e.status === 401 ? '코드가 틀렸거나 만료되었습니다. 맥 화면의 코드를 확인하세요.'
      : e.status === 429 ? '여러 번 실패했습니다. 1분 뒤 다시 시도하세요.'
      : '연결하지 못했습니다. 맥북과 아이폰이 같은 Wi-Fi에 연결되어 있는지 확인하세요.';
  }
};
// A list row: a name with a detail under it, and its buttons on the right.
function itemRow(title, detail, buttons) {
  const row = document.createElement('div');
  row.className = 'row item';
  const text = document.createElement('span'); text.className = 'text';
  const name = document.createElement('span'); name.textContent = title; text.appendChild(name);
  if (detail) { const sub = document.createElement('span'); sub.className = 'detail'; sub.textContent = detail; text.appendChild(sub); }
  const actions = document.createElement('div'); actions.className = 'item-actions';
  actions.append(...buttons);
  row.append(text, actions);
  return row;
}
function linkButton(label, onClick, danger = false, aria = '') {
  const button = document.createElement('button');
  button.className = danger ? 'link danger' : 'link';
  button.textContent = label;
  if (aria) button.setAttribute('aria-label', aria);
  button.onclick = onClick;
  return button;
}
const countLabel = count => count ? String(count) : '없음';

async function loadDevices() {
  const box = $('#devices');
  try {
    const devices = await api('/devices');
    box.replaceChildren(...devices.map(device => itemRow(device.name + (device.current ? ' · 이 기기' : ''),
      device.guest ? `게스트 · ${new Date(device.expiresAt).toLocaleString('ko-KR', { dateStyle: 'medium', timeStyle: 'short' })}까지` : '',
      [linkButton('제거', async () => {
        if (!confirm(`${device.name} 기기를 제거할까요?`)) return;
        try {
          await api('/devices/revoke', { id: device.id });
          if (device.current) { key = ''; store.set(''); closeSheets(); showPair(); }
          else await loadDevices();
        } catch (e) { $('#devices-msg').textContent = remoteText(e.message); }
      }, true, `${device.name} 제거`)])));
    box.hidden = devices.length === 0;
    $('#devices-count').textContent = countLabel(devices.length);
    $('#revoke-all').hidden = false;
    $('#devices-msg').textContent = '';
  } catch (e) {
    box.replaceChildren();
    $('#revoke-all').hidden = true;
    $('#devices-msg').textContent = remoteText(e.message);
  }
}
let sharesPoll = 0;
async function loadShares() {
  const box = $('#shares');
  let list;
  try { list = await api('/shares'); } catch (e) { $('#shares-msg').textContent = remoteText(e.message); return; }
  box.replaceChildren(...list.map(share => {
    const buttons = [];
    if (!share.connected && !share.connecting) {
      buttons.push(linkButton('연결', async () => { try { await api('/shares/connect', { id: share.id }); } catch {} watchShares(); }));
    }
    buttons.push(linkButton('제거', async () => {
      if (!confirm(`CouchDial에서 ${share.name} 공유 폴더를 제거할까요?`)) return;
      try { await api('/shares/remove', { id: share.id }); } catch (e) { $('#shares-msg').textContent = remoteText(e.message); }
      loadShares();
    }, true, `${share.name} 제거`));
    const row = itemRow(share.name, remoteText(share.status), buttons);
    row.title = share.address || '';
    return row;
  }));
  box.hidden = list.length === 0;
  $('#shares-count').textContent = countLabel(list.length);
  return list;
}
// Connecting takes a few seconds: refresh the list until it settles.
function watchShares() {
  clearTimeout(sharesPoll);
  let tries = 0;
  const tick = async () => {
    const list = await loadShares();
    if (list && list.some(share => share.connecting) && ++tries < 50) sharesPoll = setTimeout(tick, 1500);
  };
  tick();
}
$('#share-form').onsubmit = async e => {
  e.preventDefault();
  const address = $('#share-address').value.trim();
  if (!address) { $('#shares-msg').textContent = '공유 폴더 주소를 입력하세요. 예: nas.local/Movies'; return; }
  try {
    await api('/shares/add', { address, user: $('#share-user').value.trim(), password: $('#share-password').value });
    $('#share-address').value = ''; $('#share-password').value = '';
    $('#shares-msg').textContent = '동영상은 CouchDial의 동영상 메뉴에 표시됩니다.';
    haptic('tap');
  } catch (err) { $('#shares-msg').textContent = remoteText(err.message); haptic('error'); }
  watchShares();
};
let jellyfinPoll = 0;
const jellyfinNote = '동영상은 CouchDial의 동영상 메뉴에 표시됩니다.';
async function loadJellyfin() {
  const box = $('#jellyfin');
  let reply;
  try { reply = await api('/jellyfin'); } catch (e) { $('#jellyfin-msg').textContent = remoteText(e.message); return; }
  box.replaceChildren(...reply.servers.map(server => {
    const row = itemRow(server.name, remoteText(server.status), [linkButton('제거', async () => {
      if (!confirm(`${server.name}에서 로그아웃하고 CouchDial에서 제거할까요?`)) return;
      try { await api('/jellyfin/remove', { id: server.id }); } catch (e) { $('#jellyfin-msg').textContent = remoteText(e.message); }
      loadJellyfin();
    }, true, `${server.name} 제거`)]);
    row.title = `${server.address}의 ${server.user}`;
    return row;
  }));
  box.hidden = reply.servers.length === 0;
  $('#jellyfin-count').textContent = countLabel(reply.servers.length);
  if (reply.signingIn) $('#jellyfin-msg').textContent = '로그인 중…';
  return reply;
}
// Signing in takes a moment: check until it's done, then say how it went.
function watchJellyfin() {
  clearTimeout(jellyfinPoll);
  let tries = 0;
  const tick = async () => {
    const reply = await loadJellyfin();
    if (!reply) return;
    if (reply.signingIn && ++tries < 40) { jellyfinPoll = setTimeout(tick, 1000); return; }
    if (reply.error) { $('#jellyfin-msg').textContent = remoteText(reply.error); haptic('error'); }
    else { $('#jellyfin-msg').textContent = jellyfinNote; $('#jellyfin-password').value = ''; }
  };
  tick();
}
$('#jellyfin-form').onsubmit = async e => {
  e.preventDefault();
  const address = $('#jellyfin-address').value.trim();
  const user = $('#jellyfin-user').value.trim();
  if (!address || !user) { $('#jellyfin-msg').textContent = '서버 주소와 사용자 이름을 입력하세요.'; return; }
  try {
    await api('/jellyfin/add', { address, user, password: $('#jellyfin-password').value });
    haptic('tap');
  } catch (err) { $('#jellyfin-msg').textContent = remoteText(err.message); haptic('error'); return; }
  watchJellyfin();
};
$('#revoke-all').onclick = async () => {
  if (!confirm('이 기기를 포함해 연결된 모든 기기를 제거할까요?')) return;
  try { await api('/devices/revoke-all', {}); key = ''; store.set(''); closeSheets(); showPair(); }
  catch (e) { $('#devices-msg').textContent = remoteText(e.message); }
};

// Buttons
const seekButtons = document.querySelectorAll('[data-seek]');
function updateSeekButtons(available) {
  for (const button of seekButtons) {
    const action = button.dataset.seek;
    button.dataset.a = available ? action + '15' : action;
    button.classList.toggle('youtube-seek', available);
    button.querySelector('.seek-seconds').hidden = !available;
    button.setAttribute('aria-label', (available ? '15초' : '10초') + (action === 'rewind' ? ' 뒤로' : ' 앞으로'));
  }
}
document.querySelectorAll('[data-a]').forEach(b => b.addEventListener('click', () => {
  if (b.dataset.a === 'home') updateSeekButtons(false);
  send(b.dataset.a, {}, b.dataset.h || 'tick');
}));
$('#browser-retry').onclick = () => send('retrybrowser', {}, 'tap').then(refresh);
let websiteOpening = false;
$('#open-website').onsubmit = async e => {
  e.preventDefault();
  if (websiteOpening) return;
  const input = $('#website-address'), note = $('#website-open-error');
  const url = input.value.trim();
  if (!url) { note.textContent = '웹사이트 주소를 입력하세요.'; note.hidden = false; return; }
  websiteOpening = true;
  $('#website-go').disabled = true;
  note.hidden = true;
  try {
    await api('/browser/open', { url });
    input.value = '';
    haptic('tap');
    await refresh();
  } catch (error) {
    if (error.message !== 'unpaired') {
      note.textContent = remoteText(error.message) || '웹사이트를 열지 못했습니다.';
      note.hidden = false;
      haptic('error');
    }
  } finally {
    websiteOpening = false;
    $('#website-go').disabled = false;
  }
};
$('#type').onsubmit = e => {
  e.preventDefault();
  const t = $('#typed').value;
  if (t) send('text', { t }, 'tap');
  $('#typed').value = '';
};

// Sheets
const closeSheets = () => {
  const closingText = $('#text-sheet').classList.contains('show');
  document.querySelectorAll('.scrim').forEach(s => s.classList.remove('show'));
  if (closingText) $('#open-text').focus();
  if (editing) { editing = false; renderApps(); }
};
document.querySelectorAll('.scrim').forEach(s => s.addEventListener('click', e => { if (e.target === s) closeSheets(); }));
document.querySelectorAll('[data-close]').forEach(b => b.onclick = closeSheets);
$('#open-text').onclick = () => { haptic('tick'); $('#text-sheet').classList.add('show'); $('#text-sheet [data-close]').focus(); };
$('#open-apps').onclick = () => { haptic('tick'); refresh(); $('#apps-sheet').classList.add('show'); };
$('#open-power').onclick = () => { haptic('tick'); resetSleep(); showPage('settings-main'); refresh(); loadDevices(); loadShares(); loadJellyfin(); $('#power-sheet').classList.add('show'); };
// Settings opens sub-pages in place, each with a way back.
function showPage(id) {
  document.querySelectorAll('#power-sheet .page').forEach(page => { page.hidden = page.id !== id; });
  $('#power-sheet .sheet').scrollTop = 0;
  if (id === 'page-display') refreshBrightness();
}
document.querySelectorAll('#power-sheet [data-page]').forEach(row => row.onclick = () => { haptic('tick'); showPage(row.dataset.page); });
document.querySelectorAll('#power-sheet [data-back]').forEach(back => back.onclick = () => { haptic('tick'); showPage('settings-main'); });
document.querySelectorAll('#sleep-chips button').forEach(b => b.onclick = () => {
  const m = Number(b.dataset.m);
  send('sleeptimer', { m }, 'tap').then(refresh);
  showSleep(m);
});
async function chooseDisplay(display) {
  if (displayChanging || !remoteReachable) return;
  const note = $('#display-msg');
  displayChanging = true;
  note.hidden = true;
  updateDisplays({ displays: availableDisplays.map(item => ({ ...item, preferred: item === display })) });
  try {
    await api('/display/select', { id: display.id });
    haptic('tap');
  } catch (error) {
    if (error.message !== 'unpaired') {
      note.textContent = remoteText(error.message) || '재생 화면을 변경하지 못했습니다.';
      note.className = 'footnote err';
      note.hidden = false;
      haptic('error');
    }
  } finally {
    displayChanging = false;
    await refresh();
  }
}
async function choosePlayer(player) {
  const note = $('#browser-msg');
  note.hidden = true;
  try {
    await api('/browser/preference', { player });
    haptic('tap');
  } catch (error) {
    if (error.message !== 'unpaired') {
      note.textContent = remoteText(error.message) || '웹사이트 재생 앱을 변경하지 못했습니다.';
      note.hidden = false;
      haptic('error');
    }
  }
  await refresh();
}
$('#auto-skip').onchange = e => send('setting', { k: 'autoSkip', v: e.target.checked });
$('#auto-next').onchange = e => send('setting', { k: 'autoNext', v: e.target.checked });
$('#keep-awake').onchange = e => send('setting', { k: 'keepMacAwake', v: e.target.checked });
$('#lid-override').onchange = e => send('setting', { k: 'lidOverride', v: e.target.checked });
function showSleep(minutes) {
  document.querySelectorAll('#sleep-chips button').forEach(b => b.classList.toggle('on', Number(b.dataset.m) === (minutes ? -1 : 0)));
  $('#sleep-left').textContent = minutes ? `${minutes}분 뒤 재생이 멈추고 화면이 꺼집니다.` : '';
  $('#sleep-left').hidden = !minutes;
  if (minutes) document.querySelectorAll('#sleep-chips button').forEach(b => b.classList.toggle('on', b.dataset.m !== '0' && Number(b.dataset.m) >= minutes && Number(b.dataset.m) - minutes < 15));
}
$('#screen-on').onclick = () => { closeSheets(); send('screenon', {}, 'tap'); };
$('#screen-off').onclick = () => { closeSheets(); send('screenoff', {}, 'tap'); };

let sleepArmed = false;
function resetSleep() { sleepArmed = false; $('#sleep').classList.remove('armed'); $('#sleep').textContent = 'Mac 잠자기'; }
$('#sleep').onclick = () => {
  if (!sleepArmed) { sleepArmed = true; haptic('tick'); $('#sleep').classList.add('armed'); $('#sleep').textContent = '한 번 더 눌러 Mac을 잠자기 상태로 전환'; return; }
  closeSheets(); send('sleep', {}, 'tap');
};

// Tabs
function tab(which) {
  $('#tab-click').classList.toggle('on', which === 'click');
  $('#tab-touch').classList.toggle('on', which === 'touch');
  $('#clickpad').style.display = which === 'click' ? 'block' : 'none';
  $('#touchpad').style.display = which === 'touch' ? 'block' : 'none';
  try { localStorage.setItem('mactvTab', which); } catch {}
}
$('#tab-click').onclick = () => { haptic('tick'); tab('click'); };
$('#tab-touch').onclick = () => { haptic('tick'); tab('touch'); };
try { if (localStorage.getItem('mactvTab') === 'touch') tab('touch'); } catch {}

// Clickpad: tap an arrow on the ring or swipe anywhere; hold an arrow to repeat; tap the middle
// for OK. Taps outside the ring do nothing.
(() => {
  const pad = $('#clickpad');
  pad.querySelectorAll('button').forEach(button => button.addEventListener('click', e => {
    // Pointer gestures are handled below; keyboard/assistive activation produces detail=0.
    if (e.detail === 0) send(button.dataset.dir || 'ok', {}, 'tap');
  }));
  let start = null, timer = null, repeated = false;
  const zoneAt = (x, y) => {
    const r = pad.getBoundingClientRect();
    const cx = x - (r.left + r.width / 2), cy = y - (r.top + r.height / 2);
    const distance = Math.hypot(cx, cy);
    if (distance < $('#ok').getBoundingClientRect().width / 2 + 8) return 'ok';
    if (distance > pad.querySelector('.ring').getBoundingClientRect().width / 2 + 6) return null;
    return Math.abs(cx) > Math.abs(cy) ? (cx > 0 ? 'right' : 'left') : (cy > 0 ? 'down' : 'up');
  };
  const flash = zone => {
    const el = zone === 'ok' ? $('#ok') : pad.querySelector(`[data-dir="${zone}"]`);
    el.classList.add('hit');
    setTimeout(() => el.classList.remove('hit'), 140);
  };
  const stop = () => { clearTimeout(timer); clearInterval(timer); timer = null; };
  pad.addEventListener('pointerdown', e => {
    pad.setPointerCapture(e.pointerId);
    start = { x: e.clientX, y: e.clientY, zone: zoneAt(e.clientX, e.clientY), okHeld: false };
    repeated = false;
    if (start.zone === 'ok') {
      // Holding OK only means something in Arrange Apps (hold to remove), and only once the thumb has
      // stayed put for a moment: a swipe that starts in the middle is still a swipe, and a tap an OK.
      if (tvSheet === 'arrange-apps') {
        timer = setTimeout(() => {
          if (!start) return;
          start.okHeld = true;
          flash('ok');
          send('okdown', {}, 'tap');
        }, 200);
      }
    } else if (start.zone) {
      timer = setTimeout(() => {
        repeated = true;
        timer = setInterval(() => { flash(start.zone); send(start.zone, {}, 'repeat'); }, 130);
      }, 420);
    }
  });
  pad.addEventListener('pointermove', e => {
    if (!start || Math.hypot(e.clientX - start.x, e.clientY - start.y) <= 24) return;
    stop();
    // Moving away lets go of a hold, and the gesture carries on as a swipe.
    if (start.okHeld) { start.okHeld = false; send('okup', {}, 'tap'); }
  });
  pad.addEventListener('pointerup', e => {
    if (!start) return;
    stop();
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    const okHeld = start.okHeld;
    let zone = start.zone;
    start = null;
    if (okHeld) {
      send('okup', {}, 'tap');
      return;
    }
    if (Math.hypot(dx, dy) > 28) zone = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up');
    else if (repeated || !zone) return;
    flash(zone);
    send(zone, {}, zone === 'ok' ? 'tap' : 'tick');
  });
  const cancelHold = () => {
    if (start?.okHeld) send('okup', {}, 'tap');
    stop();
    start = null;
  };
  pad.addEventListener('pointercancel', cancelHold);
  pad.addEventListener('lostpointercapture', cancelHold);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState !== 'visible') cancelHold(); });
})();

// Touchpad: one finger moves the pointer, tap clicks, two fingers scroll.
(() => {
  const tp = $('#touchpad');
  const fingers = new Map();
  let travel = 0, downAt = 0, multi = false, timer = 0, inFlight = null;
  let acc = { dx: 0, dy: 0, sy: 0 };
  const flush = () => {
    clearTimeout(timer);
    timer = 0;
    if (inFlight) return inFlight;
    inFlight = (async () => {
      // Keep fractional remainders so frequent small movements are not rounded away.
      while (true) {
        const dx = Math.round(acc.dx), dy = Math.round(acc.dy), sy = Math.round(acc.sy * -3);
        if (!dx && !dy && !sy) break;
        acc.dx -= dx; acc.dy -= dy; acc.sy += sy / 3;
        // One request at a time, including when a gesture changes from moving to scrolling.
        if (dx || dy) await api('/cmd', { a: 'pointer', dx, dy }).catch(() => {});
        if (sy) await api('/cmd', { a: 'scroll', dy: sy }).catch(() => {});
      }
    })().finally(() => { inFlight = null; });
    return inFlight;
  };
  tp.addEventListener('pointerdown', e => {
    tp.setPointerCapture(e.pointerId);
    if (fingers.size === 0) { travel = 0; downAt = Date.now(); multi = false; }
    fingers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (fingers.size > 1) multi = true;
  });
  tp.addEventListener('pointermove', e => {
    const f = fingers.get(e.pointerId);
    if (!f) return;
    const dx = e.clientX - f.x, dy = e.clientY - f.y;
    f.x = e.clientX; f.y = e.clientY;
    travel += Math.abs(dx) + Math.abs(dy);
    if (fingers.size > 1) acc.sy += dy / fingers.size;
    else { const gain = 1.6 + Math.min(Math.hypot(dx, dy) / 6, 3); acc.dx += dx * gain; acc.dy += dy * gain; }
    if (!timer) timer = setTimeout(flush, 33);
  });
  const lift = e => {
    if (!fingers.delete(e.pointerId)) return;
    if (fingers.size === 0 && e.type === 'pointerup' && !multi && travel < 8 && Date.now() - downAt < 300) {
      // Deliver the last movement before the tap, even on a slow connection.
      flush().then(() => send('click', {}, 'tap'));
    }
  };
  tp.addEventListener('pointerup', lift);
  tp.addEventListener('pointercancel', lift);
})();

// Old installations stored the shared six-digit code; exchange it automatically during migration.
const initialCode = /^\d{6}$/.test(qrCode) ? qrCode : (/^\d{6}$/.test(key) ? key : '');
if (initialCode) {
  if (/^\d{6}$/.test(key)) { key = ''; store.set(''); }
  pair(initialCode, 'Phone').catch(() => { $('#code').value = ''; showPair(); });
} else { refresh(); }
setInterval(() => {
  if (document.visibilityState !== 'visible') return;
  refresh();
}, 3000);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') refresh(); });
