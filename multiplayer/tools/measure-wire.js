#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),assert=require('node:assert/strict');
const A=require('../src/arena-engine'),W=require('../src/arena-wire');
const players=Array.from({length:20},(_,i)=>({id:i<2?'10000000-0000-4000-8000-'+String(i).padStart(12,'0'):'bot:20000000-0000-4000-8000-000000000001:'+i,name:i<2?'Network Test '+i:'Bot '+i,bot:i>1,char:i%5,weapon:i%9,loadout:['barrage','bulwark']}));
const totals={old_raw:0,old_gzip:0,new_raw:0,new_gzip:0,new_brotli:0},max={old_gzip:0,new_gzip:0,new_brotli:0};let packets=0,deltas=0,fulls=0;
const measured=[];
for(const seed of [7,29,101]){
 const e=new A.Engine({id:'20000000-0000-4000-8000-'+String(seed).padStart(12,'0'),players,now:1000000,seed}),encoder=new W.Encoder(),decoder=new W.Decoder();
 for(let tick=0;tick<=400;tick++){
  const now=1000000+tick*750;e.tick(now);
  for(const h of e.s.heroes.slice(0,2))if(tick%5===0&&h.hp>0&&h.focus>=1&&!e.s.ended){try{e.act(h.id,{type:'roll',mult:1},now);}catch(_){} }
  const state={status:e.s.ended?'complete':'battle',serverNow:now,match:e.snapshot()};
  const original=Buffer.from(JSON.stringify(state));const compact=encoder.encode(state,decoder.cursor()),b=Buffer.from(JSON.stringify(compact));
  const decoded=decoder.decode(compact.match),{events,...data}=decoded;assert.deepEqual(data,W.project(state.match));
  if(compact.match.full)fulls++;else deltas++;
  const row={old_raw:original.length,old_gzip:zlib.gzipSync(original).length,new_raw:b.length,new_gzip:b.length<256?b.length:Math.min(b.length,zlib.gzipSync(b,{level:6}).length),new_brotli:b.length<256?b.length:Math.min(b.length,zlib.brotliCompressSync(b,{params:{[zlib.constants.BROTLI_PARAM_QUALITY]:4}}).length)};
  for(const k of Object.keys(totals))totals[k]+=row[k];for(const k of Object.keys(max))max[k]=Math.max(max[k],row[k]);packets++;
  if(seed===7&&[0,1,80,160,320,400].includes(tick))measured.push({elapsed_ms:tick*750,...row});
 }
}
const r={method:'Three deterministic 300-second matches with 20 combatants, two rolling scripted humans and 18 bots; 401 snapshots per client per match at 750ms. Same authoritative state encoded with old full+gzip and new full/delta+gzip/Brotli. No physics/game rules changed.',excludes:'HTTP/TLS/transport headers, uploads, cloud-save sync, initial artwork download, actions between polls and reconnect full syncs. Not physical-phone carrier metering.',snapshot_count:packets,fulls,deltas,totals,average_bytes_per_snapshot:Object.fromEntries(Object.entries(totals).map(([k,v])=>[k,Math.round(v/packets)])),average_payload_bytes_per_5_minute_match:Object.fromEntries(Object.entries(totals).map(([k,v])=>[k,Math.round(v/3)])),max_bytes:max,vs_previous_gzip_reduction_pct:{new_gzip:Math.round((1-totals.new_gzip/totals.old_gzip)*1000)/10,new_brotli:Math.round((1-totals.new_brotli/totals.old_gzip)*1000)/10},samples:measured};
const out=process.argv[2]||path.join(__dirname,'../sync-audit/bandwidth.json');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(r,null,2)+'\n');console.log(JSON.stringify(r,null,2));
