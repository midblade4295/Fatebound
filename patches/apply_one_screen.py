from pathlib import Path
p=Path('fatebound.html')
t=p.read_text(encoding='utf-8')
if 'oneScreenFit' in t:
    print('already'); raise SystemExit(0)

def once(old,new):
    global t
    n=t.count(old)
    print('count',n,old[:60])
    if n!=1: raise SystemExit('miss')
    t=t.replace(old,new,1)

once(
    'function shakeScreen(amp, ms){ shake = { t0: performance.now(), amp, ms }; }',
    'function shakeScreen(amp, ms){ shake = { t0: performance.now(), amp: Math.min(1.25, Math.max(0.4, (amp||2)*0.22)), ms: Math.min(160, ms||180) }; }'
)
extra='''<style id="oneScreenFit">
html,body,#app{height:100dvh!important;max-height:100dvh!important;overflow:hidden!important;overscroll-behavior:none}
body.ui-battle-v2,body.ui-battle-v2 #app,body.ui-battle-v2 #battle{height:100dvh!important;max-height:100dvh!important;overflow:hidden!important}
body.ui-battle-v2 #battle:not([hidden]){display:flex!important;flex-direction:column!important;padding-bottom:0!important}
body.ui-battle-v2 .arena{flex:1 1 0!important;min-height:0!important}
body.ui-battle-v2 .rollbar{flex:0 0 auto!important;padding:3px 8px calc(8px + env(safe-area-inset-bottom,0px))!important}
body.ui-battle-v2 #roll{min-height:44px!important;font-size:20px!important}
body.ui-battle-v2 #heat,body.ui-battle-v2 #ultBar,body.ui-battle-v2 #rollTrack{height:16px!important;min-height:16px!important}
#battleHeaderV2{min-height:36px!important;max-height:52px!important;height:auto!important}
#guildMomentumV2{height:16px!important}
#battleFooterV2{height:26px!important;min-height:26px!important}
#tacticalV2{min-height:0!important;max-height:36px!important}
#rivalMiniV2{transform:scale(.82);transform-origin:top left}
#suddenBanner{top:8px!important;font-size:10px!important;padding:3px 8px!important}
body.ui-battle-v2 .tbar{min-height:24px!important;padding:1px 6px!important}
canvas#fx,canvas#world{touch-action:none}
</style>
<script>
(()=>{if(window.__softShake)return;window.__softShake=1;
 if(typeof shakeScreen==="function"&&!shakeScreen.__soft){
  const prev=shakeScreen;
  shakeScreen=function(amp,ms){return prev(Math.min(amp||2,2), Math.min(ms||200,160));};
  shakeScreen.__soft=1;
 }
 document.documentElement.style.height='100dvh';
 document.body.style.overflow='hidden';
})();
</script>'''
t=t.replace('</body>',extra+'</body>',1)
p.write_text(t,encoding='utf-8')
print('ok',p.stat().st_size)
