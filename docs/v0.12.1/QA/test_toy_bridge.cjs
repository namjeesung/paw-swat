// Offline SDK mocks only. No Toy account, public scores or cloud saves touched.
const fs = require('fs'), vm = require('vm'), assert = require('assert/strict');
const code = fs.readFileSync(require('path').join(__dirname, '../../../GodotProject/web/toy_bridge.js'), 'utf8');
const BASE = 16777215;
let count = 0;
function sandbox(api) {
  let now = 100000;
  const clock = class extends Date { static now() { return now; } };
  const win = {toy: api};
  vm.runInNewContext(code, {window:win, console, setTimeout, clearTimeout, Date:clock, Map, Promise});
  async function call(op,p) {
    const id=win.pawToy.start(op,JSON.stringify(p));
    for(let i=0;i<100;i++) {await new Promise(r=>setImmediate(r)); const value=win.pawToy.poll(id);if(value!=='') return JSON.parse(value);}
    return {pending:true,id};
  }
  return {win,call,advance(ms){now+=ms;}};
}
function ok(check){assert(check); count++;}
(async()=>{
 let calls=[], gets=0;
 let env=sandbox({submitScore:async p=>{calls.push(p);return {score:p.score};},getRankList:async p=>{gets++;return [{rank:1,score:BASE-76000,nickname:'玩家甲',avatar:''},{rank:2,score:BASE-81000,nickname:'玩家乙',avatar:''}]},getMyRank:async()=>({ranked:true,rank:2,score:BASE-81000}),getUserProfile:async()=>({nickname:'B站玩家',avatar:'https://example.invalid/avatar.png',toyOpenId:'private-do-not-display'})});
 for (const [i,d] of ['easy','normal','hard','insane'].entries()){let r=await env.call('submit',{run_id:String(i),difficulty:d,time_ms:81000});ok(r.ok);ok(calls[i].board===i+1&&calls[i].score===BASE-81000);}
 const first=await env.call('board',{difficulty:'normal'});ok(first.entries.length===2&&first.entries[0].time_ms===76000);ok(first.entries[1].me===true&&!first.entries[0].me);ok(!('pid' in first.entries[0]));
 const cached=await env.call('board',{difficulty:'normal'});ok(cached.cached&&gets===1);
 await env.call('board',{difficulty:'normal',force:true});ok(gets===2);
 await env.call('submit',{run_id:'1',difficulty:'normal',time_ms:81000});ok(calls.length===4);
 let profile=await env.call('profile',{});ok(profile.nickname==='B站玩家'&&!JSON.stringify(profile).includes('private-do-not-display'));
 for (const ms of [0,-1,BASE+1,NaN,1.1])ok((await env.call('submit',{run_id:'bad'+ms,difficulty:'easy',time_ms:ms})).error==='toy_invalid_time');
 ok((await env.call('submit',{run_id:'max',difficulty:'easy',time_ms:BASE})).ok);ok(calls.at(-1).score===0);
 ok((await env.call('submit',{run_id:'min',difficulty:'easy',time_ms:1})).ok);ok(calls.at(-1).score===BASE-1);
 ok(BASE-76000>BASE-81000);
 let attempts=0;
 env=sandbox({submitScore:async()=>{attempts++;if(attempts===1)throw {type:'http_error',code:307044};return {score:BASE-76000};}});
 let p={run_id:'rate',difficulty:'easy',time_ms:76000};
 ok((await env.call('submit',p)).error==='toy_rate_limited');ok((await env.call('submit',p)).error==='toy_rate_limited'&&attempts===1);
 env.advance(2001);ok((await env.call('submit',p)).ok&&attempts===2);
 let resolve;attempts=0;
 env=sandbox({submitScore:()=>{attempts++;return new Promise(r=>resolve=r)}});
 const a=await env.call('submit',p),b=await env.call('submit',p);ok(a.pending&&b.pending&&attempts===1);
 resolve({score:BASE-76000}); await new Promise(r=>setImmediate(r));ok(JSON.parse(env.win.pawToy.poll(a.id)).ok);ok(JSON.parse(env.win.pawToy.poll(b.id)).ok);
 env=sandbox({getRankList:async()=>({entries:[]}),getMyRank:async()=>({ranked:false,rank:0,score:0})});ok((await env.call('board',{difficulty:'easy'})).error==='toy_bad_response');
 env=sandbox({getRankList:async()=>[],getMyRank:async()=>{throw {type:'not_logged_in',code:-101}}});ok((await env.call('board',{difficulty:'easy'})).entries.length===0);
 env=sandbox({submitScore:async()=>{throw {type:'not_logged_in',code:-101}}});ok((await env.call('submit',p)).error==='not_logged_in');
 env=sandbox({getUserProfile:async()=>({data:{uname:'SDK昵称',face:'',toyOpenId:'hidden'}})});profile=await env.call('profile',{});ok(profile.nickname==='SDK昵称'&&!JSON.stringify(profile).includes('hidden'));
 env=sandbox({submitScore:async()=>({})});ok((await env.call('submit',p)).error==='toy_bad_response');
 console.log(`PASS ${count} assertions: OFFLINE SDK MOCKS, no live Toy calls`);
})().catch(e=>{console.error(e);process.exitCode=1});
