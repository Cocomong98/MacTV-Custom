// Exercise the actual address form without a browser or external network.
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { script: source } = require('./page.cjs');
const start = source.indexOf('let websiteOpening = false;');
const end = source.indexOf("const typed =", start);
const messagesStart = source.indexOf('const remoteMessages =');
const messagesEnd = source.indexOf('// Keep a small bounded queue', messagesStart);
assert.ok(start >= 0 && end > start);
assert.ok(messagesStart >= 0 && messagesEnd > messagesStart);
const elements = Object.fromEntries(['open-website', 'website-address', 'website-go', 'website-open-error']
  .map(id => [id, { value: '', textContent: '', hidden: true, disabled: false }]));
const requests = [];
let resolveRequest, rejectRequest, refreshes = 0;
const closedSheets = [];
const api = (path, body) => {
  requests.push({ path, body });
  return new Promise((resolve, reject) => { resolveRequest = resolve; rejectRequest = reject; });
};
vm.runInNewContext(source.slice(messagesStart, messagesEnd) + source.slice(start, end), {
  $: selector => elements[selector.slice(1)], api, haptic() {}, refresh: async () => { refreshes++; },
  closeInputSheet: (...args) => closedSheets.push(args),
});
const submit = () => elements['open-website'].onsubmit({ preventDefault() {} });
(async () => {
  await submit();
  assert.equal(requests.length, 0);
  assert.equal(elements['website-open-error'].hidden, false);
  assert.equal(elements['website-open-error'].textContent, '웹사이트 주소를 입력하세요.');
  elements['website-address'].value = ' youtube.com ';
  const first = submit();
  await submit();
  assert.equal(requests.length, 1, 'no duplicate while pending');
  assert.equal(requests[0].path, '/browser/open');
  assert.equal(requests[0].body.url, 'youtube.com');
  assert.equal(elements['website-go'].disabled, true);
  resolveRequest({ ok: true });
  await first;
  assert.equal(elements['website-address'].value, '');
  assert.equal(elements['website-go'].disabled, false);
  assert.equal(refreshes, 1);
  assert.deepEqual(closedSheets, [['address-sheet', 'open-address']]);
  elements['website-address'].value = 'bad-address';
  const failed = submit();
  rejectRequest(new Error('<img src=x onerror=alert(1)>'));
  await failed;
  assert.equal(elements['website-open-error'].textContent, '<img src=x onerror=alert(1)>');
  assert.equal(elements['website-open-error'].hidden, false);
  assert.equal(elements['website-go'].disabled, false);
  assert.equal(elements['website-address'].value, 'bad-address', 'preserve failed address for editing');
  assert.equal(requests.some(x => x.path === '/apps/add'), false, 'navigation does not save tiles');
  console.log('Website address submission, failure recovery and duplicate prevention passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
