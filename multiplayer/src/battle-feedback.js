/* v114: one confirmed-result surface, isolated canvas transitions and bounded spell effects.
   No simulation, rewards, network timers, MutationObservers or input-swallowing handlers. */
(()=>{'use strict';
 const $=id=>document.getElementById(id),fmt=n=>Math.max(0,Math.round(Number(n)||0)).toLocaleString();
 let panel=null,result=null,online=false,banked=null,lastMatch='',sceneTower=null;
 const effects=[],stats={frames:0,mapRecoveries:0,drawRecoveries:0,transitions:0,effectsStarted:0,peakEffects:0};
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 function text(id,s){const n=$(id);if(n&&n.textContent!==String(s))n.textContent=String(s);}
 function ensure(){
  if(panel)return;
  panel=document.createElement('section');panel.id='rollOutcomeV114';panel.setAttribute('aria-label','Confirmed roll result');
  panel.innerHTML='<strong id="rollOutcomeTitle">ROLL RESULTS</strong><span id="rollOutcomeDetail">Matching dice apply together. Roll to begin.</span><small id="rollOutcomeBank"></small>';
  document.querySelector('#battle .rollbar').prepend(panel);
 }
 function scene(id){ensure();if(id===lastMatch)return;lastMatch=id;result=null;effects.length=0;panel.removeAttribute('data-symbol');text('rollOutcomeTitle','ROLL RESULTS');text('rollOutcomeDetail','Matching dice apply together. Roll to begin.');text('rollOutcomeBank','');}
 function bank(h,isOnline,practice,earned=null){scene(window.FBNext?.latest?.id||'');online=!!isOnline;
  const gold=earned?.gold??h.bankedGold??Math.min(1500,h.credit?.goldEarned??h.goldEarned??0),xp=earned?.xp??h.bankedXp??Math.min(150,h.credit?.xpEarned??h.xpEarned??0);
  banked={gold,xp,paidRolls:earned?.paidRolls??h.credit?.paidRolls??h.paidRolls};
  text('rollOutcomeBank',practice?'Practice · no persistent rewards':`Banked ${fmt(gold)} gold · ${fmt(xp)} XP · ${banked.paidRolls<5?banked.paidRolls+'/5 paid rolls to qualify':'claim at match end'}`);
 }
 function pending(){ensure();text('rollOutcomeTitle','ROLLING');text('rollOutcomeDetail','Waiting for the server-confirmed result…');}
 function notice(title,detail){ensure();text('rollOutcomeTitle',title);text('rollOutcomeDetail',detail);}
 function failed(reason){notice('ROLL NOT CONFIRMED',reason);}
 function outcome(r,isOnline){
  ensure();result=r;online=!!isOnline;
  const e=r.effects||{},title=({S:'ATTACK',C:'CRITICAL',H:'SHIELD',E:'FOCUS',G:'GOLD',F:'TEAM GIFT'})[r.symbol]||'MIXED';
  text('rollOutcomeTitle',(r.tier&&r.tier!=='none'?r.tier.toUpperCase()+' · ':'')+title);
  const items=[];
  if(r.symbol==='S'||r.symbol==='C'){
   if(r.dealt>0)items.push(fmt(r.dealt)+' damage');
   if(r.absorbed>0)items.push(fmt(r.absorbed)+' absorbed by shields');
   if(!r.dealt&&!r.absorbed)items.push('No damage confirmed');
  }else if(r.symbol==='H')items.push(e.shieldAdded>0?'+'+fmt(e.shieldAdded)+' shield absorption':'Equal or stronger shields already equipped');
  else if(r.symbol==='E')items.push(e.focusGained>0?'+'+fmt(e.focusGained)+' Focus':'Focus is already full');
  else if(r.symbol==='G')items.push(e.goldAdded>0?'+'+fmt(e.goldAdded)+' gold'+(online?' banked':''):'Match gold cap reached');
  else if(r.symbol==='F')items.push(e.giftAdded>0?'+'+fmt(e.giftAdded)+' gift damage · open Attacks to send':'Gift bank is full · open Attacks');
  else items.push('No matching action');
  if(r.symbol!=='E'&&e.focusGained>0)items.push('+'+fmt(e.focusGained)+' Focus');
  if(e.spellAdded>0)items.push('+'+e.spellAdded+' spell charge');
  text('rollOutcomeDetail',items.join(' · '));
  if(!online)text('rollOutcomeBank',window.FBNext?.active?'Practice · no persistent rewards':`Focus ${focus()}/${M.focusMax||8} · ${fmt(SAVE.gold)} gold owned`);
  panel.dataset.symbol=r.symbol||'none';
 }
 function towerChanged(from,to){
  if(from===to&&sceneTower===to)return;
  sceneTower=to;effects.length=0;stats.transitions++;
  // Coordinates, hit tweens and camera are local to the old battlefield.
  for(const h of M?.heroes||[]){h.lunge=null;h.hitAt=0;}
  for(const k of Object.keys(POS))delete POS[k];for(const k of Object.keys(TPOS))delete TPOS[k];VIS.clear();
  floats=[];projectiles=[];impacts=[];vfx=[];shake=null;
  if(typeof battlePan==='object'){battlePan.x=0;battlePan.target=0;battlePan.dragging=false;}
  ctx=cv.getContext('2d');lastCW=0;lastCH=0;
  if(!$('battle').hidden)resize();
 }
 function spell(kind,actor,tower){
  if(!M||M.inBoss||screen!=='battle'||tower!==player.tower||!['barrage','bulwark','horn','surge'].includes(kind))return false;
  if(effects.length>=8)effects.shift();
  effects.push({kind,actor,tower,at:performance.now(),match:M.arenaId||M.startAt});
  stats.effectsStarted++;stats.peakEffects=Math.max(stats.peakEffects,effects.length);return true;
 }
 function ring(c,x,y,rx,ry,col,alpha,width=2){c.globalAlpha=alpha;c.strokeStyle=col;c.lineWidth=width;c.beginPath();c.ellipse(x,y,Math.max(1,rx),Math.max(1,ry),0,0,Math.PI*2);c.stroke();}
 function drawEffects(now){
  if(!M||screen!=='battle'||M.inBoss){effects.length=0;return;}
  const c=ctx,match=M.arenaId||M.startAt;
  for(let i=effects.length-1;i>=0;i--)if(now-effects[i].at>1500||effects[i].tower!==player.tower||effects[i].match!==match)effects.splice(i,1);
  c.save();try{
   c.beginPath();c.rect(0,55,W,Math.max(1,TRAY_Y-DIE-73));c.clip();
   const pan=battlePan.enabled?battlePan.x:0;
   for(const fx of effects){
    const actor=M.heroes.find(h=>h.id===fx.actor),a=POS[fx.actor],side=actor?.side||0,t=(now-fx.at)/1500,fade=Math.sin(Math.min(1,t)*Math.PI);
    const ax=(a?.x??(side===0?110:290))+pan,ay=a?.y??H*.55;
    const targets=M.heroes.filter(h=>h.tower===player.tower&&h.side!==(side)).map(h=>POS[h.id]).filter(Boolean).slice(0,3);
    if(fx.kind==='barrage'){
     for(let i=0;i<3;i++){
      const p=targets[i%Math.max(1,targets.length)],x=(p?.x??(side===0?290:110))+pan+(i-1)*13,y=p?.y??H*.43;
      const u=Math.max(0,Math.min(1,(t-i*.13)*2.6));if(u<=0)continue;
      if(!reduced.matches&&u<.7){const q=u/.7,sy=y-135,sx=x-75;
       const g=c.createLinearGradient(sx,sy,x,y);g.addColorStop(0,'#f2693210');g.addColorStop(1,'#ffdc92');c.globalAlpha=.85;c.strokeStyle=g;c.lineWidth=4;c.beginPath();c.moveTo(sx+75*Math.max(0,q-.3),sy+135*Math.max(0,q-.3));c.lineTo(sx+75*q,sy+135*q);c.stroke();}
      else {const v=Math.max(0,(u-.7)/.3);ring(c,x,y+4,8+v*34,4+v*15,'#ffd791',fade*(1-v*.7),3);
       const particles=reduced.matches?4:12;for(let j=0;j<particles;j++){const an=j*Math.PI*2/particles;c.globalAlpha=fade*.8;c.fillStyle=j%2?'#f89b47':'#ffe4a0';c.fillRect(x+Math.cos(an)*(10+v*34),y+Math.sin(an)*(10+v*25)-v*15,2,3);}}
     }
    }else if(fx.kind==='bulwark'){
     for(const h of M.heroes.filter(h=>h.side===side&&h.tower===player.tower).slice(0,8)){
      const p=POS[h.id];if(!p)continue;const x=p.x+pan,y=p.y;
      ring(c,x,y+5,32,12,'#89fff0',fade*.8,2);
      c.globalAlpha=fade*.25;c.fillStyle='#74eeec';c.beginPath();c.ellipse(x,y-26,32,46,0,Math.PI,Math.PI*2);c.lineTo(x+32,y+4);c.quadraticCurveTo(x,y+14,x-32,y+4);c.closePath();c.fill();
      c.globalAlpha=fade*.8;c.strokeStyle='#a0fff1';c.lineWidth=2;c.stroke();
     }
    }else if(fx.kind==='horn'){
     for(let i=0;i<3;i++){const u=reduced.matches?.4:Math.max(0,t-i*.13);ring(c,ax,ay+5,18+u*120,7+u*45,'#ffe2a2',Math.max(0,fade*(1-u)),2);}
     c.globalAlpha=fade*.3;c.fillStyle='#efd087';c.fillRect(ax-3,ay-100,6,105);
    }else{
     ring(c,ax,ay+8,36,13,'#d6afff',fade*.85,2);
     const spin=reduced.matches?0:t*2.2;c.strokeStyle='#d4a3ff';c.lineWidth=2;c.globalAlpha=fade*.8;
     for(let j=0;j<8;j++){const an=j*Math.PI/4+spin;c.beginPath();c.moveTo(ax+Math.cos(an)*31,ay-26+Math.sin(an)*34);c.lineTo(ax+Math.cos(an+.2)*23,ay-26+Math.sin(an+.2)*25);c.lineTo(ax+Math.cos(an+.1)*40,ay-26+Math.sin(an+.1)*43);c.stroke();}
    }
   }
  }finally{c.restore();}
 }
 // Outermost transition guard: old synchronous wrappers may not run before an async server move is accepted.
 const enter=enterTower;
 enterTower=function(ti){
  if(!Number.isInteger(ti)||!M?.towers?.[ti])return false;
  if(window.FBNext?.active&&!FBNext.rendering)return FBNext.move(ti);
  const from=player.tower;ctx=cv.getContext('2d');scene(M.arenaId||'solo-'+M.startAt);
  try{const out=enter.apply(this,arguments);towerChanged(from,player.tower);return out;}
  finally{ctx=cv.getContext('2d');}
 };
 const baseMap=renderMap;
 renderMap=function(){
  const real=cv.getContext('2d');try{return baseMap.apply(this,arguments);}
  catch(e){wcv.width=wcv.width;stats.mapRecoveries++;console.warn('Map rendering recovered:',e.message);text('battleNoticeText','Map artwork is recovering. Tap a tower again.');}
  finally{ctx=real;HEX_SQ=.58;FLIP_OVERRIDE=null;}
 };
 const baseDraw=draw;
 draw=function(now){
  const real=cv.getContext('2d');ctx=real;real.save();
  try{real.setTransform(SC,0,0,SC,0,0);real.globalAlpha=1;real.globalCompositeOperation='source-over';baseDraw(now);stats.frames++;}
  catch(e){cv.width=cv.width;lastCW=0;resize();stats.drawRecoveries++;console.warn('Battle rendering recovered:',e.message);}
  finally{real.restore();ctx=real;FLIP_OVERRIDE=null;}
 };
 // Preserve the exact solo resolver's descriptive receipt, rather than inventing rewards.
 const apply=applyRoll;applyRoll=function(who,faces,mult){const out=apply.apply(this,arguments);
  if(who===player&&!M?.arena){ensure();const win=FBArenaWire.winningDice(faces);text('rollOutcomeTitle',win.tier.toUpperCase()+' · '+({S:'ATTACK',C:'CRITICAL',H:'SHIELD',G:'GOLD',E:'FOCUS',F:'GIFT'}[win.symbol]||'MIXED'));text('rollOutcomeDetail',out.text||'No matching action');text('rollOutcomeBank',`Focus ${focus()}/${M.focusMax||8} · ${fmt(SAVE.gold)} gold owned`);}
  return out;
 };
 // Existing offline spell entry point; emit only after a charge was actually consumed.
 const cast=window.FateboundSpells?.cast;
 if(cast)FateboundSpells.cast=function(k){const before=FateboundSpells.charges();const out=cast(k);if(!FBNext.active&&FateboundSpells.charges()<before)spell(k==='hold'?'bulwark':k,player.id,player.tower);return out;};
 // Keep the viewport inside the visible region, including a phone's on-screen keyboard.
 function viewport(){const v=window.visualViewport;document.documentElement.style.setProperty('--game-vh',Math.floor(v?.height||innerHeight)+'px');if(!document.activeElement?.matches('input,textarea'))requestAnimationFrame(()=>{if(!$('battle').hidden)resize();});}
 window.visualViewport?.addEventListener('resize',viewport,{passive:true});window.addEventListener('resize',viewport,{passive:true});viewport();
 window.FateboundBattle={bank,pending,failed,notice,outcome,towerChanged,spell,drawEffects,get diagnostics(){return {...stats,effects:effects.length,lastResult:result,banked};}};ensure();
})();
