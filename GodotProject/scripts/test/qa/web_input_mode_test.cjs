'use strict';
// Deterministic DOM mocks executing the production Web input bridge, not Edge
// hardware/browser execution. No server, SDK, account, score or network writes.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const head = fs.readFileSync(path.join(root, 'web/head_include.html'), 'utf8');
const marker = '/* Canvas-only input observation.';
assert(head.includes(marker));
const source = head.slice(head.indexOf(marker)).split('</script>')[0];
let checks = 0;
function check(name, passed) {
  checks++;
  assert(passed, name);
  console.log('[input-mode-web] PASS ' + name);
}
class Target {
  constructor() { this.handlers = []; }
  addEventListener(type, callback, options) { this.handlers.push({ type, callback, options }); }
  dispatch(event) {
    event.preventDefault = () => { throw new Error('Observer canceled ' + event.type); };
    event.stopPropagation = () => { throw new Error('Observer stopped ' + event.type); };
    const handlers = this.handlers.filter(h => h.type === event.type).slice();
    handlers.sort((a, b) => Number(!!b.options?.capture) - Number(!!a.options?.capture));
    handlers.forEach(h => h.callback(event));
  }
}
const edgeUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0';
function fixture({ nav = {}, queries = {}, legacy = false, ontouch = false } = {}) {
  const canvas = new Target(); canvas.dataset = {};
  const document = new Target(); document.visibilityState = 'visible';
  document.getElementById = id => id === 'canvas' ? canvas : null;
  const window = new Target(); window.innerWidth = 1920; window.innerHeight = 1080;
  window.matchMedia = query => ({ matches: !!queries[query] });
  if (!legacy) window.PointerEvent = function () {};
  if (ontouch) window.ontouchstart = null;
  let now = 10000;
  const context = vm.createContext({ window, document, navigator: { userAgent: edgeUA, platform: 'Win32', maxTouchPoints: 0, ...nav }, Date: { now: () => now } });
  vm.runInContext(source, context);
  const api = window.pawInput;
  return { api, canvas, window, document, context, tick: ms => { now += ms; } };
}
const fine = { '(pointer: fine)': true, '(hover: hover)': true, '(any-pointer: coarse)': true };
const coarse = { '(pointer: coarse)': true, '(hover: none)': true };
[
  ['desktop Edge mouse only', { queries: fine }, false],
  ['desktop touch API exposed alone', { queries: fine, ontouch: true }, false],
  ['Windows hybrid maxTouchPoints 10 with primary mouse', { nav: { maxTouchPoints: 10 }, queries: fine, ontouch: true }, false],
  ['unknown capability-only maxTouchPoints', { nav: { maxTouchPoints: 10 } }, false],
  ['legacy msMaxTouchPoints does not force mobile', { nav: { msMaxTouchPoints: 5 }, queries: fine }, false],
  ['non-Edge Windows Chrome hybrid', { nav: { userAgent: edgeUA.replace(/ Edg\/[^ ]+/, ''), maxTouchPoints: 10 }, queries: fine }, false],
  ['Windows touch-primary tablet', { nav: { maxTouchPoints: 10 }, queries: coarse }, true],
  ['Android mobile', { nav: { userAgent: 'Mozilla/5.0 (Linux; Android 15) Mobile', maxTouchPoints: 5 }, queries: coarse }, true],
  ['iPhone without exposed touch APIs', { nav: { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)' } }, true],
  ['iPad legacy UA', { nav: { userAgent: 'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)', platform: 'iPad' } }, true],
  ['iPad desktop UA and multitouch', { nav: { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)', platform: 'MacIntel', maxTouchPoints: 5 }, queries: fine }, true],
  ['MacBook desktop UA without multitouch', { nav: { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)', platform: 'MacIntel' }, queries: fine }, false],
  ['UA client hints mobile', { nav: { userAgent: '', userAgentData: { mobile: true } } }, true],
  ['generic primary coarse no-hover', { nav: { userAgent: '' }, queries: coarse }, true],
].forEach(([name, options, expected]) => check(name, fixture(options).api.usesTouch() === expected));
const f = fixture({ nav: { maxTouchPoints: 10 }, queries: fine, ontouch: true });
const changes = [];
f.api.onModeChange(value => changes.push(value));
f.canvas.dispatch({ type: 'pointerdown', pointerType: 'touch' });
check('real hybrid touch enables controls immediately', f.api.usesTouch() && changes.join(',') === 'true');
let modeAtEngineTouch = false;
f.canvas.addEventListener('touchstart', () => { modeAtEngineTouch = f.api.usesTouch(); });
const finger = { identifier: -1 };
f.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
check('capture mode set before original engine touch callback', modeAtEngineTouch && f.api.isActive(-1));
f.canvas.dispatch({ type: 'pointerdown', pointerType: 'mouse', sourceCapabilities: { firesTouchEvents: true } });
check('touch-generated mouse cannot hide virtual controls', f.api.usesTouch());
f.canvas.dispatch({ type: 'pointermove', pointerType: 'mouse' });
check('passive mouse movement does not flip touch mode', f.api.usesTouch());
f.canvas.dispatch({ type: 'touchend', changedTouches: [finger], targetTouches: [] });
check('touch end retains mobile controls and normal release', f.api.usesTouch() && !f.api.consumeCancel(-1));
f.canvas.dispatch({ type: 'pointerdown', pointerType: 'mouse' });
check('real mouse switches hybrid back to keyboard mouse', !f.api.usesTouch() && changes.join(',') === 'true,false');
f.window.innerWidth = 600; f.window.innerHeight = 1000; f.window.dispatch({ type: 'resize' });
check('portrait desktop resize never forces mobile', !f.api.usesTouch());
f.window.innerWidth = 2400; f.window.innerHeight = 1080; f.window.dispatch({ type: 'resize' });
check('landscape desktop resize retains desktop', !f.api.usesTouch());
f.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
check('genuine touch fallback works without preceding pointerdown', f.api.usesTouch());
f.document.dispatch({ type: 'keydown', code: 'F8' });
check('diagnostic hotkey does not alter input mode', f.api.usesTouch());
f.document.dispatch({ type: 'keydown', code: 'KeyW', target: { tagName: 'INPUT' } });
check('typing a name does not switch game controls', f.api.usesTouch());
f.document.dispatch({ type: 'keydown', code: 'KeyW', target: f.canvas });
check('gameplay keyboard switches back to desktop', !f.api.usesTouch());
f.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
f.canvas.dispatch({ type: 'pointerdown', pointerType: 'pen' });
check('pen uses mouse-style aiming rather than fake touch sticks', !f.api.usesTouch());
f.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
f.window.dispatch({ type: 'blur' });
check('existing blur cancellation survives mode detection', f.api.usesTouch() && !f.api.isActive(-1) && f.api.consumeCancel(-1));
f.api.reset();
check('session touch reset preserves selected input mode', f.api.usesTouch() && !f.api.observed());
f.window.innerHeight = 2000; f.window.dispatch({ type: 'resize' });
check('touch-selected mode survives rotation', f.api.usesTouch());
const g = fixture({ legacy: true, nav: { userAgent: 'Android', maxTouchPoints: 5 }, queries: coarse });
g.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
g.tick(2000);
g.canvas.dispatch({ type: 'mousedown' });
check('legacy compatibility mouse ignored while touch held', g.api.usesTouch());
g.canvas.dispatch({ type: 'touchend', changedTouches: [finger], targetTouches: [] });
g.canvas.dispatch({ type: 'mousedown' });
check('legacy post-touch compatibility click ignored', g.api.usesTouch());
g.tick(801); g.canvas.dispatch({ type: 'mousedown' });
check('legacy real mouse can switch after touch grace period', !g.api.usesTouch());
const h = fixture({ nav: { maxTouchPoints: 10 }, queries: fine });
h.api.onModeChange(() => h.api.reset()); // Production HUD clears stale input on mode changes.
h.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
check('mode callback reset retains original new touch ownership', h.api.usesTouch() && h.api.observed() && h.api.isActive(-1));
h.document.dispatch({ type: 'keydown', code: 'ShiftLeft' });
check('keyboard alternate roll key switches to desktop', !h.api.usesTouch() && !h.api.isActive(-1));
h.canvas.dispatch({ type: 'touchstart', changedTouches: [finger], targetTouches: [finger] });
h.canvas.dispatch({ type: 'touchcancel', changedTouches: [finger], targetTouches: [] });
check('cancellation semantics survive callback-driven mode reset', h.api.usesTouch() && h.api.consumeCancel(-1));
check('all canvas input observers remain capture-passive', f.canvas.handlers.filter(h => h.options).every(h => h.options.capture && h.options.passive));
check('no document touch interception introduced', !f.document.handlers.some(h => /^touch/.test(h.type)));
const listenerCount = f.canvas.handlers.length;
vm.runInContext(source, f.context);
check('reinitialization does not duplicate input listeners', listenerCount === f.canvas.handlers.length);
const preset = fs.readFileSync(path.join(root, 'export_presets.cfg'), 'utf8');
const encoded = preset.match(/html\/head_include=("(?:[^"\\]|\\.)*")/)[1];
check('export preset matches authoritative Web head exactly', JSON.parse(encoded) === head);
console.log('[input-mode-web] RESULT ' + JSON.stringify({ checks, failed: 0, mode: 'Node DOM mocks; not real Edge/device QA' }));
