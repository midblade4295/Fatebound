from pathlib import Path
p = Path('fatebound.html')
t = p.read_text(encoding='utf-8')
if 'clashLockBattle' in t:
    print('already')
    raise SystemExit(0)

def once(old, new):
    global t
    n = t.count(old)
    print('count', n, old[:70].replace('\n',' '))
    if n != 1:
        raise SystemExit('miss')
    t = t.replace(old, new, 1)

once(
    '<div class="grid"><button data-v2-dest="home">Home</button><button data-v2-dest="hero">Hero</button><button data-v2-dest="guild">Guild</button><button data-v2-dest="friends">Friends</button><button data-v2-dest="shop">Shop</button><button data-v2-dest="sound">Sound</button></div>',
    '<div class="grid"><button data-v2-dest="sound">Mute / sound</button><p class="locknote">Home and shop unlock when the battle ends.</p></div>',
)
once(
    'if(dest==="home"){if(typeof inWar==="function"&&inWar())saveWar();homeHub();}else if(dest==="sound"){document.querySelector(".mute")?.click();}else{if(typeof inWar==="function"&&inWar())saveWar();showScreen(dest);}}',
    'if(dest==="sound"){document.querySelector(".mute")?.click();}else{if(typeof toast==="function")toast("Finish the battle first");}}',
)
once(
    'function homeHub(){\n autoRoll=false;',
    'function matchLocked(){ try{ return !!(M && !M.ended && !M.lobby && typeof inWar==="function" && inWar() && war() && war().phase!=="complete"); }catch(_){ return false; } }\nfunction homeHub(){\n if(matchLocked()){ if(typeof toast==="function")toast("Finish the battle first"); return; }\n autoRoll=false;',
)
once(
    'function showScreen(name){\n  screen = name; autoRoll = false;',
    'function showScreen(name){\n  if(typeof matchLocked==="function" && matchLocked()){ if(typeof toast==="function")toast("Finish the battle first"); return; }\n  screen = name; autoRoll = false;',
)

script = r'''<script id="clashLockBattle">
(()=>{
  const lockNav=()=>{
    document.querySelectorAll("nav button").forEach(b=>{
      if(b.dataset.clashLock) return;
      b.dataset.clashLock=1;
      b.addEventListener("click",e=>{
        if(typeof matchLocked==="function" && matchLocked()){ e.preventDefault(); e.stopImmediatePropagation(); if(typeof toast==="function")toast("Finish the battle first"); }
      },true);
    });
    ["goldPill","tokenPill","seasonPill","cheat"].forEach(id=>{
      const el=document.getElementById(id); if(!el||el.dataset.clashLock) return;
      el.dataset.clashLock=1;
      el.addEventListener("click",e=>{
        if(typeof matchLocked==="function" && matchLocked()){ e.preventDefault(); e.stopImmediatePropagation(); }
      },true);
    });
  };
  lockNav();
  const prev=window.paintHeaderV2;
  if(typeof paintHeaderV2==="function"){
    paintHeaderV2=function(now){
      const r=prev.apply(this,arguments);
      try{
        const live=typeof matchLocked==="function"&&matchLocked();
        document.body.classList.toggle("clash-lock", !!live);
        const ph=typeof phaseV2==="function"?phaseV2(now||Date.now()):{};
        let ban=document.getElementById("suddenBanner");
        if(!ban){ ban=document.createElement("div"); ban.id="suddenBanner"; ban.hidden=true; document.body.appendChild(ban); }
        const hot=ph.key==="sudden"||ph.key==="final30";
        ban.hidden=!hot;
        if(hot) ban.textContent=ph.key==="sudden"?"NEXT TOWER FLIP WINS":"FINAL 30";
        const us=document.getElementById("v2UsScore")?.textContent;
        const foe=document.getElementById("v2FoeScore")?.textContent;
        if(window.__scoreSnap && (window.__scoreSnap.us!==us || window.__scoreSnap.foe!==foe) && typeof shakeScreen==="function") shakeScreen(2,180);
        window.__scoreSnap={us,foe};
      }catch(_){}
      return r;
    };
  }
})();
</script>
<style id="clashLockStyle">
body.clash-lock nav,body.clash-lock #setup,body.clash-lock .hud,body.clash-lock .wallet,body.clash-lock #warPanel{display:none!important}
body.clash-lock.v2-sudden #battleGiftToastV2,body.clash-lock.v2-final30 #battleGiftToastV2,body.clash-lock.v2-sudden #rivalMiniV2,body.clash-lock.v2-final30 #rivalMiniV2{display:none!important}
#suddenBanner{position:fixed;left:50%;top:56px;transform:translateX(-50%);z-index:90;padding:6px 12px;border-radius:999px;background:#4a140fd9;border:1px solid #ffb15a;color:#ffe7b0;font:900 12px Nunito,system-ui;letter-spacing:.08em;pointer-events:none}
#battleDrawerV2 .locknote{grid-column:1/-1;margin:0;font-size:10px;color:#9fb4bf}
</style>
'''
t = t.replace('</body>', script + '</body>', 1)
p.write_text(t, encoding='utf-8')
print('ok', p.stat().st_size)
