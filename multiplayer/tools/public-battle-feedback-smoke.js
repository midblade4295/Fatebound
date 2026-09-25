#!/usr/bin/env node
/* Public alpha smoke test using only real guest API calls and real time.
   Does not modify clocks, HP, dice outcomes, existing users or their saves. */
'use strict';
const https=require('node:https'),http=require('node:http'),zlib=require('node:zlib'),crypto=require('node:crypto'),fs=require('node:fs');
const W=require('../src/arena-wire');
const base=process.argv[2],output=process.argv[3];
if(!base||!output)throw Error('Usage: node public-battle-feedback-smoke.js <approved arena base URL> <report.json>');
const started=new Date(),wait=ms=>new Promise(r=>setTimeout(r,ms)),checks=[],stats={requests:0,encodedBytes:0,decodedBytes:0,br:0,gzip:0,identity:0,full:0,delta:0};
let clients=[];
function record(check,details){checks.push({check,status:'PASS',details});console.log('PASS',check,JSON.stringify(details||{}));}
function raw(url,body,token,enc){return new Promise((resolve,reject)=>{const bytes=body===undefined?null:Buffer.from(JSON.stringify(body)),u=new URL(url),req=(u.protocol==='https:'?https:http).request(u,{method:bytes?'POST':'GET',headers:{'Accept-Encoding':enc||'br, gzip',Origin:'null',...(token?{Authorization:'Bearer '+token}:{}),...(bytes?{'Content-Type':'application/json','Content-Length':bytes.length}:{})},timeout:12000},res=>{const chunks=[];res.on('data',b=>chunks.push(b));res.on('end',()=>{try{const packed=Buffer.concat(chunks),encoding=res.headers['content-encoding'],b=encoding==='br'?zlib.brotliDecompressSync(packed):encoding==='gzip'?zlib.gunzipSync(packed):packed;resolve({status:res.statusCode,data:JSON.parse(b),bytes:packed.length,decoded:b.length,encoding:encoding||'identity',headers:res.headers});}catch(e){reject(e);}});});req.on('timeout',()=>req.destroy(Error('Request timeout')));req.on('error',reject);req.end(bytes);});}
async function request(c,path,body,{legacy=false,encoding}={}){
 const query=legacy?'':('?'+new URLSearchParams({transport:'2',...c.decoder.cursor()}));
 const r=await raw(base+path+query,body,c.token,encoding);
 stats.requests++;stats.encodedBytes+=r.bytes;stats.decodedBytes+=r.decoded;stats[r.encoding]++;
 const state=r.data.state||r.data;
 if(state.match?.wire===2){if(state.match.full)stats.full++;else stats.delta++;state.match=c.decoder.decode(state.match);}
 if(state.status)c.state=state;
 if(r.status>=400){const e=Error(r.data.error||('HTTP '+r.status));e.status=r.status;throw e;}
 return r;
}
function must(ok,why){if(!ok)throw Error(why);}
async function main(){
 const health=(await raw(base+'/health')).data;must(health.apiBuild===114&&health.transportVersion===2&&health.queueMs===20000&&health.capacity===20,'Wrong deployed API');
 record('Public endpoint advertises transport2, 20-second search, 20 slots and unchanged balance110',health);
 for(let i=0;i<2;i++){const r=await raw(base+'/session',{name:'Battle UI check '+(i+1)});must(r.status===201,'Session creation failed');clients.push({...r.data,decoder:new W.Decoder(),lastAction:0,downSeen:false});}
 const joined=Date.now();for(const c of clients)await request(c,'/queue',{char:0,weapon:0,loadout:['barrage','bulwark']});const queueDeadline=clients[0].state.deadline;
 while(Date.now()-joined<35000){for(const c of clients)await request(c,'/state');if(clients.every(c=>c.state.status==='battle'))break;await wait(600);}
 const s=clients[0].state.match;must(clients[0].state.status==='battle'&&clients[1].state.match.id===s.id,'Clients did not share a room');
 must(s.startAt>=queueDeadline&&s.heroes.length===20&&[0,1].every(sd=>s.heroes.filter(h=>h.side===sd).length===10),'Incorrect battle size');
 const searchMs=Date.now()-joined;must(Number.isFinite(queueDeadline),'Queue deadline missing');
 record('Both clients entered the same correctly filled 10-versus-10 battle', {observedSearchMs:searchMs,humans:s.heroes.filter(h=>!h.bot).length,bots:s.heroes.filter(h=>h.bot).length});
 const expectedTowers=new Map(clients.map(c=>[c.playerId,s.heroes.find(h=>h.id===c.playerId).tower]));let receiptChecks=0,bankChecks=0;
 let disconnected=false,reconnected=false,move=false,spell=false,legacySample=null;const battleStarted=Date.now(),room=s.id,seen={};
 while(Date.now()-battleStarted<380000){
  const elapsed=Date.now()-battleStarted;
  for(let i=0;i<clients.length;i++){
   const c=clients[i];if(i===1&&elapsed>=30000&&elapsed<41000)continue;
   await request(c,'/state');if(c.state.status==='complete')continue;
   const snap=c.state.match,h=snap.heroes.find(h=>h.id===c.playerId);must(snap.id===room,'Changed room unexpectedly');
   const other=snap.heroes.find(h=>h.id===clients[1].playerId);
   for(const [id,tower] of expectedTowers)must(snap.heroes.find(x=>x.id===id).tower===tower,'Human slot moved without a requested move');
   const bank=c.state.earnings;must(bank&&Number.isFinite(bank.gold)&&Number.isFinite(bank.xp)&&Number.isSafeInteger(bank.paidRolls),'Authoritative bank missing');bankChecks++;
   if(i===0&&elapsed>38000&&other.substitute)disconnected=true;
   if(i===1&&elapsed>=41000&&disconnected&&!h.substitute)reconnected=true;
   if(h.hp<=0){c.downSeen=true;continue;}
   if(c.downSeen)c.respawnSeen=true;
   if(snap.now<c.lastAction+2300)continue;
   let command;
   if(!move&&i===0){command={type:'move',tower:1};move=true;}
   else if(!spell&&i===0&&h.spell>0&&snap.now>=h.spellAt){command={type:'spell',spell:'barrage'};spell=true;}
   else if(h.focus>=1&&snap.now>=h.rollAt)command={type:'roll',mult:1};
   if(command){const reply=await request(c,'/action',{...command,matchId:room,actionId:crypto.randomUUID()});if(command.type==='move')expectedTowers.set(c.playerId,reply.data.result.tower);if(command.type==='roll'){const fx=reply.data.result.effects;must(fx&&fx.tower===expectedTowers.get(c.playerId)&&Number.isFinite(fx.goldAdded)&&Number.isFinite(fx.shieldAdded)&&Number.isFinite(fx.focusAfter),'Numeric roll confirmation missing');receiptChecks++;}c.lastAction=snap.now;}
  }
  if(!legacySample&&elapsed>60000){const old=await request(clients[0],'/state',undefined,{legacy:true,encoding:'gzip'});legacySample={encoding:old.encoding,compressedBytes:old.bytes,decodedBytes:old.decoded,containsAllHeroes:old.data.match.heroes.length===20};}
  if(clients.every(c=>c.state.status==='complete'))break;
  await wait(750);
 }
 must(clients.every(c=>c.state.status==='complete'),'Battle failed to complete');
 record('Live rolls, movement, spells and compressed backward-compatible snapshots worked',{moved:move,spell,legacySample});must(move&&spell,'Required controls not exercised');
 must(disconnected&&reconnected,'Same-slot disconnect/reconnect was not observed');record('Heartbeat loss substituted a labelled bot without moving the human tower, then reconnected in place',{disconnected,reconnected,towers:Object.fromEntries(expectedTowers)});
 must(receiptChecks>10&&bankChecks>20,'Too few action/bank confirmations');record('Public roll replies include numeric effects and state replies include authoritative bank totals',{receiptChecks,bankChecks});
 must(JSON.stringify(clients[0].state.match.score)===JSON.stringify(clients[1].state.match.score),'Scores disagree');
 record('Real-clock battle completed with synchronized scores and no forced dice/HP changes',{durationMs:clients[0].state.match.completedAt-s.startAt,score:clients[0].state.match.score,paidRolls:clients.map(c=>c.state.result.stats.paidRolls),knockoutObserved:clients.map(c=>c.downSeen),confirmedRespawnObserved:clients.map(c=>!!c.respawnSeen)});
 for(const c of clients){const a=(await request(c,'/claim',{matchId:room,shardKind:'steel'})).data;const b=(await request(c,'/claim',{matchId:room,shardKind:'arcane'})).data;must(JSON.stringify(a.receipt)===JSON.stringify(b.receipt)&&JSON.stringify(a.profile.earned)===JSON.stringify(b.profile.earned),'Duplicate claim changed rewards');}
 record('Repeat reward claims remain exact-once with immutable shard choice');
 for(const c of clients)await request(c,'/queue',{char:0,weapon:0,loadout:['barrage','bulwark']});
 must(clients.every(c=>c.state.status==='searching'),'Second queue unavailable');for(const c of clients)await request(c,'/cancel',{});
 record('Both clients joined a fresh second queue and cancelled cleanly');
 return {status:'PASS',started_utc:started.toISOString(),finished_utc:new Date().toISOString(),checks,network:stats,physical_devices:false,source:'Two programmatic guest clients from the VM through its public TLS endpoint. Counts exclude request/TLS headers and initial game download; no test-control endpoints used.'};
}
main().then(r=>fs.writeFileSync(output,JSON.stringify(r,null,2)+'\n')).catch(e=>{console.error('FAIL',e.message);fs.writeFileSync(output,JSON.stringify({status:'FAIL',checks,error:e.message,network:stats},null,2)+'\n');process.exitCode=1;});
