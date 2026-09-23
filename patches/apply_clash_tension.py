from pathlib import Path
p = Path('fatebound.html')
t = p.read_text(encoding='utf-8')
if 'clashTensionKit' in t:
    print('already')
    raise SystemExit(0)

script = r'''
<script id="clashTensionKit">
(()=>{
if(window.__clashTension)return;window.__clashTension=1;
const CT={spell:0,spellMax:2,mode:'barrage',foeFocus:3,foeAt:Date.now(),beep:{},lastFlip:null,score:{a:0,b:0}};
function live(){try{return !!(M&&!M.ended&&!M.lobby&&typeof inWar==='function'&&inWar());}catch(_){return false;}}
function laneOf(i){return i>=8?'COURTYARD':i>=5?'CAMP':'OUTPOST';}
function beep(kind){
  try{
    const a=new (window.AudioContext||window.webkitAudioContext)();
    const o=a.createOscillator(),g=a.createGain();
    o.type='square'; o.frequency.value=kind===10?880:kind===30?520:360;
    g.gain.value=0.05; o.connect(g); g.connect(a.destination); o.start(); o.stop(a.currentTime+0.12);
  }catch(_){}
}
function ensureHud(){
  if(document.getElementById('clashSpell'))return;
  const foot=document.getElementById('battleFooterV2');
  const btn=document.createElement('button');
  btn.id='clashSpell'; btn.type='button';
  btn.innerHTML='SPELL 0';
  btn.title='Triples charge this. Tap to cycle Barrage / Hold / Horn, hold to cast.';
  if(foot) foot.insertBefore(btn, foot.firstChild);
  else document.body.appendChild(btn);
  let down=0;
  btn.addEventListener('pointerdown',()=>{down=Date.now();});
  btn.addEventListener('pointerup',()=>{
    if(Date.now()-down>380) castSpell();
    else cycleSpell();
    paintSpell();
  });
  const pips=document.createElement('div'); pips.id='foeFocusPips'; pips.title='Enemy Focus';
  const center=document.getElementById('v2Center');
  if(center) center.appendChild(pips);
  const lanes=document.createElement('div'); lanes.id='laneLegend';
  lanes.innerHTML='<i class="op">OUTPOSTS I–V</i><i class="cp">CAMP VI–VIII</i><i class="cy">COURTYARD IX–X</i>';
  const hex=document.getElementById('whHex');
  if(hex&&!document.getElementById('laneLegend')) hex.parentElement?.insertBefore(lanes, hex);
  const medals=document.createElement('div'); medals.id='crownMedals'; medals.hidden=true;
  const end=document.getElementById('end');
  if(end) end.querySelector('.panel')?.insertBefore(medals, end.querySelector('#endSub'));
}
function cycleSpell(){ CT.mode=CT.mode==='barrage'?'hold':CT.mode==='hold'?'horn':'barrage'; toast(CT.mode.toUpperCase()); }
function paintSpell(){
  const b=document.getElementById('clashSpell'); if(!b)return;
  b.textContent=(CT.mode.toUpperCase())+' '+CT.spell+'/'+CT.spellMax;
  b.classList.toggle('ready', CT.spell>0);
  const p=document.getElementById('foeFocusPips'); if(p){
    const n=Math.max(0,Math.min(8,CT.foeFocus|0));
    p.innerHTML=Array.from({length:8},(_,i)=>'<s class="'+(i<n?'on':'')+'"></s>').join('');
  }
}
function tickFoe(){
  if(!live())return;
  const now=Date.now();
  while(now-CT.foeAt>9000 && CT.foeFocus<8){ CT.foeAt+=9000; CT.foeFocus++; }
}
function tickBeeps(){
  if(!live()||!M.endAt)return;
  const left=Math.ceil((M.endAt-Date.now())/1000);
  [60,30,10].forEach(s=>{ if(left<=s && !CT.beep[s]){ CT.beep[s]=1; beep(s); if(typeof bigBanner==='function') bigBanner(s===10?'10':'0:'+String(s).padStart(2,'0'), s===10?'LAST STAND':'CLOCK');
    if(s===10 && typeof SFX!=='undefined' && SFX.horn) SFX.horn(); }});
}
function markHex(ti, cls, ms){
  const hex=document.getElementById('whHex'); if(!hex||ti==null)return;
  const b=hex.querySelector('button[data-t="'+ti+'"]'); if(!b)return;
  b.classList.add(cls); setTimeout(()=>b.classList.remove(cls), ms||2000);
}
function lanePaint(){
  const hex=document.getElementById('whHex'); if(!hex)return;
  hex.querySelectorAll('button[data-t]').forEach(b=>{
    const i=+b.dataset.t; b.classList.toggle('lane-op', i<5); b.classList.toggle('lane-cp', i>=5&&i<8); b.classList.toggle('lane-cy', i>=8);
    if(!b.dataset.lane){ b.dataset.lane=1; const tag=document.createElement('em'); tag.className='lane-tag'; tag.textContent=i>=8?'CY':i>=5?'CP':'OP'; b.appendChild(tag); }
  });
}
function expose(ti){
  if(!M||ti==null)return; M.exposedUntil=M.exposedUntil||{}; M.exposedUntil[ti]=Date.now()+8000;
  markHex(ti,'exposed',8000); toast('Hex exposed 8s');
}
function holdHex(ti){
  if(!M||ti==null)return; M.holdUntil=M.holdUntil||{}; M.holdUntil[ti]=Date.now()+8000;
  markHex(ti,'held',8000); toast('HOLD '+((M.towers[ti]||{}).name||ti));
}
function castSpell(){
  if(!live())return;
  if(CT.spell<=0){ toast('Need a triple to charge SPELL'); return; }
  const ti=player&&player.tower;
  if(CT.mode==='horn'){
    if(typeof callRally==='function' && ti!=null){ CT.spell--; callRally(0,ti); toast('HORN — rally free'); }
  } else if(CT.mode==='hold'){
    if(ti==null){ toast('Stand on a hex first'); return; }
    CT.spell--; holdHex(ti);
  } else {
    if(ti==null){ toast('Stand on a hex first'); return; }
    CT.spell--;
    try{
      if(typeof applyRoll==='function'){ const out=applyRoll(player,['S','S','C'],1); toast('BARRAGE');
        if(typeof shakeScreen==='function') shakeScreen(5,240); }
    }catch(_){ toast('Barrage fizzled'); }
  }
  paintSpell();
}
function crowns(){
  if(!M) return {n:0,bits:[]};
  const outposts=M.towers.slice(0,5).filter(t=>typeof towerLeader==='function'&&towerLeader(t)===0).length;
  const yard=M.towers.slice(8).filter(t=>typeof towerLeader==='function'&&towerLeader(t)===0).length;
  const bits=[];
  if(outposts>=3) bits.push('OUTPOSTS');
  if(yard>=1) bits.push('COURTYARD');
  if(CT.lastFlip===0) bits.push('FINAL FLIP');
  return {n:bits.length, bits};
}
function showCrowns(){
  const box=document.getElementById('crownMedals'); if(!box)return;
  const c=crowns(); box.hidden=false;
  box.innerHTML='<small>CROWNS</small><b>'+('♕'.repeat(Math.max(1,c.n)))+'</b><span>'+(c.bits.join(' · ')||'SKIRMISH')+'</span>';
}
function wrap(){
  if(typeof applyRoll==='function' && !applyRoll.__ct){
    const prev=applyRoll;
    applyRoll=function(who,faces,mult){
      try{
        const ti=typeof heroTower==='function'?heroTower(who):(who&&who.tower);
        if(who&&who.side===1 && M&&M.holdUntil && Date.now()<(M.holdUntil[ti]||0)){
          faces=['G','H','F'];
        }
        if(who&&who.side===1 && M&&M.exposedUntil && Date.now()<(M.exposedUntil[ti]||0)){
          mult=(mult||1)*1.5;
        }
        if(who&&who.side===1){
          CT.foeFocus=Math.max(0,CT.foeFocus-1);
          markHex(ti,'tele',1800);
        }
      }catch(_){}
      const out=prev.apply(this,arguments);
      try{
        if(who===player && out&&out.res&&out.res.tier==='triple'){ CT.spell=Math.min(CT.spellMax,CT.spell+1); paintSpell(); }
        if(who===player && player.allIn===false && player.action&&player.action.mult>=8 && out&&out.res&&out.res.tier==='none'){
          expose(player.tower);
        }
      }catch(_){}
      return out;
    };
    applyRoll.__ct=1;
  }
  if(typeof callRally==='function' && !callRally.__ct){
    const prev=callRally;
    callRally=function(s,ti){
      const r=prev.apply(this,arguments);
      try{ if(s===1){ markHex(ti,'tele',2500); if(typeof bigBanner==='function') bigBanner('ENEMY RALLY', 'Tower '+((M.towers[ti]||{}).name||'')); } }catch(_){}
      return r;
    };
    callRally.__ct=1;
  }
  if(typeof eventsTick==='function' && !eventsTick.__ct){
    const prev=eventsTick;
    eventsTick=function(now){
      const before=M&&M.towers?M.towers.map(t=>t.prev):[];
      const r=prev.apply(this,arguments);
      try{
        if(M&&M.towers){
          M.towers.forEach((t,i)=>{
            if(before[i]!==undefined && t.prev!==before[i] && t.prev!==-1){
              CT.lastFlip=t.prev;
              if(typeof shakeScreen==='function') shakeScreen(t.prev===0?5:7,280);
              if(typeof SFX!=='undefined'&&SFX.flip) SFX.flip();
              if(typeof bigBanner==='function') bigBanner(t.prev===0?'TOWER TAKEN':'TOWER LOST', (t.name||'')+' · '+laneOf(i));
            }
          });
        }
      }catch(_){}
      return r;
    };
    eventsTick.__ct=1;
  }
  if(typeof finishMatch==='function' && !finishMatch.__ct){
    const prev=finishMatch;
    finishMatch=function(){
      const r=prev.apply(this,arguments);
      try{ showCrowns(); document.body.classList.remove('clash-lock'); }catch(_){}
      return r;
    };
    finishMatch.__ct=1;
  }
  if(typeof openWar==='function' && !openWar.__ct){
    const prev=openWar;
    openWar=function(){
      CT.spell=0; CT.foeFocus=3; CT.foeAt=Date.now(); CT.beep={}; CT.lastFlip=null;
      const r=prev.apply(this,arguments);
      setTimeout(()=>{ensureHud();lanePaint();paintSpell();},0);
      return r;
    };
    openWar.__ct=1;
  }
}
function loop(){
  try{
    if(live()){ ensureHud(); tickFoe(); tickBeeps(); lanePaint(); paintSpell(); document.body.classList.add('clash-lock'); }
  }catch(_){}
  requestAnimationFrame(loop);
}
wrap(); ensureHud(); loop();
})();
</script>
<style id="clashTensionStyle">
#clashSpell{min-width:72px;height:32px;border:1px solid #f2c554;border-radius:8px;background:#2a220e;color:#ffe7a3;font:900 8px Nunito,system-ui;letter-spacing:.04em}
#clashSpell.ready{background:#f2c554;color:#2a1b08}
#foeFocusPips{display:flex;gap:2px;justify-content:center;margin-top:2px}
#foeFocusPips s{width:7px;height:7px;border-radius:50%;background:#24343c;display:block;border:1px solid #3d5864}
#foeFocusPips s.on{background:#ff7a6a;border-color:#ffb3a8}
#laneLegend{display:flex;gap:6px;justify-content:center;padding:4px 8px;font:900 8px Nunito,system-ui;letter-spacing:.08em}
#laneLegend .op{color:#8fd0ff}#laneLegend .cp{color:#ffe08a}#laneLegend .cy{color:#ffb07a}
#whHex button.lane-op{box-shadow:inset 0 0 0 1px #4b8eb8aa}
#whHex button.lane-cp{box-shadow:inset 0 0 0 1px #c9a227aa}
#whHex button.lane-cy{box-shadow:inset 0 0 0 2px #e08a4aaa}
#whHex button.tele{outline:2px solid #ff6b4a;animation:ctPulse .4s linear infinite}
#whHex button.held{outline:2px solid #7ad7ff}
#whHex button.exposed{outline:2px solid #f2c554}
#whHex .lane-tag{position:absolute;top:2px;left:2px;font-size:7px;opacity:.8}
@keyframes ctPulse{50%{filter:brightness(1.4)}}
#crownMedals{display:flex;flex-direction:column;align-items:center;gap:2px;margin:8px 0;color:#f2c554}
#crownMedals small{letter-spacing:.14em;font-size:9px}
#crownMedals b{font-size:22px}
#battleFooterV2{grid-template-columns:72px 72px 1fr 54px!important}
</style>
'''

if '</body>' not in t:
    raise SystemExit('no body')
t = t.replace('</body>', script + '</body>', 1)
p.write_text(t, encoding='utf-8')
print('ok', p.stat().st_size)
