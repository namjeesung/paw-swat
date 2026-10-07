'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path');
const head=fs.readFileSync(process.argv[2]||path.join(__dirname,'../../GodotProject/web/head_include.html'),'utf8');
const code=head.match(/<script>([\s\S]*)<\/script>/)[1];
const results=[];
class Target {
 constructor(){this.listeners=new Map()}
 addEventListener(type,fn,options={}){if(!this.listeners.has(type))this.listeners.set(type,[]);this.listeners.get(type).push({fn,options})}
 dispatchEvent(event){event.preventDefault??=()=>{event.defaultPrevented=true};event.stopPropagation??=()=>{event.stopped=true};for(const listener of this.listeners.get(event.type)||[])listener.fn(event);return !event.defaultPrevented}
}
function fixture({supported=true,search='',worklet=false,readonly=false}={}){
 const window=new Target(),document=new Target(),timers=new Map(),warns=[],elements=[];
 window.location={search};document.visibilityState='visible';document.body={appendChild:e=>elements.push(e)};
 document.createElement=tag=>{assert.equal(tag,'div','Must never create hidden HTML audio');return {hidden:false,textContent:'',setAttribute(){}}};
 class AC extends Target{
  static nativeConstant=17;
  constructor(){super();this.state='suspended';this.sampleRate=48000;this.resumeCalls=0;this.suspendCalls=0;this.behavior='success';if(worklet){const context=this;this.audioWorklet={calls:[],lastPromise:null,behavior:'success',addModule(...args){this.calls.push(args);if(this.behavior==='throw')throw new Error('module sync failure');this.lastPromise=this.behavior==='reject'?Promise.reject(new Error('module load failure')):this.behavior==='hang'?new Promise(resolve=>this.resolve=resolve):Promise.resolve();return this.lastPromise}};if(readonly)Object.defineProperty(this.audioWorklet,'addModule',{writable:false})}}
  resume(){this.resumeCalls++;switch(this.behavior){case 'reject':return Promise.reject(Object.assign(new Error('policy denied'),{name:'NotAllowedError'}));case 'throw':throw new Error('resume sync failure');case 'hang':return new Promise(resolve=>this.pendingResolve=resolve);default:this.state='running';this.dispatchEvent({type:'statechange'});return Promise.resolve()}}
  suspend(){this.suspendCalls++;this.state='suspended';this.dispatchEvent({type:'statechange'});return Promise.resolve()}
 }
 if(supported)window.AudioContext=window.webkitAudioContext=AC;
 const sandbox={window,document,console:{warn:x=>warns.push(x)},Event:class{constructor(type){this.type=type}},Map,Proxy,Reflect,Array,Promise,setTimeout:fn=>{const id=timers.size+1;timers.set(id,fn);return id},clearTimeout:id=>timers.delete(id)};
 vm.createContext(sandbox);vm.runInContext(code,sandbox);
 const send=type=>{const event={type,isTrusted:true};window.dispatchEvent(event);return event};
 return {window,document,timers,warns,elements,AC,send,ctx:()=>new window.AudioContext(),snapshot:()=>window.pawAudio.snapshot(),notice:()=>elements[0],tick:async()=>{await Promise.resolve();await Promise.resolve()},timeout:()=>{for(const [id,fn]of [...timers]){timers.delete(id);fn()}}};
}
async function test(name,fn){await fn();results.push({name,result:'PASS',evidence:'Node VM mocked browser/context; not browser playback or audible proof'});console.log('PASS',name)}
(async()=>{
 await test('Pre-created suspended context; first pointer action still reaches game',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();assert.equal(c.resumeCalls,0);assert.equal(f.notice().hidden,false);let game=0;f.window.addEventListener('pointerdown',()=>game++);const e=f.send('pointerdown');await f.tick();assert.equal(c.state,'running');assert.equal(f.snapshot().contexts[0].successes,1);assert.equal(game,1);assert.ok(!e.defaultPrevented&&!e.stopped);assert.equal(f.notice().hidden,true);
 });
 await test('Touch release, click and keyboard each unlock without input cancellation',async()=>{
  for(const type of ['touchend','pointerup','click','keydown']){const f=fixture(),c=f.ctx();const e=f.send(type);await f.tick();assert.equal(c.state,'running');assert.ok(!e.defaultPrevented&&!e.stopped)}
 });
 await test('Context created after early loading gesture waits visibly for next genuine action',async()=>{
  const f=fixture();f.window.pawAudio.setReady();assert.equal(f.window.pawAudio.blocked(),true);assert.match(f.notice().textContent,/准备/);let firstAction=0;f.window.addEventListener('pointerdown',()=>firstAction++);f.send('pointerdown');assert.equal(firstAction,1);const c=f.ctx();assert.match(f.notice().textContent,/开启/);assert.equal(c.resumeCalls,0);assert.equal(f.notice().hidden,false);f.send('click');await f.tick();assert.equal(c.state,'running');
 });
 await test('Rejected resume is caught, visible and retryable next gesture',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();c.behavior='reject';f.send('pointerdown');await f.tick();assert.equal(c.state,'suspended');assert.match(f.snapshot().contexts[0].error,/NotAllowedError/);assert.match(f.notice().textContent,/重试/);assert.equal(f.snapshot().contexts[0].pending,false);c.behavior='success';f.send('pointerup');await f.tick();assert.equal(c.state,'running');assert.equal(c.resumeCalls,2);assert.equal(f.snapshot().contexts[0].error,'');
 });
 await test('Hanging resume deduplicates events then becomes retryable after timeout',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();c.behavior='hang';f.send('pointerdown');f.send('click');assert.equal(c.resumeCalls,1);f.timeout();assert.equal(f.snapshot().contexts[0].pending,false);assert.match(f.notice().textContent,/重试/);c.behavior='success';f.send('keydown');await f.tick();assert.equal(c.state,'running');assert.equal(c.resumeCalls,2);c.pendingResolve();await f.tick();assert.equal(f.snapshot().contexts[0].error,'');
 });
 await test('Synchronous resume error is caught and next gesture can retry',async()=>{
  const f=fixture(),c=f.ctx();c.behavior='throw';f.send('click');await f.tick();assert.match(f.snapshot().contexts[0].error,/sync failure/);c.behavior='success';f.send('keydown');await f.tick();assert.equal(c.state,'running');
 });
 await test('Engine-discarded resume Promise also has a rejection observer',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();c.behavior='reject';c.resume();await f.tick();assert.match(f.snapshot().contexts[0].error,/NotAllowedError/);assert.match(f.notice().textContent,/重试/);assert.equal(f.warns.length,1);
 });
 await test('Background suspends, foreground waits for gesture, settings remain unchanged',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();f.window.pawAudio.setMix({sfx:.85,music:.55});f.send('click');await f.tick();f.document.visibilityState='hidden';f.document.dispatchEvent({type:'visibilitychange'});await f.tick();assert.equal(c.state,'suspended');assert.equal(c.suspendCalls,1);f.document.visibilityState='visible';f.document.dispatchEvent({type:'visibilitychange'});assert.equal(c.resumeCalls,1);assert.equal(f.notice().hidden,false);f.send('keydown');await f.tick();assert.equal(c.state,'running');assert.equal(f.snapshot().mix.music,.55);assert.equal(f.snapshot().mix.sfx,.85);
 });
 await test('Late resume completing while backgrounded is suspended again',async()=>{
  const f=fixture(),c=f.ctx();c.behavior='hang';f.send('click');f.document.visibilityState='hidden';f.document.dispatchEvent({type:'visibilitychange'});c.state='running';c.pendingResolve();await f.tick();assert.equal(c.state,'suspended');
 });
 await test('Explicit saved mute is respected; no audio element or session/gain override',async()=>{
  const f=fixture(),c=f.ctx();f.window.pawAudio.setReady();f.window.pawAudio.setMix({sfx:0,music:0});assert.equal(f.notice().hidden,true);f.send('click');await f.tick();assert.equal(f.snapshot().mix.sfx,0);assert.equal(f.snapshot().mix.music,0);assert.equal(c.state,'running');assert.equal(f.elements.length,1);assert.ok(!code.includes('navigator.audioSession'));assert.ok(!code.includes('createGain'));
 });
 await test('Constructor aliases/static properties and idempotent setup preserved',async()=>{
  const f=fixture();assert.equal(f.window.AudioContext,f.window.webkitAudioContext);assert.equal(f.window.AudioContext.nativeConstant,17);const c=f.ctx();assert.ok(c instanceof f.AC);assert.ok(c instanceof f.window.AudioContext);const before=f.window.listeners.get('click').length;vm.runInContext(code,vm.createContext({window:f.window}));assert.equal(f.window.listeners.get('click').length,before);
 });
 await test('Synthetic gestures, repeated keys and closed contexts never resume',async()=>{
  const f=fixture(),c=f.ctx();f.window.dispatchEvent({type:'click',isTrusted:false});f.window.dispatchEvent({type:'keydown',isTrusted:true,repeat:true});assert.equal(c.resumeCalls,0);c.state='closed';f.send('click');assert.equal(c.resumeCalls,0);assert.equal(f.window.pawAudio.blocked(),false);
 });
 await test('Unsupported browser gets readable status',async()=>{
  const f=fixture({supported:false});f.window.pawAudio.setReady();assert.match(f.notice().textContent,/不支持/);assert.equal(f.snapshot().supported,false);
 });
 await test('Diagnostics are off by default and query opt-in shows version/mix without audible claim',async()=>{
  const normal=fixture();assert.equal(normal.snapshot().diagnosticVisible,false);assert.equal(normal.elements.length,1);
  const f=fixture({search:'?debug=audio'}),c=f.ctx();f.window.pawAudio.setMix({sfx:.85,music:.55});const diag=f.elements.find(e=>e.id==='paw-audio-diagnostic');assert.ok(diag);assert.equal(diag.hidden,false);assert.match(diag.textContent,/v0\.9/);assert.match(diag.textContent,/85%.*55%/);f.send('click');await f.tick();assert.equal(f.snapshot().contextRunning,true);assert.equal(f.snapshot().outputVerified,false);assert.match(diag.textContent,/尚不证明设备出声/);
 });
 await test('F8 toggles diagnostic without cancelling input or changing saved mix',async()=>{
  const f=fixture();f.ctx();f.window.pawAudio.setMix({sfx:0,music:.55});let game=0;f.window.addEventListener('keydown',()=>game++);const first={type:'keydown',code:'F8',key:'F8',isTrusted:true};f.window.dispatchEvent(first);await f.tick();assert.equal(game,1);assert.ok(!first.defaultPrevented&&!first.stopped);assert.equal(f.snapshot().diagnosticVisible,true);assert.equal(f.snapshot().mix.sfx,0);f.window.dispatchEvent({type:'keydown',code:'F8',isTrusted:true,repeat:true});assert.equal(f.snapshot().diagnosticVisible,true);f.window.dispatchEvent({type:'keydown',key:'F8',isTrusted:true});assert.equal(f.snapshot().diagnosticVisible,false);assert.equal(f.elements.find(e=>e.id==='paw-audio-diagnostic').hidden,true);
 });
 await test('Worklet fulfilled observation preserves exact Promise, receiver and options',async()=>{
  const f=fixture({worklet:true,search:'?debug=audio'}),c=f.ctx(),options={credentials:'same-origin'};const request=c.audioWorklet.addModule('https://example.test/index.audio.worklet.js?token=not-exposed',options);assert.equal(request,c.audioWorklet.lastPromise);assert.equal(c.audioWorklet.calls.length,1);assert.equal(c.audioWorklet.calls[0][1],options);assert.equal(f.snapshot().contexts[0].worklet.modules[0].state,'pending');await f.tick();const module=f.snapshot().contexts[0].worklet.modules[0];assert.equal(module.state,'fulfilled');assert.equal(module.name,'index.audio.worklet.js');assert.ok(!JSON.stringify(module).includes('not-exposed'));assert.equal(c.resumeCalls,0);
 });
 await test('Worklet rejected observation leaves original Promise rejected with no fallback/retry',async()=>{
  const f=fixture({worklet:true}),c=f.ctx();c.audioWorklet.behavior='reject';const request=c.audioWorklet.addModule('index.audio.worklet.js');assert.equal(request,c.audioWorklet.lastPromise);await assert.rejects(request,/module load failure/);await f.tick();const module=f.snapshot().contexts[0].worklet.modules[0];assert.equal(module.state,'rejected');assert.match(module.error,/module load failure/);assert.equal(c.audioWorklet.calls.length,1);assert.equal(c.resumeCalls,0);assert.equal(c.state,'suspended');
 });
 await test('Worklet pending/synchronous throw remain original behavior and are separately visible',async()=>{
  const f=fixture({worklet:true}),c=f.ctx();c.audioWorklet.behavior='hang';const request=c.audioWorklet.addModule('index.audio.position.worklet.js');assert.equal(request,c.audioWorklet.lastPromise);f.timeout();assert.equal(f.snapshot().contexts[0].worklet.modules[0].state,'pending');c.audioWorklet.behavior='throw';assert.throws(()=>c.audioWorklet.addModule('index.audio.worklet.js'),/module sync failure/);assert.equal(f.snapshot().contexts[0].worklet.modules[1].state,'rejected');c.audioWorklet.resolve();await f.tick();assert.equal(f.snapshot().contexts[0].worklet.modules[0].state,'fulfilled');assert.equal(c.audioWorklet.calls.length,2);
 });
 await test('Unavailable or read-only worklet observation does not alter native API',async()=>{
  const missing=fixture(),a=missing.ctx();assert.equal(missing.snapshot().contexts[0].worklet.supported,false);assert.equal(a.audioWorklet,undefined);const f=fixture({worklet:true,readonly:true}),c=f.ctx();assert.equal(f.snapshot().contexts[0].worklet.observer,'unavailable');const request=c.audioWorklet.addModule('index.audio.worklet.js');assert.equal(request,c.audioWorklet.lastPromise);await request;assert.equal(c.audioWorklet.calls.length,1);assert.equal(f.snapshot().contexts[0].worklet.modules.length,0);
 });
 fs.writeFileSync(path.join(__dirname,'audio-bridge-results.json'),JSON.stringify({scope:'Logic-only mock tests, not real browser or hardware audio proof',results},null,2)+'\n');
 console.log(results.length+' mocked audio bridge tests passed');
})().catch(error=>{console.error(error);process.exitCode=1});
