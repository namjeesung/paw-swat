'use strict';
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const original=fs.readFileSync(path.join(__dirname,'original-head_include.html'),'utf8').match(/<script>([\s\S]*)<\/script>/)[1];
const events={},tags=[],settings={type:'auto'},unhandled=[];
class Context {constructor(){this.state='suspended';this.calls=0}resume(){this.calls++;return Promise.reject(Object.assign(new Error('policy denied'),{name:'NotAllowedError'}))}}
const window={AudioContext:Context,addEventListener:(type,fn)=>events[type]=fn};
const document={addEventListener(){},createElement(tag){tags.push(tag);return {paused:true,setAttribute(){},play:()=>Promise.resolve(),pause(){}}}};
const sandbox={window,document,navigator:{audioSession:settings}};vm.createContext(sandbox);vm.runInContext(original,sandbox);
const context=new window.AudioContext();
process.on('unhandledRejection',error=>unhandled.push(error.name+': '+error.message));
if(events.pointerdown)events.pointerdown({type:'pointerdown'});
assert.equal(context.calls,0,'Original has no pointerdown resume observer');
events.keydown({type:'keydown'});
setImmediate(()=>{
 assert.equal(unhandled.length,1,'Original discarded resume rejection becomes unhandled');
 assert.equal(settings.type,'playback','Original overrides default browser audio session');
 assert.equal(tags.filter(tag=>tag==='audio').length,1,'Original creates hidden looping HTML audio');
 const report={scope:'Node VM reproduction of original source defects, not real-browser silence proof',evidence:{no_pointerdown_resume_observer:true,discarded_resume_rejection:unhandled,audio_session_forced:settings.type,hidden_audio_elements_created:tags.filter(tag=>tag==='audio').length},root_cause_status:'The reported real-browser silence cannot be conclusively attributed without browser/device playback evidence'};
 fs.writeFileSync(path.join(__dirname,'original-bridge-defects.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
});
