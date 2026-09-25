"""Full bundled HTML against the real local arena server. Test-only save/time fixtures.
No fixture or request routing from this file is included in the shipped HTML/server.
"""
from pathlib import Path
import json, requests, time, traceback
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).parents[1]
GAME_PATH=ROOT/'fatebound.html' if (ROOT/'fatebound.html').exists() else ROOT.parent/'fatebound.html'
GAME_TEXT=GAME_PATH.read_text()
import hashlib
SOURCE_SHA256=hashlib.sha256(GAME_TEXT.encode()).hexdigest()
results=[];errors=[];console_errors=[]
def record(name,detail=''):
 results.append({'check':name,'status':'PASS','detail':detail});print('PASS',name,detail,flush=True)
def debug(cmd):
 r=requests.get('http://127.0.0.1:8852/'+cmd,timeout=15);r.raise_for_status();return r.json()
def routed(r):
 u=r.request.url
 if u.startswith('https://arena.test/'):
  h={k:v for k,v in r.request.headers.items() if k.lower() in ('authorization','content-type')};h['Origin']='null'
  try:
   a=requests.request(r.request.method,u.replace('https://arena.test','http://127.0.0.1:8851'),headers=h,data=r.request.post_data,timeout=12)
   r.fulfill(status=a.status_code,body=a.content,headers={'content-type':'application/json','access-control-allow-origin':'*','access-control-allow-headers':'Authorization,Content-Type'})
  except Exception:r.abort()
 else:r.abort()
def bundled(seed=None,storage=None):
 save=seed or {'owned':[0], 'tutorial':{'done':True,'paused':True},'tutorialBattle':{'done':True,'paused':True}}
 shim='''<script>Object.defineProperty(window,'localStorage',{value:(()=>{const m=new Map(Object.entries(INIT));return {getItem:k=>m.has(k)?m.get(k):null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k),clear:()=>m.clear()};})(),configurable:true});window.FATEBOUND_ARENA_URL='https://arena.test/fatebound/arena';</script>'''.replace('INIT',json.dumps(storage or {'fatebound-save':json.dumps(save)}))
 return GAME_TEXT.replace('<head>','<head>'+shim,1)
def ready_page(browser,storage=None):
 ctx=browser.new_context(viewport={'width':393,'height':852},is_mobile=True,has_touch=True,device_scale_factor=1)
 page=ctx.new_page();page.set_default_timeout(12000);page.route('**/*',routed)
 page.on('pageerror',lambda e:(errors.append(e.stack),print('PAGEERROR',e.stack,flush=True)))
 page.on('console',lambda m:console_errors.append(m.text) if m.type=='error' and 'Failed to load' not in m.text else None)
 page.set_content(bundled(storage=storage),wait_until='load',timeout=60000);page.wait_for_timeout(1200)
 return page
# A centre-point hit test catches overlays and invisible Home panels, not just CSS 'visible'.
def hit(page,selector):
 return page.locator(selector).evaluate('''e=>{const r=e.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,h=document.elementFromPoint(x,y);return {ok:!!h&&(h===e||e.contains(h)),h:h?.id||h?.tagName,rect:{x:r.x,y:r.y,w:r.width,h:r.height},vw:innerWidth,vh:innerHeight};}''')
