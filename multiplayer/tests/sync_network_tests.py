"""Full v113 HTML regression tests. All time/HP/face fixtures are localhost-only.
Never run this fixture server or expose its controls on the production machine.
"""
from pathlib import Path
import json,time
BASE=Path(__file__).with_name('browser_tests.py');space={'__file__':str(BASE)}
exec(BASE.read_text().split('with sync_playwright() as pw:')[0],space)
globals().update({k:v for k,v in space.items() if not k.startswith('__')})
OUT=ROOT/'sync-audit';OUT.mkdir(exist_ok=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  debug('reset');p=ready_page(b);q=ready_page(b)
  # Exhaustive result decisions and physical top faces use the full game's actual functions.
  faces=p.evaluate("""()=>{const f=['S','C','H','G','E','F'];let total=0;for(const a of f)for(const b of f)for(const c of f){const x=[a,b,c],r=R.resolve(x),s=FBArena.resolve(x),w=FBArenaWire.winningDice(x);if(r.action!==s.action||r.tier!==s.tier||w.symbol!==s.action||w.tier!==s.tier)throw Error('resolver mismatch '+x);total++;}return total;}""")
  assert faces==216;record('All 216 combinations agree across solo, server and displayed winning dice')
  physical=p.evaluate("""()=>[['S','S','E'],['C','H','C'],['G','F','F'],['H','H','H']].map(f=>{const d=makeDiceThrow(f);return {requested:f,top:d.map(x=>dieTop(new CANNON.Quaternion(...x.frames.at(-1).q)).face)};})""")
  assert all(x['requested']==x['top'] for x in physical);record('Actual recorded dice trajectories land on all three confirmed faces',physical)
  for page in [p,q]:
   page.locator('#adventurePrepareButton').tap();page.locator('#adventureQueue').tap();page.wait_for_function("document.getElementById('queueCount').textContent.includes('/ 20')")
  debug('advance?ms=20000')
  for page in [p,q]:page.wait_for_function('FBNext.active&&FBNext.online');page.wait_for_timeout(900)
  debug('boost');p.wait_for_timeout(1100)
  assert p.evaluate('FBNext.latest.id')==q.evaluate('FBNext.latest.id')
  p.wait_for_function('FBNext.transport.delta>0');record('Two full browser clients negotiate transport2 and share one authoritative 20-slot room',p.evaluate('FBNext.transport'))
  # Show the old solo chest counters cannot repaint the online status row.
  p.evaluate("SAVE.rollTrack={progress:7,ready:2,gold:400,shards:{steel:2,arcane:0,fletch:0}};renderRollTrack()")
  labels=p.evaluate("""async()=>{const a=[];for(let i=0;i<80;i++){await new Promise(r=>setTimeout(r,20));a.push(document.getElementById('rollTrackLabel').textContent);}return [...new Set(a)];}""")
  assert len(labels)==1 and labels[0].startswith('ONLINE'),labels
  record('Online chest/status row stays identical through overlapping old HUD refresh intervals',labels)
  p.locator('#battleChests').tap();assert p.locator('#chestInbox').is_visible();p.locator('#chestInbox footer button').tap()
  assert p.evaluate('rollTrack().ready')==2;record('Existing saved roll chests stay accessible and are not consumed by online status rendering')
  pid=p.evaluate('player.id');debug('knockout?player='+pid+'&ms=45000');p.wait_for_function('player.hp===0')
  downstate=p.evaluate("({down:down(player),disabled:document.getElementById('roll').disabled,pose:heroFrame(player,performance.now(),down(player)).state,status:FBNext.rollStatus(),serverHP:FBNext.latest.heroes.find(h=>h.id===player.id).hp})")
  assert downstate['down'] and downstate['disabled'] and downstate['pose']=='death' and downstate['serverHP']==0,downstate
  record('Server KO immediately shows death pose, zero HP and disabled ROLL with respawn countdown',downstate)
  # Polling can be delayed while CSS keeps running. A local elapsed timer must not resurrect a hero.
  p.evaluate("window.__realFetch=window.fetch;window.__holdPoll=true;window.__releasePoll=null;window.fetch=async(...args)=>{const res=await __realFetch(...args);if(__holdPoll&&String(args[0]).includes('/state?'))return new Promise(resolve=>window.__releasePoll=()=>resolve(res));return res;};player.downUntil=Date.now()-1000;")
  p.wait_for_function('!!window.__releasePoll');p.wait_for_timeout(4300)
  stale=p.evaluate("({down:down(player),hp:player.hp,disabled:document.getElementById('roll').disabled,status:FBNext.rollStatus()})")
  assert stale['down'] and stale['hp']==0 and stale['disabled'] and 'Reconnecting' in stale['status'],stale
  record('Expired local timers and delayed packets never make a zero-HP online hero alive',stale)
  p.evaluate('window.__holdPoll=false;window.__releasePoll();');debug('advance?ms=45000');p.wait_for_function('player.hp>0');p.wait_for_timeout(900)
  assert p.evaluate("!down(player)&&!document.getElementById('roll').disabled"),p.evaluate('FBNext.rollStatus()')
  record('Only a server-confirmed positive-HP respawn restores the alive pose and ROLL')
  # A queued older poll must not undo a fresher action result.
  debug('boost');p.wait_for_timeout(1100)
  p.evaluate('window.__holdPoll=true;window.__releasePoll=null;');p.wait_for_function('!!window.__releasePoll')
  oldrev=p.evaluate('FBNext.latest.revision');p.locator('#roll').tap();p.wait_for_function(f'FBNext.latest.revision>{oldrev}')
  newer=p.evaluate('({revision:FBNext.latest.revision,hp:player.hp,rolls:player.rolls})')
  p.evaluate('window.__holdPoll=false;window.__releasePoll();');p.wait_for_timeout(150)
  after=p.evaluate('({revision:FBNext.latest.revision,hp:player.hp,rolls:player.rolls})')
  assert after['revision']>=newer['revision'] and after['rolls']>=newer['rolls'],(newer,after)
  p.wait_for_timeout(2600);record('A delayed poll cannot rewind the HP/roll count from a newer confirmed action',{'before':newer,'after':after,'decoder':p.evaluate('FBNext.transport')})
  # Verify the complaint's concrete pair positions against the live renderer and server effects.
  cases=[(['H','H','C'],'pair:H:0,1'),(['G','S','G'],'pair:G:0,2'),(['E','F','F'],'pair:F:1,2'),(['S','S','E'],'pair:S:0,1')]
  reports=[]
  for requested,expected in cases:
   debug('boost');debug('force-faces?faces='+','.join(requested));p.wait_for_timeout(1000)
   before=p.evaluate("({rolls:player.rolls,hero:FBNext.latest.heroes.find(h=>h.id===player.id)})")
   p.locator('#roll').tap();p.wait_for_function(f'player.rolls>{before["rolls"]}');p.wait_for_timeout(2000)
   state=p.evaluate("({faces:player.lastFaces,marker:document.getElementById('board').dataset.diceResult,hero:FBNext.latest.heroes.find(h=>h.id===player.id),lunge:player.lunge})")
   assert state['faces']==requested and state['marker']==expected,state
   if requested[0]=='H':assert sum(state['hero']['shieldSlots'])>sum(before['hero']['shieldSlots']) and state['lunge'] is None,state
   if requested[0]=='G':assert state['lunge'] is None,state
   if requested[1]=='F':assert state['hero']['giftDamage']>before['hero']['giftDamage'],state
   if requested[0]=='S':assert state['hero']['damage']>before['hero']['damage'],state
   reports.append({'faces':state['faces'],'highlighted':state['marker']})
  record('Left/middle, left/right and middle/right pairs highlight exactly their contributing dice and apply correct effects',reports)
  p.screenshot(path=str(OUT/'pair-left-middle.png'))
  # The first roll reply is lost after server execution. A substitute can roll before
  # the same action ID is retried; its old receipt must not replace the latest dice.
  debug('boost');debug('force-faces?faces=H,H,C');p.wait_for_timeout(1000)
  lost={'once':False}
  def lost_action(route):
   if not lost['once'] and route.request.method=='POST' and json.loads(route.request.post_data or '{}').get('type')=='roll':
    lost['once']=True
    headers={k:v for k,v in route.request.headers.items() if k.lower() in ('authorization','content-type')};headers['Origin']='null'
    response=requests.post(route.request.url.replace('https://arena.test','http://127.0.0.1:8851'),headers=headers,data=route.request.post_data,timeout=12)
    response.raise_for_status();lost['index']=response.json()['result']['rollIndex']
    debug('substitute-roll?player='+pid+'&faces=G,G,E');route.abort();return
   routed(route)
  p.route('**/action?**',lost_action);rolls=p.evaluate('player.rolls');p.locator('#roll').tap()
  p.wait_for_function(f'player.rolls>={rolls+2}');p.wait_for_timeout(800);p.unroute('**/action?**',lost_action)
  replay=p.evaluate("({faces:player.lastFaces,rolls:player.rolls,serverFaces:FBNext.latest.heroes.find(h=>h.id===player.id).lastFaces,marker:document.getElementById('board').dataset.diceResult})")
  assert lost['once'] and replay['rolls']==rolls+2 and replay['faces']==['G','G','E'] and replay['serverFaces']==replay['faces'] and replay['marker']=='pair:G:0,1',replay
  record('Lost first action reply retries exactly once without overwriting newer substitute dice',{'originalReceiptIndex':lost['index'],'current':replay})

  # No changing sound architecture. First mixer interaction still works on actual browser graph.
  p.locator('#v2MoreBtn').tap();p.locator('[data-v2-dest="sound"]').tap();p.locator('[data-preview="sword"]').tap();p.wait_for_timeout(150)
  assert p.evaluate("FateboundAudio.diagnostics.counts.sword>0");p.locator('#soundDone').tap();record('v112 sound unlock and sample playback remain functional in the browser')
  for w,h in [(360,640),(393,852),(640,360)]:
   p.set_viewport_size({'width':w,'height':h});p.wait_for_timeout(300)
   for s in ['#roll','#battleChests','#v2MapBtn']:
    p.locator(s).evaluate('e=>e.disabled=false');check_hit(p,s)
  record('New status messages preserve ROLL/Chest/Map hit areas in short portrait and landscape')
  p.set_viewport_size({'width':393,'height':852})
  debug('finish');p.wait_for_selector('#adventureResult:not([hidden])');q.wait_for_selector('#adventureResult:not([hidden])')
  for page in [p,q]:page.locator('#resultClaim').tap();page.wait_for_function("screen==='home'&&!FBNext.active")
  assert p.evaluate('rollTrack().ready')==2;record('Completion and claim return Home without consuming saved offline roll chests')
  for page in [p,q]:
   page.locator('#adventurePrepareButton').tap();page.locator('#adventureQueue').tap();page.wait_for_function("document.getElementById('queueCount').textContent.includes('/ 20')")
  debug('advance?ms=20000')
  for page in [p,q]:page.wait_for_function('FBNext.active&&FBNext.online')
  assert p.evaluate('FBNext.latest.id')==q.evaluate('FBNext.latest.id');record('Second shared online match starts after KO, network delay, dice and reward regressions')
  assert not errors,errors;assert not console_errors,console_errors
 finally:
  (OUT/'browser-regressions.json').write_text(json.dumps({'source_sha256':SOURCE_SHA256,'checks':results,'errors':errors,'console_errors':console_errors,'physical_phone_tested':False},indent=2)+'\n');b.close()
