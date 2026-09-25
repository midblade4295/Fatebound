#!/usr/bin/env node
/* Dedicated Fatebound arena. Node >=20; no npm dependencies. Default bind is loopback.
   This service neither loads nor changes Legionary, legacy cloud saves, keys or app builds. */
'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),zlib=require('node:zlib');
const A=require('./arena-engine.js');
const W=require('./arena-wire.js'),{compress}=require('./http-compression.js');
const clean=(x,max=24)=>String(x||'').replace(/[<>\x00-\x1f\x7f]/g,'').trim().slice(0,max);
const sha=x=>crypto.createHash('sha256').update(x).digest('hex'),id=()=>crypto.randomUUID(),token=()=>crypto.randomBytes(32).toString('base64url');
const day=now=>new Date(now).toISOString().slice(0,10);
const serverRandom=()=>crypto.randomInt(0,0x100000000)/0x100000000;
function assert(ok,msg,status=400){if(!ok){const e=new Error(msg);e.status=status;throw e;}}
class Store{
 constructor(filename){this.filename=filename;this.data={schema:1,users:{},guilds:{},rooms:{}};if(filename&&fs.existsSync(filename)){this.data=JSON.parse(fs.readFileSync(filename,'utf8'));assert(this.data.schema===1,'Unsupported store schema');}}
 save(){if(!this.filename)return;fs.mkdirSync(path.dirname(this.filename),{recursive:true,mode:0o700});const tmp=this.filename+'.tmp',fd=fs.openSync(tmp,'w',0o600);try{fs.writeFileSync(fd,JSON.stringify(this.data));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}fs.renameSync(tmp,this.filename);}
}
class Matchmaker{
 constructor({store=new Store(null),now=()=>Date.now(),seed=()=>crypto.randomBytes(4).readUInt32LE(),searchMs=A.SEARCH_MS}={}){
  this.store=store;this.now=now;this.seed=seed;this.searchMs=searchMs;this.lobbies=[];this.rooms=new Map();this.membership=new Map();this.dirty=false;
  this.tokenIndex=new Map(Object.values(store.data.users).map(u=>[u.tokenHash,u]));
  for(const [rid,r]of Object.entries(store.data.rooms)){const e=A.Engine.restore(r.engine);e.random=serverRandom;this.rooms.set(rid,{engine:e,acks:r.acks||{},completed:r.completed||false,results:r.results||{}});for(const h of e.s.heroes)if(!h.bot&&!store.data.users[h.id]?.receipts[rid]?.claimed)this.membership.set(h.id,{type:'room',id:rid});}
 }
 createSession(name){const tid=token(),pid=id(),now=this.now();const u={id:pid,tokenHash:sha(tid),name:clean(name)||'Player '+pid.slice(0,4),createdAt:now,lastSeen:now,mastery:{},receipts:{},guildId:null,days:{},earned:{gold:0,fate:0,pts:0,shards:0,xp:0,tokens:0}};this.store.data.users[pid]=u;this.tokenIndex.set(u.tokenHash,u);this.store.save();return {playerId:pid,token:tid,name:u.name,protocol:A.VERSION};}
 auth(raw){assert(raw&&raw.length<300,'Sign in to the arena',401);const hash=sha(raw),u=this.tokenIndex.get(hash);assert(u,'Arena session expired',401);u.lastSeen=this.now();return u;}
 user(pid){const u=this.store.data.users[pid];assert(u,'Unknown player',401);return u;}
 profile(u){return {id:u.id,name:u.name,mastery:u.mastery,earned:u.earned,guild:this.guildView(u),active:this.membership.get(u.id)||null,
  pendingRewards:Object.values(u.receipts).filter(r=>!r.claimed).length};}
 pendingRewards(u){
  // The room may expire after 24h, but earned rewards must remain discoverable.
  return {receipts:Object.values(u.receipts).filter(r=>!r.claimed).sort((a,b)=>(a.at||0)-(b.at||0)).slice(0,100)};
 }
 join(u,prefs){assert(prefs&&typeof prefs==='object'&&!Array.isArray(prefs),'Invalid queue request');const old=this.membership.get(u.id);if(old)return this.state(u);const load=A.loadout(prefs.loadout);assert(Number.isInteger(prefs.char)&&prefs.char>=0&&prefs.char<5,'Invalid hero');assert(Number.isInteger(prefs.weapon)&&prefs.weapon>=0&&prefs.weapon<9,'Invalid weapon');const now=this.now();
  let lobby=this.lobbies.find(l=>l.players.length<A.CAPACITY&&l.deadline>now);if(!lobby){assert(this.lobbies.length<50,'Queue is busy; retry shortly',503);lobby={id:id(),createdAt:now,deadline:now+this.searchMs,players:[]};this.lobbies.push(lobby);}
  lobby.players.push({id:u.id,name:u.name,char:prefs.char,weapon:prefs.weapon,loadout:load,joinedAt:now,lastSeen:now,bot:false});this.membership.set(u.id,{type:'queue',id:lobby.id});return this.state(u);
 }
 cancel(u){const m=this.membership.get(u.id);if(!m)return {status:'idle'};assert(m.type==='queue','A live battle cannot be cancelled',409);const l=this.lobbies.find(x=>x.id===m.id);if(l)l.players=l.players.filter(p=>p.id!==u.id);this.membership.delete(u.id);this.lobbies=this.lobbies.filter(x=>x.players.length);return {status:'idle'};}
 tick(){const now=this.now();for(const l of [...this.lobbies]){const gone=l.players.filter(p=>now-p.lastSeen>8000);for(const p of gone)this.membership.delete(p.id);l.players=l.players.filter(p=>now-p.lastSeen<=8000);if(!l.players.length){this.lobbies=this.lobbies.filter(x=>x!==l);continue;}if(now<l.deadline)continue;
   const players=l.players.map(x=>({...x}));while(players.length<A.CAPACITY){const n=players.length;players.push({id:'bot:'+l.id+':'+n,name:'Bot '+(n+1),bot:true,char:n%5,weapon:[0,1,4,5,7][n%5],loadout:n%2?['barrage','surge']:['bulwark','horn']});}
   const engine=new A.Engine({id:l.id,players,now,seed:this.seed()});engine.random=serverRandom;this.rooms.set(l.id,{engine,acks:{},completed:false,results:{}});for(const p of l.players)this.membership.set(p.id,{type:'room',id:l.id});this.lobbies=this.lobbies.filter(x=>x!==l);this.dirty=true;
  }
  for(const [rid,r]of this.rooms){const s=r.engine.s;if(!s.ended){for(const h of s.heroes)if(!h.bot){h.connected=now-h.lastSeen<=8000;h.substitute=!h.connected;}r.engine.tick(now);this.dirty=true;}
   if(s.ended&&!r.completed){
    r.results||={};
    for(const h of s.heroes.filter(h=>!h.bot)){
     const result=r.results[h.id]||r.engine.result(h.id);r.results[h.id]=result;
     this.awardResult(this.user(h.id),result);
    }
    r.completed=true;this.dirty=true;
   }
   if(s.ended&&now-s.completedAt>86400000){for(const h of s.heroes)if(this.membership.get(h.id)?.id===rid)this.membership.delete(h.id);this.rooms.delete(rid);delete this.store.data.rooms[rid];this.dirty=true;}
  }
 }
 state(u){const m=this.membership.get(u.id),now=this.now();if(!m)return {status:'idle',serverNow:now};if(m.type==='queue'){const l=this.lobbies.find(x=>x.id===m.id);if(!l){this.membership.delete(u.id);return {status:'idle',serverNow:now};}const p=l.players.find(x=>x.id===u.id);if(p)p.lastSeen=now;return {status:'searching',lobbyId:l.id,deadline:l.deadline,serverNow:now,humans:l.players.length,capacity:A.CAPACITY,waitMs:this.searchMs};}
  const r=this.rooms.get(m.id);if(!r){this.membership.delete(u.id);return {status:'idle',serverNow:now,reason:'room_expired',pendingRewards:Object.values(u.receipts).filter(r=>!r.claimed).length};}const h=r.engine.hero(u.id);h.lastSeen=now;if(!h.connected||h.substitute){h.connected=true;h.substitute=false;if(!r.engine.s.ended)r.engine.s.revision++;}const credit=r.engine.currentRules()?(h.credit||{}):h;return {earnings:{gold:Math.min(1500,credit.goldEarned||0),xp:Math.min(150,credit.xpEarned||0),paidRolls:credit.paidRolls||0},status:r.engine.s.ended?'complete':'battle',serverNow:now,match:r.engine.snapshot(),result:r.engine.s.ended?(r.results?.[u.id]||r.engine.result(u.id)):null,receipt:r.engine.s.ended?u.receipts[m.id]||null:null};
 }
 act(u,request){assert(request&&typeof request==='object'&&!Array.isArray(request),'Invalid action request');const m=this.membership.get(u.id);assert(m?.type==='room','No active battle',409);const r=this.rooms.get(m.id);assert(request.matchId===m.id,'Stale match action',409);assert(typeof request.actionId==='string'&&/^[\w-]{8,80}$/.test(request.actionId),'Invalid action identifier');const key=u.id+':'+request.actionId;if(r.acks[key])return {...r.acks[key],state:this.state(u),replayed:true};
  assert(!r.engine.hero(u.id).substitute,'Reconnect before acting',409);const out=r.engine.act(u.id,request,this.now());if(request.type==='roll'){out.rollIndex=r.engine.hero(u.id).rolls;out.appliedAt=this.now();}r.acks[key]={result:out};/* Keep action receipts for the whole match; replaying an old ID must never act twice. */this.dirty=true;return {result:out,state:this.state(u)};
 }
 awardResult(u,r){if(u.receipts[r.id])return u.receipts[r.id];const d=u.days[day(this.now())]||={fate:0,expedition:0};const reward={...r.reward,fate:Math.min(r.reward.fate,Math.max(0,20-d.fate))};d.fate+=reward.fate;
  for(const k of Object.keys(u.earned))u.earned[k]+=reward[k]||0;const mastery=u.mastery[r.char]||={assault:0,guardian:0,commander:0};if(r.eligible)for(const k of Object.keys(mastery))mastery[k]+=r.mastery[k]||0;
  const g=u.guildId&&this.store.data.guilds[u.guildId];let expedition=0;if(g&&r.eligible){this.week(g);const merit=g.route==='defense'?Math.floor(r.stats.absorbed/150)+Math.floor(r.stats.defenseSeconds/25):g.route==='command'?r.stats.rallyAssists+r.stats.flips:Math.floor(r.stats.damage/350);expedition=Math.min(5,Math.max(1,merit),Math.max(0,20-d.expedition));d.expedition+=expedition;g.progress+=expedition;g.contributions[u.id]=(g.contributions[u.id]||0)+expedition;}
  const receipt={id:r.id,at:r.completedAt||this.now(),season:A.seasonKey(r.completedAt||this.now()),char:r.char,weapon:r.weapon,eligible:r.eligible,
   win:r.win,draw:r.draw,stats:r.stats,balanceVersion:r.balanceVersion||109,reward,
   mastery:r.eligible?r.mastery:{assault:0,guardian:0,commander:0},expedition,claimed:false};u.receipts[r.id]=receipt;return receipt;
 }
 claim(u,matchId,shardKind){assert(typeof matchId==='string'&&Object.hasOwn(u.receipts,matchId),'Rewards not ready',409);const receipt=u.receipts[matchId];assert(receipt&&typeof receipt==='object','Rewards not ready',409);if(shardKind!==undefined)assert(['steel','arcane','fletch'].includes(shardKind),'Invalid shard choice');if(!receipt.claimed)receipt.shardKind=shardKind||([5,6].includes(receipt.weapon)?'arcane':[7,8].includes(receipt.weapon)?'fletch':'steel');receipt.claimed=true;const m=this.membership.get(u.id);if(m?.id===matchId)this.membership.delete(u.id);this.flush();return {receipt,profile:this.profile(u)};}
 week(g){const wk=A.weekKey(this.now());if(g.week!==wk){g.week=wk;g.route='assault';g.progress=0;g.contributions={};}return g;}
 guildView(u){const g=u.guildId&&this.store.data.guilds[u.guildId];if(!g)return null;this.week(g);return {id:g.id,name:g.name,code:g.code,leader:g.leader,route:g.route,week:g.week,progress:g.progress,milestones:[20,60,120],members:g.members.map(pid=>({id:pid,name:this.user(pid).name,contribution:g.contributions[pid]||0})),claimed:[0,1,2].filter(i=>u.receipts['guild:'+g.week+':'+i])};}
 guild(u,req){assert(req&&typeof req==='object'&&!Array.isArray(req),'Invalid guild request');assert(!this.membership.has(u.id),'Finish or cancel the match first',409);let g=u.guildId&&this.store.data.guilds[u.guildId];if(req.type==='create'){assert(!g,'Already in a guild');const name=clean(req.name,32);assert(name.length>=2,'Guild name is too short');const code=crypto.randomBytes(5).toString('hex').toUpperCase();g={id:id(),name,code,leader:u.id,members:[u.id]};this.week(g);this.store.data.guilds[g.id]=g;u.guildId=g.id;}
  else if(req.type==='join'){assert(!g,'Leave your current guild first');g=Object.values(this.store.data.guilds).find(x=>x.code===String(req.code).trim().toUpperCase());assert(g,'Guild code not found',404);assert(g.members.length<100,'Guild is full');g.members.push(u.id);u.guildId=g.id;this.week(g);}
  else if(req.type==='leave'){assert(g,'No guild');g.members=g.members.filter(x=>x!==u.id);if(g.leader===u.id)g.leader=g.members[0]||null;u.guildId=null;if(!g.members.length)delete this.store.data.guilds[g.id];}
  else if(req.type==='route'){assert(g,'Join a guild first');this.week(g);assert(g.leader===u.id,'Only the guild leader chooses the route',403);assert(g.progress===0,'The expedition route is already underway',409);assert(['assault','defense','command'].includes(req.route),'Invalid route');g.route=req.route;}
  else if(req.type==='claim'){assert(g,'Join a guild first');this.week(g);const i=req.milestone;assert(Number.isInteger(i)&&i>=0&&i<3&&g.progress>=[20,60,120][i],'Milestone locked');assert((g.contributions[u.id]||0)>0,'Contribute once to claim expedition rewards');const key='guild:'+g.week+':'+i;if(!u.receipts[key]){const reward={gold:[150,300,600][i],fate:0,pts:0,shards:[2,4,8][i],xp:0,tokens:[1,2,4][i]};u.receipts[key]={id:key,at:this.now(),season:A.seasonKey(this.now()),reward,char:0,weapon:0,mastery:{},claimed:false};u.earned.gold+=reward.gold;u.earned.shards+=reward.shards;u.earned.tokens=(u.earned.tokens||0)+reward.tokens;}this.flush();return {guild:this.guildView(u),receipt:u.receipts[key]};}
  else throw Error('Unknown guild action');this.flush();return {guild:this.guildView(u)};
 }
 flush(){for(const [rid,r]of this.rooms)this.store.data.rooms[rid]={engine:r.engine.export(),acks:r.acks,completed:r.completed,results:r.results||{}};this.store.save();this.dirty=false;}
}
function createServer({dataFile=null,allowedOrigins=[],allowLocal=false,trustProxy=false,now,rateLimit=120,staticFile=null}={}){
 const mm=new Matchmaker({store:new Store(dataFile),...(now?{now}:{})}),rates=new Map(),wire=new W.Encoder();let lastFlush=Date.now();
 const server=http.createServer(async(req,res)=>{const origin=req.headers.origin,allowed=!origin||allowedOrigins.includes(origin)||(allowLocal&&origin==='null');
  const url=new URL(req.url,'http://localhost');
  const route=url.pathname.replace(/^\/fatebound\/arena/,'').replace(/^\/arena/,'');
  const negotiated=url.searchParams.get('transport')==='2';
  const number=k=>{const raw=url.searchParams.get(k);if(raw===null||!/^\d{1,16}$/.test(raw))return undefined;const n=Number(raw);return Number.isSafeInteger(n)?n:undefined;};
  const cursor={match:url.searchParams.get('match'),revision:number('revision'),seq:number('seq')};
  let authenticated=null;
  const json=async(status,obj)=>{
   if(negotiated){if(obj?.state?.match)obj={...obj,state:wire.encode(obj.state,cursor)};else if(obj?.match)obj=wire.encode(obj,cursor);}
   // Compress a captured response off the event loop, rather than stopping combat ticks.
   const raw=Buffer.from(JSON.stringify(obj)),packed=await compress(raw,req.headers['accept-encoding']);
   if(res.destroyed||res.writableEnded)return;
   res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');
   res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Vary','Origin, Accept-Encoding');
   if(origin&&allowed)res.setHeader('Access-Control-Allow-Origin',origin);
   if(packed.encoding)res.setHeader('Content-Encoding',packed.encoding);
   res.setHeader('Content-Length',packed.body.length);res.writeHead(status);res.end(packed.body);
  };
  try{assert(allowed,'Origin is not allowed',403);const ip=trustProxy?String(req.headers['x-forwarded-for']||req.socket.remoteAddress).split(',')[0].trim():req.socket.remoteAddress;
   const bucket=Math.floor(Date.now()/60000),key=ip+':'+bucket,n=(rates.get(key)||0)+1;rates.set(key,n);assert(n<=rateLimit*20,'Too many requests',429);if(rates.size>20000)for(const k of rates.keys())if(!k.endsWith(':'+bucket))rates.delete(k);
   if(req.method==='OPTIONS'){res.setHeader('Access-Control-Allow-Origin',origin||'');res.setHeader('Access-Control-Allow-Headers','Authorization,Content-Type');res.setHeader('Access-Control-Allow-Methods','GET,POST,OPTIONS');res.writeHead(204);res.end();return;}
   if(route==='/health'&&req.method==='GET'){await json(200,{ok:true,game:'Fatebound',protocol:1,transportVersion:2,apiBuild:114,balanceVersion:A.BALANCE_VERSION,queueMs:A.SEARCH_MS,capacity:A.CAPACITY,rooms:mm.rooms.size,activeRooms:[...mm.rooms.values()].filter(r=>!r.engine.s.ended).length,queuedPlayers:mm.lobbies.reduce((n,l)=>n+l.players.length,0)});return;}
   if(route==='/'&&staticFile){res.setHeader('Content-Type','text/html; charset=utf-8');fs.createReadStream(staticFile).pipe(res);return;}
   let body={};if(req.method==='POST'){let size=0,chunks=[];for await(const chunk of req){size+=chunk.length;assert(size<=4096,'Request too large',413);chunks.push(chunk);}try{body=JSON.parse(Buffer.concat(chunks).toString()||'{}');}catch(_){throw Error('Invalid JSON');}assert(body!==null&&typeof body==='object'&&!Array.isArray(body),'Expected a JSON object');}
   if(route==='/session'&&req.method==='POST'){const sk=ip+':session:'+bucket,c=(rates.get(sk)||0)+1;rates.set(sk,c);assert(c<=10,'Too many guest sessions',429);await json(201,mm.createSession(body.name));return;}
   const u=mm.auth((req.headers.authorization||'').replace(/^Bearer /,'')),uk=u.id+':'+bucket,un=(rates.get(uk)||0)+1;rates.set(uk,un);assert(un<=rateLimit,'Slow down and retry',429);
   authenticated=u;
   // A heartbeat is applied before ticking, avoiding replacement at an exact deadline.
   if(route==='/state'||route==='/action')mm.state(u);mm.tick();let out;
   if(route==='/profile'&&req.method==='GET')out=mm.profile(u);
   else if(route==='/pending-rewards'&&req.method==='GET')out=mm.pendingRewards(u);
   else if(route==='/queue'&&req.method==='POST')out=mm.join(u,body);
   else if(route==='/cancel'&&req.method==='POST')out=mm.cancel(u);
   else if(route==='/state'&&req.method==='GET')out=mm.state(u);
   else if(route==='/action'&&req.method==='POST')out=mm.act(u,body);
   else if(route==='/claim'&&req.method==='POST')out=mm.claim(u,body.matchId,body.shardKind);
   else if(route==='/guild'&&req.method==='POST')out=mm.guild(u,body);
   else {await json(404,{error:'Not found'});return;}
   if(req.method==='POST')mm.flush();await json(200,out);
  }catch(e){
   let state;
   // Recover authoritative HP/cooldowns even when an authenticated action is rejected.
   if(authenticated&&route==='/action')try{state=mm.state(authenticated);}catch(_){}
   try{await json(e.status||400,{error:clean(e.message,160),...(state?{state}:{})});}
   catch(error){console.error('Arena response failed:',error.message);if(!res.headersSent)res.writeHead(503);res.end();}
  }
 });
 server.headersTimeout=10000;server.requestTimeout=10000;server.keepAliveTimeout=5000;
 const timer=setInterval(()=>{try{mm.tick();if(mm.dirty&&Date.now()-lastFlush>=5000){mm.flush();lastFlush=Date.now();}}catch(e){console.error('Arena tick:',e);}},250);timer.unref();
 server.on('close',()=>{clearInterval(timer);mm.flush();});return {server,mm};
}
if(require.main===module){const port=Number(process.env.PORT||8081),host=process.env.HOST||'127.0.0.1';const {server,mm}=createServer({dataFile:process.env.DATA_FILE||path.join(__dirname,'../data/arena.json'),allowedOrigins:(process.env.ALLOWED_ORIGINS||'').split(',').filter(Boolean),allowLocal:process.env.ALLOW_LOCAL_CLIENTS==='1',trustProxy:process.env.TRUST_PROXY==='1',rateLimit:180});server.listen(port,host,()=>console.log(`Fatebound arena listening on ${host}:${port}; 20 slots / 20 seconds`));for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>{mm.flush();server.close(()=>process.exit(0));setTimeout(()=>process.exit(1),5000).unref();});}
module.exports={Store,Matchmaker,createServer};
