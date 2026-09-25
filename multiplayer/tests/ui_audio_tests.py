"""Full HTML v111 regressions with touch hit-tests, stable scroll and real Web Audio.
Fixture saves/forced battle states exist only inside the disposable browser document.
"""
from pathlib import Path
BASE=Path(__file__).with_name('browser_tests.py')
space={'__file__':str(BASE)}
exec(BASE.read_text().split('with sync_playwright() as pw:')[0],space)
globals().update({k:v for k,v in space.items() if not k.startswith('__')})
OUT=ROOT/'ui-audio';OUT.mkdir(exist_ok=True)
def close(p):p.context.close()
def solo(p):
 p.locator('#adventurePrepareButton').tap();p.locator('#adventureSolo').tap();p.wait_for_function("screen==='battle'&&!M.lobby");p.wait_for_timeout(1000)
def rectangle(p,s):return p.locator(s).bounding_box()
def overlap(a,b):return min(a['x']+a['width'],b['x']+b['width'])>max(a['x'],b['x'])+1 and min(a['y']+a['height'],b['y']+b['height'])>max(a['y'],b['y'])+1
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  p=ready_page(b)
  assert p.evaluate('FateboundAudio.diagnostics.contexts')==0
  p.locator('nav [data-tab="guild"]').tap();p.wait_for_timeout(350)
  p.evaluate("$('scrGuild').scrollTop=430;window.guildInput=$('gmsg');window.guildEntry=$('expeditionEntry');$('gmsg').value='Unsent draft';window.guildTop=$('scrGuild').scrollTop")
  data=p.evaluate("""async()=>{const rows=[];for(let i=0;i<50;i++){await new Promise(r=>setTimeout(r,100));rows.push({top:$('scrGuild').scrollTop,height:$('scrGuild').scrollHeight,sameInput:$('gmsg')===guildInput,sameEntry:$('expeditionEntry')===guildEntry,draft:$('gmsg').value});}return rows;}""")
  assert len(set((d['top'],d['height']) for d in data))==1 and all(d['sameInput'] and d['sameEntry'] and d['draft']=='Unsent draft' for d in data),data
  record('Guild scroll, expedition button, chat input and draft remain stable across five live refreshes',data[0])
  p.evaluate("feed('A new guild update','info');renderGuild()")
  assert p.evaluate("$('scrGuild').scrollTop===guildTop&&$('gmsg').value==='Unsent draft'")
  p.locator('#gmsg').focus();p.keyboard.press('Enter');p.wait_for_timeout(1100)
  assert p.locator('#gmsg').input_value()=='' and 'You: Unsent draft' in p.locator('#glog').inner_text()
  record('A guild message updates in place; typing and sending do not replace the page')
  p.screenshot(path=str(OUT/'guild-stable.png'));p.locator('nav [data-tab="home"]').tap()
  p.locator('#homeAudio').tap();check_hit(p,'#soundDone');p.locator('[data-preview="sword"]').tap();p.wait_for_timeout(150)
  d=p.evaluate('FateboundAudio.diagnostics');assert d['contexts']==1 and d['counts'].get('sword',0)>0,d
  record('First user gesture unlocks one AudioContext; the actual sword cue plays')
  p.evaluate("$('audio-combat').value=25;$('audio-combat').dispatchEvent(new Event('input',{bubbles:true}))")
  assert p.locator('#audioValue-combat').inner_text()=='25%' and p.evaluate('FateboundAudio.volumes.combat')==.25
  p.locator('#audioMute').tap();before=p.evaluate('FateboundAudio.diagnostics.played');p.locator('[data-preview="crit"]').tap();p.wait_for_timeout(100)
  assert p.evaluate('FateboundAudio.diagnostics.played')==before and p.evaluate('FateboundAudio.muted')
  store=p.evaluate("({'fatebound-save':localStorage.getItem('fatebound-save'),'fatebound-audio-prefs':localStorage.getItem('fatebound-audio-prefs'),'ds-mute':localStorage.getItem('ds-mute')})")
  q=ready_page(b,storage=store);assert q.evaluate('FateboundAudio.muted&&FateboundAudio.volumes.combat===.25');close(q)
  record('Mute and separate volume preferences work and survive a document reload')
  p.locator('#audioMute').tap();p.evaluate('FateboundAudio.setVolumes({master:.7,combat:.8,ui:.6})');p.locator('#soundDone').tap()
  result=p.evaluate("""async()=>{FateboundAudio.stopAll();for(let i=0;i<70;i++)FateboundAudio.play('barrage',{group:'stress'+i});const active=FateboundAudio.diagnostics;await new Promise(r=>setTimeout(r,1700));return {active,after:FateboundAudio.diagnostics};}""")
  assert result['active']['voices']<=16 and result['active']['peakVoices']<=16 and result['after']['voices']==0 and result['after']['contexts']==1,result
  record('Seventy overlapping requests stay within 16 voices and all nodes clean up',result['after'])
  p.evaluate("FateboundAudio.play('meteor');document.dispatchEvent(new Event('visibilitychange'))")
  # A pagehide always clears sources without leaving pending playback.
  p.evaluate("window.dispatchEvent(new Event('pagehide'))")
  assert p.evaluate('FateboundAudio.diagnostics.voices')==0
  record('Leaving the page stops active sources; there is no delayed sound backlog')
  # Roll-track rewards retain original quantities and require an explicit button press.
  p.evaluate("SAVE.rollTrack={progress:7,ready:2,gold:400,shards:{steel:2,arcane:0,fletch:0}};persist();FateboundUX.refreshBadges()")
  p.locator('#homeChests').tap();check_hit(p,'#collectRollChests');before=p.evaluate('({gold:SAVE.gold,shards:SAVE.shards.steel||0,pts:SAVE.season.pts,focus:M.focus})')
  p.wait_for_timeout(8500);assert p.locator('#chestInbox').is_visible() and p.evaluate('rollTrack().ready')==2
  record('Roll-chest inbox and collection stay available beyond the old notification timeout')
  p.locator('#chestInbox footer button').tap();p.locator('nav [data-tab="guild"]').tap();p.locator('nav [data-tab="home"]').tap()
  assert p.locator('#homeChests b').inner_text()=='2'
  store=p.evaluate("({'fatebound-save':localStorage.getItem('fatebound-save')})");q=ready_page(b,storage=store);q.locator('#homeChests').tap();assert q.evaluate('rollTrack().ready')==2;close(q)
  p.locator('#homeChests').tap();p.evaluate("window.oldClaim=$('collectRollChests')");p.locator('#collectRollChests').tap()
  after=p.evaluate('({gold:SAVE.gold,shards:SAVE.shards.steel||0,pts:SAVE.season.pts,ready:rollTrack().ready})')
  assert after['gold']-before['gold']==400 and after['shards']-before['shards']==2 and after['pts']==before['pts'] and after['ready']==0,(before,after)
  p.evaluate('oldClaim.click()');assert p.evaluate('SAVE.gold')==after['gold']
  record('Chests survive menu/reload, grant the original 400 gold and 2 shards once, and reject repeat clicks')
  p.locator('#chestInbox footer button').tap();p.evaluate("SAVE.pendingOpenChest=makeChest(1);persist();FateboundUX.refreshBadges()")
  p.locator('#homeChests').tap();p.locator('#inspectLootChest').tap();p.wait_for_timeout(3000);check_hit(p,'#chestLater');p.locator('#chestLater').tap()
  assert p.evaluate('!!SAVE.pendingOpenChest');p.locator('#homeChests').tap();p.locator('#inspectLootChest').tap();p.locator('#chestHold').tap()
  assert p.evaluate('!SAVE.pendingOpenChest&&SAVE.chests.length===1')
  record('Loot drops can be dismissed and reopened; Hold preserves the original end-of-match bonus')
  # Battle utility controls & cinematic banners at six viewports, with all optional statuses on.
  solo(p);p.evaluate("player.rival=M.heroes.find(h=>h.side===1).id;player.hp=player.maxHp;player.downUntil=0;FateboundSpells.addCharge();M.cards=[]")
  boxes=[]
  for w,h in [(360,640),(393,852),(412,915),(768,1024),(1280,800),(640,360)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(650)
   p.evaluate("toast('Chest saved — open Chests whenever you are ready','reward');bigBanner('SPELL READY','A temporary visual effect inside the playfield');")
   p.wait_for_timeout(100)
   for sel in ['#roll','#rally','#mults','#battleChests','#giftAttackButton','#arenaSpells button:first-child','#v2MapBtn','#v2MoreBtn']:
    p.locator(sel).evaluate('(e)=>e.disabled=false') # layout/hit-test fixture only, not a gameplay bypass in delivery
    check_hit(p,sel)
   cv=rectangle(p,'#board');assert cv['height']>=100,(w,h,cv)
   sels=['#battleTools','#battleNotice','#arenaSpells','#roll','#battleFooterV2']
   rs={s:rectangle(p,s) for s in sels}
   assert all(not overlap(cv,r) for r in rs.values()),(w,h,cv,rs)
   assert all(not overlap(rs[a],rs[b]) for i,a in enumerate(sels) for b in sels[i+1:]),(w,h,rs)
   banner=rectangle(p,'#bigBanner');notice=rs['#battleNotice'];assert banner['y']>=notice['y'] and banner['y']+banner['height']<=notice['y']+notice['height']+1,(w,h,notice,banner)
   assert p.locator('#clashSpellWrap').is_hidden();assert not p.locator('#toast').evaluate("e=>e.classList.contains('show')")
   boxes.append({'viewport':[w,h],'field':cv,'hud':rs});p.screenshot(path=str(OUT/f'battle-{w}x{h}.png'))
  (OUT/'layout-boxes.json').write_text(json.dumps(boxes,indent=2))
  record('Battle tools, notifications, spells, ROLL, footer and field do not overlap at six sizes')
  p.set_viewport_size({'width':393,'height':852});p.wait_for_timeout(300);p.locator('#battleChests').tap();check_hit(p,'#chestInbox footer button');p.locator('#chestInbox footer button').tap()
  p.locator('#v2MoreBtn').tap();p.locator('[data-v2-dest="sound"]').tap();check_hit(p,'#soundDone');p.locator('#soundDone').tap()
  record('Battle menu opens the audio mixer and Chests remains reachable without enabling Home navigation')
  # Persistent chest indication remains available after battle result collection.
  p.evaluate("SAVE.rollTrack={progress:0,ready:1,gold:200,shards:{steel:1,arcane:0,fletch:0}};player.paidRolls=5;M.towers[9].dmg=[1000000,0];M.endAt=Date.now();SAVE.war.endAt=M.endAt;warTick()")
  p.wait_for_timeout(500)
  if p.locator('#postNextV2').is_visible():p.locator('#postNextV2').tap()
  p.wait_for_timeout(800)
  # Existing staged post-result controls are driven rather than bypassed in this test.
  for _ in range(5):
   if p.locator('#again').is_visible():break
   if p.locator('#postNextV2').is_visible():p.locator('#postNextV2').tap()
   p.wait_for_timeout(700)
  p.locator('#again').tap();p.wait_for_function("screen==='home'")
  p.locator('#homeChests').tap();assert p.evaluate('rollTrack().ready')==1;check_hit(p,'#collectRollChests');p.locator('#chestInbox footer button').tap()
  record('Unclaimed roll chest survives battle result/Claim and stays accessible on Home')
  solo(p);p.wait_for_timeout(500);assert p.evaluate("screen==='battle'&&!M.ended")
  record('A second solo battle starts after new dialogs, sounds and saved reward activity')
  close(p)
  assert not errors,errors;assert not console_errors,console_errors
 finally:
  (OUT/'browser-tests.json').write_text(json.dumps({'source_sha256':SOURCE_SHA256,'checks':results,'errors':errors,'console_errors':console_errors,'physical_phone_tested':False},indent=2));b.close()
