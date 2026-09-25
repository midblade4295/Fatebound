'use strict';
// Reproducible offline policy simulation; not player telemetry or a win-rate guarantee.
const fs=require('node:fs'),A=require('../src/arena-engine'),Old=require('../tests/fixtures/arena-engine-v109.cjs');
const START=1790337600000;
const pairs=[['barrage','bulwark'],['barrage','surge'],['bulwark','horn'],['bulwark','surge'],['horn','surge'],['barrage','horn']];
function run(Mod,seed,{policy='x1',char=0,spells=pairs[0]}={}){
 const primary=seed%2;
 const players=Array.from({length:20},(_,i)=>({id:'p'+i,name:'P'+i,bot:i>1,char:i===primary?char:i<2?0:Math.floor(i/2)%5,weapon:0,loadout:i===primary?spells:pairs[0]}));
 const e=new Mod.Engine({id:'sim-'+seed,players,now:START,seed:seed*173+43});
 for(let t=START;t<=START+365000&&!e.s.ended;t+=500){
  e.tick(t);if(e.s.ended)break;
  for(let i=0;i<2;i++){
   const h=e.s.heroes[i];if(h.hp<=0)continue;
   const pi=i===primary?policy:'x1';
   try{
    if(h.ult>=100){e.act(h.id,{type:'ultimate'},t);continue;}
    const o=e.s.objective;
    if(o.status==='active'&&h.tower!==o.tower){e.act(h.id,{type:'move',tower:o.tower},t);continue;}
    // Rotate to a contested high-value tower after the supply encounter; same policy both sides.
    if(t>START+165000&&h.tower<8){e.act(h.id,{type:'move',tower:8},t);continue;}
    if(h.giftDamage>0){const al=e.s.heroes.find(a=>a.id!==h.id&&a.side===h.side&&a.hp>0&&(a.storedDamage||0)<a.maxHp);if(al)e.act(h.id,{type:'gift',target:al.id},t);}
    if(h.storedDamage)e.act(h.id,{type:'stored'},t);
    if(h.spell>0&&t>=h.spellAt){
     let spell=h.loadout.includes('surge')&&h.focus<=4?'surge':h.loadout.includes('bulwark')&&t>=(e.s.holds[h.side][h.tower]||0)&&e.s.heroes.some(a=>a.side!==h.side&&a.tower===h.tower&&a.hp>0)?'bulwark':h.loadout.includes('barrage')?'barrage':h.loadout.includes('horn')&&h.ralliesLeft&&t>=h.rallyAt?'horn':null;
     if(spell){e.act(h.id,{type:'spell',spell},t);continue;}
    }
    if(t<h.rollAt||h.focus<1&&!h.rampage)continue;
    let mult=1,allIn=false;
    if(pi==='x2')mult=h.focus>=2?2:1;
    if(pi==='allin4'){if(h.focus<4&&!h.rampage)continue;allIn=true;}
    if(pi==='adaptive')allIn=h.focus>=6;
    e.act(h.id,{type:'roll',mult,allIn},t);
   }catch(err){if(!/cooling|unavailable|remaining|Focus|full/.test(err.message))throw err;}
  }
 }
 if(!e.s.ended)e.finish(START+365000);
 const h=e.s.heroes[primary],r=e.result(h.id);
 return {win:e.s.winner===h.side?1:e.s.winner===null?.5:0,damage:h.damage,rolls:h.rolls,spells:h.spellsCast,kos:h.kos,gold:r.reward.gold,fate:r.reward.fate,points:r.reward.pts,xp:r.reward.xp,eligible:r.eligible?1:0,seconds:(e.s.completedAt-START)/1000};
}
function batch(Mod,n,opt){const out=[];for(let seed=1;seed<=n;seed++)out.push(run(Mod,seed,opt));return Object.fromEntries(Object.keys(out[0]).map(k=>[k,Math.round(out.reduce((s,x)=>s+x[k],0)/n*100)/100]));}
const result={fixture:'two scripted human controllers plus 18 standard bots, 500ms tick; identical seed sets and opponent; not human win rates',seedCount:50,policy:{},loadouts:{},heroes:{}};
for(const p of ['x1','x2','allin4','adaptive']){result.policy[p]={before:batch(Old,50,{policy:p}),after:batch(A,50,{policy:p})};console.log('policy',p,result.policy[p]);}
for(const spells of pairs){result.loadouts[spells.join('+')]=batch(A,30,{policy:'adaptive',spells});console.log('loadout',spells.join('+'),result.loadouts[spells.join('+')]);}
for(let char=0;char<5;char++)result.heroes[char]=batch(A,30,{policy:'adaptive',char,spells:['barrage','surge']});
fs.writeFileSync(__dirname+'/balance-simulation.json',JSON.stringify(result,null,2)+'\n');
