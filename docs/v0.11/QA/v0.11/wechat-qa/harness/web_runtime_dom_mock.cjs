'use strict';
// Node DOM mocks, executing unchanged handlers extracted from the shipped Web
// runtime plus the candidate head's passive observer. Not a browser/device test.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const qa = path.resolve(__dirname, '..');
const project = path.resolve(qa, '../project');
const runtime = fs.readFileSync(path.resolve(qa, '../../build/v010-web/index.js'), 'utf8');
const head = fs.readFileSync(path.join(project, 'web/head_include.html'), 'utf8');
const inputScript = head.slice(head.indexOf('/* Canvas-only input observation.')).split('</script>')[0];
const checks = [];
function check(name, pass, details = {}) {
  checks.push({name, passed: !!pass, details});
  console.log(`[web-input-dom-mock] ${pass ? 'PASS' : 'FAIL'} ${name}`);
}
class Target {
  constructor() { this.handlers = []; }
  addEventListener(type, callback, options) { this.handlers.push({type, callback, options}); }
  dispatch(event) {
    event.preventDefaultCount = 0; event.stopped = false;
    event.preventDefault = () => { event.preventDefaultCount++; };
    event.stopPropagation = () => { event.stopped = true; };
    const selected = this.handlers.filter(h => h.type === event.type);
    selected.sort((a, b) => Number(!!(b.options === true || b.options?.capture)) - Number(!!(a.options === true || a.options?.capture)));
    selected.forEach(h => h.callback(event));
    return event;
  }
}
const canvas = new Target();
canvas.dataset = {}; canvas.width = 2400; canvas.height = 1080; canvas.focusCount = 0;
canvas.focus = () => { canvas.focusCount++; };
canvas.getBoundingClientRect = () => ({x: 10, y: 20, left: 10, top: 20, width: 800, height: 360});
const document = new Target();
document.getElementById = id => id === 'canvas' ? canvas : null;
document.visibilityState = 'visible';
const window = new Target();
const nativeEvents = []; const heap = new Map();
const context = vm.createContext({window, document, navigator: {maxTouchPoints: 5}, console, Map, Number, Array,
  GodotConfig: {canvas},
  GodotRuntime: {
    get_func: () => (type, count) => {
      const events = Array.from({length: count}, (_, i) => {
        const id = heap.get(100 + i * 4);
        return {id, x: heap.get(200 + i * 16), y: heap.get(208 + i * 16),
          canceled: type === 1 && window.pawInput.consumeCancel(id)};
      });
      nativeEvents.push({type, events});
    },
    setHeapValue: (address, value, type) => { heap.set(address, type === 'i32' ? value | 0 : value); },
  },
  GodotEventListeners: {add: (target, type, fn, capture) => target.addEventListener(type, fn, capture)},
});
// Extract exact shipped computePosition and touch registration functions.
function extract(start, end) { const at = runtime.indexOf(start); const to = runtime.indexOf(end, at); if (at < 0 || to < 0) throw new Error('Runtime handler boundary missing'); return runtime.slice(at, to); }
vm.runInContext('var GodotInput = {' + extract('computePosition:function', ',onKeyEvent:function') + '};', context);
vm.runInContext(inputScript, context);
vm.runInContext(extract('function _godot_js_input_touch_cb(', 'function _godot_js_input_vibrate_handheld('), context);
vm.runInContext('_godot_js_input_touch_cb(1,100,200);', context);
const touch = (id, x = 100, y = 100) => ({identifier: id, clientX: x, clientY: y, target: canvas});
function send(type, changed, live, cancelable = true) {
  const event = {type, changedTouches: changed, targetTouches: live, cancelable};
  const result = canvas.dispatch(event);
  check(`observer_preserves_${type}_propagation_${checks.length}`, !result.stopped && result.preventDefaultCount === (cancelable ? 1 : 0));
  return nativeEvents.at(-1);
}
check('observer_listeners_are_canvas_capture_passive', canvas.handlers.filter(h => typeof h.options === 'object').every(h => h.options.capture && h.options.passive));
check('no_document_touchmove_or_dblclick_interception', !document.handlers.some(h => ['touchmove','dblclick'].includes(h.type)));
let a = touch(-2147483648); let b = touch(-1, 600, 200);
let received = send('touchstart', [a, b], [a, b]);
check('runtime_and_observer_preserve_extreme_signed_ids', received.events.map(e => e.id).join(',') === '-2147483648,-1' && window.pawInput.isActive(-1) && window.pawInput.isActive(-2147483648));
check('actual_runtime_canvas_css_to_pixel_mapping', received.events[0].x === 270 && received.events[0].y === 240);
a = touch(-2147483648, 150, 140);
received = send('touchmove', [a], [a, b]);
check('multifinger_drag_keeps_untouched_fire_contact', received.type === 2 && window.pawInput.isActive(-1));
received = send('touchcancel', [b], [a]);
check('actual_runtime_maps_cancel_to_release_but_observer_recovers_it', received.type === 1 && received.events[0].canceled && !window.pawInput.isActive(-1) && window.pawInput.isActive(-2147483648));
received = send('touchend', [a], []);
check('ordinary_release_is_not_cancellation', received.type === 1 && !received.events[0].canceled);
const old = touch(10); const fresh = touch(11);
send('touchstart', [old], [old]);
send('touchstart', [fresh], [fresh]);
check('live_contact_list_repairs_missing_old_end', !window.pawInput.isActive(10) && window.pawInput.isActive(11) && window.pawInput.consumeCancel(10));
send('touchend', [old], [fresh]);
check('late_old_end_preserves_new_contact', window.pawInput.isActive(11));
send('touchcancel', [fresh], []);
send('touchstart', [fresh], [fresh]);
check('reused_contact_id_clears_old_cancel_marker', !window.pawInput.consumeCancel(11) && window.pawInput.isActive(11));
const revision = window.pawInput.revision();
window.dispatch({type: 'blur'});
check('blur_cancels_all_active_contacts_and_changes_revision', !window.pawInput.isActive(11) && window.pawInput.consumeCancel(11) && window.pawInput.revision() > revision);
send('touchstart', [a], [a]);
document.visibilityState = 'hidden'; document.dispatch({type: 'visibilitychange'});
check('hidden_document_cancels_contacts', !window.pawInput.isActive(-2147483648) && window.pawInput.consumeCancel(-2147483648));
document.visibilityState = 'visible';
send('touchstart', [a], [a]); window.pawInput.reset();
check('new_session_clears_active_cancel_and_seen_state', !window.pawInput.observed() && !window.pawInput.isActive(-2147483648) && !window.pawInput.consumeCancel(-2147483648));
received = send('touchmove', [a], undefined, false);
check('missing_targetTouches_does_not_kill_held_contact', window.pawInput.isActive(-2147483648) && received.type === 2);
const cap = vm.createContext({navigator: {maxTouchPoints: 5}});
check('maxTouchPoints_detection_handles_missing_mobile_UA_and_ontouchstart', vm.runInContext('Number(navigator.maxTouchPoints || navigator.msMaxTouchPoints || 0) > 0', cap));
check('audio_head_prefix_is_unchanged', head.startsWith(fs.readFileSync(path.join(qa, 'checkpoints/before/head_include.html'), 'utf8')));
window.pawInput.reset();
const passiveObserver = canvas.handlers.find(h => h.type === 'touchstart' && h.options?.capture).callback;
function observeOnly(type, changed, live) { passiveObserver({type, changedTouches: changed, targetTouches: live}); }
const reused = touch(99);
observeOnly('touchstart', [reused], [reused]);
observeOnly('touchcancel', [reused], []);
observeOnly('touchstart', [reused], [reused]);
check('buffered_old_cancel_survives_new_same_id_DOM_press', window.pawInput.consumeCancel(99) === true && window.pawInput.isActive(99));
observeOnly('touchend', [reused], []);
check('new_same_id_ordinary_release_is_not_old_cancel', window.pawInput.consumeCancel(99) === false);
const failed = checks.filter(c => !c.passed);
const report = {mode: 'Node DOM mocks executing unchanged shipped Godot 4.6.3 Web handlers and candidate canvas observer; not Chromium, WeChat, hardware or browser process QA', checks, passed: failed.length === 0, failed: failed.length};
fs.writeFileSync(path.join(qa, 'evidence/web-runtime-dom-mock-report.json'), JSON.stringify(report, null, 2));
console.log(`[web-input-dom-mock] RESULT ${JSON.stringify({checks: checks.length, failed: failed.length})}`);
process.exitCode = failed.length ? 1 : 0;
