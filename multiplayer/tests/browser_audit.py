"""Full-game audit regressions. Isolated saves; production code is not instrumented.
Real fixture server for normal actions; explicitly mocked transport failures and
receipt fixtures exercise browser recovery paths. Never deploy fixture endpoints.
"""
from pathlib import Path
BASE=Path(__file__).with_name('browser_tests.py')
space={'__file__':str(BASE)}
exec(BASE.read_text().split('with sync_playwright() as pw:')[0],space)
globals().update({k:v for k,v in space.items() if not k.startswith('__')})
import copy
OUT=ROOT/'audit'/'browser-audit.json'

def close(p):p.context.close()
def enter_online(p):
 p.locator('#adventurePrepareButton').tap();p.locator('#adventureQueue').tap()
 p.wait_for_function("document.getElementById('queueCount').textContent.includes('/ 20')")
 debug('advance?ms=20000');p.wait_for_function('FBNext.active');debug('boost');p.wait_for_timeout(900)

def receipt_page(browser,stale=False,storage=None):
 now=int(time.time()*1000);sid=max(0,(now-1767571200000)//(30*86400000))
 date=time.strftime('%a %b %d %Y',time.gmtime(now/1000))
 save={'owned':[0],'tutorial':{'done':True},'tutorialBattle':{'done':True},
  'gold':0,'season':{'id':sid,'pts':0,'free':[],'prem':[],'premium':False},
  'daily':{'date':date,'q':[2,4,7],'p':{},'done':[]},'login':{'date':date,'streak':1}}
 ident={'playerId':'audit-guest','token':'t'*43}
 receipt={'id':'audit-pending-receipt','char':0,'weapon':0,'at':now-(31*86400000 if stale else 0),
  'season':sid-(1 if stale else 0),'eligible':True,'win':True,'claimed':True,
  'reward':{'gold':100,'fate':2,'pts':10,'xp':0,'shards':2},'shardKind':'steel',
  'mastery':{'assault':5,'guardian':2,'commander':1},
  'stats':{'paidRolls':5,'rolls':5,'triples':2,'damage':4000,'kos':0,'shieldsBroken':0,'gifts':0,'flips':0}}
 profile={'id':ident['playerId'],'guild':None,'active':None,'pendingRewards':0,'mastery':{}}
 initial=storage or {'fatebound-save':json.dumps(save),'fatebound-arena-identity':json.dumps(ident),
                    'fatebound-arena-pending-claim':json.dumps({'playerId':ident['playerId'],'matchId':receipt['id']})}
 ctx=browser.new_context(viewport={'width':393,'height':852},is_mobile=True,has_touch=True)
 p=ctx.new_page();p.set_default_timeout(12000)
 p.on('pageerror',lambda e:errors.append(e.stack))
 def route(r):
  if 'arena.test/' not in r.request.url:return r.abort()
  data={'receipt':receipt,'profile':profile} if r.request.url.endswith('/claim') else {'status':'idle'} if r.request.url.endswith('/state') else profile
  r.fulfill(status=200,body=json.dumps(data),headers={'content-type':'application/json'})
 p.route('**/*',route);p.set_content(bundled(storage=initial),timeout=60000);p.wait_for_timeout(1300)
 return p

with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  p=ready_page(b)
  x=p.evaluate('''()=>{const save=structuredClone(SAVE);SAVE.bonus=0;SAVE.war={id:'audit',snapshot:{focus:0,focusMax:8}};SAVE.pendingRoll={paid:8,resource:'focus',warId:'audit'};normalizeSave();const r={fate:SAVE.bonus,focus:SAVE.war.snapshot.focus,pending:SAVE.pendingRoll};SAVE=save;return r;}''')
  assert x=={'fate':0,'focus':8,'pending':None},x;record('Interrupted Focus payments refund matching battle Focus, never permanent Fate')
  x=p.evaluate('''()=>{const save=structuredClone(SAVE);SAVE.bonus=0;SAVE.war={id:'other',snapshot:{focus:0,focusMax:8}};SAVE.pendingRoll={paid:8,warId:'older'};normalizeSave();const r=[SAVE.bonus,SAVE.war.snapshot.focus];SAVE=save;return r;}''')
  assert x==[0,0];record('An old pending roll cannot credit a different battle')
  x=p.evaluate('''()=>{const old=M;M={lobby:false,ended:false,focus:8,focusMax:8,focusAt:Date.now()-60000};pairFocusTick();spendFocus(8);pairFocusTick();const r=focus();M=old;return r;}''')
  assert x==0;record('Waiting at capped Focus cannot bank regeneration ticks')
  # Malformed optional metadata is staged only in a disposable test save.
  p.evaluate("SAVE.adventure={loadout:['bad','bad'],mastery:5,receipts:'bad',path:'invalid'};FBNext.openPrep()")
  p.wait_for_timeout(250);assert p.evaluate('SAVE.adventure.loadout')==['barrage','bulwark'];check_hit(p,'#adventureQueue');p.locator('#adventurePrep [data-dismiss]').tap()
  record('Invalid adventure metadata recovers without blocking the menus')
  p.evaluate("SAVE.daily.q=[99,2,2];SAVE.daily.done=null;SAVE.daily.p=null;SAVE.tiers[0]=999;SAVE.season.free='bad';SAVE.giftsDue=[null];normalizeSave();")
  assert p.evaluate('SAVE.daily.q')==[2];assert p.evaluate('SAVE.tiers[0]')==0
  p.locator('nav [data-tab="hero"]').tap();p.locator('nav [data-tab="home"]').tap();record('Malformed daily, tier, gift and Season Pass metadata cannot crash menu rendering')
  # Verify the real exit button, not merely a direct call to the cleanup function.
  p.locator('#hubTutorial').tap();p.wait_for_function('!!TRAIN')
  p.evaluate("TRAIN.index=BATTLE_LESSONS.findIndex(x=>x.action==='roll');trainingLesson();")
  p.locator('#roll').tap();p.wait_for_timeout(150);assert p.locator('#coachExit').is_enabled();p.locator('#coachExit').tap()
  p.wait_for_function("!TRAIN&&screen==='home'");before=p.evaluate('SAVE.gold');p.wait_for_timeout(3500)
  assert p.evaluate("!TRAIN&&screen==='home'&&SAVE.gold===%s"%before);record('Training can be exited during a throw; the delayed result cannot affect Home')
  # Solo spells resolve damage only, not a hidden dice throw or a charge refund.
  p.locator('#adventurePrepareButton').tap();p.locator('#adventureSolo').tap();p.wait_for_function("screen==='battle'&&!M.lobby");p.wait_for_timeout(500)
  r=p.evaluate("""()=>{player.hp=player.maxHp;player.downUntil=0;M.focus=4;M.captureRewardAt={};M.towers[player.tower].dmg=[0,0];FateboundSpells.addCharge();const before={rolls:player.rolls,focus:focus(),charges:FateboundSpells.charges()};FateboundSpells.cast('barrage');return {before,after:{rolls:player.rolls,focus:focus(),charges:FateboundSpells.charges()}};}""")
  assert r['before']['rolls']==r['after']['rolls'];assert r['before']['focus']==r['after']['focus'];assert r['after']['charges']==r['before']['charges']-1,r
  record('Solo Barrage is an actual spell, not a free roll/Focus/charge exploit')
  p.evaluate("player.rampage=5;player.allIn=true;player.mult=4;M.focus=0;player.hp=player.maxHp;player.downUntil=0")
  p.locator('#roll').tap();p.wait_for_timeout(250);a=p.evaluate('player.action');assert a['mult']==1 and a['paid']==0,a
  p.wait_for_timeout(3500);record('Solo Rampage executes free ×1 rolls, not free ALL-IN')
  close(p);p=ready_page(b)
  p.locator('#homeRaid').tap();p.locator('#bossGo').tap();p.wait_for_function('M.inBoss');p.wait_for_timeout(500)
  assert p.locator('#arenaExtras').is_hidden();record('Raid does not display unusable arena spell controls')
  x=p.evaluate("""()=>{const B=bossCheck();B.hp=B.max;B.dmg=0;BR.ended=false;player.hp=player.maxHp;player.downUntil=0;M.giftAttackUntil=0;damageGiftBox(player).items=[100];const old=SAVE.stats.damage;const result=useStoredAttack(0);return {result,contribution:B.dmg,stats:SAVE.stats.damage-old,items:damageGiftBox(player).items.length};}""")
  assert x=={'result':True,'contribution':100,'stats':100,'items':0},x;record('Stored raid attacks credit the player and damage quest, not the boss identity')
  # End an attempt during a throw; later raid callbacks must not mutate the hub.
  p.wait_for_timeout(1200);p.locator('#roll').tap();p.wait_for_timeout(150);p.evaluate('leaveBoss(false);homeHub()');p.wait_for_timeout(300)
  before=p.evaluate('bossCheck().hp');p.wait_for_timeout(3500);assert p.evaluate("screen==='home'&&!M.inBoss");assert p.evaluate('bossCheck().hp')==before
  record('A departed raid cannot land delayed dice or bot attacks on the next screen');close(p)
  # Fixture receipts execute the real browser journal, transaction and duplicate checks.
  p=receipt_page(b);r=p.evaluate('({gold:SAVE.gold,pts:SAVE.season.pts,done:SAVE.daily.done,matches:SAVE.stats.matches,wins:SAVE.stats.wins,damage:SAVE.stats.damage,pending:localStorage.getItem("fatebound-arena-pending-claim")})')
  assert r['gold']==600 and r['pts']==19 and set(r['done'])=={2,4,7} and r['matches']==1 and r['wins']==1 and r['damage']==4000 and r['pending'] is None,r
  record('Verified online result updates daily quests and lifetime stats once')
  store=p.evaluate("({'fatebound-save':localStorage.getItem('fatebound-save'),'fatebound-arena-identity':localStorage.getItem('fatebound-arena-identity')})")
  store['fatebound-arena-pending-claim']=json.dumps({'playerId':'audit-guest','matchId':'audit-pending-receipt'})
  q=receipt_page(b,storage=store);assert q.evaluate('SAVE.stats.matches')==1;assert q.evaluate('SAVE.gold')==r['gold'];record('Reloading a claimed receipt cannot repeat coins, dailies or lifetime stats');close(q);close(p)
  p=receipt_page(b,stale=True);assert p.evaluate('SAVE.gold')==100;assert p.evaluate('SAVE.season.pts')==0;assert p.evaluate('SAVE.daily.done')==[];record('Old-season rewards retain currency but cannot farm new-season points or current dailies');close(p)
  # Real HTTP arena: deliberately drop a committed roll reply once.
  debug('reset');p=ready_page(b);enter_online(p);drop={'count':0,'ids':[]}
  def lost(r):
   if not r.request.url.endswith('/action'):return routed(r)
   data=json.loads(r.request.post_data);drop['ids'].append(data['actionId'])
   if data.get('type')=='roll' and drop['count']==0:
    headers={k:v for k,v in r.request.headers.items() if k.lower() in ('authorization','content-type')};headers['Origin']='null'
    response=requests.post(r.request.url.replace('https://arena.test','http://127.0.0.1:8851'),headers=headers,data=r.request.post_data,timeout=10);assert response.status_code==200
    drop['count']+=1;r.abort()
   else:routed(r)
  p.unroute('**/*');p.route('**/*',lost);p.locator('#roll').tap();p.wait_for_timeout(4000)
  assert drop['count']==1 and len(drop['ids'])==2 and len(set(drop['ids']))==1,drop
  assert p.evaluate('player.rolls')==1;record('A lost committed roll reply retries the same action ID and spends only once')
  def idle(r):
   if r.request.url.endswith('/state'):r.fulfill(status=200,body='{"status":"idle"}',headers={'content-type':'application/json'})
   else:routed(r)
  p.unroute('**/*');p.route('**/*',idle);p.wait_for_function("screen==='home'&&!FBNext.active");p.locator('nav [data-tab="guild"]').tap();p.locator('nav [data-tab="home"]').tap();record('An expired online room returns to usable Home instead of leaving the battle lock');close(p)
  # Network callback races must not re-open a user-dismissed dialog.
  p=ready_page(b)
  p.evaluate("window.__normalFetch=fetch;window.fetch=async(...args)=>{const r=await __normalFetch(...args);await new Promise(resolve=>setTimeout(resolve,900));return r;};FBNext.openExpedition();")
  p.wait_for_timeout(80);p.locator('#adventureGuild [data-dismiss]').tap();p.wait_for_timeout(2300)
  assert p.locator('#adventureGuild').is_hidden();p.locator('nav [data-tab="hero"]').tap();record('A delayed guild connection cannot reopen a dismissed modal');close(p)
  debug('reset');p=ready_page(b);p.evaluate('FBNext.openExpedition()');p.wait_for_selector('#guildName')
  p.locator('#guildName').fill('Audit milestone');p.locator('#guildCreate').tap();p.wait_for_selector('#guildRoute')
  debug('guild-progress');p.locator('#adventureGuild [data-dismiss]').tap();p.evaluate('FBNext.openExpedition()');p.wait_for_selector('[data-exp-claim="0"]:enabled')
  before=p.evaluate('({gold:SAVE.gold,shards:SAVE.shards.steel,tokens:SAVE.tokens})');drop_guild={'count':0}
  def lost_guild(r):
   data=json.loads(r.request.post_data or '{}')
   if r.request.url.endswith('/guild') and data.get('type')=='claim' and drop_guild['count']==0:
    headers={k:v for k,v in r.request.headers.items() if k.lower() in ('authorization','content-type')};headers['Origin']='null'
    response=requests.post(r.request.url.replace('https://arena.test','http://127.0.0.1:8851'),headers=headers,data=r.request.post_data,timeout=10);assert response.status_code==200
    drop_guild['count']+=1;r.abort()
   else:routed(r)
  p.unroute('**/*');p.route('**/*',lost_guild);p.locator('[data-exp-claim="0"]').tap();p.wait_for_timeout(600)
  assert drop_guild['count']==1
  p.locator('#adventureGuild [data-dismiss]').tap();p.evaluate('FBNext.openExpedition()');p.wait_for_selector('#guildRoute')
  after=p.evaluate('({gold:SAVE.gold,shards:SAVE.shards.steel,tokens:SAVE.tokens})');assert after=={'gold':before['gold']+150,'shards':before['shards']+2,'tokens':before['tokens']+1},(before,after)
  p.locator('#adventureGuild [data-dismiss]').tap();p.evaluate('FBNext.openExpedition()');p.wait_for_selector('#guildRoute');assert p.evaluate('SAVE.gold')==after['gold']
  record('A lost guild milestone reply is discovered and recovered once through the real server');close(p)
  p=ready_page(b);p.locator('nav [data-tab="shop"]').tap()
  assert p.locator('[data-shop]').count()==0 and p.locator('[data-relic="cap"]').count()==0
  x=p.evaluate("""()=>{const gold=player.gold,tokens=SAVE.tokens;for(const k of ['energy10','shield','rally','buff','not-real']){const b=document.createElement('button');b.dataset.shop=k;document.getElementById('scrShop').appendChild(b);b.click();b.remove();}return {gold:player.gold===gold,tokens:SAVE.tokens===tokens};}""")
  assert x=={'gold':True,'tokens':True};record('Home cannot sell disappearing battle consumables or unused Fate; forged stale buttons spend nothing')
  x=p.evaluate("""()=>{SAVE.tokens=100;SAVE.relics.atk=0;renderShop();const before={tokens:SAVE.tokens,atk:player.atk};const original=persist;persist=()=>false;document.querySelector('[data-relic="atk"]').click();persist=original;return {tokens:SAVE.tokens,atk:player.atk,level:SAVE.relics.atk,before};}""")
  assert x['tokens']==x['before']['tokens'] and x['atk']==x['before']['atk'] and x['level']==0,x
  record('A failed relic save rolls back both the token cost and combat bonus')
  p.locator('[data-relic="atk"]').tap();assert p.evaluate('SAVE.relics.atk')==1 and p.evaluate('SAVE.tokens')==85
  p.locator('nav [data-tab="hero"]').tap()
  x=p.evaluate("""()=>{SAVE.owned=[0];player.weapon=0;SAVE.tiers[0]=0;SAVE.shards.steel=100;SAVE.gold=player.gold=20000;player.weaponMult=weaponMultOf(player);const mult=player.weaponMult;const original=persist;persist=()=>false;const ok=forge(0);persist=original;return {ok,gold:player.gold,shards:SAVE.shards.steel,tier:SAVE.tiers[0],mult:player.weaponMult,oldMult:mult};}""")
  assert not x['ok'] and x['gold']==20000 and x['shards']==100 and x['tier']==0 and x['mult']==x['oldMult'],x
  assert p.evaluate('forge(0)') and p.evaluate('SAVE.tiers[0]')==1
  assert p.evaluate('forgeCost(0).gated') is False
  p.evaluate('renderHero()');assert 'all nine base weapons' not in p.locator('#scrHero').inner_text()
  record('Forge is atomic on save failure and follows the displayed costs without a hidden nine-weapon gate')
  p.locator('nav [data-tab="home"]').tap();gold=p.evaluate('SAVE.gold');p.locator('#hubTutorial').tap()
  p.evaluate("TRAIN.index=BATTLE_LESSONS.findIndex(x=>x.action==='buyEnergy');trainingLesson();")
  p.locator('[data-shop="energy10"]').tap();p.wait_for_timeout(350)
  assert p.evaluate("BATTLE_LESSONS[TRAIN.index].title")== 'Check your Fate balance'
  p.locator('#coachExit').tap();p.wait_for_function('!TRAIN');assert p.evaluate('SAVE.gold')==gold
  record('The labelled practice purchase advances training without spending the real saved gold');close(p)
  assert not errors,errors
  record('No uncaught JavaScript errors across the added browser regressions')
 finally:
  OUT.parent.mkdir(exist_ok=True);OUT.write_text(json.dumps({'source_sha256':SOURCE_SHA256,'checks':results,'uncaught_errors':errors,'console_errors':console_errors,'fixtures':'isolated full HTML, mobile Chromium, actual loopback arena; deliberate failure/receipt mocks explicitly labelled'},indent=2));b.close()
