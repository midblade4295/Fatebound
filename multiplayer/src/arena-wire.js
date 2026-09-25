/* Optional arena transport v2: bounded field deltas over ordinary compressed HTTP.
   Combat protocol, authoritative rules, persisted matches and reward receipts stay v1.
   A missing baseline ALWAYS produces a full snapshot; no delta changes game state in place. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.FBArenaWire=api;})(globalThis,function(){
'use strict';
const VERSION=2;
const GLOBAL=['version','balanceVersion','id','mode','practice','startAt','endAt','regulationEnd','phase','ended','now','revision','seq','control','controlDuration','rally','holds','score','winner','objective','completedAt'];
const HERO=['id','name','bot','substitute','connected','side','char','weapon','level','atk','maxHp','hp','tower','shieldSlots','downUntil','focus','focusAt','spell','loadout','ult','forcedCrits','rampage','surgeUntil','rollAt','moveAt','spellAt','rallyAt','ralliesLeft','damage','shieldsBroken','kos','rolls','paidRolls','triples','focusSpent','spellsCast','ultsUsed','streak','hot','lastFaces','giftDamage','storedDamage'];
const TOWER=['id','name','pts','dmg','prev'];
const clone=x=>JSON.parse(JSON.stringify(x));
const pick=(x,keys)=>Object.fromEntries(keys.filter(k=>Object.hasOwn(x,k)).map(k=>[k,clone(x[k])]));
const validInt=n=>Number.isSafeInteger(n)&&n>=0;
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function project(s){
 const x=pick(s,GLOBAL);x.heroes=s.heroes.map(h=>({...pick(h,HERO),storedDamage:h.storedDamage||0}));x.towers=s.towers.map(t=>pick(t,TOWER));
 return x;
}
function changed(a,b,keys){const p={};for(const k of keys)if(Object.hasOwn(b,k)&&!same(a[k],b[k]))p[k]=clone(b[k]);return p;}
function recentEvents(s,cursor){return (s.events||[]).filter(e=>e.seq>cursor&&s.now-e.at<=3000).map(clone);}
function validate(x){
 if(!x||typeof x.id!=='string'||!validInt(x.revision)||!validInt(x.seq)||!Number.isFinite(x.now)||!Array.isArray(x.heroes)||x.heroes.length!==20||!Array.isArray(x.towers)||x.towers.length!==10)throw Error('Invalid arena snapshot');
 if(new Set(x.heroes.map(h=>h.id)).size!==20)throw Error('Duplicate arena slot');
 for(const h of x.heroes)if(typeof h.id!=='string'||!Number.isFinite(h.hp)||h.hp<0||!Number.isFinite(h.downUntil)||!Number.isInteger(h.tower)||h.tower<0||h.tower>=10||!Array.isArray(h.shieldSlots))throw Error('Invalid arena hero');
 return x;
}
class Encoder{
 constructor({maxRooms=128,history=64}={}){this.rooms=new Map();this.maxRooms=maxRooms;this.history=history;}
 encode(state,cursor={}){
  if(!state?.match)return state;
  const original=state.match,current=project(original),id=current.id;
  let history=this.rooms.get(id);
  if(!history){history=new Map();this.rooms.set(id,history);}
  // LRU by room. This cache is disposable; a server restart does not require a save migration.
  this.rooms.delete(id);this.rooms.set(id,history);
  while(this.rooms.size>this.maxRooms)this.rooms.delete(this.rooms.keys().next().value);
  const baseline=cursor.match===id&&validInt(cursor.revision)?history.get(cursor.revision):null;
  const events=recentEvents(original,validInt(cursor.seq)?cursor.seq:0);
  let packet={wire:VERSION,id,revision:current.revision,seq:current.seq,full:current,events};
  if(baseline&&baseline.revision<=current.revision&&baseline.heroes.every((h,i)=>h.id===current.heroes[i].id)){
   const delta={wire:VERSION,id,base:baseline.revision,revision:current.revision,seq:current.seq,set:changed(baseline,current,GLOBAL),heroes:[],towers:[],events};
   current.heroes.forEach((h,i)=>{const p=changed(baseline.heroes[i],h,HERO);if(Object.keys(p).length)delta.heroes.push([i,p]);});
   current.towers.forEach((t,i)=>{const p=changed(baseline.towers[i],t,TOWER);if(Object.keys(p).length)delta.towers.push([i,p]);});
   if(JSON.stringify(delta).length<JSON.stringify(packet).length)packet=delta;
  }
  history.set(current.revision,current);
  while(history.size>this.history)history.delete(history.keys().next().value);
  return {...state,match:packet};
 }
}
class Decoder{
 constructor({history=96}={}){this.history=history;this.snapshots=new Map();this.latest=null;this.stats={full:0,delta:0,stale:0,resync:0};}
 clear(){this.snapshots.clear();this.latest=null;}
 cursor(){return this.latest?{match:this.latest.id,revision:this.latest.revision,seq:this.latest.seq}:{};}
 decode(packet){
  if(!packet||packet.wire!==VERSION)return packet; // Older servers/clients remain compatible.
  const key=id=>packet.id+':'+id;let next;
  if(packet.full){next=clone(packet.full);this.stats.full++;}
  else{
   const baseline=this.snapshots.get(key(packet.base));
   if(!baseline){this.stats.resync++;const e=new Error('Arena baseline expired; requesting a full resync');e.resync=true;throw e;}
   next=clone(baseline);
   function patch(target,data,allowed){if(!data||Array.isArray(data)||typeof data!=='object')throw Error('Invalid arena patch');for(const [k,v]of Object.entries(data)){if(!allowed.includes(k))throw Error('Unknown arena field');target[k]=clone(v);}}
   patch(next,packet.set,GLOBAL);
   for(const [items,field,keys,max] of [[packet.heroes,'heroes',HERO,20],[packet.towers,'towers',TOWER,10]]){
    if(!Array.isArray(items)||items.length>max)throw Error('Invalid arena slots');
    const seen=new Set();for(const [i,p]of items){if(!Number.isInteger(i)||i<0||i>=max||seen.has(i))throw Error('Invalid arena slot index');seen.add(i);patch(next[field][i],p,keys);}
   }
   this.stats.delta++;
  }
  validate(next);
  if(next.id!==packet.id||next.revision!==packet.revision||next.seq!==packet.seq||!Array.isArray(packet.events)||packet.events.length>80)throw Error('Arena revision mismatch');
  if(this.latest?.id===next.id&&next.revision<this.latest.revision)this.stats.stale++;
  else this.latest=next;
  this.snapshots.set(key(next.revision),next);
  while(this.snapshots.size>this.history)this.snapshots.delete(this.snapshots.keys().next().value);
  return {...clone(next),events:clone(packet.events)};
 }
}
function winningDice(faces){
 if(!Array.isArray(faces)||faces.length!==3||faces.some(f=>!['S','C','H','G','E','F'].includes(f)))return {indices:[],tier:'none',symbol:null};
 const count={};for(const f of faces)count[f]=(count[f]||0)+1;
 const symbol=Object.keys(count).find(k=>count[k]===3)||Object.keys(count).find(k=>count[k]===2)|| (faces.includes('S')?'S':faces.includes('G')?'G':null);
 return {indices:faces.map((f,i)=>f===symbol?i:-1).filter(i=>i>=0),tier:symbol&&count[symbol]===3?'triple':symbol&&count[symbol]===2?'pair':'none',symbol};
}
return {VERSION,GLOBAL,HERO,TOWER,project,Encoder,Decoder,winningDice};
});
