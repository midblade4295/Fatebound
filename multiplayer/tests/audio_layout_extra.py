"""Extra real mixer/offline rendering and worst-case UI geometry checks. Test fixtures only."""
from pathlib import Path
BASE=Path(__file__).with_name('browser_tests.py');space={'__file__':str(BASE)}
exec(BASE.read_text().split('with sync_playwright() as pw:')[0],space)
globals().update({k:v for k,v in space.items() if not k.startswith('__')})
OUT=ROOT/'ui-audio'
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  p=ready_page(b)
  mixed=p.evaluate('''async()=>{const ctx=new OfflineAudioContext(1,64000,32000);Object.defineProperty(ctx,'state',{get:()=> 'running'});const events={};const win={AudioContext:function(){return ctx},localStorage:{getItem:()=>null,setItem:()=>{}},document:{hidden:false,addEventListener:(n,f)=>events[n]=f},performance,addEventListener:()=>{}};const audio=FateboundSoundDesign.create(win);audio.unlock();audio.setVolumes({master:1,combat:1,ui:1});for(let i=0;i<16;i++)audio.play('meteor',{group:'mix'+i});const rendered=await ctx.startRendering();const pcm=rendered.getChannelData(0);let peak=0,power=0;for(const s of pcm){if(!Number.isFinite(s))throw Error('Nonfinite PCM');peak=Math.max(peak,Math.abs(s));power+=s*s;}return {peak,rms:Math.sqrt(power/pcm.length),samples:pcm.length,voices:audio.diagnostics.peakVoices};}''')
  assert mixed['peak']<.98 and mixed['peak']>.1 and mixed['voices']==16,mixed;record('The actual mixer renders 16 simultaneous Meteor cues below full scale at maximum user volume',mixed)
  r=p.evaluate('''()=>{const events={};const win={localStorage:{getItem:()=>null,setItem:()=>{throw Error('disabled storage')}},document:{hidden:false,addEventListener:(k,f)=>events[k]=f},performance,addEventListener:()=>{}};const a=FateboundSoundDesign.create(win);a.unlock();a.setVolumes({master:.5});a.toggle();a.toggle();return {played:a.play('sword'),contexts:a.diagnostics.contexts};}''')
  assert r=={'played':False,'contexts':0};record('Missing Web Audio or blocked audio-preference storage does not break gameplay')
  p.locator('#homeAudio').tap()
  for w,h in [(360,640),(393,852),(412,915),(768,1024),(1280,800),(640,360)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(120);check_hit(p,'#soundDone');check_hit(p,'#soundSettings .comfort-close')
  p.set_viewport_size({'width':393,'height':852});p.screenshot(path=str(OUT/'sound-settings.png'));p.locator('#soundDone').tap();record('Sound sliders scroll while Close and Done stay accessible at six viewport sizes')
  p.evaluate('SAVE.rollTrack={ready:1,progress:0,gold:200,shards:{steel:1,arcane:0,fletch:0}};FateboundUX.refreshBadges()');p.locator('#homeChests').tap();p.screenshot(path=str(OUT/'chest-inbox.png'));p.locator('#chestInbox footer button').tap()
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureSolo').tap();p.wait_for_timeout(1200)
  # Immediate, same-task geometry reads prevent the regular renderer from replacing
  # these intentionally long label fixtures before the worst-case measurement.
  for w,h in [(360,640),(393,852),(412,915),(640,360)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(200)
   r=p.evaluate('''()=>{for(const [id,t] of [['arenaConnection','Reconnecting — verifying your last action with the server…'],['arenaObjective','SUPPLY: Tower VIII · 29 seconds remaining'],['arenaDefense','Allied protection 8s · ENEMY PROTECTED 6s · Arcane Surge 10s']]){$(id).textContent=t;}
    $('battleGiftToastV2').hidden=false;$('v2GiftText').textContent='A guild gift is waiting — collect when ready';
    const ids=['board','roll','arenaSpells','battleGiftToastV2','battleFooterV2'];return Object.fromEntries(ids.map(id=>{const e=$(id),r=e.getBoundingClientRect();return [id,{x:r.x,y:r.y,w:r.width,h:r.height}]}));}''')
   assert all(v['y']>=0 and v['y']+v['h']<=h+1 for v in r.values()),(w,h,r)
   assert r['board']['h']>=100,(w,h,r)
  record('Long reconnect/objective/defense text plus a guild gift fit without pushing controls off screen')
  p.set_viewport_size({'width':393,'height':852});p.wait_for_timeout(300);p.locator('#v2MapBtn').tap();p.wait_for_timeout(200);check_hit(p,'#mapChests');p.locator('#mapChests').tap();check_hit(p,'#chestInbox footer button');p.locator('#chestInbox footer button').tap();record('Persistent chest access works on the locked tower map as well as Home/battle')
  assert not errors,errors
 finally:
  (OUT/'extra-tests.json').write_text(json.dumps({'source_sha256':SOURCE_SHA256,'checks':results,'errors':errors,'console_errors':console_errors,'physical_phone_tested':False},indent=2));b.close()
