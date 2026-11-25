// Run with Node 22+: node Tests/WebPlayback/layout.test.cjs
// Render the real remote in an isolated headless browser; no app or user profile is touched.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const candidates = [process.env.BROWSER_BIN, '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser', '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'];
const browser = candidates.find(file => file && fs.existsSync(file));
if (!browser) { console.log('SKIP remote layout: set BROWSER_BIN or install Chrome/Brave'); process.exit(0); }
if (!globalThis.WebSocket) { console.error('Remote layout test requires Node 22 or newer'); process.exit(1); }
const { html } = require('./page.cjs');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, 'remote controls have unique IDs');
const screenshotDir = process.env.MACTV_LAYOUT_SCREENSHOTS;
if (screenshotDir) fs.mkdirSync(screenshotDir, { recursive: true });
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mactv-layout-'));
fs.chmodSync(profile, 0o700);
const server = http.createServer((req, res) => {
  if (req.url === '/appicon.png') { res.writeHead(200, { 'Content-Type': 'image/png' }); res.end(fs.readFileSync('Assets/AppIcon.png')); return; }
  res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(html);
});
let child, socket, closeBrowser;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function run() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  child = spawn(browser, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0',
    `--user-data-dir=${profile}`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
  const port = await new Promise((resolve, reject) => {
    let data = ''; const timer = setTimeout(() => reject(new Error('Browser did not start')), 15000);
    child.on('error', error => { clearTimeout(timer); reject(error); });
    child.on('exit', code => { clearTimeout(timer); reject(new Error(`Browser exited: ${code}`)); });
    child.stderr.on('data', chunk => { data += chunk; const m = data.match(/DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//); if (m) { clearTimeout(timer); resolve(m[1]); } });
  });
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let seq = 0; const pending = new Map();
  socket.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP ${method} timed out`)); }, 5000);
    pending.set(id, m => { clearTimeout(timer); m.error ? reject(new Error(m.error.message)) : resolve(m.result); });
    socket.send(JSON.stringify({ id, method, params }));
  });
  closeBrowser = () => call('Browser.close');
  const screenshot = async name => {
    if (!screenshotDir) return;
    const result = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    fs.writeFileSync(path.join(screenshotDir, name), Buffer.from(result.data, 'base64'));
  };
  const evaluate = async expression => {
    const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
    return result.result.value;
  };
  await call('Page.enable'); await call('Runtime.enable');
  await call('Page.addScriptToEvaluateOnNewDocument', { source: `
    localStorage.setItem('mactvKey', 'a'.repeat(64));
    window.testState = { apps: [], autoSkip: false, autoNext: false,
      keepMacAwake: false, lidOverride: false, displaySetup: { displays: [] },
      speakerVolume: { id:13, name:'MacBook Air Speakers', value:42, muted:false } };
    window.sentCommands = [];
    window.volumeWrites = [];
    window.remoteOffline = false;
    window.brightness = [{ id:'built-in', name:'Built-in Retina Display', value:35, method:'builtIn' },
      { id:'lg', name:'LG HDR 4K', value:50, method:'betterDisplay' },
      { id:'unavailable', name:'Other display', error:'No brightness available' }];
    window.brightnessWrites = [];
    window.fetch = async (path, options) => {
      if (window.remoteOffline) throw new Error('Disconnected');
      if (path === '/cmd') window.sentCommands.push(JSON.parse(options.body).a);
      if (path === '/audio/volume') {
        const write = JSON.parse(options.body);
        window.volumeWrites.push(write);
        const value = { value:write.value, muted:false };
        Object.assign(window.testState.speakerVolume, value);
        return { status:200, ok:true, json:async () => value };
      }
      if (path === '/display/brightness') {
        if (options.method === 'GET') return { status:200, ok:true, json:async () => window.brightness };
        const write = JSON.parse(options.body);
        window.brightnessWrites.push(write);
        window.brightness.find(display => display.id === write.id).value = write.value;
        return { status:200, ok:true, json:async () => ({ value:write.value }) };
      }
      return { status: 200, ok: true, json: async () => path === '/state' ? window.testState : [] };
    };
  ` });
  await call('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/` });
  await delay(500);
  const sizes = [[320,568],[375,667],[390,844],[430,932],[568,320],[844,390]];
  for (const [width, height] of sizes) {
    await call('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
    for (const mode of ['none', 'embedded', 'brave', 'iina']) {
      const geometry = await evaluate(`(async () => {
        testState.mode = ${mode === 'none' ? "'launcher'" : "'player'"};
        testState.externalBrowser = ${mode === 'brave' ? "{name:'Brave',service:'Video',accessibilityAllowed:true}" : 'null'};
        testState.externalPlayer = ${mode === 'iina' ? "{name:'IINA',status:'Playing'}" : 'null'};
        await refresh();
        const r = e => { const x=e.getBoundingClientRect(); return {w:x.width,h:x.height,top:x.top,bottom:x.bottom}; };
        return { ring:r(document.querySelector('#clickpad .ring')), keys:[...document.querySelectorAll('.key')].map(r),
          arrows:[...document.querySelectorAll('#clickpad .chev, #clickpad .ok')].map(r),
          tool:r(document.querySelector('#open-text')), scroll:document.documentElement.scrollWidth,
          viewport:innerWidth, height:innerHeight, page:document.documentElement.scrollHeight,
          controls: ${mode === 'brave' ? "!document.querySelector('#browser-controls').hidden" : mode === 'iina' ? "!document.querySelector('#iina-controls').hidden" : 'true'} };
      })()`);
      const label = `${width}x${height} ${mode}`;
      assert.ok(Math.abs(geometry.ring.w - geometry.ring.h) < 1 && geometry.ring.w >= 100, `${label}: circular D-pad`);
      for (const key of geometry.keys) assert.ok(Math.abs(key.w-key.h) < 1 && key.w >= 44 && key.h >= 44, `${label}: circular 44px media key`);
      for (const arrow of geometry.arrows) assert.ok(arrow.w >= 44 && arrow.h >= 44, `${label}: 44px D-pad target`);
      assert.ok(geometry.scroll <= geometry.viewport + 1, `${label}: no horizontal overflow`);
      assert.ok(geometry.controls, `${label}: active controls visible`);
      const home = await evaluate(`(async () => {
        const button = document.querySelector('[data-a="home"]');
        const before = sentCommands.length;
        const rect = button.getBoundingClientRect();
        button.click();
        await new Promise(resolve => setTimeout(resolve, 0));
        return { label: button.textContent.trim(), width: rect.width, height: rect.height,
          displayed: getComputedStyle(button).display !== 'none', action: sentCommands[before] };
      })()`);
      assert.equal(home.label, '홈', `${label}: Home is visibly labeled`);
      assert.ok(home.displayed && home.width >= 44 && home.height >= 44, `${label}: Home stays available`);
      assert.equal(home.action, 'home', `${label}: Home sends its command`);
      if (width === 320 && height === 568 && (mode === 'none' || mode === 'brave')) await screenshot(`320x568-${mode}.png`);
      if (mode === 'none' && height > width) assert.ok(geometry.tool.bottom <= geometry.height + 1, `${label}: portrait controls fit`);
      if (mode === 'none' && height < width) assert.ok(geometry.page >= geometry.tool.bottom, `${label}: landscape controls scroll into view`);
    }
    const sheet = await evaluate(`(() => {
      document.querySelector('#open-text').click();
      const visible = s => { const e=document.querySelector(s), r=e.getBoundingClientRect(); return !!r.width && !!r.height && getComputedStyle(e).visibility !== 'hidden'; };
      const result = { visible: visible('#text-sheet'), website: visible('#website-address'), typing: visible('#typed'),
        websiteLabel: document.querySelector('#website-address').getAttribute('aria-label'),
        typingLabel: document.querySelector('#typed').getAttribute('aria-label'),
        width: document.documentElement.scrollWidth, viewport: innerWidth };
      return result;
    })()`);
    assert.ok(sheet.visible && sheet.website && sheet.typing && sheet.websiteLabel && sheet.typingLabel, `${width}x${height}: accessible text sheet`);
    assert.ok(sheet.width <= sheet.viewport + 1, `${width}x${height}: sheet does not overflow`);
    if (width === 390 && height === 844) await screenshot('390x844-text-sheet.png');
    await evaluate(`document.querySelector('#text-sheet [data-close]').click()`);
    if (width === 390 && height === 844) {
      const brightness = await evaluate(`(async () => {
        document.querySelector('#open-power').click();
        document.querySelector('[data-page="page-display"]').click();
        const settle = () => new Promise(resolve => setTimeout(resolve, 0));
        await settle();
        const [builtIn, lg, unavailable] = [...document.querySelectorAll('#display-brightness input')];
        const wasEditable = !builtIn.disabled && !lg.disabled;
        const presets = [...lg.closest('.brightness-row').querySelectorAll('button')];
        const presetNames = presets.map(button => button.textContent);
        const disabledPresets = [...unavailable.closest('.brightness-row').querySelectorAll('button')].every(button => button.disabled);
        presets[1].click();
        await settle();
        const selected = presets.find(button => button.getAttribute('aria-pressed') === 'true')?.textContent;
        const track = lg.parentElement;
        track.scrollIntoView({block:'center'});
        const rect = track.getBoundingClientRect();
        return { wasEditable, unavailableDisabled:unavailable.disabled && disabledPresets,
          label:lg.getAttribute('aria-label'), presetNames, selected, writes:brightnessWrites, lgValue:lg.value,
          track:{ left:rect.left, width:rect.width, y:rect.top + rect.height / 2 } };
      })()`);
      assert.ok(brightness.wasEditable && brightness.unavailableDisabled, 'only confirmed brightness is editable');
      assert.equal(brightness.label, 'LG HDR 4K (BetterDisplay) 밝기');
      assert.deepEqual(brightness.presetNames, ['0%', '25%', '50%', '75%', '100%']);
      assert.equal(brightness.selected, '25%');
      assert.deepEqual(brightness.writes, [{ id:'lg', value:25, method:'betterDisplay' }]);
      assert.equal(brightness.lgValue, '25');

      const touch = (type, percent) => call('Input.dispatchTouchEvent', {
        type, touchPoints: percent === undefined ? [] : [{
          x:brightness.track.left + brightness.track.width * percent / 100, y:brightness.track.y, id:1,
        }],
      });
      await touch('touchStart', 25);
      await delay(400);
      await touch('touchMove', 62);
      assert.equal(await evaluate("document.querySelectorAll('#display-brightness input')[1].value"), '62');
      assert.equal(await evaluate('brightnessWrites.length'), 1, 'a held drag shows a preview without writing');
      await touch('touchEnd');
      await delay(100);
      assert.deepEqual(await evaluate('brightnessWrites.at(-1)'), { id:'lg', value:62, method:'betterDisplay' });

      await touch('touchStart', 76);
      await touch('touchEnd');
      await delay(100);
      assert.deepEqual(await evaluate('brightnessWrites.at(-1)'), { id:'lg', value:75, method:'betterDisplay' });

      await evaluate("document.querySelectorAll('#display-brightness .brightness-row')[1].querySelectorAll('button')[4].click()");
      await delay(100);
      assert.deepEqual(await evaluate('brightnessWrites.at(-1)'), { id:'lg', value:100, method:'betterDisplay' });

      await touch('touchStart', 95);
      await delay(400);
      await touch('touchMove', 47);
      await touch('touchCancel');
      assert.equal(await evaluate('brightnessWrites.length'), 4, 'cancelling a gesture discards its preview');
      assert.equal(await evaluate("document.querySelectorAll('#display-brightness input')[1].value"), '100');
      assert.equal(await evaluate("document.querySelectorAll('#display-brightness input')[0].value"), '35');

      const sound = await evaluate(`(async () => {
        const range = document.querySelector('#speaker-range');
        const amount = document.querySelector('#speaker-value');
        const message = document.querySelector('#speaker-msg');
        const initial = amount.textContent;
        range.value = '64';
        range.dispatchEvent(new Event('input'));
        const preview = amount.textContent;
        const writesDuringDrag = volumeWrites.length;
        range.dispatchEvent(new Event('change'));
        await new Promise(resolve => setTimeout(resolve, 0));
        const confirmed = amount.textContent;
        testState.speakerVolume.muted = true;
        await refresh();
        const muted = amount.textContent;
        const name = 'USB audio device with a deliberately long display name';
        testState.speakerVolume = { name, error:'Switch to built-in output.' };
        await refresh();
        const unavailable = { disabled:range.disabled, name:document.querySelector('#speaker-name').textContent, message:message.textContent };
        remoteOffline = true;
        await refresh();
        const offline = range.disabled && amount.textContent === '—' && message.textContent === 'Mac 연결이 끊겼습니다.' &&
          [...document.querySelectorAll('#display-brightness input')].every(input => input.disabled);
        remoteOffline = false;
        testState.speakerVolume = { id:13, name:'MacBook Air Speakers', value:33, muted:false };
        await refresh();
        await new Promise(resolve => setTimeout(resolve, 0));
        return { initial, preview, writesDuringDrag, confirmed, muted, unavailable, offline, writes:volumeWrites,
          reconnected: !range.disabled && !message.textContent && amount.textContent === '33%' &&
            !document.querySelector('#display-brightness input').disabled };
      })()`);
      assert.equal(sound.initial, '42%');
      assert.equal(sound.preview, '64%');
      assert.equal(sound.writesDuringDrag, 0);
      assert.equal(sound.confirmed, '64%');
      assert.deepEqual(sound.writes, [{ id:13, value:64 }]);
      assert.equal(sound.muted, '음소거');
      assert.ok(sound.unavailable.disabled && sound.unavailable.name.length > 40 && sound.unavailable.message);
      assert.ok(sound.offline && sound.reconnected);
      await evaluate(`document.querySelector('#power-sheet [data-close]').click()`);
    }
    const seek = await evaluate(`(async () => {
      const keys = [...document.querySelectorAll('[data-seek]')];
      testState.current = { id:'youtube' };
      testState.youtubeSeekSeconds = 15;
      await refresh();
      const labels = keys.map(key => key.getAttribute('aria-label'));
      const shown = keys.every(key => !key.querySelector('.seek-seconds').hidden && key.getBoundingClientRect().height >= 44);
      keys.forEach(key => key.click());
      await new Promise(resolve => setTimeout(resolve, 0));
      const commands = sentCommands.slice(-2);
      document.querySelector('[data-a="home"]').click();
      const hiddenOnHome = keys.every(key => key.querySelector('.seek-seconds').hidden);
      testState.current = { id:'netflix' };
      await refresh();
      const otherService = keys.map(key => key.dataset.a);
      return { labels, shown, commands, hiddenOnHome, otherService };
    })()`);
    assert.deepEqual(seek, { labels:['15초 뒤로','15초 앞으로'], shown:true, commands:['rewind15','forward15'],
      hiddenOnHome:true, otherService:['rewind','forward'] });
    console.log(`PASS remote layout ${width}x${height}`);
  }
}
(async () => {
  try { await run(); }
  catch (error) { console.error(error); process.exitCode = 1; }
  finally {
    // Graceful browser shutdown lets its helpers flush and close the profile too.
    // Killing only the parent can leave a helper recreating files during removal.
    if (closeBrowser && child?.exitCode === null && child?.signalCode === null) {
      try { await closeBrowser(); } catch { /* The browser can close CDP before replying. */ }
      if (child.exitCode === null && child.signalCode === null) {
        await Promise.race([new Promise(resolve => child.once('exit', resolve)), delay(3000)]);
      }
    }
    if (socket) socket.close();
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM');
      await Promise.race([new Promise(resolve => child.once('exit', resolve)), delay(3000)]);
      if (child.exitCode === null && child.signalCode === null) { child.kill('SIGKILL'); await new Promise(resolve => child.once('exit', resolve)); }
    }
    await new Promise(resolve => server.close(resolve));
    await fs.promises.rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 150 });
  }
})();
