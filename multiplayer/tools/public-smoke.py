#!/usr/bin/env python3
"""Explicit operator-only live alpha check. Not run at server startup.
Creates two labelled verification guests; uses real clocks/rules/TLS; no control
endpoints. Tokens stay in process memory, not the report or command line.
"""
import argparse,json,time,urllib.request,urllib.error,uuid
from pathlib import Path
P=argparse.ArgumentParser();P.add_argument('--base',required=True);P.add_argument('--out',required=True);args=P.parse_args()
base=args.base.rstrip('/');report={'base':base,'started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'checks':[],'physical_devices':False,'clock_overrides':False}
def api(path,data=None,token=None):
 headers={'Content-Type':'application/json','Origin':'null'}
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(base+path,data=None if data is None else json.dumps(data).encode(),headers=headers)
 with urllib.request.urlopen(req,timeout=12) as r:return json.load(r)
def check(name,**evidence):
 report['checks'].append({'check':name,'status':'PASS',**evidence});print('PASS',name,flush=True)
def st(s):return api('/state',token=s['token'])
def act(s,room,typ,**kwargs):return api('/action',dict(matchId=room,actionId=str(uuid.uuid4()),type=typ,**kwargs),s['token'])
try:
 h=api('/health');assert h['queueMs']==20000 and h['capacity']==20 and h['balanceVersion']==110,h
 check('Public TLS health reports audited balance and unchanged queue rules')
 clients=[api('/session',{'name':'Audit verification '+name}) for name in ['A','B']]
 prefs={'char':0,'weapon':0,'loadout':['barrage','bulwark']}
 first=api('/queue',prefs,clients[0]['token']);second=api('/queue',prefs,clients[1]['token']);assert first['lobbyId']==second['lobbyId']
 deadline=first['deadline'];monotonic=time.monotonic();states=[]
 while time.monotonic()-monotonic<40:
  states=[st(s) for s in clients]
  if states[0]['status']=='battle':break
  assert states[0]['status']=='searching';time.sleep(1)
 assert all(x['status']=='battle' for x in states),states[0]['status']
 assert all(x['serverNow']>=deadline for x in states)
 room=states[0]['match']['id'];assert room==states[1]['match']['id']
 heroes=states[0]['match']['heroes'];assert len(heroes)==20 and [sum(h['side']==i for h in heroes) for i in [0,1]]==[10,10]
 check('Two public clients wait the real deadline then share a 10-vs-10 room',wait_seconds=round(time.monotonic()-monotonic,2),humans=sum(not h['bot'] for h in heroes),bots=sum(h['bot'] for h in heroes))
 start=time.monotonic();moved=False;casted=False;sub_seen=False;reconnected=False;old_id=clients[1]['playerId']
 while time.monotonic()-start<385:
  elapsed=time.monotonic()-start
  # Deliberately stop one client's heartbeat for >8s, then recover its same slot.
  for i,s in enumerate(clients):
   if i==1 and 50<=elapsed<63:continue
   x=st(s);states[i]=x
   if x['status']=='complete':continue
   assert x['status']=='battle' and x['match']['id']==room
   me=next(h for h in x['match']['heroes'] if h['id']==s['playerId']);now=x['serverNow']
   if i==0 and 59<=elapsed<63:
    sub_seen=next(h for h in x['match']['heroes'] if h['id']==old_id)['substitute']
   if i==1 and elapsed>=63 and not reconnected:
    assert not me['substitute'];reconnected=True
   if me['hp']<=0:continue
   if i==0 and not moved:
    act(s,room,'move',tower=(me['tower']+1)%10);moved=True
   elif me['spell']>0 and now>=me['spellAt']:
    act(s,room,'spell',spell='barrage');casted=True
   elif me['focus']>=1 and now>=me['rollAt']:
    act(s,room,'roll',mult=1,allIn=False)
  if all(x['status']=='complete' for x in states):break
  time.sleep(1.25)
 states=[st(s) for s in clients];assert all(x['status']=='complete' for x in states)
 assert moved and casted and sub_seen and reconnected,(moved,casted,sub_seen,reconnected)
 check('Actual rolls, spell, tower move and in-place disconnect/reconnect work')
 assert all(x['result']['eligible'] and x['result']['stats']['paidRolls']>=5 for x in states)
 assert states[0]['result']['score']==states[1]['result']['score']
 check('Real-clock battle completes with matching scores and eligible own-action rewards',duration_seconds=round(time.monotonic()-start,2),paid_rolls=[x['result']['stats']['paidRolls'] for x in states])
 for s in clients:
  before=api('/profile',token=s['token'])['earned']
  a=api('/claim',{'matchId':room,'shardKind':'arcane'},s['token']);b=api('/claim',{'matchId':room,'shardKind':'steel'},s['token'])
  assert a['receipt']==b['receipt'] and b['receipt']['shardKind']=='arcane'
  assert before==b['profile']['earned'];assert st(s)['status']=='idle'
 check('Duplicate public claims do not grant twice or change the material choice')
 a=api('/queue',prefs,clients[0]['token']);b=api('/queue',prefs,clients[1]['token']);assert a['status']==b['status']=='searching' and a['lobbyId']==b['lobbyId'] and a['lobbyId']!=room
 for s in clients:assert api('/cancel',{},s['token'])['status']=='idle'
 check('Both clients can enter a fresh second queue and cancel cleanly')
 report['status']='PASS'
except Exception as e:
 report['status']='FAIL';report['error']=str(e);print('FAIL',type(e).__name__,str(e),flush=True);raise
finally:
 report['finished_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime());Path(args.out).write_text(json.dumps(report,indent=2)+'\n')
