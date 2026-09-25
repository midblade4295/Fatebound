/* Fatebound Arena protocol 1. Shared, deterministic combat rules; no DOM or network.
   The server is the authority online. Local challenges run this same engine explicitly offline. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.FBArena=api;})(globalThis,function(){
'use strict';
const VERSION=1,CAPACITY=20,SEARCH_MS=20000,MATCH_MS=300000,OVERTIME_MS=60000;
// Rules are stamped per match. Older saved matches retain their original reward math.
const BALANCE_VERSION=110, CAPTURE_REWARD_MS=30000;
const CREDIT_KEYS=['damage','absorbed','shieldsBroken','kos','rolls','paidRolls','triples',
 'focusSpent','goldEarned','xpEarned','flips','defenseSeconds','rallyAssists','gifts','giftsSent','spellsCast','ultsUsed'];
const newCredit=()=>Object.fromEntries(CREDIT_KEYS.map(k=>[k,0]));
const seasonKey=now=>Math.max(0,Math.floor((now-Date.UTC(2026,0,5))/(30*86400000)));
const SPELLS={barrage:{name:'Barrage',desc:'An immediate 1.5× triple-sword strike. No Focus cost.'},bulwark:{name:'Bulwark',desc:'8 seconds of half damage and a shield for allies here.'},horn:{name:'War Horn',desc:'Rally teammates here without spending Focus.'},surge:{name:'Arcane Surge',desc:'+4 Focus and +25% roll results for 10 seconds.'}};
const CHAR=[{atk:1,hp:1.15,crit:0},{atk:1,hp:1,crit:.3},{atk:1.1,hp:1,crit:0},{atk:1,hp:.95,crit:.1,gold:1.25},{atk:1.05,hp:1,crit:.1,energy:1}];
const ROMAN=['I','II','III','IV','V','VI','VII','VIII','IX','X'];
const MODES={standard:{name:'Fair-play skirmish',regen:14000},focus:{name:'Focus rush',regen:7000},draft:{name:'Fixed-loadout trial',regen:14000,loadout:['barrage','bulwark']},ward:{name:'Guardian trial',regen:14000}};
const clone=x=>JSON.parse(JSON.stringify(x));
const cap=(x,a,b)=>Math.max(a,Math.min(b,x));
function check(ok,msg){if(!ok)throw new Error(msg);}
function loadout(x){check(Array.isArray(x)&&x.length===2&&x[0]!==x[1]&&x.every(k=>typeof k==='string'&&Object.hasOwn(SPELLS,k)),'Choose two different spells');return [...x];}
function weekKey(now){const d=new Date(now);d.setUTCHours(0,0,0,0);d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7));return d.toISOString().slice(0,10);}
function dailyMode(now){return ['focus','draft','ward'][Math.floor(now/86400000)%3];}
function resolve(faces){const counts={};faces.forEach(x=>counts[x]=(counts[x]||0)+1);const sym=Object.keys(counts).find(x=>counts[x]===3)||Object.keys(counts).find(x=>counts[x]===2);const tier=sym?(counts[sym]===3?'triple':'pair'):'none';return {action:sym||(faces.includes('S')?'S':faces.includes('G')?'G':null),tier,units:{none:1,pair:2,triple:5}[tier]};}
class Engine{
 constructor({id,players,now,seed=12345,mode='standard',duration=MATCH_MS,practice=false,scenario=null}){
  check(typeof id==='string'&&Array.isArray(players)&&players.length===CAPACITY,'A match needs exactly 20 combatants');
  check(new Set(players.map(p=>p.id)).size===CAPACITY,'Duplicate participant');check(typeof mode==='string'&&Object.hasOwn(MODES,mode),'Unknown mode');
  this.seed=seed>>>0||1;this.s={version:VERSION,balanceVersion:BALANCE_VERSION,id,mode,practice,startAt:now,endAt:now+duration,regulationEnd:now+duration,phase:'day',ended:false,now,revision:0,events:[],seq:0,control:[0,0],controlDuration:0,rally:[null,null],holds:[{},{}],score:[0,0],winner:null,
   objective:{tower:5+Math.floor(this.random()*3),warnAt:now+105000,startAt:now+120000,endAt:now+150000,held:[0,0],status:'upcoming',winner:null},towers:ROMAN.map((name,i)=>({id:i,name,pts:i>=8?3:i>=5?2:1,dmg:[0,0],prev:-1}))};
  const counts=[0,0];this.s.heroes=players.map((p,i)=>{const side=i%2,ci=Number.isInteger(p.char)?cap(p.char,0,4):0,c=CHAR[ci],maxHp=Math.round(1800*c.hp),sp=MODES[mode].loadout||loadout(p.loadout||['barrage','bulwark']);return {id:p.id,name:String(p.name||'Player').slice(0,24),bot:!!p.bot,substitute:false,connected:!p.bot,side,char:ci,weapon:cap(p.weapon|0,0,8),level:10,atk:Math.round(30*c.atk),maxHp,hp:maxHp,weaponMult:1,tier:0,tower:counts[side]++,shieldSlots:[],downUntil:0,focus:4,focusAt:now,spell:0,loadout:[...sp],ult:0,forcedCrits:0,rampage:0,surgeUntil:0,rollAt:now,nextBot:now+2500+i*173,lastSeen:now,moveAt:0,spellAt:0,ultAt:0,rallyAt:0,ralliesLeft:2,damage:0,absorbed:0,shieldsBroken:0,kos:0,rolls:0,paidRolls:0,triples:0,focusSpent:0,goldEarned:0,xpEarned:0,flips:0,defenseSeconds:0,rallyAssists:0,gifts:0,giftDamage:0,spellsCast:0,ultsUsed:0,streak:0,hot:false,lastFaces:null,credit:newCredit(),captureRewardAt:{},storedDamage:0};});
  if(mode==='ward')for(const h of this.s.heroes)this.shields(h,1,60);
  if(scenario&&practice){const ti=cap(scenario.tower|0,0,9);this.s.heroes[0].tower=ti;this.s.heroes[1].tower=ti;this.s.towers[ti].dmg=[0,Math.max(0,Number(scenario.deficit)||180)];}
  this.event('start','20 combatants · 5-minute battle',now);this.updateScores();
 }
 currentRules(){return (this.s.balanceVersion||109)>=110;}
 bump(h,key,amount){
  h[key]=(h[key]||0)+amount;
  // A bot substitute preserves the slot, not the absent player's earning power.
  if(this.currentRules()&&!h.bot&&!h.substitute){
   h.credit||=newCredit();h.credit[key]=(h.credit[key]||0)+amount;
  }
 }
 giftLimit(h){return this.currentRules()?h.maxHp*2:Infinity;}
 random(){let x=this.seed;x^=x<<13;x^=x>>>17;x^=x<<5;this.seed=x>>>0;return this.seed/4294967296;}
 faces(){const symbols=['S','C','H','G','E','F'],bucket=this.random(),take=()=>symbols.splice(Math.floor(this.random()*symbols.length),1)[0],a=take();const f=bucket<.15?[a,a,a]:bucket<.70?[a,a,take()]:[a,take(),take()];for(let i=2;i>0;i--){const j=Math.floor(this.random()*(i+1));[f[i],f[j]]=[f[j],f[i]];}return f;}
 event(type,text,now,extra={}){const s=this.s;s.events.push({seq:++s.seq,type,text,at:now,...extra});if(s.events.length>80)s.events.shift();}
 hero(id){const h=this.s.heroes.find(x=>x.id===id);check(h,'Not in this match');return h;}
 leader(t){return t.dmg[0]>t.dmg[1]?0:t.dmg[1]>t.dmg[0]?1:-1;}
 points(sd){return this.s.towers.reduce((n,t)=>n+(this.leader(t)===sd?t.pts:0),0);}
 updateScores(){this.s.score=[0,1].map(sd=>Math.round((this.s.controlDuration?this.s.control[sd]/this.s.controlDuration:0)+this.points(sd)*2));}
 shields(h,n,strength){let gain=0;for(let i=0;i<n;i++){if(h.shieldSlots.length<3){h.shieldSlots.push(strength);gain+=strength;}else{const min=Math.min(...h.shieldSlots),ix=h.shieldSlots.indexOf(min);if(strength>min){h.shieldSlots[ix]=strength;gain+=strength-min;}}}return gain;}
 hit(who,amount,now,{ignoreShield=false,rewardCapture=false}={}){
  const s=this.s,ti=who.tower,t=s.towers[ti],before=this.leader(t),foes=s.heroes.filter(h=>h.side!==who.side&&h.tower===ti&&h.hp>0);let damage=Math.round(amount),absorbed=0,dealt=0;
  if((s.holds[1-who.side][ti]||0)>now)damage=Math.round(damage*.5);
  if(!foes.length){dealt=Math.round(damage*1.2);t.dmg[who.side]+=dealt;this.bump(who,'damage',dealt);}
  else{for(const h of foes){if(damage<=0)break;h.shieldSlots.sort((a,b)=>a-b);while(!ignoreShield&&damage>0&&h.shieldSlots.length){const v=Math.min(damage,h.shieldSlots[0]);h.shieldSlots[0]-=v;damage-=v;absorbed+=v;this.bump(h,'absorbed',v);if(h.shieldSlots[0]<=0){h.shieldSlots.shift();this.bump(who,'shieldsBroken',1);}}
    if(damage<=0)break;const v=Math.min(damage,h.hp);h.hp-=v;damage-=v;dealt+=v;this.bump(who,'damage',v);t.dmg[who.side]+=v;
    if(h.hp<=0){h.downUntil=now+45000;h.shieldSlots=[];this.bump(who,'kos',1);this.event('ko',`${who.name} defeated ${h.name}`,now,{actor:who.id,target:h.id,tower:ti});}
   }
   if(foes.every(h=>h.hp<=0)){const breach=Math.round(foes.reduce((a,h)=>a+h.maxHp,0)*.15);t.dmg[who.side]+=breach;this.bump(who,'damage',breach);dealt+=breach;}
  }
  const after=this.leader(t);
  if(after!==before&&after===who.side){
   if(before!==-1)this.bump(who,'flips',1);
   t.prev=after;
   // Neutral tagging, spells, ultimates and stored gifts cannot fund another spell.
   // A paid roll can earn a contested-capture bonus at most once per tower per 30s.
   who.captureRewardAt||={};
   const eligible=!this.currentRules()||(rewardCapture&&before!==-1&&
    now>=(who.captureRewardAt[ti]??-Infinity)+CAPTURE_REWARD_MS);
   if(eligible){who.focus=Math.min(8,who.focus+1);who.spell=Math.min(2,who.spell+1);who.captureRewardAt[ti]=now;}
   this.event('capture',`Tower ${t.name} captured${eligible?' · +1 Focus and spell charge':''}`,now,{actor:who.id,side:who.side,tower:ti,rewarded:eligible});
  }
  return {dealt,absorbed};
 }
 power(now){const elapsed=now-this.s.startAt;return elapsed>=240000?1.5:elapsed>=120000?1.15:1;}
 rally(h,now,free=false){check(now>=h.rallyAt,'Rally is cooling down');check(h.ralliesLeft>0,'No rallies remaining');if(!free){check(h.focus>=2,'Rally needs 2 Focus');h.focus-=2;}
  h.ralliesLeft--;h.rallyAt=now+60000;this.s.rally[h.side]={leader:h.id,tower:h.tower,until:now+60000,rollers:[]};
  // Human teammates choose whether to rotate. Only explicitly labelled bots move automatically.
  for(const b of this.s.heroes)if(b.side===h.side&&(b.bot||b.substitute)&&this.random()<.45)b.tower=h.tower;
  this.event('rally',`${h.name} rallied Tower ${ROMAN[h.tower]}`,now,{actor:h.id,side:h.side,tower:h.tower});
 }
 act(id,input,now){const h=this.hero(id);check(!this.s.ended,'Match has ended');check(h.hp>0,'Wait to respawn');check(input&&typeof input.type==='string','Invalid action');let result={type:input.type};
  if(input.type==='move'){check(Number.isInteger(input.tower)&&input.tower>=0&&input.tower<10,'Invalid tower');check(now>=h.moveAt,'Moving too fast');h.tower=input.tower;h.moveAt=now+700;result.tower=h.tower;}
  else if(input.type==='roll'){
   check(now>=h.rollAt,'Dice are still settling');check(input.allIn===undefined||typeof input.allIn==='boolean','Invalid ALL-IN flag');
   check(input.mult===undefined||(Number.isInteger(input.mult)&&input.mult>=1&&input.mult<=4),'Multiplier must be an integer from 1 to 4');
   const freeRampage=this.currentRules()&&h.rampage>0;
   const mult=freeRampage?1:input.allIn?Math.max(4,h.focus*2):(input.mult??1),req={1:0,2:2,3:4,4:6};
   check(freeRampage|| (input.allIn?h.focus>=3:(Object.hasOwn(req,mult)&&h.focus>=req[mult])),'Multiplier unavailable');
   const cost=h.rampage>0?0:input.allIn?h.focus:mult;check(h.focus>=cost,'Not enough Focus');
   h.focus-=cost;this.bump(h,'focusSpent',cost);h.rollAt=now+2200;this.bump(h,'rolls',1);if(cost>0&&!h.bot&&!h.substitute){this.bump(h,'paidRolls',1);this.bump(h,'xpEarned',cost);}
   const enchanted=h.forcedCrits>0;const f=this.faces();if(h.hot){f[2]=f[0];h.hot=false;h.streak=0;}if(h.forcedCrits>0){f[2]='C';if(f[0]!=='C'&&f[1]!=='C')f[1]='C';h.forcedCrits--;}
   const r=resolve(f);h.lastFaces=f;const triple=r.tier==='triple';if(triple){this.bump(h,'triples',1);h.spell=Math.min(2,h.spell+(this.s.endAt-now<=30000?2:1));}
   if(r.tier!=='none'&&cost>0){h.streak++;if(h.streak>=10)h.hot=true;}
   const surge=now<h.surgeUntil?1.25:1,rally=this.s.rally[h.side],rallyHere=rally&&rally.tower===h.tower&&rally.until>now,rm=rallyHere?Math.min(2,1+.1*rally.rollers.length):1;
   if(rallyHere&&h.id!==rally.leader&&!rally.rollers.includes(h.id)){rally.rollers.push(h.id);this.bump(this.hero(rally.leader),'rallyAssists',1);}
   let strike={dealt:0,absorbed:0};
   if(r.action==='S'||r.action==='C'){strike=this.hit(h,r.units*h.atk*mult*surge*rm*this.power(now)*(h.streak>=5?1.1:1)*(h.rampage>0?2:1)*(r.action==='C'?3+CHAR[h.char].crit+(this.currentRules()&&enchanted?1:0):1)*(r.action==='C'&&triple?1.25:1),now,{rewardCapture:cost>0});}
   else if(r.action==='H'){const targets=triple?this.s.heroes.filter(a=>a.side===h.side&&a.tower===h.tower&&a.hp>0):[h];for(const a of targets)this.shields(a,1,Math.round(2*h.atk*mult*surge));}
   else if(r.action==='E')h.focus=Math.min(8,h.focus+Math.round(((triple?5:1)+(CHAR[h.char].energy||0))*mult*surge));
   else if(r.action==='F'){
    const amount=this.currentRules()?Math.round(r.units*h.atk*mult*surge*this.power(now)*1.25):Math.round(500*mult*(triple?3:1));
    h.giftDamage=Math.min(this.giftLimit(h),h.giftDamage+amount);this.bump(h,'gifts',1);
   }
   else if(r.action==='G')this.bump(h,'goldEarned',Math.round(({none:5,pair:25,triple:200}[r.tier])*mult*surge*(CHAR[h.char].gold||1)));
   if(r.tier!=='none'&&r.action!=='E')h.focus=Math.min(8,h.focus+1);
   if(h.rampage>0)h.rampage--;else h.ult=Math.min(100,h.ult+Math.min(10,(triple?8:r.tier==='pair'?3:1)*mult));
   result={...result,faces:f,tier:r.tier,symbol:r.action,mult,cost,...strike};this.event('roll',`${h.name}: ${r.tier} ${r.action||'mixed'}`,now,{actor:id,tower:h.tower,...result});
  }else if(input.type==='spell'){
   check(h.loadout.includes(input.spell),'Spell is not equipped');check(h.spell>0,'No spell charges');check(now>=h.spellAt,'Spell is cooling down');if(input.spell==='horn'){check(now>=h.rallyAt&&h.ralliesLeft>0,'Rally unavailable');}
   h.spell--;this.bump(h,'spellsCast',1);h.spellAt=now+650;
   if(input.spell==='barrage')Object.assign(result,this.hit(h,(this.currentRules()?5:2)*h.atk*1.5*this.power(now),now));
   if(input.spell==='bulwark'){this.s.holds[h.side][h.tower]=now+8000;for(const a of this.s.heroes.filter(a=>a.side===h.side&&a.tower===h.tower&&a.hp>0))this.shields(a,1,h.atk*4);}
   if(input.spell==='horn')this.rally(h,now,true);
   if(input.spell==='surge'){h.focus=Math.min(8,h.focus+4);h.surgeUntil=now+10000;}
   this.event('spell',`${h.name}: ${SPELLS[input.spell].name}`,now,{actor:id,tower:h.tower,spell:input.spell});
  }else if(input.type==='rally')this.rally(h,now);
  else if(input.type==='gift'){check(h.giftDamage>0,'No stored attack to send');const target=this.hero(input.target);check(target.id!==h.id&&target.side===h.side,'Choose a teammate');const room=Math.max(0,this.giftLimit(target)-(target.storedDamage||0));
   check(room>0,'That teammate already has a full stored-attack bank');
   const sent=Math.min(room,h.giftDamage);target.storedDamage=(target.storedDamage||0)+sent;h.giftDamage-=sent;this.bump(h,'giftsSent',1);result.sent=sent;this.event('gift',`${h.name} sent an attack to ${target.name}`,now,{actor:id,target:target.id});}
  else if(input.type==='stored'){check((h.storedDamage||0)>0,'No stored attack');Object.assign(result,this.hit(h,h.storedDamage,now));h.storedDamage=0;}
  else if(input.type==='ultimate'){
   check(h.ult>=100,'Ultimate is not ready');h.ult=0;this.bump(h,'ultsUsed',1);
   if(h.char===0){this.s.holds[h.side][h.tower]=now+10000;for(const a of this.s.heroes.filter(a=>a.side===h.side&&a.tower===h.tower))this.shields(a,a.id===h.id?3:2,h.atk*2);}
   if(h.char===1)h.forcedCrits=3;if(h.char===2)h.rampage=5;
   if(h.char===3){const pool=this.s.heroes.filter(a=>a.side!==h.side&&a.tower===h.tower).reduce((n,a)=>n+a.maxHp,0);Object.assign(result,this.hit(h,pool*.25*this.power(now),now,{ignoreShield:true}));}
   if(h.char===4){const before=h.kos;for(let i=0;i<6;i++)this.hit(h,h.atk*2*this.power(now),now);
    if(this.currentRules())h.focus=Math.min(8,h.focus+3*(h.kos-before));
   }
   this.event('ultimate',`${h.name} used an ultimate`,now,{actor:id,tower:h.tower});
  }else throw Error('Unknown action');
  this.s.revision++;this.updateScores();return result;
 }
 tick(now){const s=this.s;if(s.ended)return;const prev=s.now,dt=cap(now-prev,0,5000);s.now=now;
  const bankTo=Math.min(now,s.startAt+240000),bankFrom=Math.min(prev,s.startAt+240000),bankDt=Math.max(0,bankTo-bankFrom);s.controlDuration+=bankDt;for(const sd of [0,1])s.control[sd]+=this.points(sd)*bankDt;
  for(const h of s.heroes){if(h.hp<=0&&now>=h.downUntil){h.hp=h.maxHp;h.downUntil=0;this.event('respawn',`${h.name} returned`,now,{actor:h.id});}
   const n=Math.floor((now-h.focusAt)/MODES[s.mode].regen);if(n>0){h.focus=Math.min(8,h.focus+n);h.focusAt+=n*MODES[s.mode].regen;}
   if(h.hp>0&&this.leader(s.towers[h.tower])===h.side&&s.heroes.some(a=>a.side!==h.side&&a.tower===h.tower&&a.hp>0))this.bump(h,'defenseSeconds',dt/1000);
  }
  const o=s.objective;
  if(o.status==='upcoming'&&now>=o.warnAt){o.status='warning';this.event('objective',`Supply objective at Tower ${ROMAN[o.tower]} in 15 seconds`,now,{tower:o.tower});}
  if(o.status==='warning'&&now>=o.startAt){o.status='active';this.event('objective',`Hold Tower ${ROMAN[o.tower]} for the supply bonus`,now,{tower:o.tower});}
  if(o.status==='active'){const side=this.leader(s.towers[o.tower]);if(side>=0)o.held[side]+=Math.max(0,Math.min(now,o.endAt)-Math.max(prev,o.startAt));if(now>=o.endAt){o.status='complete';o.winner=o.held[0]>o.held[1]?0:o.held[1]>o.held[0]?1:null;if(o.winner!==null)for(const h of s.heroes.filter(h=>h.side===o.winner)){h.focus=Math.min(8,h.focus+1);h.spell=Math.min(2,h.spell+1);}this.event('objective',o.winner===null?'Supply objective tied — no bonus':'Supply objective secured · +1 Focus and spell charge',now,{side:o.winner,tower:o.tower});}}
  const old=s.phase;if(s.phase!=='overtime')s.phase=now>=s.startAt+240000?'finale':now>=s.startAt+120000?'pressure':'day';if(old!==s.phase)this.event('phase',s.phase==='finale'?'FINAL MINUTE · attack ×1.5':'PRESSURE RISING · attack ×1.15',now);
  for(const h of s.heroes){if(!(h.bot||h.substitute)||h.hp<=0||now<h.nextBot)continue;h.nextBot=now+2600+Math.floor(this.random()*2700);
   try{if(o.status==='active'&&this.random()<.4)h.tower=o.tower;else if(this.random()<.12)h.tower=Math.floor(this.random()*10);
    if(h.ult>=100)this.act(h.id,{type:'ultimate'},now);
    else if(h.spell>0&&this.random()<.4)this.act(h.id,{type:'spell',spell:h.loadout[Math.floor(this.random()*2)]},now);
    else if(h.focus>=1||h.rampage>0)this.act(h.id,{type:'roll',mult:h.focus>=4&&this.random()<.4?2:1},now);
    if(h.giftDamage){
     const eligible=s.heroes.filter(a=>a.id!==h.id&&a.side===h.side&&a.hp>0&&(a.storedDamage||0)<this.giftLimit(a));
     const friend=this.currentRules()?eligible[Math.floor(this.random()*eligible.length)]:s.heroes.find(a=>a.id!==h.id&&a.side===h.side);
     if(friend)this.act(h.id,{type:'gift',target:friend.id},now);
    }if(h.storedDamage)this.act(h.id,{type:'stored'},now);
   }catch(_){} // legal cooldown/resource misses are expected for bots
  }
  this.updateScores();
  if(s.phase==='overtime'&&(s.score[0]!==s.score[1]||now>=s.endAt))this.finish(now);
  else if(now>=s.endAt){if(s.score[0]===s.score[1]){s.phase='overtime';s.endAt=now+OVERTIME_MS;this.event('phase','SUDDEN DEATH · next crown lead wins',now);}else this.finish(now);}
  s.revision++;
 }
 finish(now){const s=this.s;if(s.ended)return;this.updateScores();const d=[0,1].map(sd=>s.heroes.filter(h=>h.side===sd).reduce((n,h)=>n+h.damage,0));s.winner=s.score[0]>s.score[1]?0:s.score[1]>s.score[0]?1:d[0]>d[1]?0:d[1]>d[0]?1:null;s.ended=true;s.phase='complete';s.completedAt=now;this.event('end',s.winner===null?'DRAW':'MATCH COMPLETE',now,{winner:s.winner});}
 result(id){const actor=this.hero(id),s=this.s;check(s.ended,'Match is not complete');
  const h=this.currentRules()?{...actor,...(actor.credit||newCredit())}:actor;
  const eligible=!s.practice&&h.paidRolls>=5,win=s.winner===h.side;
  const allies=s.heroes.filter(a=>a.side===h.side).map(a=>this.currentRules()&&!a.bot?{...a,...(a.credit||newCredit())}:a);
  const champ=h.damage>0&&allies.every(a=>a.damage<=h.damage),breaker=h.shieldsBroken>0&&allies.every(a=>a.shieldsBroken<=h.shieldsBroken),
   mastery={assault:Math.min(60,Math.floor(h.damage/150)),guardian:Math.min(60,Math.floor(h.absorbed/100)+Math.floor(h.defenseSeconds/15)),commander:Math.min(60,h.rallyAssists*3+h.flips*2)},
   tip=h.spell>0?`You finished with ${h.spell} unused spell charge${h.spell===1?'':'s'}.`:h.flips===0?'Try rotating to a contested objective before the final minute.':'Review your final tower choice and try a different spell pairing.';
  return {id:s.id,char:h.char,weapon:h.weapon,balanceVersion:s.balanceVersion||109,completedAt:s.completedAt,eligible,practice:s.practice,win,draw:s.winner===null,score:s.score,side:h.side,mastery,stats:{damage:h.damage,absorbed:h.absorbed,defenseSeconds:Math.floor(h.defenseSeconds),rallyAssists:h.rallyAssists,flips:h.flips,rolls:h.rolls,paidRolls:h.paidRolls,triples:h.triples,kos:h.kos,shieldsBroken:h.shieldsBroken,gifts:this.currentRules()?(h.giftsSent||0):h.gifts,spells:h.spellsCast},tip,scenario:{tower:h.tower,deficit:Math.max(0,s.towers[h.tower].dmg[1-h.side]-s.towers[h.tower].dmg[h.side])},reward:{gold:eligible?(win?180:80)+Math.min(1500,h.goldEarned):0,fate:eligible?(win?5:2):0,pts:eligible?(win?10:5)+(champ?5:0)+(breaker?3:0):0,shards:eligible?(win?4:2):0,xp:eligible?Math.min(150,h.xpEarned):0}};
 }
 snapshot(){return clone(this.s);}
 export(){return {seed:this.seed,state:this.snapshot()};}
 static restore(v){check(v.state.version===VERSION,'Unsupported arena snapshot');const e=Object.create(Engine.prototype);e.seed=v.seed;e.s=clone(v.state);return e;}
}
return {VERSION,BALANCE_VERSION,CAPACITY,SEARCH_MS,MATCH_MS,OVERTIME_MS,SPELLS,MODES,Engine,resolve,loadout,weekKey,dailyMode,seasonKey};
});