def check_hit(page,selector):
 h=hit(page,selector);assert h['ok'],(selector,h);assert h['rect']['y']>=-1 and h['rect']['y']+h['rect']['h']<=h['vh']+1,(selector,h)
 return h
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  debug('reset');p=ready_page(browser)
  assert p.evaluate("screen==='home'&&!TRAIN")
  record('Full audited HTML boots with a preserved completed tutorial save')
  for menu in ['guild','hero','friends','shop','home']:
   p.locator(f'nav [data-tab="{menu}"]').tap();p.wait_for_timeout(150)
   roots=p.evaluate('activeRoots()');assert roots==[{'home':'setup','guild':'scrGuild','hero':'scrHero','friends':'scrFriends','shop':'scrShop'}[menu]],roots
   p.locator('#seasonPill').tap();check_hit(p,'#passClose');p.locator('#passClose').tap()
  record('Five menus remain exclusive; Season Pass opens and closes above each')
  p.locator('#homeRaid').tap();p.wait_for_timeout(200);check_hit(p,'#bossBack');assert p.locator('#bossUI').is_visible()
  p.screenshot(path=str(ROOT/'docs/raid-fixed.png'))
  p.locator('#bossBack').tap();record('Raid dialog receives touches above Home and Back remains reachable')
  p.locator('#homeRaid').tap();p.locator('#bossGo').tap();p.wait_for_timeout(1000)
  assert p.evaluate('M.inBoss&&!M.lobby');check_hit(p,'#roll');p.locator('#roll').tap();p.wait_for_timeout(3000)
  p.evaluate("BR.until=Date.now()-1");p.wait_for_function("screen==='home'&&!M.inBoss");p.wait_for_timeout(700)
  if p.locator('#bossUI').is_visible():p.locator('#bossBack').tap()
  p.evaluate('homeHub()');p.wait_for_timeout(200);record('Raid attempt opens, rolls and exits without leaving covered roots')
  # Existing helper/gift dialogs, and level rewards, with staged disposable test data.
  for overlay,close,openjs in [('scoreHelp','shOk',"$('scoreHelp').hidden=false"),('noEnergy','neOk',"$('noEnergy').hidden=false"),('giftAttackPicker','giftAttackClose',"renderGiftAttacks();$('giftAttackPicker').hidden=false")]:
   p.evaluate(openjs);p.wait_for_timeout(120);check_hit(p,'#'+close);p.locator('#'+close).tap()
  p.evaluate('homeHub()');record('Score help, low-resource and stored-gift modal controls remain above the current menu')
  p.locator('#adventurePrepareButton').tap();p.locator('[data-equip="surge"]').tap();p.locator('[data-equip="barrage"]').tap()
  assert p.evaluate('SAVE.adventure.loadout')==['surge','barrage']
  p.locator('#adventureGoal').select_option('0');assert 'remaining' in p.locator('#adventureGoalText').inner_text()
  record('Two-spell selection persists and pinned upgrade reports actual remaining costs')
  # Modal layout audit with real computed viewport and hit tests at six sizes.
  for w,h in [(360,640),(393,852),(412,915),(768,1024),(1280,800),(640,360)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(150)
   check_hit(p,'#adventureQueue');check_hit(p,'#adventureSolo')
   p.locator('#adventurePrep [data-dismiss]').tap();p.locator('#homeRaid').tap();check_hit(p,'#bossBack');p.locator('#bossBack').tap();p.locator('#adventurePrepareButton').tap()
  p.set_viewport_size({'width':393,'height':852});p.screenshot(path=str(ROOT/'docs/prepare-tested.png'));record('Preparation and raid modal controls fit six portrait/landscape/desktop viewports')
  p.locator('#adventureExpedition').tap();p.wait_for_selector('#guildCreate');p.locator('#guildName').fill('QA Expedition');p.locator('#guildCreate').tap();p.wait_for_selector('#guildRoute');p.locator('#guildRoute').select_option('defense');p.wait_for_timeout(300)
  assert 'defense' in p.locator('#adventureGuild').inner_text();p.locator('#adventureGuild [data-dismiss]').tap();record('Live guild create and leader route selection use the real HTTP service')
  # Offline challenge uses the same combat engine but does not grant rewards.
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureChallenge').tap();p.wait_for_timeout(1200)
  assert p.evaluate('FBNext.active&&!FBNext.online&&M.heroes.length===20')
  check_hit(p,'#roll');assert p.evaluate('getComputedStyle(document.querySelector("nav")).display')=='none'
  p.locator('#roll').tap();p.wait_for_timeout(3200);assert p.evaluate('player.rolls')==1
  record('Equalized offline challenge starts, all dice settle, and Home navigation is absent')
  # Finish this practice through its engine deadline, a test-only clock change.
  beforePractice=p.evaluate('({gold:SAVE.gold,mastery:JSON.stringify(SAVE.adventure.mastery)})')
  p.evaluate('window.__testRealDateNow=Date.now;Date.now=()=>__testRealDateNow()+400000;')
  p.wait_for_timeout(900)
  if not p.locator('#adventureResult').is_visible():
   p.evaluate('Date.now=()=>__testRealDateNow()+470000;');p.wait_for_timeout(500)
  p.locator('#resultClaim').tap();p.wait_for_function("screen==='home'&&!FBNext.active")
  assert p.evaluate('({gold:SAVE.gold,mastery:JSON.stringify(SAVE.adventure.mastery)})')==beforePractice
  record('Offline challenge result and Claim return Home without granting resources or mastery')
  p.context.close();p=ready_page(browser);q=ready_page(browser)
  for page in [p,q]:
   page.locator('#adventurePrepareButton').tap();page.locator('#adventureQueue').tap();page.wait_for_function("document.getElementById('queueCount').textContent.includes('/ 20')")
  assert '/ 20 human' in p.locator('#queueCount').inner_text()
  debug('advance?ms=19000');p.wait_for_timeout(180);assert not p.evaluate('FBNext.active')
  debug('advance?ms=1000');p.wait_for_function('FBNext.active');q.wait_for_function('FBNext.active')
  a=p.evaluate('FBNext.latest');b=q.evaluate('FBNext.latest');assert a['id']==b['id'];assert len(a['heroes'])==20;assert sum(h['bot'] for h in a['heroes'])==18
  assert [len([h for h in a['heroes'] if h['side']==sd]) for sd in [0,1]]==[10,10]
  record('Two browser clients join one authoritative 20-slot room after the deadline', '18 labelled bots; 10 vs 10')
  resumeStore=p.evaluate("({'fatebound-save':localStorage.getItem('fatebound-save'),'fatebound-arena-identity':localStorage.getItem('fatebound-arena-identity')})")
  p.context.close();p=ready_page(browser,storage=resumeStore);p.wait_for_function('FBNext.active');assert p.evaluate('M.arenaId')==a['id'];assert p.evaluate('M.heroes.length')==20
  record('Reload automatically resumes the same room/identity without allocating another seat')
  for i in range(5):
   debug('boost');p.wait_for_timeout(850);p.locator('#roll').tap();p.wait_for_timeout(3000)
  assert p.evaluate('player.paidRolls')>=5
  assert q.evaluate('FBNext.latest.heroes.find(h=>h.id!==player.id&&!h.bot).paidRolls')>=5
  record('Five server-authorized throws settle on the client and synchronize to the other browser')
  debug('boost');p.wait_for_timeout(850);p.locator('[data-cast="barrage"]').tap();p.wait_for_timeout(900)
  assert p.evaluate('FBNext.latest.heroes.find(h=>h.id===player.id).spellsCast')==1
  # Check that server damage mirrors in both tabs after polling.
  a=p.evaluate('FBNext.latest.towers');b=q.evaluate('FBNext.latest.towers');assert a==b
  record('Equipped spell casts from the shared charge pool; tower damage agrees across clients')
  p.locator('#v2MapBtn').tap();p.wait_for_timeout(300);assert p.evaluate('screen')=='map'
  # Map header scrolls to tower. Actual canvas tap enters it.
  point=p.evaluate('''()=>{const c=document.getElementById('warcv'),r=c.getBoundingClientRect(),k=r.width/WAR_W;const pos=WPOS.find(v=>r.top+(v.y0+v.y1)/2*k>160&&r.top+(v.y0+v.y1)/2*k<innerHeight-80);return pos?{x:r.left+(pos.x0+pos.x1)/2*k,y:r.top+(pos.y0+pos.y1)/2*k}:null;}''')
  assert point; p.touchscreen.tap(point['x'],point['y']);p.wait_for_timeout(900);assert p.evaluate('screen')=='battle'
  record('Tower map remains usable during locked online matches and a map tap returns to battle')
  debug('finish');p.wait_for_selector('#adventureResult:not([hidden])');q.wait_for_selector('#adventureResult:not([hidden])');check_hit(p,'#resultClaim');p.screenshot(path=str(ROOT/'docs/result-tested.png'))
  before=p.evaluate('SAVE.gold');shardsBefore=p.evaluate('SAVE.shards.arcane');p.locator('#resultShardChoice').select_option('arcane');p.locator('#resultClaim').tap();p.wait_for_function("screen==='home'&&!FBNext.active");assert p.evaluate('SAVE.gold')>before;assert p.evaluate('SAVE.shards.arcane')>shardsBefore
  assert p.evaluate('activeRoots()')==['setup'];p.locator('#seasonPill').tap();check_hit(p,'#passClose');p.locator('#passClose').tap()
  record('Server result, exact-once reward application, Home restoration and Season Pass after claim')
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureQueue').tap();p.wait_for_function("document.getElementById('queueCount').textContent.includes('/ 20')");debug('advance?ms=20000');p.wait_for_function('FBNext.active');assert p.evaluate('M.heroes.length')==20
  record('A second online battle starts after Claim, pass use and loadout reopening')
  p.screenshot(path=str(ROOT/'docs/online-tested.png'))
  # Lost acknowledgement: server commits the claim but the response never reaches this client.
  for i in range(5):
   debug('boost');p.wait_for_timeout(850);p.locator('#roll').tap();p.wait_for_timeout(3000)
  debug('finish');p.wait_for_selector('#adventureResult:not([hidden])');claimBefore=p.evaluate('SAVE.gold')
  def lost_claim(route):
   req=route.request
   resp=requests.post('http://127.0.0.1:8851/fatebound/arena/claim',headers={'Authorization':req.headers['authorization'],'Content-Type':'application/json','Origin':'null'},data=req.post_data,timeout=12)
   assert resp.status_code==200
   route.abort()
  p.route('https://arena.test/fatebound/arena/claim',lost_claim)
  p.locator('#resultClaim').tap();p.wait_for_function("document.getElementById('resultError').textContent.includes('Retry Claim')")
  journalStore=p.evaluate("Object.fromEntries(['fatebound-save','fatebound-arena-identity','fatebound-arena-pending-claim'].map(k=>[k,localStorage.getItem(k)]))")
  p.context.close();p=ready_page(browser,storage=journalStore);p.wait_for_function("localStorage.getItem('fatebound-arena-pending-claim')===null")
  assert p.evaluate('SAVE.gold')>claimBefore;assert p.evaluate('screen')=='home';claimedGold=p.evaluate('SAVE.gold')
  repeatStore=p.evaluate("Object.fromEntries(['fatebound-save','fatebound-arena-identity'].map(k=>[k,localStorage.getItem(k)]))")
  p.context.close();p=ready_page(browser,storage=repeatStore);assert p.evaluate('SAVE.gold')==claimedGold
  record('Lost claim acknowledgement recovers on document reload without losing or duplicating rewards')
  p.context.close();q.context.close()
  # Legacy progression, existing training and all original modal families use a fresh document.
  p=ready_page(browser)
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureSolo').tap();p.wait_for_timeout(1200)
  assert p.evaluate('!FBNext.active&&M.campaign&&!M.arena')
  check_hit(p,'#roll');assert p.locator('#arenaSpells button').count()==2
  p.locator('#roll').tap();p.wait_for_function('player.rolls>=1',timeout=15000)
  assert p.evaluate('player.rolls')>=1
  record('Original solo progression remains playable with two spell buttons')
  p.context.close();p=ready_page(browser);p.locator('#hubTutorial').tap();p.wait_for_timeout(800);assert p.evaluate('!!TRAIN')
  p.evaluate('FBNext.openPrep()');assert not p.locator('#adventurePrep').is_visible()
  p.locator('#coachNext').tap();p.locator('#coachNext').tap();p.locator('#roll').tap();p.wait_for_timeout(5000)
  assert p.evaluate('player.rolls')>=1
  p.wait_for_function("!document.getElementById('coachExit').disabled")
  p.evaluate("TRAIN.index=BATTLE_LESSONS.findIndex(l=>l.action==='giftOpen');trainingLesson();")
  p.locator('#giftAttackButton').tap();p.wait_for_timeout(300)
  assert p.locator('#battleCoach').is_visible();assert p.locator('#giftAttackPicker').is_visible()
  p.locator('#giftAttackList [data-use-attack]').first.tap();p.wait_for_timeout(500)
  p.evaluate("TRAIN.index=BATTLE_LESSONS.findIndex(l=>l.action==='visitGuild');trainingLesson();")
  p.locator('nav [data-tab="guild"]').tap();p.wait_for_timeout(300);assert p.locator('#battleCoach').is_visible();check_hit(p,'#coachNext')
  record('Guided gift use and menu-navigation lessons retain the coach above their dialogs')
  p.locator('#coachExit').tap();p.wait_for_function("screen==='home'&&!TRAIN")
  record('Guided training introduction, scripted roll and safe exit still work')
  p.route('https://arena.test/**',lambda r:r.fulfill(status=503,body='{"error":"Test server unavailable"}',headers={'content-type':'application/json','access-control-allow-origin':'*'}))
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureQueue').tap();p.wait_for_function("document.getElementById('queueCount').textContent==='Connection required'")
  assert not p.evaluate('FBNext.active');p.locator('#queueCancel').tap();assert p.evaluate('screen')=='home'
  record('Unavailable networking presents an explicit error and cancel, never a fake live bot match')
  assert not errors,errors;assert not console_errors,console_errors
  record('No uncaught game JavaScript or game-console errors in completed runs')
 except Exception as e:
  print('FAIL',repr(e),flush=True);traceback.print_exc()
  results.append({'check':'Runtime suite interrupted','status':'FAIL','detail':str(e)})
  try:p.screenshot(path=str(ROOT/'audit/browser-failure.png'));print('STATE',p.evaluate('({screen,root:activeRoots(),cls:document.body.className,train:!!TRAIN,active:FBNext.active})'),flush=True)
  except Exception:pass
 finally:
  print('ERRORS',errors,'CONSOLE',console_errors,flush=True)
  (ROOT/'audit/full-browser-tests.json').write_text(json.dumps({'sourceSha256':SOURCE_SHA256,'checks':results,'pageErrors':errors,'consoleErrors':console_errors},indent=2))
  browser.close()

if any(x['status']!='PASS' for x in results) or errors or console_errors:
 raise SystemExit(1)
