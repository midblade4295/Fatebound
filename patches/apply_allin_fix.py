from pathlib import Path
p = Path('fatebound.html')
t = p.read_text(encoding='utf-8')
if 'allInSafeMult' in t and 'giftNoJank' in t:
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
    'const multUnlocked = m => MULTS.find(x=>x[0]===m)[1] <= focus();',
    'const allInSafeMult=1; const multUnlocked = m => { const row=MULTS.find(x=>x[0]===m); return !!(row && row[1]<=focus()); };',
)
once(
    'if(typeof allIn!=="undefined"&&allIn) player.allIn=false;});',
    'if(typeof allIn!=="undefined"&&allIn){ player.allIn=false; player.mult=1; }});',
)
once(
    'if(player.allIn){ player.allIn=false; player.mult=1; renderMult(); SFX.tap(); return; }',
    'if(player.allIn){ player.allIn=false; player.mult=1; try{renderMult();}catch(_){} SFX.tap(); return; }',
)
extra = '''<style id="giftNoJank">
#battleGiftToastV2{position:fixed!important;left:8px!important;right:8px!important;bottom:calc(72px + env(safe-area-inset-bottom,0px))!important;margin:0!important;transform:none!important;z-index:80!important;pointer-events:auto}
#battleGiftToastV2.compact{left:auto!important;right:8px!important;width:44px!important;bottom:calc(72px + env(safe-area-inset-bottom,0px))!important}
body.ui-battle-v2 #chat{display:none!important}
</style>'''
if 'giftNoJank' not in t:
    t = t.replace('</body>', extra + '</body>', 1)
p.write_text(t, encoding='utf-8')
print('ok', p.stat().st_size)
