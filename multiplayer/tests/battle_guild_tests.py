"""v114 full-game regressions. Forced clocks/outcomes are localhost fixtures only."""
from pathlib import Path
P=Path(__file__).with_name('browser_tests.py');ns={'__file__':str(P)}
exec(P.read_text().split('with sync_playwright() as pw:')[0],ns)
globals().update({k:v for k,v in ns.items() if not k.startswith('__')})
OUT=ROOT/'battle-guild-audit';OUT.mkdir(exist_ok=True)
def overlap(a,b):return min(a['x']+a['width'],b['x']+b['width'])>max(a['x'],b['x'])+1 and min(a['y']+a['height'],b['y']+b['height'])>max(a['y'],b['y'])+1
def queue(p,loadout=None):
 p.locator('#adventurePrepareButton').tap()
 if loadout:
  for k in loadout:p.locator('[data-equip="'+k+'"]').tap()
 p.locator('#adventureQueue').tap();p.wait_for_selector('#queueCount');p.wait_for_timeout(300)
def roll(p,faces):
 debug('boost');debug('force-faces?faces='+faces);p.wait_for_timeout(850);p.locator('#roll').tap();p.wait_for_timeout(2600)
 assert not p.locator('#roll').evaluate("e=>e.classList.contains('busy')")
 return p.evaluate('FateboundBattle.diagnostics.lastResult')
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  debug('reset');p=ready_page(b)
  p.locator('nav [data-tab="guild"]').tap();p.wait_for_timeout(400)
  assert p.locator('#guildPane-overview').is_visible();assert p.locator('#guildPane-chat').is_hidden()
  p.screenshot(path=str(OUT/'guild-overview.png'))
  record('New Guild hall has distinct live-expedition, solo-company and hero-perk sections')
  p.locator('#guildTab-chat').tap();p.locator('#gmsg').press_sequentially('Guild push east',delay=80)
  assert p.locator('#gmsg').input_value()=='Guild push east'
  p.evaluate("$('gmsg').setSelectionRange(6,6);window.composeInput=$('gmsg');window.composeTop=$('scrGuild').scrollTop")
  for i in range(5):
   p.evaluate("M.startAt++;renderGuild();feed('Fresh battle update','info');renderGuild();")
   p.wait_for_timeout(120)
  assert p.evaluate("$('gmsg')===composeInput&&$('gmsg').selectionStart===6&&$('gmsg').selectionEnd===6")
  p.keyboard.insert_text('careful ');assert p.locator('#gmsg').input_value()=='Guild careful push east'
  record('Typing stays left-to-right and mid-text caret survives rekeyed match data and five live refreshes')
  p.evaluate("$('gmsg').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}));$('gmsg').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:229,isComposing:true,bubbles:true,cancelable:true}));renderGuild()")
  assert p.evaluate('FateboundGuild.diagnostics.sent')==0
  assert p.locator('#gmsg').input_value()=='Guild careful push east'
  p.evaluate("$('gmsg').dispatchEvent(new CompositionEvent('compositionend',{data:'east',bubbles:true}))")
  p.locator('#gsend').tap();assert 'You: Guild careful push east' in p.locator('#glog').inner_text();assert p.locator('#gmsg').input_value()==''
  record('IME confirmation does not prematurely send; a deliberate Send adds exactly one message')
  p.locator('#gmsg').fill('Next wave');p.locator('#guildTab-roster').tap();p.locator('#guildTab-chat').tap();assert p.locator('#gmsg').input_value()=='Next wave'
  p.screenshot(path=str(OUT/'guild-war-room.png'));p.locator('#guildTab-roster').tap();p.screenshot(path=str(OUT/'guild-roster.png'))
  record('Guild tabs preserve the mounted composer and unsent draft; local feed is labelled honestly')
  p.locator('#guildTab-overview').tap();p.evaluate("$('scrGuild').scrollTop=250;window.stableTop=$('scrGuild').scrollTop")
  vals=p.evaluate("""async()=>{const out=[];for(let i=0;i<25;i++){await new Promise(r=>setTimeout(r,100));out.push([$ ('scrGuild').scrollTop,$('scrGuild').scrollHeight]);}return out}""")
  assert len({tuple(v) for v in vals})==1,vals
  record('Guild Overview scroll height/position stays constant through repeated live refreshes',vals[0])
  p.locator('nav [data-tab="home"]').tap()
  q=ready_page(b);queue(p);queue(q,['horn','surge']);debug('advance?ms=20000')
  p.wait_for_function('FBNext.active');q.wait_for_function('FBNext.active');debug('boost');p.wait_for_timeout(900)
  assert p.evaluate('M.arenaId')==q.evaluate('M.arenaId');assert p.evaluate('FBNext.latest.heroes.filter(h=>h.bot).length')==18
  record('Both touch clients join the same 20-slot match after the full search deadline')
  # Numeric receipts are compared with server effects, not expected decorative text alone.
  startGold=p.evaluate('SAVE.gold')
  for faces,title in [('G,G,H','GOLD'),('H,G,H','SHIELD'),('S,E,E','FOCUS'),('F,F,G','TEAM GIFT'),('C,H,C','CRITICAL'),('S,S,H','ATTACK')]:
   r=roll(p,faces);assert r is not None,(faces,p.locator('#rollOutcomeV114').inner_text())
   assert title in p.locator('#rollOutcomeTitle').inner_text();assert p.evaluate('SAVE.gold')==startGold
   detail=p.locator('#rollOutcomeDetail').inner_text();assert detail not in ['', 'Waiting for the server-confirmed result…']
   record('Confirmed '+title+' receipt is visible and does not directly mint online wallet rewards',{'faces':r['faces'],'effects':r['effects'],'detail':detail})
  assert 'banked' in p.locator('#rollOutcomeDetail').inner_text().lower() or p.evaluate('FateboundBattle.diagnostics.banked.gold')>0
  before=p.locator('#rollOutcomeV114').inner_text()
  p.evaluate("for(let i=0;i<20;i++)toast('Bot '+i+' used an ultimate','info')")
  p.wait_for_timeout(800);assert p.locator('#rollOutcomeV114').inner_text()==before
  record('Ambient bot notifications do not replace the persistent personal result/earnings panel')
  # Delaying only action responses leaves the browser event loop and state polling operational.
  p.evaluate("""()=>{window.normalFetch=fetch;window.stateDuringAction=0;window.holdAction=true;window.actionWaiting=false;window.fetch=async(...args)=>{const url=String(args[0]);if(url.includes('/state')&&actionWaiting)stateDuringAction++;const r=await normalFetch(...args);if(url.includes('/action')&&holdAction){holdAction=false;actionWaiting=true;await new Promise(x=>setTimeout(x,2200));actionWaiting=false;}return r;};}""")
  debug('boost');p.wait_for_timeout(900);p.locator('#roll').tap();p.wait_for_timeout(300);assert 'Confirming' in p.locator('#rollCost').inner_text()
  p.wait_for_timeout(4500);assert p.evaluate('FBNext.latest.heroes.find(h=>h.id===player.id).connected')
  assert p.evaluate('stateDuringAction')>=2;assert p.evaluate('FateboundBattle.diagnostics.lastResult.type')=='roll';p.evaluate('()=>{window.fetch=normalFetch;}')
  record('A delayed action receipt does not stop state polling or strand the dice input')
  # Moving is asynchronous. No outer legacy wrapper is allowed to mutate view or Focus early.
  p.locator('#v2MapBtn').tap();p.wait_for_timeout(300)
  p.evaluate("""()=>{window.normalFetch=fetch;window.fetch=async(...args)=>{const r=await normalFetch(...args);if(String(args[0]).includes('/action'))await new Promise(x=>setTimeout(x,600));return r;};window.beforeMoveFocus=M.focus;window.beforeTower=player.tower;window.movePromise=enterTower(4);}""")
  assert p.evaluate("screen==='map'")
  p.wait_for_function("screen==='battle'&&player.tower===4");p.evaluate('()=>{window.fetch=normalFetch;}')
  assert p.evaluate('M.focus===FBNext.latest.heroes.find(h=>h.id===player.id).focus')
  record('Tower view opens only after confirmation and cannot grant legacy client-only Focus')
  # Never move on a pointerdown/scroll gesture, even if it starts on a clickable tower.
  p.locator('#v2MapBtn').tap();p.wait_for_timeout(250);before=p.evaluate('player.tower')
  p.evaluate("""()=>{const r=wcv.getBoundingClientRect();wcv.dispatchEvent(new PointerEvent('pointerdown',{pointerId:9,button:0,clientX:r.left+130,clientY:r.top+300,bubbles:true}));wcv.dispatchEvent(new PointerEvent('pointermove',{pointerId:9,clientX:r.left+132,clientY:r.top+355,bubbles:true}));wcv.dispatchEvent(new PointerEvent('pointerup',{pointerId:9,button:0,clientX:r.left+132,clientY:r.top+355,bubbles:true}));}""")
  p.wait_for_timeout(500);assert p.evaluate('player.tower')==before and p.evaluate("screen==='map'")
  record('Dragging/scrolling the tower map never counts as a tower selection')
  # Inject the exact unsafe-context scenario found in v113, then verify recovery.
  proof=p.evaluate("""()=>{const old=drawHero;let once=true;drawHero=function(...a){if(once){once=false;ctx.save();ctx.scale(4,4);throw Error('expected fixture atlas failure')}return old(...a)};try{renderMap()}finally{drawHero=old}return {correct:ctx===cv.getContext('2d'),count:FateboundBattle.diagnostics.mapRecoveries};}""")
  assert proof['correct'] and proof['count']==1,proof
  p.evaluate('enterTower(6)');p.wait_for_function("screen==='battle'&&player.tower===6")
  n=p.evaluate('FateboundBattle.diagnostics.frames');p.wait_for_timeout(600);assert p.evaluate('FateboundBattle.diagnostics.frames')>n+5
  assert p.evaluate('Math.abs(ctx.getTransform().a-SC)<.001')
  record('Injected map-atlas failure restores the battle canvas; tower switch and subsequent frames recover',proof)
  proof=p.evaluate("""()=>{const old=drawHero;let once=true;drawHero=function(...a){if(once){once=false;ctx.save();ctx.beginPath();ctx.rect(0,0,1,1);ctx.clip();throw Error('expected fixture paint failure')}return old(...a)};try{draw(performance.now())}finally{drawHero=old}return {correct:ctx===cv.getContext('2d'),count:FateboundBattle.diagnostics.drawRecoveries};}""")
  assert proof['correct'] and proof['count']==1; p.wait_for_timeout(500);assert p.evaluate('Math.abs(ctx.getTransform().a-SC)<.001')
  record('A failed sprite cannot leave a clipped/scaled canvas corrupting every subsequent frame',proof)
  for tower in [7,3,8]:
   p.locator('#v2MapBtn').tap();p.evaluate(f'enterTower({tower})');p.wait_for_function(f"screen==='battle'&&player.tower==={tower}");p.wait_for_timeout(900)
  assert p.evaluate('player.tower===FBNext.latest.heroes.find(h=>h.id===player.id).tower')
  record('Repeated tower changes preserve authoritative tower, correct canvas scale and interactive ROLL')
  # A successful roll may still be animating when a player deliberately changes view.
  debug('boost');debug('force-faces?faces=G,G,H');p.wait_for_timeout(850);p.locator('#roll').tap()
  p.wait_for_function("!!FateboundBattle.diagnostics.lastResult&&player.rolls>=8")
  p.locator('#v2MapBtn').tap();p.evaluate('enterTower(2)');p.wait_for_function("screen==='battle'&&player.tower===2")
  p.wait_for_timeout(2700);assert not p.locator('#roll').evaluate("e=>e.classList.contains('busy')")
  assert 'GOLD' in p.locator('#rollOutcomeTitle').inner_text();assert 'gold banked' in p.locator('#rollOutcomeDetail').inner_text()
  assert p.evaluate("player.tower===2&&ctx===cv.getContext('2d')")
  record('Changing tower during a dice animation preserves the accepted reward and cancels old-board tweens')
  p.locator('#v2MapBtn').tap();p.evaluate('enterTower(8)');p.wait_for_function("screen==='battle'&&player.tower===8");p.wait_for_timeout(800)
  # Real action effects: p casts Barrage/Bulwark, q has Horn/Surge. Nearby client also receives effects.
  q.evaluate('enterTower(8)');q.wait_for_function('player.tower===8');q.wait_for_timeout(700)
  for page,key in [(p,'barrage'),(p,'bulwark'),(q,'horn'),(q,'surge')]:
   debug('boost');page.wait_for_timeout(850);start=page.evaluate('FateboundBattle.diagnostics.effectsStarted');page.locator('[data-cast="'+key+'"]').tap();page.wait_for_timeout(380)
   assert page.evaluate('FateboundBattle.diagnostics.effectsStarted')>start,key
   page.screenshot(path=str(OUT/f'spell-{key}.png'));record('Confirmed '+key+' creates its own in-field effect without blocking controls')
  p.evaluate("for(let i=0;i<50;i++)FateboundBattle.spell(['barrage','bulwark','horn','surge'][i%4],player.id,player.tower)")
  assert p.evaluate('FateboundBattle.diagnostics.effects')<=8
  p.wait_for_timeout(1700);assert p.evaluate('FateboundBattle.diagnostics.effects')==0
  record('Spell effects cap at eight active instances and expire without persistent DOM or timers')
  # The user's problematic optional states coexist; no resetting hidden flags to make the test pass.
  layouts=[]
  for w,h in [(360,640),(393,852),(412,915),(768,1024),(1280,800),(640,360),(320,568)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(450)
   p.evaluate("toast('Nearby ultimate','info');bigBanner('SPELL READY','Barrage confirmed');")
   for sel in ['#roll','#v2MoreBtn','#v2MapBtn','#battleChests','#giftAttackButton','#arenaSpells button:first-child']:check_hit(p,sel)
   sels=['#battleHeaderV2','#battleTools','#board','#battleNotice','#rollOutcomeV114','#arenaSpells','#roll','#battleFooterV2']
   rects={s:p.locator(s).bounding_box() for s in sels}
   for i,a in enumerate(sels):
    for bb in sels[i+1:]:assert not overlap(rects[a],rects[bb]),(w,h,a,bb,rects[a],rects[bb])
   assert p.locator('#tacticalV2').is_hidden();assert p.locator('#board').bounding_box()['height']>=80
   p.locator('#v2MoreBtn').tap();check_hit(p,'#v2DrawerClose');check_hit(p,'[data-v2-dest="sound"]')
   assert not overlap(p.locator('#v2DrawerClose').bounding_box(),p.locator('[data-v2-dest="sound"]').bounding_box())
   p.screenshot(path=str(OUT/f'drawer-{w}x{h}.png'));p.locator('#v2DrawerClose').tap();p.screenshot(path=str(OUT/f'battle-{w}x{h}.png'));layouts.append({'viewport':[w,h],'regions':rects})
  (OUT/'layout-boxes.json').write_text(json.dumps(layouts,indent=2));record('Seven viewport sizes keep scoreboard, spells, result, canvas and footer separate; drawer buttons stay above footer')
  p.set_viewport_size({'width':393,'height':852});p.wait_for_timeout(400)
  # A hidden/late modal must not reintroduce the floating notification from the screenshot.
  p.locator('#v2MoreBtn').tap();p.evaluate("toast('Bot used an ultimate','info')");assert p.locator('#toast').is_hidden();p.locator('[data-v2-dest="sound"]').tap();check_hit(p,'#soundDone');p.locator('#soundDone').tap()
  record('Battle notifications stay out of control space even with More/Sound dialogs open')
  # Actual match-end receipt still grants banked gold only once.
  goldBefore=p.evaluate('SAVE.gold');debug('finish');p.wait_for_selector('#resultClaim');reward=p.evaluate('FBNext.receipt.reward.gold');assert reward>0
  p.locator('#resultClaim').tap();p.wait_for_function("screen==='home'&&!FBNext.active");assert p.evaluate('SAVE.gold')==goldBefore+reward
  q.wait_for_selector('#resultClaim');q.locator('#resultClaim').tap();q.wait_for_function("screen==='home'&&!FBNext.active")
  record('Online banked gold is granted exactly at final Claim, not on each local result animation',reward)
  queue(p);queue(q);debug('advance?ms=20000');p.wait_for_function('FBNext.active');q.wait_for_function('FBNext.active')
  assert p.evaluate('M.arenaId')==q.evaluate('M.arenaId');assert p.evaluate('FateboundBattle.diagnostics.lastResult') is None
  record('A second shared battle resets its own feedback/FX without resetting progress or breaking input')
  assert not errors,errors;assert not console_errors,console_errors
 finally:
  (OUT/'browser-tests.json').write_text(json.dumps({'source_sha256':SOURCE_SHA256,'checks':results,'errors':errors,'console_errors':console_errors,'physical_phone_tested':False},indent=2));b.close()
