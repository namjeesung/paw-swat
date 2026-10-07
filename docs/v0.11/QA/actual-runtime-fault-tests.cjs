// Tests unchanged functions extracted from the actual shipped index.js.
// This is a unit boundary/fault-injection test. It does not instantiate Godot's
// WASM, use a real browser, prove the hosting error, or prove audible playback.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const build = path.resolve(__dirname, '../../Web/index.js');
const shipped = fs.readFileSync(build, 'utf8');
const start = shipped.indexOf('var GodotAudioWorklet=');
const end = shipped.indexOf('function _godot_js_config_canvas_id_get', start);
assert(start >= 0 && end > start, 'Cannot identify actual runtime functions');
const unchanged = shipped.slice(start, end);
const rejections = [];
process.on('unhandledRejection', error => {
  rejections.push({name: error.name, message: error.message});
});

async function scenario(name, behavior) {
  const calls = {urls: [], createdNodes: 0, connections: 0, postedCommands: [], outputCallbacks: 0, errors: []};
  const heap = new Float32Array(8192);
  const ctx = {state: 'running', destination: {}, audioWorklet: {addModule(url) {
    calls.urls.push(url);
    if (behavior === 'synchronous-load-throw') throw new Error('Injected synchronous addModule throw');
    if (behavior === 'asynchronous-load-reject') {
      const error = new Error('Injected failed worklet fetch/CSP boundary');
      error.name = 'AbortError';
      return Promise.reject(error);
    }
    return Promise.resolve();
  }}};
  const sandbox = {
    Float32Array, Promise,
    HEAPF32: heap,
    GodotConfig: {locate_file: file => file.replace(/^godot\./, 'index.')},
    GodotAudio: {ctx, driver: null},
    GodotRuntime: {
      error: (...args) => calls.errors.push(args.map(arg => arg && arg.message || String(arg))),
      heapSlice: (buffer, ptr, size) => buffer.slice(ptr / 4, ptr / 4 + size),
      heapSub: (buffer, ptr, size) => buffer.subarray(ptr / 4, ptr / 4 + size),
      get_func: func => func,
    },
    AudioWorkletNode: class AudioWorkletNode {
      constructor() {
        calls.createdNodes++;
        if (behavior === 'asynchronous-node-throw') throw new Error('Injected worklet node constructor failure');
        this.port = {onmessage: null, postMessage(message) {calls.postedCommands.push(message.cmd);}};
      }
      connect() {calls.connections++;}
      disconnect() {}
    },
  };
  vm.createContext(sandbox);
  vm.runInContext(unchanged, sandbox, {filename: 'unchanged-shipped-worklet-functions.js'});
  const rejectionStart = rejections.length;
  const returnCode = sandbox._godot_audio_worklet_create(2);
  if (returnCode === 0) sandbox._godot_audio_worklet_start_no_threads(
    0, 4096, () => {calls.outputCallbacks++;}, 16384, 4096, () => {}
  );
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  const result = {
    name, behavior, returnCode,
    contextState: ctx.state,
    driverAssignedWorklet: sandbox.GodotAudio.driver === sandbox.GodotAudioWorklet,
    workletExists: sandbox.GodotAudioWorklet.worklet !== null,
    ...calls,
    unhandledRejections: rejections.slice(rejectionStart),
  };
  if (behavior.startsWith('asynchronous-')) {
    assert.equal(returnCode, 0);
    assert.equal(result.driverAssignedWorklet, true);
    assert.equal(result.workletExists, false);
    assert.equal(calls.connections, 0);
    assert.equal(calls.postedCommands.length, 0);
    assert.equal(result.unhandledRejections.length, 1);
  } else if (behavior === 'synchronous-load-throw') {
    assert.equal(returnCode, 1);
    assert.equal(result.driverAssignedWorklet, false);
  } else {
    assert.equal(returnCode, 0);
    assert.equal(result.workletExists, true);
    assert.equal(calls.connections, 1);
    assert.deepEqual(calls.postedCommands, ['start_nothreads']);
    assert.equal(result.unhandledRejections.length, 0);
  }
  return result;
}

(async () => {
  const results = [];
  for (const behavior of ['healthy-control', 'asynchronous-load-reject', 'asynchronous-node-throw', 'synchronous-load-throw']) {
    results.push(await scenario(behavior, behavior));
  }
  const report = {
    scope: 'Unchanged shipped JS driver unit boundary with deliberately injected browser API faults; no browser/WASM/audio-output claim',
    indexJsSha256: crypto.createHash('sha256').update(shipped).digest('hex'),
    extractedFunctionsSha256: crypto.createHash('sha256').update(unchanged).digest('hex'),
    extractedFunctionsBytes: Buffer.byteLength(unchanged),
    allAssertionsPassed: true,
    results,
  };
  fs.writeFileSync(path.resolve(__dirname, 'actual-runtime-fault-results.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
})().catch(error => {console.error(error); process.exitCode = 1;});
