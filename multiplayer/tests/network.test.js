'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),http=require('node:http'),zlib=require('node:zlib');
const A=require('../src/arena-engine'),W=require('../src/arena-wire'),{encoding,compress}=require('../src/http-compression'),{createServer}=require('../src/arena-server');
function engine(){return new A.Engine({id:'network-fixture',now:100000,players:Array.from({length:20},(_,i)=>({id:'slot-'+i,name:'Test '+i,bot:i>1,char:i%5,weapon:i%9,loadout:['barrage','bulwark']}))});}
const state=e=>({status:e.s.ended?'complete':'battle',serverNow:e.s.now,match:e.snapshot()});
const eq=(a,b)=>{const {events,...plain}=a;assert.deepEqual(plain,W.project(b));};
test('all 216 symbol triples resolve the same winning dice as authoritative combat, for every pair position',()=>{
 const f=['S','C','H','G','E','F'];let count=0;
 for(const x of f)for(const y of f)for(const z of f){const faces=[x,y,z],r=A.resolve(faces),w=W.winningDice(faces);assert.equal(w.symbol,r.action);assert.equal(w.tier,r.tier);if(r.tier!=='none')assert.equal(w.indices.length,r.tier==='triple'?3:2);for(const i of w.indices)assert.equal(faces[i],r.action);count++;}
 assert.equal(count,216);assert.deepEqual(W.winningDice(['S','S','E']).indices,[0,1]);assert.deepEqual(W.winningDice(['S','E','S']).indices,[0,2]);assert.deepEqual(W.winningDice(['E','S','S']).indices,[1,2]);
});
test('full transport snapshot preserves render/control fields but omits internal reward counters and schedules',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();const packet=enc.encode(state(e));assert.equal(packet.match.wire,2);eq(dec.decode(packet.match),e.s);
 for(const h of packet.match.full.heroes){assert(!('credit' in h));assert(!('lastSeen' in h));assert(!('nextBot' in h));assert(!('captureRewardAt' in h));}
});
test('field deltas reproduce every authoritative field across 400 changing combat states',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();let delta=0;
 for(let i=0;i<400;i++){e.tick(100000+i*750);const packet=enc.encode(state(e),dec.cursor());if(!packet.match.full)delta++;eq(dec.decode(packet.match),e.s);}
 assert(delta>350);
});
test('KO, elapsed deadline, confirmed respawn and immediate legal roll survive full/delta encoding',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();dec.decode(enc.encode(state(e)).match);const h=e.s.heroes[0];
 h.hp=0;h.downUntil=e.s.now+45000;e.s.revision++;
 let decoded=dec.decode(enc.encode(state(e),dec.cursor()).match);assert.equal(decoded.heroes[0].hp,0);
 assert.throws(()=>e.act(h.id,{type:'roll'},e.s.now),/respawn/);
 e.tick(h.downUntil-1);decoded=dec.decode(enc.encode(state(e),dec.cursor()).match);assert.equal(decoded.heroes[0].hp,0);
 e.tick(h.downUntil);decoded=dec.decode(enc.encode(state(e),dec.cursor()).match);assert(decoded.heroes[0].hp>0);assert.equal(decoded.heroes[0].downUntil,0);assert.doesNotThrow(()=>e.act(h.id,{type:'roll'},e.s.now));
});
test('out-of-order snapshot decoding does not rewind the newest cursor',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();dec.decode(enc.encode(state(e)).match);const cursor=dec.cursor();
 e.tick(100750);const slow=enc.encode(state(e),cursor);e.tick(101500);const fast=enc.encode(state(e),cursor);
 const newest=dec.decode(fast.match);dec.decode(slow.match);assert.equal(dec.cursor().revision,newest.revision);assert.equal(dec.stats.stale,1);
});
test('lost/expired decoder baseline requests resync; missing encoder baseline sends full state',()=>{
 const e=engine(),enc=new W.Encoder({history:1}),dec=new W.Decoder();dec.decode(enc.encode(state(e)).match);const old=dec.cursor();
 e.tick(100750);const packet=enc.encode(state(e),old);assert(!packet.match.full);dec.clear();assert.throws(()=>dec.decode(packet.match),e=>e.resync===true);
 e.tick(101500);assert(enc.encode(state(e),old).match.full);
});
test('event cursor does not resend notifications, and old reconnect events are not shipped',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();dec.decode(enc.encode(state(e)).match);
 e.event('spell','A real new spell',e.s.now);e.s.revision++;
 let x=enc.encode(state(e),dec.cursor());assert.equal(x.match.events.length,1);dec.decode(x.match);
 x=enc.encode(state(e),dec.cursor());assert.equal(x.match.events.length,0);
 e.s.now+=4000;e.s.revision++;assert.equal(enc.encode(state(e),{}).match.events.length,0);
});
test('invalid patch keys, indices and mismatched revisions cannot partially corrupt a decoder',()=>{
 const e=engine(),enc=new W.Encoder(),dec=new W.Decoder();dec.decode(enc.encode(state(e)).match);const cur=dec.cursor();e.tick(100750);
 const packet=enc.encode(state(e),cur).match;const bad=JSON.parse(JSON.stringify(packet));bad.heroes=[[24,{hp:0}]];assert.throws(()=>dec.decode(bad),/index/);assert.deepEqual(dec.cursor(),cur);
 const polluted=JSON.parse(JSON.stringify(packet));polluted.set=JSON.parse('{"__proto__":{"polluted":true}}');assert.throws(()=>dec.decode(polluted),/Unknown/);assert.equal({}.polluted,undefined);
 eq(dec.decode(packet),e.s);
});
test('Accept-Encoding honors q=0 and quality ordering, preferring Brotli only when acceptable',()=>{
 assert.equal(encoding('br,gzip'),'br');assert.equal(encoding('br;q=0,gzip;q=1'),'gzip');assert.equal(encoding('br;q=.3,gzip;q=.8'),'gzip');assert.equal(encoding('br;q=0,gzip;q=0'),null);assert.equal(encoding('gzip;q=0,*;q=1'),'br');assert.equal(encoding('gzip;q=garbage'),null);
});
test('Brotli/gzip decompress byte-exactly, and tiny/uncompressible JSON is not inflated',async()=>{
 const b=Buffer.from(JSON.stringify({heroes:Array.from({length:20},()=>({hp:2000,focus:4,tower:3}))}));
 for(const c of ['gzip','br']){const r=await compress(b,c);assert.equal(r.encoding,c);assert(r.body.length<b.length);assert.deepEqual(c==='br'?zlib.brotliDecompressSync(r.body):zlib.gunzipSync(r.body),b);}
 assert.equal((await compress(Buffer.from('{}'),'gzip')).encoding,null);
});
function send(port,path,body,token,enc='br, gzip'){
 return new Promise((resolve,reject)=>{const b=body===undefined?null:JSON.stringify(body);const req=http.request({host:'127.0.0.1',port,path,method:b?'POST':'GET',headers:{'Accept-Encoding':enc,Origin:'null',...(token?{Authorization:'Bearer '+token}:{}),...(b?{'Content-Type':'application/json','Content-Length':Buffer.byteLength(b)}:{})}},res=>{const parts=[];res.on('data',x=>parts.push(x));res.on('end',()=>{let data=Buffer.concat(parts);const bytes=data.length;try{if(res.headers['content-encoding']==='br')data=zlib.brotliDecompressSync(data);if(res.headers['content-encoding']==='gzip')data=zlib.gunzipSync(data);resolve({status:res.statusCode,headers:res.headers,bytes,json:JSON.parse(data)});}catch(e){reject(e);}});});req.on('error',reject);req.end(b);});
}
test('real HTTP negotiates deltas, compression and authoritative error recovery; old clients still receive full snapshots',async()=>{
 let now=Date.now();const {server,mm}=createServer({now:()=>now,allowLocal:true,rateLimit:10000});await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;
 try{
  const session=(await send(port,'/session',{name:'Wire test'})).json,token=session.token;
  await send(port,'/queue',{char:0,weapon:0,loadout:['barrage','bulwark']},token);now+=20000;mm.state(mm.user(session.playerId));
  const old=await send(port,'/state',undefined,token);assert(old.json.match.heroes.length===20);assert.equal(old.json.match.wire,undefined);
  const first=await send(port,'/state?transport=2',undefined,token);assert.equal(first.headers['content-encoding'],'br');assert(first.headers.vary.includes('Accept-Encoding'));const dec=new W.Decoder();dec.decode(first.json.match);
  now+=750;const query=new URLSearchParams({transport:'2',...dec.cursor()});const next=await send(port,'/state?'+query,undefined,token,'gzip');assert(!next.json.match.full);dec.decode(next.json.match);
  const room=mm.rooms.get(dec.latest.id);room.engine.hero(session.playerId).hp=0;room.engine.hero(session.playerId).downUntil=now+45000;
  const error=await send(port,'/action?transport=2',{matchId:room.engine.s.id,actionId:'net-error-test',type:'roll'},token);assert.equal(error.status,400);assert.match(error.json.error,/respawn/);assert.equal(dec.decode(error.json.state.match).heroes.find(h=>h.id===session.playerId).hp,0);
 }finally{await new Promise(r=>server.close(r));}
});

test('replayed roll receipts identify their original roll, not the later substitute/current roll',()=>{
 const {Matchmaker}=require('../src/arena-server');let now=1000000;const mm=new Matchmaker({now:()=>now});
 const session=mm.createSession('Reply recovery'),u=mm.user(session.playerId);mm.join(u,{char:0,weapon:0,loadout:['barrage','bulwark']});now+=20000;mm.state(u);mm.tick();
 const room=mm.rooms.get(mm.membership.get(u.id).id),h=room.engine.hero(u.id);room.engine.faces=()=>['H','H','S'];
 const command={type:'roll',matchId:room.engine.s.id,actionId:'original-roll'};
 const first=mm.act(u,command);assert.equal(first.result.rollIndex,1);
 now+=2300;h.focus=8;room.engine.faces=()=>['G','G','S'];mm.act(u,{...command,actionId:'subsequent-roll'});
 const replay=mm.act(u,command);assert(replay.replayed);assert.equal(replay.result.rollIndex,1);assert.equal(replay.state.match.heroes.find(x=>x.id===u.id).rolls,2);assert.deepEqual(replay.state.match.heroes.find(x=>x.id===u.id).lastFaces,['G','G','S']);
});
