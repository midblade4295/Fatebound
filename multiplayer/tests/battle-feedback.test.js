'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const A=require('../src/arena-engine'),W=require('../src/arena-wire');
const players=()=>Array.from({length:20},(_,i)=>({id:'p'+i,name:'QA '+i,bot:i>1,char:0,weapon:0,loadout:['barrage','bulwark']}));
function engine(){return new A.Engine({id:'feedback-fixture',players:players(),now:1000000,seed:98423});}
test('all 216 roll combinations report actual resource/shield/damage deltas without crediting the wallet',()=>{
 let checked=0;for(const x of ['S','C','H','G','E','F'])for(const y of ['S','C','H','G','E','F'])for(const z of ['S','C','H','G','E','F']){
  const e=engine(),h=e.hero('p0');h.focus=8;e.faces=()=>[x,y,z];const before={focus:h.focus,gold:h.credit.goldEarned,xp:h.credit.xpEarned,shield:h.shieldSlots.reduce((n,v)=>n+v,0),gift:h.giftDamage};
  const r=e.act(h.id,{type:'roll',mult:1},1000000),fx=r.effects;
  assert.equal(r.symbol,A.resolve([x,y,z]).action);assert.equal(fx.focusAfter,h.focus);assert.equal(fx.focusGained,Math.max(0,h.focus-before.focus+r.cost));
  assert.equal(fx.goldAdded,h.credit.goldEarned-before.gold);assert.equal(fx.xpAdded,h.credit.xpEarned-before.xp);assert.equal(fx.giftAdded,h.giftDamage-before.gift);
  assert.equal(fx.paidRolls,1);assert.equal(fx.tower,0);assert(!('gold' in h));checked++;
 }assert.equal(checked,216);
});
test('shield pair reports absorption gained, and full stronger slots honestly report no upgrade',()=>{
 const e=engine(),h=e.hero('p0');e.faces=()=>['H','H','G'];let r=e.act(h.id,{type:'roll',mult:1},1000000);assert.equal(r.effects.shieldAdded,60);
 h.shieldSlots=[300,300,300];h.rollAt=0;h.focus=8;r=e.act(h.id,{type:'roll',mult:1},1004000);assert.equal(r.effects.shieldAdded,0);assert.equal(h.shieldSlots.length,3);
});
test('gold and XP feedback respects the existing match reward caps',()=>{
 const e=engine(),h=e.hero('p0');h.credit.goldEarned=1495;h.credit.xpEarned=149;e.faces=()=>['G','G','S'];
 const r=e.act(h.id,{type:'roll',mult:1},1000000);assert.equal(r.effects.goldAdded,5);assert.equal(r.effects.xpAdded,1);assert.equal(h.credit.goldEarned,1520);
});
test('blocked damage is explicitly reported as absorption',()=>{
 const e=engine(),h=e.hero('p0'),foe=e.hero('p1');foe.shieldSlots=[10000];e.faces=()=>['C','C','H'];
 const r=e.act(h.id,{type:'roll',mult:1},1000000);assert.equal(r.dealt,0);assert(r.absorbed>0);assert.equal(foe.hp,foe.maxHp);
});
test('human substitute cannot auto-rotate to a random or supply tower',()=>{
 for(let seed=1;seed<=30;seed++){
  const e=engine(),h=e.hero('p0');e.seed=seed;h.substitute=true;h.connected=false;h.tower=2;e.s.objective={tower:8,status:'active',held:[0,0],startAt:1000000,endAt:1200000};
  for(let j=1;j<=24;j++){h.hp=h.maxHp;h.focus=8;h.nextBot=0;e.tick(1000000+j*4000);assert.equal(h.tower,2,'seed '+seed+' step '+j);}
 }
});
test('a rally never forcibly moves human slots, including substitutes',()=>{
 const e=engine(),h=e.hero('p0'),leader=e.hero('p2');h.substitute=true;h.tower=2;leader.tower=8;e.random=()=>0;
 e.rally(leader,1000000,true);assert.equal(h.tower,2);assert.equal(e.hero('p4').tower,8);
});
test('substitute keeps fighting without receiving personal roll rewards',()=>{
 const e=engine(),h=e.hero('p0');h.substitute=true;h.focus=8;h.nextBot=0;h.tower=2;e.faces=()=>['G','G','G'];e.tick(1000001);
 assert(h.rolls>0);assert.equal(h.credit.paidRolls,0);assert.equal(h.credit.goldEarned,0);assert.equal(h.tower,2);
});
test('movement and numeric feedback do not change combat protocol, balance or wire fields',()=>{
 const e=engine();assert.equal(e.s.balanceVersion,110);assert.equal(e.s.version,1);assert.equal(W.VERSION,2);
 assert(!W.HERO.includes('bankedGold'));assert(!W.HERO.includes('bankedXp'));assert.equal(A.SEARCH_MS,20000);assert.equal(A.CAPACITY,20);
 const h=e.hero('p0');e.act(h.id,{type:'move',tower:7},1000000);assert.equal(h.tower,7);
});
