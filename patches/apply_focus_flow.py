from pathlib import Path
p = Path('fatebound.html')
t = p.read_text(encoding='utf-8')
if 'focusFlowLayout' in t and 'pairFocusTick' in t:
    print('already')
    raise SystemExit(0)

def once(old, new):
    global t
    n = t.count(old)
    print('count', n, old[:80].replace('\n',' '))
    if n != 1:
        raise SystemExit('miss')
    t = t.replace(old, new, 1)

once(
    "if (res.energy){ if (who===player){ const e = ((res.energy + (CHARS[who.char||0].energy||0)) * mult); if(M&&!M.ended&&!M.lobby){ addFocus(e); out.push(`${res.tier==='triple'?'TRIPLE ':''}+${e} Focus`); } else { addEnergy(e); out.push(`${res.tier==='triple'?'TRIPLE ':''}+${e} energy`); } } else out.push('energy'); }",
    "if (who===player && M && !M.ended && !M.lobby && res.tier && res.tier!=='none' && !res.energy){ addFocus(1); out.push('+1 Focus'); }\n  if (res.energy){ if (who===player){ const e = ((res.energy + (CHARS[who.char||0].energy||0)) * mult); if(M&&!M.ended&&!M.lobby){ addFocus(e); out.push(`${res.tier==='triple'?'TRIPLE ':''}+${e} Focus`); } else { addEnergy(e); out.push(`${res.tier==='triple'?'TRIPLE ':''}+${e} energy`); } } else out.push('energy'); }",
)
once(
    'function paintFocusHud(){ let fate=0,cap=50,foc=0,fmax=8;',
    'function pairFocusTick(){ if(!M||M.ended||M.inBoss||M.lobby) return; M.focusAt=M.focusAt||Date.now(); const step=14000; const now=Date.now(); while(now-M.focusAt>=step && focus()<(M.focusMax||8)){ M.focusAt+=step; M.focus=Math.min(M.focusMax||8,(M.focus||0)+1);} }\nfunction paintFocusHud(){ try{pairFocusTick();}catch(_){} let fate=0,cap=50,foc=0,fmax=8;',
)
extra = '''<style id="focusFlowLayout">
html,body{height:100dvh!important;max-height:100dvh!important;overflow:hidden!important;overscroll-behavior:none}
#app{height:100dvh!important;max-height:100dvh!important;overflow:hidden!important}
#setup{height:100%!important;max-height:100dvh!important;overflow:auto!important;-webkit-overflow-scrolling:touch}
body.ui-battle-v2,body.ui-battle-v2 #app,body.ui-battle-v2 #battle{height:100dvh!important;max-height:100dvh!important;overflow:hidden!important}
body.ui-battle-v2 #battle:not([hidden]){display:flex!important;flex-direction:column!important}
body.ui-battle-v2 .arena{flex:1 1 0!important;min-height:0!important}
body.ui-battle-v2 .rollbar{flex:0 0 auto!important}
body.ui-battle-v2 #battleFooterV2{flex:0 0 28px!important;height:28px!important}
body.ui-battle-v2 .tbar{min-height:28px!important}
</style>'''
if 'focusFlowLayout' not in t:
    t = t.replace('</body>', extra + '</body>', 1)
p.write_text(t, encoding='utf-8')
print('ok', p.stat().st_size)
